//
//  ADXCSJNativeExpressAdapter.m
//  AdWinX
//
//  Created by AdWinX on 2026/08/31.
//

#import "ADXCSJNativeExpressAdapter.h"
#import "ADXAdSourceInfo.h"
#import "ADXBidResult.h"
#import "ADXLogger.h"
#import <BUAdSDK/BUAdSDK.h>
#import <UIKit/UIKit.h>

static BOOL _csjNativeSDKInitialized = NO;

@interface ADXCSJNativeExpressAdapter () <BUNativeExpressAdViewDelegate>

@property (nonatomic, strong, nullable) BUNativeExpressAdManager *nativeExpressAdManager;
@property (nonatomic, strong, nullable) BUNativeExpressAdView *nativeExpressAdView;
@property (nonatomic, copy, nullable) void (^loadCompletion)(ADXBidResult *result);
/// 渲染结果回调（render 异步，成功/失败时各回调一次后清空）
@property (nonatomic, copy, nullable) void (^renderCompletion)(UIView * _Nullable adView, NSError * _Nullable error);
@property (nonatomic, strong, nullable) ADXAdSourceInfo *currentSourceInfo;

@end

@implementation ADXCSJNativeExpressAdapter

#pragma mark - SDK Initialization

+ (void)setupSDKWithConfig:(NSDictionary *)adnConfig
{
    [self setupSDKWithConfig:adnConfig completion:NULL];
}

+ (void)setupSDKWithConfig:(NSDictionary *)adnConfig
                completion:(nullable void (^)(BOOL success))completion
{
    static NSString * const kAppIdKey = @"appId";

    // appId 优先取传入配置，未传时使用内置默认值（后续由配置下发替换）
    NSString *appId = adnConfig[kAppIdKey] ?: @"5431421";

    // 与开屏/激励 Adapter 各自持有静态去重变量，但底层 BUAdSDKManager 启动幂等，
    // 多注册场景下由注册中心去重保证只调度一次
    if (_csjNativeSDKInitialized) {
        if (completion) {
            completion(YES);
        }
        return;
    }

    BUAdSDKConfiguration *configuration = [BUAdSDKConfiguration configuration];
    configuration.appID = appId;

    [BUAdSDKManager startWithAsyncCompletionHandler:^(BOOL success, NSError *error) {
        _csjNativeSDKInitialized = success;
        if (success) {
            ADXLogInfo(@"穿山甲 SDK 启动成功（信息流 Adapter），appId: %@", appId);
        } else {
            ADXLogError(@"穿山甲 SDK 启动失败（信息流 Adapter），error: %@", error);
        }
        if (completion) {
            completion(success);
        }
    }];
}

#pragma mark - ADXAdapter

- (void)loadAdWithSourceInfo:(ADXAdSourceInfo *)sourceInfo
                  completion:(void (^)(ADXBidResult *result))completion
{
    self.currentSourceInfo = sourceInfo;
    self.loadCompletion = completion;

    BUAdSlot *slot = [[BUAdSlot alloc] init];
    slot.ID = sourceInfo.placementId;
    slot.AdType = BUAdSlotAdTypeFeed;
    slot.position = BUAdSlotPositionFeed;
    slot.imgSize = [BUSize sizeBy:BUProposalSize_Feed690_388];
    slot.supportRenderControl = YES;

    CGFloat adWidth = sourceInfo.adWidth > 0 ? sourceInfo.adWidth : CGRectGetWidth([UIScreen mainScreen].bounds);
    CGSize adSize = CGSizeMake(adWidth, 0.0);
    self.nativeExpressAdManager = [[BUNativeExpressAdManager alloc] initWithSlot:slot adSize:adSize];
    self.nativeExpressAdManager.delegate = self;
    [self.nativeExpressAdManager loadAdDataWithCount:1];
}

- (void)notifyWinWithCostPrice:(NSInteger)costPrice
                     lossPrice:(NSInteger)lossPrice
{
    if (!self.nativeExpressAdView) {
        return;
    }

    // 穿山甲 BUAdClientBiddingProtocol：先设置实际结算价，再通知竞胜（传第二名出价）
    [self.nativeExpressAdView setPrice:@(costPrice)];
    [self.nativeExpressAdView win:@(lossPrice)];
}

- (void)notifyLossWithWinPrice:(NSInteger)winPrice
                    lossReason:(NSInteger)lossReason
                   winnerAdnId:(NSString *)winnerAdnId
{
    if (!self.nativeExpressAdView) {
        return;
    }

    // 穿山甲 lossReason 为字符串，直接透传引擎的原因码
    NSString *reason = [NSString stringWithFormat:@"%ld", (long)lossReason];
    [self.nativeExpressAdView loss:@(winPrice) lossReason:reason winBidder:winnerAdnId];

    // 竞败释放资源
    [self cleanupAd];
}

- (void)renderNativeAdViewWithResult:(ADXBidResult *)result
                    rootViewController:(UIViewController *)rootViewController
                            completion:(void (^)(UIView * _Nullable adView, NSError * _Nullable error))completion
{
    // 预检：广告视图已释放（可能已被竞败清理）或渲染控制器为空
    if (!self.nativeExpressAdView || !rootViewController) {
        ADXLogError(@"%@ 渲染失败：广告视图已释放或渲染控制器为空", result.sourceId);
        completion(nil, [NSError errorWithDomain:@"ADXCSJNativeExpressAdapter"
                                            code:-1
                                        userInfo:@{NSLocalizedDescriptionKey: @"广告视图已释放或渲染控制器为空"}]);
        return;
    }

    self.renderCompletion = completion;
    // 穿山甲模板广告落地页由视图内部处理，rootViewController 必须在 render 前设置
    self.nativeExpressAdView.rootViewController = rootViewController;
    [self.nativeExpressAdView render];
}

#pragma mark - BUNativeExpressAdViewDelegate

- (void)nativeExpressAdSuccessToLoad:(BUNativeExpressAdManager *)nativeExpressAdManager views:(NSArray<__kindof BUNativeExpressAdView *> *)views
{
    if (!self.loadCompletion) {
        return;
    }

    BUNativeExpressAdView *adView = views.firstObject;
    if (!adView) {
        ADXLogError(@"%@ 加载成功但返回空视图数组（穿山甲）", self.currentSourceInfo.sourceId);
        [self deliverResultWithSuccess:NO price:0 error:[NSError errorWithDomain:@"ADXCSJNativeExpressAdapter"
                                                                             code:-1
                                                                         userInfo:@{NSLocalizedDescriptionKey: @"加载成功但返回空视图数组"}]];
        return;
    }
    self.nativeExpressAdView = adView;

    // 穿山甲瀑布源无实时价格 API，使用预设 floorEcpm 作为比价价格（与开屏/激励 Adapter 一致）
    ADXLogInfo(@"%@ 加载成功：无实时价，使用 floor=%ld（瀑布源，穿山甲）",
               self.currentSourceInfo.sourceId, (long)self.currentSourceInfo.floorEcpm);
    [self deliverResultWithSuccess:YES price:self.currentSourceInfo.floorEcpm error:nil];
}

- (void)nativeExpressAdFailToLoad:(BUNativeExpressAdManager *)nativeExpressAdManager error:(NSError *)error
{
    if (!self.loadCompletion) {
        return;
    }

    ADXLogError(@"%@ 加载失败（穿山甲）：%@", self.currentSourceInfo.sourceId, error);
    [self deliverResultWithSuccess:NO price:0 error:error];
}

- (void)nativeExpressAdViewRenderSuccess:(BUNativeExpressAdView *)nativeExpressAdView
{
    if (!self.renderCompletion) {
        return;
    }

    ADXLogInfo(@"%@ 信息流渲染成功（穿山甲），高度 %.0f", self.currentSourceInfo.sourceId, CGRectGetHeight(nativeExpressAdView.bounds));
    self.renderCompletion(nativeExpressAdView, nil);
    self.renderCompletion = nil;
}

- (void)nativeExpressAdViewRenderFail:(BUNativeExpressAdView *)nativeExpressAdView error:(NSError *)error
{
    if (!self.renderCompletion) {
        return;
    }

    ADXLogError(@"%@ 信息流渲染失败（穿山甲）：%@", self.currentSourceInfo.sourceId, error);
    self.renderCompletion(nil, error ?: [NSError errorWithDomain:@"ADXCSJNativeExpressAdapter"
                                                            code:-2
                                                        userInfo:@{NSLocalizedDescriptionKey: @"信息流模板渲染失败"}]);
    self.renderCompletion = nil;
}

- (void)nativeExpressAdViewWillShow:(BUNativeExpressAdView *)nativeExpressAdView
{
    ADXLogInfo(@"%@ 信息流已曝光（穿山甲）", self.currentSourceInfo.sourceId);
}

- (void)nativeExpressAdViewDidClick:(BUNativeExpressAdView *)nativeExpressAdView
{
    ADXLogInfo(@"%@ 信息流被点击（穿山甲）", self.currentSourceInfo.sourceId);
}

- (void)nativeExpressAdViewDidRemoved:(BUNativeExpressAdView *)nativeExpressAdView
{
    ADXLogInfo(@"%@ 信息流被移除（穿山甲）", self.currentSourceInfo.sourceId);
    [self cleanupAd];
}

#pragma mark - Private

/// 统一出口：回调引擎并清理 completion
- (void)deliverResultWithSuccess:(BOOL)success price:(NSInteger)price error:(NSError *)error
{
    if (!self.loadCompletion) {
        return;
    }

    ADXBidResult *result = [ADXBidResult resultWithSourceId:self.currentSourceInfo.sourceId
                                                     adType:self.currentSourceInfo.adType
                                                      price:price
                                                   adObject:success ? self.nativeExpressAdView : nil
                                                    success:success
                                                      error:error];
    self.loadCompletion(result);
    self.loadCompletion = nil;

    if (!success) {
        [self cleanupAd];
    }
}

- (void)cleanupAd
{
    self.nativeExpressAdManager.delegate = nil;
    self.nativeExpressAdManager = nil;
    self.nativeExpressAdView = nil;
}

@end
