//
//  ADXGDTRewardVideoAdapter.m
//  AdWinX
//
//  Created by AdWinX on 2026/08/30.
//

#import "ADXGDTRewardVideoAdapter.h"
#import "ADXAdSourceInfo.h"
#import "ADXBidResult.h"
#import "ADXLogger.h"
#import <GDTMobSDK/GDTRewardVideoAd.h>
#import <GDTMobSDK/GDTSDKConfig.h>

static BOOL _gdtRewardSDKInitialized = NO;

@interface ADXGDTRewardVideoAdapter () <GDTRewardedVideoAdDelegate>

@property (nonatomic, strong, nullable) GDTRewardVideoAd *rewardVideoAd;
@property (nonatomic, copy, nullable) void (^loadCompletion)(ADXBidResult *result);
@property (nonatomic, strong, nullable) ADXAdSourceInfo *currentSourceInfo;
/// 激励达成回调（业务发奖用）
@property (nonatomic, copy, nullable) void (^rewardCallback)(BOOL granted);

@end

@implementation ADXGDTRewardVideoAdapter

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

    // 与开屏 Adapter 各自持有静态去重变量，但底层 GDTSDKConfig 启动幂等，
    // 双注册场景下（开屏 + 激励视频）由注册中心去重保证只调度一次
    if (_gdtRewardSDKInitialized) {
        if (completion) {
            completion(YES);
        }
        return;
    }

    BOOL initSuccess = [GDTSDKConfig initWithAppId:appId];
    if (!initSuccess) {
        ADXLogError(@"优量汇 SDK initWithAppId 失败（激励视频 Adapter），appId: %@", appId);
        if (completion) {
            completion(NO);
        }
        return;
    }

    [GDTSDKConfig startWithCompletionHandler:^(BOOL success, NSError *error) {
        _gdtRewardSDKInitialized = success;
        if (success) {
            ADXLogInfo(@"优量汇 SDK 启动成功（激励视频 Adapter），appId: %@", appId);
        } else {
            ADXLogError(@"优量汇 SDK 启动失败（激励视频 Adapter），error: %@", error);
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

    self.rewardVideoAd = [[GDTRewardVideoAd alloc] initWithPlacementId:sourceInfo.placementId];
    self.rewardVideoAd.delegate = self;
    [self.rewardVideoAd loadAd];
}

- (void)notifyWinWithCostPrice:(NSInteger)costPrice
                     lossPrice:(NSInteger)lossPrice
{
    if (!self.rewardVideoAd) {
        return;
    }

    NSDictionary *winInfo = @{
        GDT_M_W_E_COST_PRICE: @(costPrice),
        GDT_M_W_H_LOSS_PRICE: @(lossPrice),
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
        GDT_M_L_WIN_PRICE: @(winPrice),
        GDT_M_L_LOSS_REASON: @(lossReason),
        GDT_M_ADNID: winnerAdnId ?: @"",
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
    // 预检：广告对象已释放（可能已被竞败清理）、过期/失效或展示控制器为空
    if (!self.rewardVideoAd || !rootViewController) {
        ADXLogError(@"%@ 展示失败：广告对象已释放或展示控制器为空", result.sourceId);
        completion(NO, [NSError errorWithDomain:@"ADXGDTRewardVideoAdapter"
                                            code:-1
                                        userInfo:@{NSLocalizedDescriptionKey: @"广告对象已释放或展示控制器为空"}]);
        return;
    }
    if (![self.rewardVideoAd isAdValid]) {
        ADXLogError(@"%@ 展示失败：广告已过期或失效", result.sourceId);
        completion(NO, [NSError errorWithDomain:@"ADXGDTRewardVideoAdapter"
                                            code:-2
                                        userInfo:@{NSLocalizedDescriptionKey: @"广告已过期或失效"}]);
        return;
    }

    self.rewardCallback = rewardCallback;

    // showAdFromRootViewController 返回 NO 即展示发起失败，返回 YES 视为展示成功
    // （GDT 无独立的展示失败回调）
    BOOL shown = [self.rewardVideoAd showAdFromRootViewController:rootViewController];
    if (shown) {
        ADXLogInfo(@"%@ 激励视频展示发起成功（GDT）", result.sourceId);
        completion(YES, nil);
    } else {
        ADXLogError(@"%@ 展示发起失败（GDT，showAd 返回 NO）", result.sourceId);
        completion(NO, [NSError errorWithDomain:@"ADXGDTRewardVideoAdapter"
                                            code:-3
                                        userInfo:@{NSLocalizedDescriptionKey: @"展示发起失败（showAd 返回 NO）"}]);
    }
}

#pragma mark - GDTRewardedVideoAdDelegate

- (void)gdt_rewardVideoAdDidLoad:(GDTRewardVideoAd *)rewardedVideoAd
{
    if (!self.loadCompletion) {
        return;
    }

    NSInteger eCPM = [rewardedVideoAd eCPM];
    NSInteger price;
    if (self.currentSourceInfo.runtimeMode == ADXRuntimeModeBidding) {
        // 竞价源：必须用实时 eCPM，取不到（-1）则按失败处理
        if (eCPM < 0) {
            ADXLogError(@"%@ 加载成功但实时 eCPM 获取失败（竞价源）", self.currentSourceInfo.sourceId);
            [self deliverResultWithSuccess:NO price:0 error:[NSError errorWithDomain:@"ADXGDTRewardVideoAdapter"
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

- (void)gdt_rewardVideoAdVideoDidLoad:(GDTRewardVideoAd *)rewardedVideoAd
{
    ADXLogInfo(@"%@ 视频缓存完成（GDT）", self.currentSourceInfo.sourceId);
}

- (void)gdt_rewardVideoAdDidExposed:(GDTRewardVideoAd *)rewardedVideoAd
{
    ADXLogInfo(@"%@ 激励视频已曝光（GDT）", self.currentSourceInfo.sourceId);
}

- (void)gdt_rewardVideoAdDidClicked:(GDTRewardVideoAd *)rewardedVideoAd
{
    ADXLogInfo(@"%@ 激励视频被点击（GDT）", self.currentSourceInfo.sourceId);
}

- (void)gdt_rewardVideoAd:(GDTRewardVideoAd *)rewardedVideoAd didFailWithError:(NSError *)error
{
    if (self.loadCompletion) {
        ADXLogError(@"%@ 加载失败（GDT）：%@", self.currentSourceInfo.sourceId, error);
        [self deliverResultWithSuccess:NO price:0 error:error];
        return;
    }
    ADXLogError(@"%@ 运行期错误（GDT）：%@", self.currentSourceInfo.sourceId, error);
}

- (void)gdt_adDidRewardEffective:(id<GDTAdProtocol>)adInstance info:(NSDictionary *)info
{
    ADXLogInfo(@"%@ 激励达成（GDT）：transId=%@", self.currentSourceInfo.sourceId, info[@"GDT_TRANS_ID"]);
    if (self.rewardCallback) {
        self.rewardCallback(YES);
        self.rewardCallback = nil;
    }
}

- (void)gdt_rewardVideoAdDidPlayFinish:(GDTRewardVideoAd *)rewardedVideoAd
{
    ADXLogInfo(@"%@ 激励视频播放完成（GDT）", self.currentSourceInfo.sourceId);
}

- (void)gdt_rewardVideoAdDidClose:(GDTRewardVideoAd *)rewardedVideoAd
{
    ADXLogInfo(@"%@ 激励视频已关闭（GDT）", self.currentSourceInfo.sourceId);
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

@end
