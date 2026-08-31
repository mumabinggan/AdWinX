//
//  ADXGDTSplashAdapter.m
//  AdWinX
//
//  Created by AdWinX on 2026/08/29.
//

#import "ADXGDTSplashAdapter.h"
#import "ADXAdSourceInfo.h"
#import "ADXBidResult.h"
#import "ADXLogger.h"
#import <GDTMobSDK/GDTSplashAd.h>
#import <GDTMobSDK/GDTSDKConfig.h>

static BOOL _gdtSDKInitialized = NO;

@interface ADXGDTSplashAdapter () <GDTSplashAdDelegate>

@property (nonatomic, strong) GDTSplashAd *splashAd;
@property (nonatomic, copy) void (^loadCompletion)(ADXBidResult *result);
@property (nonatomic, strong) ADXAdSourceInfo *currentSourceInfo;
@property (nonatomic, strong) NSDate *loadStartDate;
/// 展示起始时间（用于计算曝光到关闭的展示时长，诊断「一闪即关」类问题）
@property (nonatomic, strong, nullable) NSDate *showStartDate;
/// 展示结果回调（展示失败降级用）：曝光成功回 YES，展示失败/预检失败回 NO
@property (nonatomic, copy, nullable) void (^showCompletion)(BOOL success, NSError * _Nullable error);

@end

@implementation ADXGDTSplashAdapter

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

    if (_gdtSDKInitialized) {
        if (completion) {
            completion(YES);
        }
        return;
    }

    BOOL initSuccess = [GDTSDKConfig initWithAppId:appId];
    if (!initSuccess) {
        ADXLogError(@"优量汇 SDK initWithAppId 失败，appId: %@", appId);
        if (completion) {
            completion(NO);
        }
        return;
    }

    [GDTSDKConfig startWithCompletionHandler:^(BOOL success, NSError *error) {
        _gdtSDKInitialized = success;
        if (success) {
            ADXLogInfo(@"优量汇 SDK 启动成功，appId: %@", appId);
        } else {
            ADXLogError(@"优量汇 SDK 启动失败，error: %@", error);
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
    self.loadStartDate = [NSDate date];
    ADXLogInfo(@"%@ 请求发起：%@（GDT SDK 内部开始加载）",
               sourceInfo.sourceId, self.loadStartDate);

    self.splashAd = [[GDTSplashAd alloc] initWithPlacementId:sourceInfo.placementId];
    self.splashAd.delegate = self;
    self.splashAd.fetchDelay = sourceInfo.timeout;
    [self.splashAd loadAd];
}

- (void)notifyWinWithCostPrice:(NSInteger)costPrice
                     lossPrice:(NSInteger)lossPrice
{
    if (!self.splashAd) {
        return;
    }

    NSDictionary *winInfo = @{
        GDT_M_W_E_COST_PRICE: @(costPrice),
        GDT_M_W_H_LOSS_PRICE: @(lossPrice),
    };
    [self.splashAd sendWinNotificationWithInfo:winInfo];
}

- (void)notifyLossWithWinPrice:(NSInteger)winPrice
                    lossReason:(NSInteger)lossReason
                   winnerAdnId:(NSString *)winnerAdnId
{
    if (!self.splashAd) {
        return;
    }

    NSDictionary *lossInfo = @{
        GDT_M_L_WIN_PRICE: @(winPrice),
        GDT_M_L_LOSS_REASON: @(lossReason),
        GDT_M_ADNID: winnerAdnId ?: @"",
    };
    [self.splashAd sendLossNotificationWithInfo:lossInfo];
}

- (void)showSplashAdWithResult:(ADXBidResult *)result
                        window:(UIWindow *)window
                    completion:(void (^)(BOOL success, NSError * _Nullable error))completion
{
    // 预检：广告对象已释放（可能已被竞败清理）或已过期/失效，立即回 NO 触发上层降级
    if (!self.splashAd) {
        ADXLogError(@"%@ 展示失败：广告对象已释放（可能已被竞败清理）", result.sourceId);
        completion(NO, [NSError errorWithDomain:@"ADXGDTSplashAdapter"
                                            code:-1
                                        userInfo:@{NSLocalizedDescriptionKey: @"广告对象已释放"}]);
        return;
    }
    if (![self.splashAd isAdValid]) {
        ADXLogError(@"%@ 展示失败：广告已过期或失效（加载到展示间隔过长）", result.sourceId);
        completion(NO, [NSError errorWithDomain:@"ADXGDTSplashAdapter"
                                            code:-2
                                        userInfo:@{NSLocalizedDescriptionKey: @"广告已过期或失效"}]);
        return;
    }

    self.showCompletion = completion;
    self.showStartDate = [NSDate date];
    [self.splashAd showAdInWindow:window withBottomView:nil skipView:nil];
}

#pragma mark - GDTSplashAdDelegate

- (void)splashAdDidLoad:(GDTSplashAd *)splashAd
{
    if (!self.loadCompletion) {
        return;
    }

    NSInteger eCPM = [splashAd eCPM];
    NSInteger price;
    if (self.currentSourceInfo.runtimeMode == ADXRuntimeModeBidding) {
        // 竞价源：必须用实时 eCPM，取不到则按失败处理
        if (eCPM < 0) {
            ADXLogError(@"%@ 加载成功但实时 eCPM 获取失败（竞价源）", self.currentSourceInfo.sourceId);
            ADXBidResult *result = [ADXBidResult resultWithSourceId:self.currentSourceInfo.sourceId
                                                             adType:self.currentSourceInfo.adType
                                                              price:0
                                                           adObject:nil
                                                            success:NO
                                                              error:[NSError errorWithDomain:@"ADXGDTSplashAdapter"
                                                                                        code:-2
                                                                                    userInfo:@{NSLocalizedDescriptionKey: @"竞价源实时 eCPM 获取失败"}]];
            self.loadCompletion(result);
            self.loadCompletion = nil;
            return;
        }
        price = eCPM;
        ADXLogInfo(@"%@ 加载成功：实时 eCPM=%ld（竞价源），回包时间 %@，耗时 %.2fs",
                   self.currentSourceInfo.sourceId, (long)price,
                   [NSDate date], self.loadStartDate ? [[NSDate date] timeIntervalSinceDate:self.loadStartDate] : 0);
    } else {
        // 瀑布源：优先真实 eCPM，无权限时 fallback 到预设 floorEcpm
        price = eCPM >= 0 ? eCPM : self.currentSourceInfo.floorEcpm;
        ADXLogInfo(@"%@ 加载成功：实时 eCPM=%ld（%@）",
                   self.currentSourceInfo.sourceId,
                   (long)price,
                   eCPM >= 0 ? @"瀑布源" : [NSString stringWithFormat:@"无实时价，使用 floor=%ld（瀑布源）", (long)self.currentSourceInfo.floorEcpm]);
    }

    ADXBidResult *result = [ADXBidResult resultWithSourceId:self.currentSourceInfo.sourceId
                                                     adType:self.currentSourceInfo.adType
                                                      price:price
                                                   adObject:splashAd
                                                    success:YES
                                                      error:nil];
    self.loadCompletion(result);
    self.loadCompletion = nil;
}

- (void)splashAdSuccessPresentScreen:(GDTSplashAd *)splashAd
{
    ADXLogInfo(@"%@ 开屏已曝光（GDT）", self.currentSourceInfo.sourceId);
    if (self.showCompletion) {
        self.showCompletion(YES, nil);
        self.showCompletion = nil;
    }
}

- (void)splashAdFailToPresent:(GDTSplashAd *)splashAd withError:(NSError *)error
{
    ADXLogInfo(@"%@ 开屏曝光失败（GDT）：%@", self.currentSourceInfo.sourceId, error);
    // 展示失败：回 NO 供上层降级到次高价候选
    if (self.showCompletion) {
        self.showCompletion(NO, error);
        self.showCompletion = nil;
    }

    if (!self.loadCompletion) {
        return;
    }

    ADXLogError(@"%@ 请求失败：回包时间 %@，耗时 %.2fs，error=%@",
                self.currentSourceInfo.sourceId, [NSDate date],
                self.loadStartDate ? [[NSDate date] timeIntervalSinceDate:self.loadStartDate] : 0,
                error);

    ADXBidResult *result = [ADXBidResult resultWithSourceId:self.currentSourceInfo.sourceId
                                                     adType:self.currentSourceInfo.adType
                                                      price:0
                                                   adObject:nil
                                                    success:NO
                                                      error:error];
    self.loadCompletion(result);
    self.loadCompletion = nil;
}

- (void)splashAdExposured:(GDTSplashAd *)splashAd
{
    ADXLogInfo(@"%@ 开屏已曝光回调（GDT exposured）", self.currentSourceInfo.sourceId);
}

- (void)splashAdWillClosed:(GDTSplashAd *)splashAd
{
    ADXLogInfo(@"%@ 开屏将要关闭（GDT willClosed）", self.currentSourceInfo.sourceId);
}

- (void)splashAdClosed:(GDTSplashAd *)splashAd
{
    // 曝光到关闭的间隔过短（<1s）视为无效展示：素材过期或渲染异常被 SDK 立即关闭
    NSTimeInterval shownDuration = self.showStartDate ? [[NSDate date] timeIntervalSinceDate:self.showStartDate] : -1;
    ADXLogInfo(@"%@ 开屏已关闭（GDT），展示时长 %.2fs", self.currentSourceInfo.sourceId, shownDuration);
    if (shownDuration >= 0 && shownDuration < 1.0) {
        ADXLogError(@"%@ 展示时长异常过短（%.2fs），疑似素材过期或渲染异常", self.currentSourceInfo.sourceId, shownDuration);
    }
    self.showStartDate = nil;
}

@end
