//
//  ADXSigmobInterstitialAdapter.m
//  AdWinX
//
//  Created by AdWinX on 2026/08/31.
//

#import "ADXSigmobInterstitialAdapter.h"
#import "ADXAdSourceInfo.h"
#import "ADXBidResult.h"
#import "ADXLogger.h"
#import <WindSDK/WindSDK.h>

static BOOL _sigmobInterstitialSDKInitialized = NO;

@interface ADXSigmobInterstitialAdapter () <WindNewIntersititialAdDelegate>

@property (nonatomic, strong, nullable) WindNewIntersititialAd *interstitialAd;
@property (nonatomic, copy, nullable) void (^loadCompletion)(ADXBidResult *result);
@property (nonatomic, strong, nullable) ADXAdSourceInfo *currentSourceInfo;
/// 展示结果回调（展示失败降级用）：曝光成功回 YES，展示失败/预检失败回 NO
@property (nonatomic, copy, nullable) void (^showCompletion)(BOOL success, NSError * _Nullable error);

@end

@implementation ADXSigmobInterstitialAdapter

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

    // 与开屏/激励 Adapter 各自持有静态去重变量，但底层 WindAds 启动幂等，
    // 多注册场景下由注册中心去重保证只调度一次
    if (_sigmobInterstitialSDKInitialized) {
        if (completion) {
            completion(YES);
        }
        return;
    }

    WindAdOptions *options = [[WindAdOptions alloc] initWithAppId:appId appKey:appKey];
    [WindAds startWithOptions:options];
    _sigmobInterstitialSDKInitialized = YES;
    ADXLogInfo(@"Sigmob SDK 启动完成（插屏 Adapter），appId: %@", appId);

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
    self.interstitialAd = [[WindNewIntersititialAd alloc] initWithRequest:request];
    self.interstitialAd.delegate = self;
    [self.interstitialAd loadAdData];
}

- (void)notifyWinWithCostPrice:(NSInteger)costPrice
                     lossPrice:(NSInteger)lossPrice
{
    if (!self.interstitialAd) {
        return;
    }

    NSDictionary *winInfo = @{
        @"AUCTION_PRICE": @(costPrice),
        @"HIGHEST_LOSS_PRICE": @(lossPrice),
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
        @"AUCTION_PRICE": @(winPrice),
        @"LOSS_REASON": @([self sigmobLossReasonFromADXReason:lossReason]),
        @"ADN_ID": @([self sigmobAdnIdFromAdnName:winnerAdnId]),
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
    // 预检：广告对象已释放（可能已被竞败清理）或未就绪，立即回 NO 触发上层降级
    if (!self.interstitialAd || !rootViewController) {
        NSError *error = [NSError errorWithDomain:@"ADXSigmobInterstitialAdapter"
                                             code:-1
                                         userInfo:@{NSLocalizedDescriptionKey: @"广告对象已释放或展示控制器为空"}];
        completion(NO, error);
        return;
    }
    if (!self.interstitialAd.isAdReady) {
        NSError *error = [NSError errorWithDomain:@"ADXSigmobInterstitialAdapter"
                                             code:-2
                                         userInfo:@{NSLocalizedDescriptionKey: @"广告未就绪或已失效"}];
        completion(NO, error);
        return;
    }

    self.showCompletion = completion;
    [self.interstitialAd showAdFromRootViewController:rootViewController options:nil];
}

#pragma mark - WindNewIntersititialAdDelegate

- (void)intersititialAdDidLoad:(WindNewIntersititialAd *)intersititialAd
{
    if (!self.loadCompletion) {
        return;
    }

    // 瀑布源：优先实时 eCPM（单位：分），无权限访问时 fallback 到预设 floorEcpm
    NSString *ecpm = [intersititialAd getEcpm];
    NSInteger price = ecpm.length > 0 ? ecpm.integerValue : self.currentSourceInfo.floorEcpm;
    ADXLogInfo(@"%@ 加载成功：实时 eCPM=%@（%@）",
               self.currentSourceInfo.sourceId,
               ecpm.length > 0 ? ecpm : @"无",
               ecpm.length > 0 ? @"实时价" : [NSString stringWithFormat:@"无实时价，使用 floor=%ld（瀑布源）", (long)self.currentSourceInfo.floorEcpm]);
    [self deliverResultWithSuccess:YES price:price error:nil];
}

- (void)intersititialAdDidLoad:(WindNewIntersititialAd *)intersititialAd didFailWithError:(NSError *)error
{
    if (!self.loadCompletion) {
        return;
    }

    ADXLogError(@"%@ 加载失败（Sigmob）：%@", self.currentSourceInfo.sourceId, error);
    [self deliverResultWithSuccess:NO price:0 error:error];
}

- (void)intersititialAdDidVisible:(WindNewIntersititialAd *)intersititialAd
{
    ADXLogInfo(@"%@ 插屏已曝光（Sigmob）", self.currentSourceInfo.sourceId);
    if (self.showCompletion) {
        self.showCompletion(YES, nil);
        self.showCompletion = nil;
    }
}

- (void)intersititialAdDidShowFailed:(WindNewIntersititialAd *)intersititialAd error:(NSError *)error
{
    ADXLogError(@"%@ 插屏展示失败（Sigmob）：%@", self.currentSourceInfo.sourceId, error);
    // 展示失败：回 NO 供上层降级到次高价候选
    if (self.showCompletion) {
        self.showCompletion(NO, error);
        self.showCompletion = nil;
    }
    [self cleanupAd];
}

- (void)intersititialAdDidClick:(WindNewIntersititialAd *)intersititialAd
{
    ADXLogInfo(@"%@ 插屏被点击（Sigmob）", self.currentSourceInfo.sourceId);
}

- (void)intersititialAdDidClickSkip:(WindNewIntersititialAd *)intersititialAd
{
    ADXLogInfo(@"%@ 插屏被跳过（Sigmob）", self.currentSourceInfo.sourceId);
}

- (void)intersititialAdDidClose:(WindNewIntersititialAd *)intersititialAd
{
    ADXLogInfo(@"%@ 插屏已关闭（Sigmob）", self.currentSourceInfo.sourceId);
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
