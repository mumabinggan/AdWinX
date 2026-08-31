//
//  ADXSigmobRewardVideoAdapter.m
//  AdWinX
//
//  Created by AdWinX on 2026/08/30.
//

#import "ADXSigmobRewardVideoAdapter.h"
#import "ADXAdSourceInfo.h"
#import "ADXBidResult.h"
#import "ADXLogger.h"
#import <WindSDK/WindSDK.h>

static BOOL _sigmobRewardSDKInitialized = NO;

@interface ADXSigmobRewardVideoAdapter () <WindRewardVideoAdDelegate>

@property (nonatomic, strong, nullable) WindRewardVideoAd *rewardVideoAd;
@property (nonatomic, copy, nullable) void (^loadCompletion)(ADXBidResult *result);
@property (nonatomic, strong, nullable) ADXAdSourceInfo *currentSourceInfo;
/// 展示结果回调（展示失败降级用）：曝光成功回 YES，展示失败/预检失败回 NO
@property (nonatomic, copy, nullable) void (^showCompletion)(BOOL success, NSError * _Nullable error);
/// 激励达成回调（业务发奖用）
@property (nonatomic, copy, nullable) void (^rewardCallback)(BOOL granted);

@end

@implementation ADXSigmobRewardVideoAdapter

#pragma mark - SDK Initialization

+ (void)setupSDKWithConfig:(NSDictionary *)adnConfig
{
    [self setupSDKWithConfig:adnConfig completion:NULL];
}

+ (void)setupSDKWithConfig:(NSDictionary *)adnConfig
                completion:(nullable void (^)(BOOL success))completion
{
    static NSString * const kAppIdKey = @"appId";
    static NSString * const kAppKeyKey = @"appKey";

    // Sigmob 初始化需要 appId + appKey，优先取传入配置，未传时使用内置默认值
    NSString *appId = adnConfig[kAppIdKey] ?: @"81230";
    NSString *appKey = adnConfig[kAppKeyKey] ?: @"683ddbddb6f99627";

    // 与开屏 Adapter 各自持有静态去重变量，但底层 WindAds 启动幂等，
    // 双注册场景下（开屏 + 激励视频）由注册中心去重保证只调度一次
    if (_sigmobRewardSDKInitialized) {
        if (completion) {
            completion(YES);
        }
        return;
    }

    WindAdOptions *options = [[WindAdOptions alloc] initWithAppId:appId appKey:appKey];
    [WindAds startWithOptions:options];
    _sigmobRewardSDKInitialized = YES;
    ADXLogInfo(@"Sigmob SDK 启动完成（激励视频 Adapter），appId: %@", appId);

    // Sigmob 初始化为同步完成，直接回调就绪
    if (completion) {
        completion(YES);
    }
}

#pragma mark - ADXAdapter

- (void)loadAdWithSourceInfo:(ADXAdSourceInfo *)sourceInfo
                  completion:(void (^)(ADXBidResult *result))completion
{
    self.currentSourceInfo = sourceInfo;
    self.loadCompletion = completion;

    WindAdRequest *request = [WindAdRequest request];
    request.placementId = sourceInfo.placementId;
    self.rewardVideoAd = [[WindRewardVideoAd alloc] initWithRequest:request];
    self.rewardVideoAd.delegate = self;
    [self.rewardVideoAd loadAdData];
}

- (void)notifyWinWithCostPrice:(NSInteger)costPrice
                     lossPrice:(NSInteger)lossPrice
{
    if (!self.rewardVideoAd) {
        return;
    }

    NSDictionary *winInfo = @{
        @"AUCTION_PRICE": @(costPrice),
        @"HIGHEST_LOSS_PRICE": @(lossPrice),
    };
    [self.rewardVideoAd sendWinNotificationWithInfo:winInfo];
}

- (void)notifyLossWithWinPrice:(NSInteger)winPrice
                    lossReason:(NSInteger)lossReason
                   winnerAdnId:(NSString *)winnerAdnId
{
    if (!self.rewardVideoAd) {
        return;
    }

    NSDictionary *lossInfo = @{
        @"AUCTION_PRICE": @(winPrice),
        @"LOSS_REASON": @([self sigmobLossReasonFromADXReason:lossReason]),
        @"ADN_ID": @([self sigmobAdnIdFromAdnName:winnerAdnId]),
    };
    [self.rewardVideoAd sendLossNotificationWithInfo:lossInfo];

    // 竞败释放资源
    self.rewardVideoAd.delegate = nil;
    self.rewardVideoAd = nil;
}

- (void)showRewardVideoAdWithResult:(ADXBidResult *)result
                 fromViewController:(UIViewController *)rootViewController
                      rewardCallback:(nullable void (^)(BOOL granted))rewardCallback
                          completion:(void (^)(BOOL success, NSError * _Nullable error))completion
{
    // 预检：广告对象已释放（可能已被竞败清理）或未就绪，立即回 NO 触发上层降级
    if (!self.rewardVideoAd || !rootViewController) {
        NSError *error = [NSError errorWithDomain:@"ADXSigmobRewardVideoAdapter"
                                             code:-1
                                         userInfo:@{NSLocalizedDescriptionKey: @"广告对象已释放或展示控制器为空"}];
        completion(NO, error);
        return;
    }
    if (!self.rewardVideoAd.isAdReady) {
        NSError *error = [NSError errorWithDomain:@"ADXSigmobRewardVideoAdapter"
                                             code:-2
                                         userInfo:@{NSLocalizedDescriptionKey: @"广告未就绪或已失效"}];
        completion(NO, error);
        return;
    }

    self.showCompletion = completion;
    self.rewardCallback = rewardCallback;
    [self.rewardVideoAd showAdFromRootViewController:rootViewController options:nil];
}

#pragma mark - WindRewardVideoAdDelegate

- (void)rewardVideoAdDidLoad:(WindRewardVideoAd *)rewardVideoAd
{
    if (!self.loadCompletion) {
        return;
    }

    // 瀑布源：优先实时 eCPM（单位：分），无权限访问时 fallback 到预设 floorEcpm
    NSString *ecpm = [rewardVideoAd getEcpm];
    NSInteger price = ecpm.length > 0 ? ecpm.integerValue : self.currentSourceInfo.floorEcpm;
    ADXLogInfo(@"%@ 加载成功：实时 eCPM=%@（%@）",
               self.currentSourceInfo.sourceId,
               ecpm.length > 0 ? ecpm : @"无",
               ecpm.length > 0 ? @"实时价" : [NSString stringWithFormat:@"无实时价，使用 floor=%ld（瀑布源）", (long)self.currentSourceInfo.floorEcpm]);
    [self deliverResultWithSuccess:YES price:price error:nil];
}

- (void)rewardVideoAdDidLoad:(WindRewardVideoAd *)rewardVideoAd didFailWithError:(NSError *)error
{
    if (!self.loadCompletion) {
        return;
    }

    ADXLogError(@"%@ 加载失败（Sigmob）：%@", self.currentSourceInfo.sourceId, error);
    [self deliverResultWithSuccess:NO price:0 error:error];
}

- (void)rewardVideoAdDidVisible:(WindRewardVideoAd *)rewardVideoAd
{
    ADXLogInfo(@"%@ 激励视频已曝光（Sigmob）", self.currentSourceInfo.sourceId);
    if (self.showCompletion) {
        self.showCompletion(YES, nil);
        self.showCompletion = nil;
    }
}

- (void)rewardVideoAdDidShowFailed:(WindRewardVideoAd *)rewardVideoAd error:(NSError *)error
{
    ADXLogError(@"%@ 激励视频展示失败（Sigmob）：%@", self.currentSourceInfo.sourceId, error);
    // 展示失败：回 NO 供上层降级到次高价候选
    if (self.showCompletion) {
        self.showCompletion(NO, error);
        self.showCompletion = nil;
    }
    [self cleanupAd];
}

- (void)rewardVideoAdDidClick:(WindRewardVideoAd *)rewardVideoAd
{
    ADXLogInfo(@"%@ 激励视频被点击（Sigmob）", self.currentSourceInfo.sourceId);
}

- (void)rewardVideoAd:(WindRewardVideoAd *)rewardVideoAd reward:(WindRewardInfo *)reward
{
    ADXLogInfo(@"%@ 激励达成（Sigmob）：%@", self.currentSourceInfo.sourceId, reward);
    if (self.rewardCallback) {
        self.rewardCallback(YES);
        self.rewardCallback = nil;
    }
}

- (void)rewardVideoAdDidPlayFinish:(WindRewardVideoAd *)rewardVideoAd didFailWithError:(NSError *)error
{
    if (error) {
        ADXLogError(@"%@ 激励视频播放失败（Sigmob）：%@", self.currentSourceInfo.sourceId, error);
    } else {
        ADXLogInfo(@"%@ 激励视频播放完成（Sigmob）", self.currentSourceInfo.sourceId);
    }
}

- (void)rewardVideoAdDidClose:(WindRewardVideoAd *)rewardVideoAd
{
    ADXLogInfo(@"%@ 激励视频已关闭（Sigmob）", self.currentSourceInfo.sourceId);
    // 关闭时若激励回调尚未触发（用户提前关闭未看完），补发 granted=NO 供业务区分
    if (self.rewardCallback) {
        self.rewardCallback(NO);
        self.rewardCallback = nil;
    }
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
                                                   adObject:success ? self.rewardVideoAd : nil
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
    self.rewardVideoAd.delegate = nil;
    self.rewardVideoAd = nil;
}

/// ADXLossReason → Sigmob WindAdBiddingLossReason
- (NSInteger)sigmobLossReasonFromADXReason:(NSInteger)lossReason
{
    switch (lossReason) {
        case ADXLossReasonLowPrice:
            return WindAdBiddingLossReasonLowPrice;
        case ADXLossReasonTimeout:
            return WindAdBiddingLossReasonLoadTimeout;
        default:
            return WindAdBiddingLossReasonOther;
    }
}

/// ADN 名称 → Sigmob 渠道 ID（1 sigmob / 2 穿山甲 / 3 腾讯广告 / 4 快手 / 5 百度 / 10001 其他）
- (NSInteger)sigmobAdnIdFromAdnName:(NSString *)adnName
{
    if ([adnName isEqualToString:@"Sigmob"]) {
        return 1;
    }
    if ([adnName isEqualToString:@"CSJ"]) {
        return 2;
    }
    if ([adnName isEqualToString:@"GDT"]) {
        return 3;
    }
    if ([adnName isEqualToString:@"Baidu"]) {
        return 5;
    }
    return 10001;
}

@end
