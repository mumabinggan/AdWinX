//
//  ADXCSJInterstitialAdapter.m
//  AdWinX
//
//  Created by AdWinX on 2026/08/31.
//

#import "ADXCSJInterstitialAdapter.h"
#import "ADXAdSourceInfo.h"
#import "ADXBidResult.h"
#import "ADXLogger.h"
#import <BUAdSDK/BUAdSDK.h>

static BOOL _csjInterstitialSDKInitialized = NO;

@interface ADXCSJInterstitialAdapter () <BUNativeExpressFullscreenVideoAdDelegate>

@property (nonatomic, strong, nullable) BUNativeExpressFullscreenVideoAd *fullscreenVideoAd;
@property (nonatomic, copy, nullable) void (^loadCompletion)(ADXBidResult *result);
@property (nonatomic, strong, nullable) ADXAdSourceInfo *currentSourceInfo;

@end

@implementation ADXCSJInterstitialAdapter

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
    if (_csjInterstitialSDKInitialized) {
        if (completion) {
            completion(YES);
        }
        return;
    }

    BUAdSDKConfiguration *configuration = [BUAdSDKConfiguration configuration];
    configuration.appID = appId;

    [BUAdSDKManager startWithAsyncCompletionHandler:^(BOOL success, NSError *error) {
        _csjInterstitialSDKInitialized = success;
        if (success) {
            ADXLogInfo(@"穿山甲 SDK 启动成功（插屏 Adapter），appId: %@", appId);
        } else {
            ADXLogError(@"穿山甲 SDK 启动失败（插屏 Adapter），error: %@", error);
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

    self.fullscreenVideoAd = [[BUNativeExpressFullscreenVideoAd alloc] initWithSlotID:sourceInfo.placementId];
    self.fullscreenVideoAd.delegate = self;
    [self.fullscreenVideoAd loadAdData];
}

- (void)notifyWinWithCostPrice:(NSInteger)costPrice
                     lossPrice:(NSInteger)lossPrice
{
    if (!self.fullscreenVideoAd) {
        return;
    }

    // 穿山甲 BUAdClientBiddingProtocol：先设置实际结算价，再通知竞胜（传第二名出价）
    [self.fullscreenVideoAd setPrice:@(costPrice)];
    [self.fullscreenVideoAd win:@(lossPrice)];
}

- (void)notifyLossWithWinPrice:(NSInteger)winPrice
                    lossReason:(NSInteger)lossReason
                   winnerAdnId:(NSString *)winnerAdnId
{
    if (!self.fullscreenVideoAd) {
        return;
    }

    // 穿山甲 lossReason 为字符串，直接透传引擎的原因码
    NSString *reason = [NSString stringWithFormat:@"%ld", (long)lossReason];
    [self.fullscreenVideoAd loss:@(winPrice) lossReason:reason winBidder:winnerAdnId];
}

- (void)showInterstitialAdWithResult:(ADXBidResult *)result
                  fromViewController:(UIViewController *)rootViewController
                          completion:(void (^)(BOOL success, NSError * _Nullable error))completion
{
    // 预检：广告对象已释放（可能已被竞败清理）或展示控制器为空
    if (!self.fullscreenVideoAd || !rootViewController) {
        ADXLogError(@"%@ 展示失败：广告对象已释放或展示控制器为空", result.sourceId);
        completion(NO, [NSError errorWithDomain:@"ADXCSJInterstitialAdapter"
                                            code:-1
                                        userInfo:@{NSLocalizedDescriptionKey: @"广告对象已释放或展示控制器为空"}]);
        return;
    }

    // showAdFromRootViewController 返回 NO 即展示发起失败（未加载完/已过期），
    // 返回 YES 视为展示成功（穿山甲无独立的展示失败回调）
    BOOL shown = [self.fullscreenVideoAd showAdFromRootViewController:rootViewController];
    if (shown) {
        ADXLogInfo(@"%@ 插屏展示发起成功（穿山甲）", result.sourceId);
        completion(YES, nil);
    } else {
        ADXLogError(@"%@ 展示发起失败（穿山甲，showAd 返回 NO）", result.sourceId);
        completion(NO, [NSError errorWithDomain:@"ADXCSJInterstitialAdapter"
                                            code:-2
                                        userInfo:@{NSLocalizedDescriptionKey: @"展示发起失败（showAd 返回 NO）"}]);
    }
}

#pragma mark - BUNativeExpressFullscreenVideoAdDelegate

- (void)nativeExpressFullscreenVideoAdDidLoad:(BUNativeExpressFullscreenVideoAd *)fullscreenVideoAd
{
    if (!self.loadCompletion) {
        return;
    }

    // 穿山甲瀑布源无实时价格 API，使用预设 floorEcpm 作为比价价格（与开屏/激励 Adapter 一致）
    ADXLogInfo(@"%@ 加载成功：无实时价，使用 floor=%ld（瀑布源）",
               self.currentSourceInfo.sourceId, (long)self.currentSourceInfo.floorEcpm);
    ADXBidResult *result = [ADXBidResult resultWithSourceId:self.currentSourceInfo.sourceId
                                                     adType:self.currentSourceInfo.adType
                                                      price:self.currentSourceInfo.floorEcpm
                                                   adObject:fullscreenVideoAd
                                                    success:YES
                                                      error:nil];
    self.loadCompletion(result);
    self.loadCompletion = nil;
}

- (void)nativeExpressFullscreenVideoAd:(BUNativeExpressFullscreenVideoAd *)fullscreenVideoAd didFailWithError:(NSError *)error
{
    if (!self.loadCompletion) {
        return;
    }

    ADXLogError(@"%@ 加载失败（穿山甲）：%@", self.currentSourceInfo.sourceId, error);
    ADXBidResult *result = [ADXBidResult resultWithSourceId:self.currentSourceInfo.sourceId
                                                     adType:self.currentSourceInfo.adType
                                                      price:0
                                                   adObject:nil
                                                    success:NO
                                                      error:error];
    self.loadCompletion(result);
    self.loadCompletion = nil;
}

- (void)nativeExpressFullscreenVideoAdDidDownLoadVideo:(BUNativeExpressFullscreenVideoAd *)fullscreenVideoAd
{
    ADXLogInfo(@"%@ 插屏视频缓存完成（穿山甲）", self.currentSourceInfo.sourceId);
}

- (void)nativeExpressFullscreenVideoAdViewRenderSuccess:(BUNativeExpressFullscreenVideoAd *)fullscreenVideoAd
{
    ADXLogInfo(@"%@ 插屏渲染成功（穿山甲）", self.currentSourceInfo.sourceId);
}

- (void)nativeExpressFullscreenVideoAdViewRenderFail:(BUNativeExpressFullscreenVideoAd *)fullscreenVideoAd error:(NSError *)error
{
    ADXLogError(@"%@ 插屏渲染失败（穿山甲）：%@", self.currentSourceInfo.sourceId, error);
}

- (void)nativeExpressFullscreenVideoAdDidVisible:(BUNativeExpressFullscreenVideoAd *)fullscreenVideoAd
{
    ADXLogInfo(@"%@ 插屏已曝光（穿山甲）", self.currentSourceInfo.sourceId);
}

- (void)nativeExpressFullscreenVideoAdDidClick:(BUNativeExpressFullscreenVideoAd *)fullscreenVideoAd
{
    ADXLogInfo(@"%@ 插屏被点击（穿山甲）", self.currentSourceInfo.sourceId);
}

- (void)nativeExpressFullscreenVideoAdDidPlayFinish:(BUNativeExpressFullscreenVideoAd *)fullscreenVideoAd didFailWithError:(NSError *)error
{
    if (error) {
        ADXLogError(@"%@ 插屏播放失败（穿山甲）：%@", self.currentSourceInfo.sourceId, error);
    } else {
        ADXLogInfo(@"%@ 插屏播放完成（穿山甲）", self.currentSourceInfo.sourceId);
    }
}

- (void)nativeExpressFullscreenVideoAdDidClose:(BUNativeExpressFullscreenVideoAd *)fullscreenVideoAd
{
    ADXLogInfo(@"%@ 插屏已关闭（穿山甲）", self.currentSourceInfo.sourceId);
    [self cleanupAd];
}

#pragma mark - Private

- (void)cleanupAd
{
    self.fullscreenVideoAd.delegate = nil;
    self.fullscreenVideoAd = nil;
}

@end
