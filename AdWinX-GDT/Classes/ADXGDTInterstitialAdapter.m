//
//  ADXGDTInterstitialAdapter.m
//  AdWinX
//
//  Created by AdWinX on 2026/08/31.
//

#import "ADXGDTInterstitialAdapter.h"
#import "ADXAdSourceInfo.h"
#import "ADXBidResult.h"
#import "ADXLogger.h"
#import <GDTMobSDK/GDTUnifiedInterstitialAd.h>
#import <GDTMobSDK/GDTSDKConfig.h>

static BOOL _gdtInterstitialSDKInitialized = NO;

@interface ADXGDTInterstitialAdapter () <GDTUnifiedInterstitialAdDelegate>

@property (nonatomic, strong, nullable) GDTUnifiedInterstitialAd *interstitialAd;
@property (nonatomic, copy, nullable) void (^loadCompletion)(ADXBidResult *result);
@property (nonatomic, strong, nullable) ADXAdSourceInfo *currentSourceInfo;
/// 展示结果回调（展示失败降级用）：展示成功回 YES，展示失败/预检失败回 NO
@property (nonatomic, copy, nullable) void (^showCompletion)(BOOL success, NSError * _Nullable error);

@end

@implementation ADXGDTInterstitialAdapter

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
    if (_gdtInterstitialSDKInitialized) {
        if (completion) {
            completion(YES);
        }
        return;
    }

    BOOL initSuccess = [GDTSDKConfig initWithAppId:appId];
    if (!initSuccess) {
        ADXLogError(@"优量汇 SDK initWithAppId 失败（插屏 Adapter），appId: %@", appId);
        if (completion) {
            completion(NO);
        }
        return;
    }

    [GDTSDKConfig startWithCompletionHandler:^(BOOL success, NSError *error) {
        _gdtInterstitialSDKInitialized = success;
        if (success) {
            ADXLogInfo(@"优量汇 SDK 启动成功（插屏 Adapter），appId: %@", appId);
        } else {
            ADXLogError(@"优量汇 SDK 启动失败（插屏 Adapter），error: %@", error);
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

    self.interstitialAd = [[GDTUnifiedInterstitialAd alloc] initWithPlacementId:sourceInfo.placementId];
    self.interstitialAd.delegate = self;
    [self.interstitialAd loadAd];
}

- (void)notifyWinWithCostPrice:(NSInteger)costPrice
                     lossPrice:(NSInteger)lossPrice
{
    if (!self.interstitialAd) {
        return;
    }

    NSDictionary *winInfo = @{
        GDT_M_W_E_COST_PRICE: @(costPrice),
        GDT_M_W_H_LOSS_PRICE: @(lossPrice),
    };
    [self.interstitialAd sendWinNotificationWithInfo:winInfo];
}

- (void)notifyLossWithWinPrice:(NSInteger)winPrice
                    lossReason:(NSInteger)lossReason
                   winnerAdnId:(NSString *)winnerAdnId
{
    if (!self.interstitialAd) {
        return;
    }

    NSDictionary *lossInfo = @{
        GDT_M_L_WIN_PRICE: @(winPrice),
        GDT_M_L_LOSS_REASON: @(lossReason),
        GDT_M_ADNID: winnerAdnId ?: @"",
    };
    [self.interstitialAd sendLossNotificationWithInfo:lossInfo];

    // 竞败释放资源
    self.interstitialAd.delegate = nil;
    self.interstitialAd = nil;
}

- (void)showInterstitialAdWithResult:(ADXBidResult *)result
                  fromViewController:(UIViewController *)rootViewController
                          completion:(void (^)(BOOL success, NSError * _Nullable error))completion
{
    // 预检：广告对象已释放（可能已被竞败清理）、过期/失效或展示控制器为空
    if (!self.interstitialAd || !rootViewController) {
        ADXLogError(@"%@ 展示失败：广告对象已释放或展示控制器为空", result.sourceId);
        completion(NO, [NSError errorWithDomain:@"ADXGDTInterstitialAdapter"
                                            code:-1
                                        userInfo:@{NSLocalizedDescriptionKey: @"广告对象已释放或展示控制器为空"}]);
        return;
    }
    if (![self.interstitialAd isAdValid]) {
        ADXLogError(@"%@ 展示失败：广告已过期或失效", result.sourceId);
        completion(NO, [NSError errorWithDomain:@"ADXGDTInterstitialAdapter"
                                            code:-2
                                        userInfo:@{NSLocalizedDescriptionKey: @"广告已过期或失效"}]);
        return;
    }

    self.showCompletion = completion;
    // present 无返回值，展示成败由 unifiedInterstitialDidPresentScreen / FailToPresent 回调
    [self.interstitialAd presentAdFromRootViewController:rootViewController];
}

#pragma mark - GDTUnifiedInterstitialAdDelegate

- (void)unifiedInterstitialSuccessToLoadAd:(GDTUnifiedInterstitialAd *)unifiedInterstitial
{
    if (!self.loadCompletion) {
        return;
    }

    NSInteger eCPM = [unifiedInterstitial eCPM];
    NSInteger price;
    if (self.currentSourceInfo.runtimeMode == ADXRuntimeModeBidding) {
        // 竞价源：必须用实时 eCPM，取不到（-1）则按失败处理
        if (eCPM < 0) {
            ADXLogError(@"%@ 加载成功但实时 eCPM 获取失败（竞价源）", self.currentSourceInfo.sourceId);
            [self deliverResultWithSuccess:NO price:0 error:[NSError errorWithDomain:@"ADXGDTInterstitialAdapter"
                                                                                 code:-2
                                                                             userInfo:@{NSLocalizedDescriptionKey: @"竞价源实时 eCPM 获取失败"}]];
            return;
        }
        price = eCPM;
        ADXLogInfo(@"%@ 加载成功：实时 eCPM=%ld（竞价源）", self.currentSourceInfo.sourceId, (long)price);
    } else {
        // 瀑布源：优先真实 eCPM，无权限时 fallback 到预设 floorEcpm
        price = eCPM >= 0 ? eCPM : self.currentSourceInfo.floorEcpm;
        ADXLogInfo(@"%@ 加载成功：实时 eCPM=%ld（%@）",
                   self.currentSourceInfo.sourceId,
                   (long)price,
                   eCPM >= 0 ? @"瀑布源" : [NSString stringWithFormat:@"无实时价，使用 floor=%ld（瀑布源）", (long)self.currentSourceInfo.floorEcpm]);
    }

    [self deliverResultWithSuccess:YES price:price error:nil];
}

- (void)unifiedInterstitialFailToLoadAd:(GDTUnifiedInterstitialAd *)unifiedInterstitial error:(NSError *)error
{
    if (!self.loadCompletion) {
        return;
    }

    ADXLogError(@"%@ 加载失败（GDT）：%@", self.currentSourceInfo.sourceId, error);
    [self deliverResultWithSuccess:NO price:0 error:error];
}

- (void)unifiedInterstitialDidDownloadVideo:(GDTUnifiedInterstitialAd *)unifiedInterstitial
{
    ADXLogInfo(@"%@ 插屏视频缓存完成（GDT）", self.currentSourceInfo.sourceId);
}

- (void)unifiedInterstitialRenderSuccess:(GDTUnifiedInterstitialAd *)unifiedInterstitial
{
    ADXLogInfo(@"%@ 插屏渲染成功（GDT）", self.currentSourceInfo.sourceId);
}

- (void)unifiedInterstitialRenderFail:(GDTUnifiedInterstitialAd *)unifiedInterstitial error:(NSError *)error
{
    ADXLogError(@"%@ 插屏渲染失败（GDT）：%@", self.currentSourceInfo.sourceId, error);
    // 渲染失败即广告不可展示：若加载回调尚未消费按加载失败处理；若在展示等待期则回 NO 供上层降级
    if (self.loadCompletion) {
        [self deliverResultWithSuccess:NO price:0 error:error];
        return;
    }
    if (self.showCompletion) {
        self.showCompletion(NO, error);
        self.showCompletion = nil;
    }
    [self cleanupAd];
}

- (void)unifiedInterstitialDidPresentScreen:(GDTUnifiedInterstitialAd *)unifiedInterstitial
{
    ADXLogInfo(@"%@ 插屏已展示（GDT）", self.currentSourceInfo.sourceId);
    if (self.showCompletion) {
        self.showCompletion(YES, nil);
        self.showCompletion = nil;
    }
}

- (void)unifiedInterstitialFailToPresent:(GDTUnifiedInterstitialAd *)unifiedInterstitial error:(NSError *)error
{
    ADXLogError(@"%@ 插屏展示失败（GDT）：%@", self.currentSourceInfo.sourceId, error);
    if (self.showCompletion) {
        self.showCompletion(NO, error);
        self.showCompletion = nil;
    }
    [self cleanupAd];
}

- (void)unifiedInterstitialWillExposure:(GDTUnifiedInterstitialAd *)unifiedInterstitial
{
}

- (void)unifiedInterstitialClicked:(GDTUnifiedInterstitialAd *)unifiedInterstitial
{
    ADXLogInfo(@"%@ 插屏被点击（GDT）", self.currentSourceInfo.sourceId);
}

- (void)unifiedInterstitialDidDismissScreen:(GDTUnifiedInterstitialAd *)unifiedInterstitial
{
    ADXLogInfo(@"%@ 插屏已关闭（GDT）", self.currentSourceInfo.sourceId);
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
                                                   adObject:success ? self.interstitialAd : nil
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
    self.interstitialAd.delegate = nil;
    self.interstitialAd = nil;
}

@end
