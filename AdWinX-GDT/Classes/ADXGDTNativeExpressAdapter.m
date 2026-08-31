//
//  ADXGDTNativeExpressAdapter.m
//  AdWinX
//
//  Created by AdWinX on 2026/08/31.
//

#import "ADXGDTNativeExpressAdapter.h"
#import "ADXAdSourceInfo.h"
#import "ADXBidResult.h"
#import "ADXLogger.h"
#import <GDTMobSDK/GDTNativeExpressAd.h>
#import <GDTMobSDK/GDTNativeExpressAdView.h>
#import <GDTMobSDK/GDTSDKConfig.h>
#import <GDTMobSDK/GDTAdProtocol.h>
#import <UIKit/UIKit.h>

static BOOL _gdtNativeSDKInitialized = NO;

@interface ADXGDTNativeExpressAdapter () <GDTNativeExpressAdDelegete>

@property (nonatomic, strong, nullable) GDTNativeExpressAd *nativeExpressAd;
@property (nonatomic, strong, nullable) GDTNativeExpressAdView *nativeExpressAdView;
@property (nonatomic, copy, nullable) void (^loadCompletion)(ADXBidResult *result);
/// 渲染结果回调（render 异步，成功/失败时各回调一次后清空）
@property (nonatomic, copy, nullable) void (^renderCompletion)(UIView * _Nullable adView, NSError * _Nullable error);
@property (nonatomic, strong, nullable) ADXAdSourceInfo *currentSourceInfo;

@end

@implementation ADXGDTNativeExpressAdapter

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
    NSString *appId = adnConfig[kAppIdKey] ?: @"1219134196";

    // 与开屏/激励 Adapter 各自持有静态去重变量，但底层 GDTSDKConfig 启动幂等，
    // 多注册场景下由注册中心去重保证只调度一次
    if (_gdtNativeSDKInitialized) {
        if (completion) {
            completion(YES);
        }
        return;
    }

    BOOL initSuccess = [GDTSDKConfig initWithAppId:appId];
    if (!initSuccess) {
        ADXLogError(@"优量汇 SDK initWithAppId 失败（信息流 Adapter），appId: %@", appId);
        if (completion) {
            completion(NO);
        }
        return;
    }

    [GDTSDKConfig startWithCompletionHandler:^(BOOL success, NSError *error) {
        _gdtNativeSDKInitialized = success;
        if (success) {
            ADXLogInfo(@"优量汇 SDK 启动成功（信息流 Adapter），appId: %@", appId);
        } else {
            ADXLogError(@"优量汇 SDK 启动失败（信息流 Adapter），error: %@", error);
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

    CGFloat adWidth = sourceInfo.adWidth > 0 ? sourceInfo.adWidth : CGRectGetWidth([UIScreen mainScreen].bounds);
    CGSize adSize = CGSizeMake(adWidth, 0.0);
    self.nativeExpressAd = [[GDTNativeExpressAd alloc] initWithPlacementId:sourceInfo.placementId
                                                                     adSize:adSize];
    self.nativeExpressAd.delegate = self;
    [self.nativeExpressAd loadAd:1];
}

- (void)notifyWinWithCostPrice:(NSInteger)costPrice
                     lossPrice:(NSInteger)lossPrice
{
    if (!self.nativeExpressAdView) {
        return;
    }

    // 客户端竞价竞胜上报：setBidECPM 上报实际扣费价 + sendWinNotification 携带次高价（单位：分）
    [self.nativeExpressAdView setBidECPM:costPrice];
    NSDictionary *winInfo = @{
        GDT_M_W_E_COST_PRICE: @(costPrice),
        GDT_M_W_H_LOSS_PRICE: @(lossPrice),
    };
    [self.nativeExpressAdView sendWinNotificationWithInfo:winInfo];
}

- (void)notifyLossWithWinPrice:(NSInteger)winPrice
                    lossReason:(NSInteger)lossReason
                   winnerAdnId:(NSString *)winnerAdnId
{
    if (!self.nativeExpressAdView) {
        return;
    }

    NSDictionary *lossInfo = @{
        GDT_M_L_WIN_PRICE: @(winPrice),
        GDT_M_L_LOSS_REASON: @(lossReason),
        GDT_M_ADNID: winnerAdnId ?: @"",
    };
    [self.nativeExpressAdView sendLossNotificationWithInfo:lossInfo];

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
        completion(nil, [NSError errorWithDomain:@"ADXGDTNativeExpressAdapter"
                                            code:-1
                                        userInfo:@{NSLocalizedDescriptionKey: @"广告视图已释放或渲染控制器为空"}]);
        return;
    }
    // 预检：广告过期/失效（竞胜后长期未渲染）
    if (![self.nativeExpressAdView isAdValid]) {
        ADXLogError(@"%@ 渲染失败：广告已过期或失效", result.sourceId);
        completion(nil, [NSError errorWithDomain:@"ADXGDTNativeExpressAdapter"
                                            code:-2
                                        userInfo:@{NSLocalizedDescriptionKey: @"广告已过期或失效"}]);
        return;
    }

    self.renderCompletion = completion;
    // GDT 模板广告落地页由视图内部处理，controller 必须在 render 前设置
    self.nativeExpressAdView.controller = rootViewController;
    [self.nativeExpressAdView render];
}

#pragma mark - GDTNativeExpressAdDelegete

- (void)nativeExpressAdSuccessToLoad:(GDTNativeExpressAd *)nativeExpressAd views:(NSArray<__kindof GDTNativeExpressAdView *> *)views
{
    if (!self.loadCompletion) {
        return;
    }

    GDTNativeExpressAdView *adView = views.firstObject;
    if (!adView) {
        ADXLogError(@"%@ 加载成功但返回空视图数组（GDT）", self.currentSourceInfo.sourceId);
        [self deliverResultWithSuccess:NO price:0 error:[NSError errorWithDomain:@"ADXGDTNativeExpressAdapter"
                                                                             code:-1
                                                                         userInfo:@{NSLocalizedDescriptionKey: @"加载成功但返回空视图数组"}]];
        return;
    }
    self.nativeExpressAdView = adView;

    NSInteger eCPM = [adView eCPM];
    NSInteger price;
    if (self.currentSourceInfo.runtimeMode == ADXRuntimeModeBidding) {
        // 竞价源：必须用实时 eCPM，取不到（-1）则按失败处理
        if (eCPM < 0) {
            ADXLogError(@"%@ 加载成功但实时 eCPM 获取失败（竞价源）", self.currentSourceInfo.sourceId);
            [self deliverResultWithSuccess:NO price:0 error:[NSError errorWithDomain:@"ADXGDTNativeExpressAdapter"
                                                                                 code:-2
                                                                             userInfo:@{NSLocalizedDescriptionKey: @"竞价源实时 eCPM 获取失败"}]];
            return;
        }
        price = eCPM;
        ADXLogInfo(@"%@ 加载成功：实时 eCPM=%ld（竞价源，GDT）", self.currentSourceInfo.sourceId, (long)price);
    } else {
        // 瀑布源：优先真实 eCPM，无权限时 fallback 到预设 floorEcpm
        price = eCPM >= 0 ? eCPM : self.currentSourceInfo.floorEcpm;
        ADXLogInfo(@"%@ 加载成功：eCPM=%ld（%@）",
                   self.currentSourceInfo.sourceId,
                   (long)price,
                   eCPM >= 0 ? @"实时价" : [NSString stringWithFormat:@"无实时价，使用 floor=%ld（瀑布源）", (long)self.currentSourceInfo.floorEcpm]);
    }

    [self deliverResultWithSuccess:YES price:price error:nil];
}

- (void)nativeExpressAdFailToLoad:(GDTNativeExpressAd *)nativeExpressAd error:(NSError *)error
{
    if (!self.loadCompletion) {
        return;
    }

    ADXLogError(@"%@ 加载失败（GDT）：%@", self.currentSourceInfo.sourceId, error);
    [self deliverResultWithSuccess:NO price:0 error:error];
}

- (void)nativeExpressAdViewRenderSuccess:(GDTNativeExpressAdView *)nativeExpressAdView
{
    if (!self.renderCompletion) {
        return;
    }

    ADXLogInfo(@"%@ 信息流渲染成功（GDT），高度 %.0f", self.currentSourceInfo.sourceId, CGRectGetHeight(nativeExpressAdView.bounds));
    self.renderCompletion(nativeExpressAdView, nil);
    self.renderCompletion = nil;
}

- (void)nativeExpressAdViewRenderFail:(GDTNativeExpressAdView *)nativeExpressAdView
{
    if (!self.renderCompletion) {
        return;
    }

    ADXLogError(@"%@ 信息流渲染失败（GDT）", self.currentSourceInfo.sourceId);
    self.renderCompletion(nil, [NSError errorWithDomain:@"ADXGDTNativeExpressAdapter"
                                                   code:-3
                                               userInfo:@{NSLocalizedDescriptionKey: @"信息流模板渲染失败"}]);
    self.renderCompletion = nil;
}

- (void)nativeExpressAdViewExposure:(GDTNativeExpressAdView *)nativeExpressAdView
{
    ADXLogInfo(@"%@ 信息流已曝光（GDT）", self.currentSourceInfo.sourceId);
}

- (void)nativeExpressAdViewClicked:(GDTNativeExpressAdView *)nativeExpressAdView
{
    ADXLogInfo(@"%@ 信息流被点击（GDT）", self.currentSourceInfo.sourceId);
}

- (void)nativeExpressAdViewClosed:(GDTNativeExpressAdView *)nativeExpressAdView
{
    ADXLogInfo(@"%@ 信息流被关闭（GDT）", self.currentSourceInfo.sourceId);
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
    self.nativeExpressAd.delegate = nil;
    self.nativeExpressAd = nil;
    self.nativeExpressAdView = nil;
}

@end
