//
//  ADXSigmobSplashAdapter.m
//  AdWinX
//
//  Created by AdWinX on 2026/08/29.
//

#import "ADXSigmobSplashAdapter.h"
#import "ADXAdSourceInfo.h"
#import "ADXBidResult.h"
#import "ADXLogger.h"
#import <WindSDK/WindSDK.h>

static BOOL _sigmobSDKInitialized = NO;

@interface ADXSigmobSplashAdapter () <WindSplashAdViewDelegate>

@property (nonatomic, strong) WindSplashAdView *splashAdView;
@property (nonatomic, copy) void (^loadCompletion)(ADXBidResult *result);
@property (nonatomic, strong) ADXAdSourceInfo *currentSourceInfo;
/// 展示结果回调（展示失败降级用）：曝光成功回 YES，展示失败/预检失败回 NO
@property (nonatomic, copy, nullable) void (^showCompletion)(BOOL success, NSError * _Nullable error);

@end

@implementation ADXSigmobSplashAdapter

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

    if (_sigmobSDKInitialized) {
        if (completion) {
            completion(YES);
        }
        return;
    }

    WindAdOptions *options = [[WindAdOptions alloc] initWithAppId:appId appKey:appKey];
    [WindAds startWithOptions:options];
    _sigmobSDKInitialized = YES;
    ADXLogInfo(@"Sigmob SDK 启动完成，appId: %@，SDKVersion: %@", appId, [WindAds sdkVersion]);

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

    UIWindow *window = [self adx_currentWindow];

    WindAdRequest *request = [WindAdRequest request];
    request.placementId = sourceInfo.placementId;
    self.splashAdView = [[WindSplashAdView alloc] initWithRequest:request];
    self.splashAdView.delegate = self;
    self.splashAdView.fetchDelay = sourceInfo.timeout;

    if (window) {
        // 预挂载到窗口但保持隐藏：加载成功参与拍卖，竞胜后再显示
        self.splashAdView.rootViewController = window.rootViewController;
        self.splashAdView.frame = window.bounds;
        self.splashAdView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
        [window addSubview:self.splashAdView];
        self.splashAdView.hidden = YES;
    }

    [self.splashAdView loadAdData];
}

- (void)notifyWinWithCostPrice:(NSInteger)costPrice
                     lossPrice:(NSInteger)lossPrice
{
    if (!self.splashAdView) {
        return;
    }

    NSDictionary *winInfo = @{
        @"AUCTION_PRICE": @(costPrice),
        @"HIGHEST_LOSS_PRICE": @(lossPrice),
    };
    [self.splashAdView sendWinNotificationWithInfo:winInfo];
}

- (void)notifyLossWithWinPrice:(NSInteger)winPrice
                    lossReason:(NSInteger)lossReason
                   winnerAdnId:(NSString *)winnerAdnId
{
    if (!self.splashAdView) {
        return;
    }

    NSDictionary *lossInfo = @{
        @"AUCTION_PRICE": @(winPrice),
        @"LOSS_REASON": @([self sigmobLossReasonFromADXReason:lossReason]),
        @"ADN_ID": @([self sigmobAdnIdFromAdnName:winnerAdnId]),
    };
    [self.splashAdView sendLossNotificationWithInfo:lossInfo];

    // 竞败释放资源
    [self clearSplashAdView];
}

- (void)showSplashAdWithResult:(ADXBidResult *)result
                        window:(UIWindow *)window
                    completion:(void (^)(BOOL success, NSError * _Nullable error))completion
{
    // 预检：广告对象已释放（可能已被竞败清理）或已过期/失效（Sigmob 开屏有效期很短，
    // 加载到展示间隔过长会报 600180「广告过期」），立即回 NO 触发上层降级
    if (!self.splashAdView || !window) {
        NSError *error = [NSError errorWithDomain:@"ADXSigmobSplashAdapter"
                                             code:-1
                                         userInfo:@{NSLocalizedDescriptionKey: @"广告对象已释放或 window 为空"}];
        completion(NO, error);
        return;
    }
    if (!self.splashAdView.isAdValid) {
        NSError *error = [NSError errorWithDomain:@"ADXSigmobSplashAdapter"
                                             code:-2
                                         userInfo:@{NSLocalizedDescriptionKey: @"广告已过期或失效（加载到展示间隔过长）"}];
        completion(NO, error);
        return;
    }

    self.showCompletion = completion;
    self.splashAdView.frame = window.bounds;
    if (self.splashAdView.superview != window) {
        [self.splashAdView removeFromSuperview];
        [window addSubview:self.splashAdView];
    }
    [window bringSubviewToFront:self.splashAdView];
    self.splashAdView.hidden = NO;
    self.splashAdView.alpha = 1.0;
    self.splashAdView.userInteractionEnabled = YES;
}

#pragma mark - WindSplashAdViewDelegate

- (void)onSplashAdDidLoad:(WindSplashAdView *)splashAdView
{
    if (!self.loadCompletion) {
        return;
    }

    if (!splashAdView.isAdValid) {
        ADXLogError(@"%@ 加载回调但广告无效", self.currentSourceInfo.sourceId);
        [self deliverResultWithSuccess:NO price:0 error:[NSError errorWithDomain:@"ADXSigmobSplashAdapter"
                                                                             code:-2
                                                                         userInfo:@{NSLocalizedDescriptionKey: @"广告无效"}]];
        return;
    }

    // 瀑布源：优先实时 eCPM，无权限访问时 fallback 到预设 floorEcpm
    NSString *ecpm = [splashAdView getEcpm];
    NSInteger price = ecpm.length > 0 ? ecpm.integerValue : self.currentSourceInfo.floorEcpm;
    ADXLogInfo(@"%@ 加载成功：实时 eCPM=%@（%@）",
               self.currentSourceInfo.sourceId,
               ecpm.length > 0 ? ecpm : @"无",
               ecpm.length > 0 ? @"实时价" : [NSString stringWithFormat:@"无实时价，使用 floor=%ld（瀑布源）", (long)self.currentSourceInfo.floorEcpm]);
    [self deliverResultWithSuccess:YES price:price error:nil];
}

- (void)onSplashAdLoadFail:(WindSplashAdView *)splashAdView error:(NSError *)error
{
    if (!self.loadCompletion) {
        return;
    }

    [self deliverResultWithSuccess:NO price:0 error:error];
}

- (void)onSplashAdSuccessPresentScreen:(WindSplashAdView *)splashAdView
{
    ADXLogInfo(@"%@ 开屏已曝光（Sigmob）", self.currentSourceInfo.sourceId);
    if (self.showCompletion) {
        self.showCompletion(YES, nil);
        self.showCompletion = nil;
    }
}

- (void)onSplashAdClicked:(WindSplashAdView *)splashAdView
{
    ADXLogInfo(@"%@ 开屏被点击（Sigmob）", self.currentSourceInfo.sourceId);
}

- (void)onSplashAdSkiped:(WindSplashAdView *)splashAdView
{
    ADXLogInfo(@"%@ 开屏已跳过（Sigmob）", self.currentSourceInfo.sourceId);
}

- (void)onSplashAdClosed:(WindSplashAdView *)splashAdView
{
    ADXLogInfo(@"%@ 开屏已关闭（Sigmob）", self.currentSourceInfo.sourceId);
    [self clearSplashAdView];
}

- (void)onSplashAdFailToPresent:(WindSplashAdView *)splashAdView withError:(NSError *)error
{
    ADXLogError(@"%@ 开屏展示失败（Sigmob）：%@", self.currentSourceInfo.sourceId, error);
    // 展示失败（如 600180 广告过期）：回 NO 供上层降级到次高价候选
    if (self.showCompletion) {
        self.showCompletion(NO, error);
        self.showCompletion = nil;
    }
    [self clearSplashAdView];
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
                                                   adObject:success ? self.splashAdView : nil
                                                    success:success
                                                      error:error];
    self.loadCompletion(result);
    self.loadCompletion = nil;

    if (!success) {
        [self clearSplashAdView];
    }
}

- (void)clearSplashAdView
{
    [self.splashAdView removeFromSuperview];
    self.splashAdView = nil;
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

/// 当前可用窗口（iOS 13+ 场景兼容）
- (UIWindow *)adx_currentWindow
{
    UIApplication *application = [UIApplication sharedApplication];
    if (@available(iOS 13.0, *)) {
        for (UIScene *scene in application.connectedScenes) {
            if (scene.activationState != UISceneActivationStateForegroundActive ||
                ![scene isKindOfClass:[UIWindowScene class]]) {
                continue;
            }
            for (UIWindow *window in ((UIWindowScene *)scene).windows) {
                if (window.isKeyWindow) {
                    return window;
                }
            }
        }
    }
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
    return application.keyWindow;
#pragma clang diagnostic pop
}

@end
