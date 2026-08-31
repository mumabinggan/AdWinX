//
//  ADXBaiduRewardVideoAdapter.m
//  AdWinX
//
//  Created by AdWinX on 2026/08/30.
//

#import "ADXBaiduRewardVideoAdapter.h"
#import "ADXAdSourceInfo.h"
#import "ADXBidResult.h"
#import "ADXLogger.h"
#import <BaiduMobAdSDK/BaiduMobAdSDK.h>
#import <UIKit/UIKit.h>

static BOOL _baiduRewardSDKInitialized = NO;
static NSString *_baiduRewardAppId = nil;

@interface ADXBaiduRewardVideoAdapter () <BaiduMobAdRewardVideoDelegate>

@property (nonatomic, strong, nullable) BaiduMobAdRewardVideo *rewardVideoAd;
@property (nonatomic, copy, nullable) void (^loadCompletion)(ADXBidResult *result);
@property (nonatomic, strong, nullable) ADXAdSourceInfo *currentSourceInfo;
/// 激励达成回调（业务发奖用）
@property (nonatomic, copy, nullable) void (^rewardCallback)(BOOL granted);

@end

@implementation ADXBaiduRewardVideoAdapter

#pragma mark - SDK Initialization

+ (void)setupSDKWithConfig:(NSDictionary *)adnConfig
{
    [self setupSDKWithConfig:adnConfig completion:NULL];
}

+ (void)setupSDKWithConfig:(NSDictionary *)adnConfig
                completion:(nullable void (^)(BOOL success))completion
{
    static NSString * const kAppIdKey = @"appId";

    // appId 优先取传入配置，未传时使用内置默认值。
    // 百度的 publisherId 是实例级属性（每次 load 前都要设置），这里静态记忆初始化时的 appId
    _baiduRewardAppId = adnConfig[kAppIdKey] ?: @"ca18a163";

    // 与开屏 Adapter 各自持有静态去重变量，但底层 BaiduMobAdManager 启动幂等，
    // 双注册场景下（开屏 + 激励视频）由注册中心去重保证只调度一次
    if (_baiduRewardSDKInitialized) {
        if (completion) {
            completion(YES);
        }
        return;
    }

    // 关闭百度 SDK 内置 debug 日志（默认开启）。
    // 百度 debug 日志会在主线程大量打印，实测会挤占主线程拖慢竞价回包，生产环境一律关闭
    [[BaiduMobAdSetting sharedInstance] setDebugLogEnable:NO];

    [BaiduMobAdManager setAppsid:_baiduRewardAppId];
    [BaiduMobAdManager startWithCompletionHandler:^(BOOL success, NSError * _Nullable error) {
        _baiduRewardSDKInitialized = success;
        if (success) {
            ADXLogInfo(@"百度 SDK 启动成功（激励视频 Adapter），appId: %@", _baiduRewardAppId);
        } else {
            ADXLogError(@"百度 SDK 启动失败（激励视频 Adapter），error: %@", error);
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

    BaiduMobAdRewardVideo *rewardVideoAd = [[BaiduMobAdRewardVideo alloc] init];
    rewardVideoAd.delegate = self;
    rewardVideoAd.publisherId = _baiduRewardAppId ?: @"ca18a163";
    rewardVideoAd.adUnitTag = sourceInfo.placementId;
    rewardVideoAd.timeout = sourceInfo.timeout;
    rewardVideoAd.bidFloor = (int)sourceInfo.floorEcpm;  // 客户端底价过滤（单位：分）
    self.rewardVideoAd = rewardVideoAd;

    [rewardVideoAd load];
}

- (void)notifyWinWithCostPrice:(NSInteger)costPrice
                     lossPrice:(NSInteger)lossPrice
{
    if (!self.rewardVideoAd) {
        return;
    }

    // 竞胜上报：上报竞败方（排名第二）的出价，单位：分
    NSDictionary *secondInfo = @{@"ecpm": @(lossPrice)};
    [self.rewardVideoAd biddingSuccessWithSecondInfo:secondInfo
                                          completion:^(BOOL success, NSString *errorInfo) {
        if (!success) {
            ADXLogError(@"百度竞胜上报失败：%@", errorInfo);
        }
    }];
}

- (void)notifyLossWithWinPrice:(NSInteger)winPrice
                    lossReason:(NSInteger)lossReason
                   winnerAdnId:(NSString *)winnerAdnId
{
    if (!self.rewardVideoAd) {
        return;
    }

    // 竞败上报：上报竞胜方出价，单位：分
    NSDictionary *winInfo = @{@"ecpm": @(winPrice)};
    [self.rewardVideoAd biddingFailWithWinInfo:winInfo
                                    completion:^(BOOL success, NSString *errorInfo) {
        if (!success) {
            ADXLogError(@"百度竞败上报失败：%@", errorInfo);
        }
    }];

    // 竞败释放资源
    self.rewardVideoAd.delegate = nil;
    self.rewardVideoAd = nil;
}

- (void)showRewardVideoAdWithResult:(ADXBidResult *)result
                 fromViewController:(UIViewController *)rootViewController
                      rewardCallback:(nullable void (^)(BOOL granted))rewardCallback
                          completion:(void (^)(BOOL success, NSError * _Nullable error))completion
{
    // 预检：广告对象已释放（可能已被竞败清理）或未就绪（缓存失败/已过期），回 NO 触发上层降级
    if (!self.rewardVideoAd || !rootViewController) {
        ADXLogError(@"%@ 展示失败：广告对象已释放或展示控制器为空", result.sourceId);
        completion(NO, [NSError errorWithDomain:@"ADXBaiduRewardVideoAdapter"
                                            code:-1
                                        userInfo:@{NSLocalizedDescriptionKey: @"广告对象已释放或展示控制器为空"}]);
        return;
    }
    if (![self.rewardVideoAd isReady]) {
        ADXLogError(@"%@ 展示时广告未就绪（缓存失败或已过期）", result.sourceId);
        completion(NO, [NSError errorWithDomain:@"ADXBaiduRewardVideoAdapter"
                                            code:-2
                                        userInfo:@{NSLocalizedDescriptionKey: @"广告未就绪（缓存失败或已过期）"}]);
        return;
    }

    self.rewardCallback = rewardCallback;

    // 百度展示失败回调（rewardedVideoAdShowFailed）无法携带到本 completion，
    // 预检通过、展示发起成功即视为成功
    [self.rewardVideoAd showFromViewController:rootViewController];
    ADXLogInfo(@"%@ 激励视频展示发起成功（百度）", result.sourceId);
    completion(YES, nil);
}

#pragma mark - BaiduMobAdRewardVideoDelegate

- (void)rewardedAdLoadSuccess:(BaiduMobAdRewardVideo *)video
{
    if (!self.loadCompletion) {
        return;
    }

    NSString *pecpm = [video getPECPM];
    NSString *ecpmLevel = [video getECPMLevel];
    ADXLogInfo(@"%@ 请求成功：pECPM=%@，价格标签=%@（百度 SDK %@）",
               self.currentSourceInfo.sourceId,
               pecpm.length > 0 ? pecpm : @"无",
               ecpmLevel.length > 0 ? ecpmLevel : @"无",
               [BaiduMobAdManager getSDKVersion]);

    NSInteger price;
    if (self.currentSourceInfo.runtimeMode == ADXRuntimeModeBidding) {
        // 竞价源：优先实时 eCPM；取不到时降级用价格标签 getECPMLevel（新版 SDK 部分流量不返回 pECPM），
        // 两者都无则按失败处理
        if (pecpm.length == 0) {
            if (ecpmLevel.length > 0) {
                price = [self ecpmFromLevel:ecpmLevel];
                ADXLogInfo(@"%@ 降级用价格标签 %@ ≈ %ld 分（竞价源）",
                           self.currentSourceInfo.sourceId, ecpmLevel, (long)price);
            } else {
                ADXLogError(@"%@ 请求成功但实时 eCPM 获取失败（竞价源）", self.currentSourceInfo.sourceId);
                [self deliverResultWithSuccess:NO price:0 error:[NSError errorWithDomain:@"ADXBaiduRewardVideoAdapter"
                                                                                     code:-3
                                                                                 userInfo:@{NSLocalizedDescriptionKey: @"竞价源实时 eCPM 获取失败"}]];
                return;
            }
        } else {
            price = pecpm.integerValue;
            ADXLogInfo(@"%@ 实时 eCPM=%@（竞价源）", self.currentSourceInfo.sourceId, pecpm);
        }
    } else {
        // 瀑布源：优先真实 eCPM，无权限访问时 fallback 到预设 floorEcpm
        price = pecpm.length > 0 ? pecpm.integerValue : self.currentSourceInfo.floorEcpm;
        ADXLogInfo(@"%@ eCPM=%ld（%@）",
                   self.currentSourceInfo.sourceId,
                   (long)price,
                   pecpm.length > 0 ? @"实时价" : [NSString stringWithFormat:@"无实时价，使用 floor=%ld（瀑布源）", (long)self.currentSourceInfo.floorEcpm]);
    }

    [self deliverResultWithSuccess:YES price:price error:nil];
}

- (void)rewardedAdLoadFailCode:(NSString *)errCode
                       message:(NSString *)message
                    rewardedAd:(BaiduMobAdRewardVideo *)video
{
    if (!self.loadCompletion) {
        return;
    }

    ADXLogError(@"%@ 请求失败（百度）：[%@] %@", self.currentSourceInfo.sourceId, errCode, message);
    [self deliverResultWithSuccess:NO price:0 error:[NSError errorWithDomain:@"ADXBaiduRewardVideoAdapter"
                                                                        code:-1
                                                                    userInfo:@{NSLocalizedDescriptionKey: [NSString stringWithFormat:@"[%@] %@", errCode, message ?: @""]}]];
}

- (void)rewardedVideoAdLoaded:(BaiduMobAdRewardVideo *)video
{
    ADXLogInfo(@"%@ 视频缓存完成（百度）", self.currentSourceInfo.sourceId);
}

- (void)rewardedVideoAdDidExposured:(BaiduMobAdRewardVideo *)video
{
    ADXLogInfo(@"%@ 激励视频已曝光（百度）", self.currentSourceInfo.sourceId);
}

- (void)rewardedVideoAdShowFailed:(BaiduMobAdRewardVideo *)video withError:(BaiduMobFailReason)reason
{
    ADXLogError(@"%@ 激励视频展示失败（百度）：reason=%ld", self.currentSourceInfo.sourceId, (long)reason);
    [self cleanupAd];
}

- (void)rewardedVideoAdDidStarted:(BaiduMobAdRewardVideo *)video
{
}

- (void)rewardedVideoAdDidPlayFinish:(BaiduMobAdRewardVideo *)video
{
    ADXLogInfo(@"%@ 激励视频播放完成（百度）", self.currentSourceInfo.sourceId);
}

- (void)rewardedVideoAdRewardDidSuccess:(BaiduMobAdRewardVideo *)video verify:(BOOL)verify rewardInfo:(NSDictionary *)rewardInfo
{
    ADXLogInfo(@"%@ 激励达成（百度，verify=%@）：%@",
               self.currentSourceInfo.sourceId, verify ? @"YES" : @"NO", rewardInfo);
    if (self.rewardCallback) {
        self.rewardCallback(verify);
        self.rewardCallback = nil;
    }
}

- (void)rewardedVideoAdDidSkip:(BaiduMobAdRewardVideo *)video withPlayingProgress:(CGFloat)progress
{
    ADXLogInfo(@"%@ 用户跳过（百度，进度 %.0f%%）", self.currentSourceInfo.sourceId, progress * 100);
}

- (void)rewardedVideoAdDidClose:(BaiduMobAdRewardVideo *)video withPlayingProgress:(CGFloat)progress
{
    ADXLogInfo(@"%@ 激励视频已关闭（百度，进度 %.0f%%）", self.currentSourceInfo.sourceId, progress * 100);
    // 关闭时若激励回调尚未触发（用户提前关闭未看完），补发 granted=NO 供业务区分
    if (self.rewardCallback) {
        self.rewardCallback(NO);
        self.rewardCallback = nil;
    }
    [self cleanupAd];
}

- (void)rewardedVideoAdDidClick:(BaiduMobAdRewardVideo *)video withPlayingProgress:(CGFloat)progress
{
    ADXLogInfo(@"%@ 激励视频被点击（百度）", self.currentSourceInfo.sourceId);
}

#pragma mark - Private

/// 百度价格标签（A~E 等）→ 估算 eCPM（单位：分）
/// 百度官方价格标签分档：A(>300 分) B(150~300) C(80~150) D(30~80) E(<30)，取档位区间中值估算
- (NSInteger)ecpmFromLevel:(NSString *)level
{
    if ([level isEqualToString:@"A"]) {
        return 300;
    }
    if ([level isEqualToString:@"B"]) {
        return 225;
    }
    if ([level isEqualToString:@"C"]) {
        return 115;
    }
    if ([level isEqualToString:@"D"]) {
        return 55;
    }
    if ([level isEqualToString:@"E"]) {
        return 15;
    }
    return 0;
}

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
