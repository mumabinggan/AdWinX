//
//  ADXBaiduSplashAdapter.m
//  AdWinX
//
//  Created by AdWinX on 2026/08/29.
//

#import "ADXBaiduSplashAdapter.h"
#import "ADXAdSourceInfo.h"
#import "ADXBidResult.h"
#import "ADXLogger.h"
#import <BaiduMobAdSDK/BaiduMobAdManager.h>
#import <BaiduMobAdSDK/BaiduMobAdSplash.h>
#import <BaiduMobAdSDK/BaiduMobAdSetting.h>

static BOOL _baiduSDKInitialized = NO;
static NSString *_baiduAppId = nil;

@interface ADXBaiduSplashAdapter () <BaiduMobAdSplashDelegate>

@property (nonatomic, strong) BaiduMobAdSplash *splashAd;
@property (nonatomic, strong) UIView *containerView;
@property (nonatomic, copy) void (^loadCompletion)(ADXBidResult *result);
@property (nonatomic, strong) ADXAdSourceInfo *currentSourceInfo;

@end

@implementation ADXBaiduSplashAdapter

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
    _baiduAppId = adnConfig[kAppIdKey] ?: @"ca18a163";

    if (_baiduSDKInitialized) {
        if (completion) {
            completion(YES);
        }
        return;
    }

    // 关闭百度 SDK 内置 debug 日志（默认开启）。
    // 百度 debug 日志会在主线程大量打印，实测会挤占主线程导致竞价回包被延迟（gdt_bid 超 2s），
    // 生产环境一律关闭，仅在定位百度自身问题时临时打开。
    [[BaiduMobAdSetting sharedInstance] setDebugLogEnable:NO];

    [BaiduMobAdManager setAppsid:_baiduAppId];
    [BaiduMobAdManager startWithCompletionHandler:^(BOOL success, NSError * _Nullable error) {
        _baiduSDKInitialized = success;
        if (success) {
            ADXLogInfo(@"百度 SDK 启动成功，appId: %@，SDKVersion: %@", _baiduAppId, [BaiduMobAdManager getSDKVersion]);
        } else {
            ADXLogError(@"百度 SDK 启动失败，error: %@", error);
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

    BaiduMobAdSplash *splash = [[BaiduMobAdSplash alloc] init];
    splash.delegate = self;
    splash.publisherId = _baiduAppId ?: @"ca18a163";
    splash.adUnitTag = sourceInfo.placementId;
    splash.adSize = [UIScreen mainScreen].bounds.size;
    splash.timeout = sourceInfo.timeout;
    splash.bidFloor = (int)sourceInfo.floorEcpm;  // 客户端底价过滤（单位：分）
    self.splashAd = splash;

    // 仅请求不展示，广告就绪后由引擎结算决定是否 show
    [splash load];
}

- (void)notifyWinWithCostPrice:(NSInteger)costPrice
                     lossPrice:(NSInteger)lossPrice
{
    if (!self.splashAd) {
        return;
    }

    // 竞胜上报：上报竞败方（排名第二）的出价，单位：分
    NSDictionary *secondInfo = @{@"ecpm": @(lossPrice)};
    [self.splashAd biddingSuccessWithSecondInfo:secondInfo
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
    if (!self.splashAd) {
        return;
    }

    // 竞败上报：上报竞胜方出价，单位：分
    NSDictionary *winInfo = @{@"ecpm": @(winPrice)};
    [self.splashAd biddingFailWithWinInfo:winInfo
                               completion:^(BOOL success, NSString *errorInfo) {
        if (!success) {
            ADXLogError(@"百度竞败上报失败：%@", errorInfo);
        }
    }];

    // 竞败释放资源
    [self.splashAd stop];
    self.splashAd = nil;
}

- (void)showSplashAdWithResult:(ADXBidResult *)result
                        window:(UIWindow *)window
                    completion:(void (^)(BOOL success, NSError * _Nullable error))completion
{
    // 预检：广告对象已释放（可能已被竞败清理）或未就绪（缓存失败/已过期），回 NO 触发上层降级
    if (!self.splashAd || !window) {
        completion(NO, [NSError errorWithDomain:@"ADXBaiduSplashAdapter"
                                            code:-1
                                        userInfo:@{NSLocalizedDescriptionKey: @"广告对象已释放或 window 为空"}]);
        return;
    }
    if (![self.splashAd isReady]) {
        ADXLogError(@"%@ 展示时广告未就绪（缓存失败或已过期）", self.currentSourceInfo.sourceId);
        completion(NO, [NSError errorWithDomain:@"ADXBaiduSplashAdapter"
                                            code:-2
                                        userInfo:@{NSLocalizedDescriptionKey: @"广告未就绪（缓存失败或已过期）"}]);
        return;
    }

    UIView *containerView = [[UIView alloc] initWithFrame:window.bounds];
    containerView.backgroundColor = [UIColor blackColor];
    containerView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    [window addSubview:containerView];
    self.containerView = containerView;

    // 百度展示失败回调（splashAdShowFail）无法携带到本 completion，预检通过、
    // 展示发起成功即视为成功
    [self.splashAd showInContainerView:containerView];
    completion(YES, nil);
}

#pragma mark - BaiduMobAdSplashDelegate

- (void)splashAdLoadSuccess:(BaiduMobAdSplash *)splash
{
    // 请求成功，等待素材缓存完成（splashAdCacheSuccess 才代表可展示）
    ADXLogInfo(@"%@ 请求成功，等待素材缓存（百度）", self.currentSourceInfo.sourceId);
}

- (void)splashAdCacheSuccess:(BaiduMobAdSplash *)splash
{
    if (!self.loadCompletion) {
        return;
    }

    NSString *pecpm = [splash getPECPM];
    NSString *ecpmLevel = [splash getECPMLevel];
    ADXLogInfo(@"%@ 竞价原始数据：pECPM=%@，价格标签=%@（百度 SDK %@）",
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
                ADXLogInfo(@"%@ 缓存成功：pECPM 无值，降级用价格标签 %@ ≈ %ld 分（竞价源）",
                           self.currentSourceInfo.sourceId, ecpmLevel, (long)price);
            } else {
                ADXLogError(@"%@ 缓存成功但实时 eCPM 获取失败（竞价源）", self.currentSourceInfo.sourceId);
                [self deliverFailResultWithError:[NSError errorWithDomain:@"ADXBaiduSplashAdapter"
                                                                     code:-3
                                                                 userInfo:@{NSLocalizedDescriptionKey: @"竞价源实时 eCPM 获取失败"}]];
                return;
            }
        } else {
            price = pecpm.integerValue;
            ADXLogInfo(@"%@ 缓存成功：实时 eCPM=%@（竞价源，SDKVersion=%@）",
                       self.currentSourceInfo.sourceId, pecpm, [BaiduMobAdManager getSDKVersion]);
        }
    } else {
        // 瀑布源：优先真实 eCPM，无权限访问时 fallback 到预设 floorEcpm
        price = pecpm.length > 0 ? pecpm.integerValue : self.currentSourceInfo.floorEcpm;
        ADXLogInfo(@"%@ 缓存成功：实时 eCPM=%@（%@）",
                   self.currentSourceInfo.sourceId,
                   pecpm.length > 0 ? pecpm : @"无",
                   pecpm.length > 0 ? @"实时价" : [NSString stringWithFormat:@"无实时价，使用 floor=%ld（瀑布源）", (long)self.currentSourceInfo.floorEcpm]);
    }

    ADXBidResult *result = [ADXBidResult resultWithSourceId:self.currentSourceInfo.sourceId
                                                     adType:self.currentSourceInfo.adType
                                                      price:price
                                                   adObject:splash
                                                    success:YES
                                                      error:nil];
    self.loadCompletion(result);
    self.loadCompletion = nil;
}

- (void)splashAdCacheFail:(BaiduMobAdSplash *)splash
{
    if (!self.loadCompletion) {
        return;
    }

    ADXLogError(@"%@ 素材缓存失败（百度）", self.currentSourceInfo.sourceId);
    [self deliverFailResultWithError:[NSError errorWithDomain:@"ADXBaiduSplashAdapter"
                                                         code:-2
                                                     userInfo:@{NSLocalizedDescriptionKey: @"素材缓存失败"}]];
}

- (void)splashAdLoadFailCode:(NSString *)errCode
                     message:(NSString *)message
                    splashAd:(BaiduMobAdSplash *)splashAd
{
    if (!self.loadCompletion) {
        return;
    }

    ADXLogError(@"%@ 请求失败（百度）：[%@] %@", self.currentSourceInfo.sourceId, errCode, message);
    [self deliverFailResultWithError:[NSError errorWithDomain:@"ADXBaiduSplashAdapter"
                                                         code:-1
                                                     userInfo:@{NSLocalizedDescriptionKey: [NSString stringWithFormat:@"[%@] %@", errCode, message ?: @""]}]];
}

- (void)splashDidExposure:(BaiduMobAdSplash *)splash
{
    ADXLogInfo(@"%@ 开屏已曝光（百度）", self.currentSourceInfo.sourceId);
}

- (void)splashDidClicked:(BaiduMobAdSplash *)splash
{
    ADXLogInfo(@"%@ 开屏被点击（百度）", self.currentSourceInfo.sourceId);
}

- (void)splashDidDismissScreen:(BaiduMobAdSplash *)splash
{
    ADXLogInfo(@"%@ 开屏已关闭（百度）", self.currentSourceInfo.sourceId);
    [self clearAdResources];
}

- (void)splashlFailPresentScreen:(BaiduMobAdSplash *)splash withError:(BaiduMobFailReason)reason
{
    ADXLogError(@"%@ 开屏展示失败（百度）：reason=%ld", self.currentSourceInfo.sourceId, (long)reason);
    [self clearAdResources];
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

- (void)deliverFailResultWithError:(NSError *)error
{
    if (!self.loadCompletion) {
        return;
    }

    ADXBidResult *result = [ADXBidResult resultWithSourceId:self.currentSourceInfo.sourceId
                                                     adType:self.currentSourceInfo.adType
                                                      price:0
                                                   adObject:nil
                                                    success:NO
                                                      error:error];
    self.loadCompletion(result);
    self.loadCompletion = nil;

    [self clearAdResources];
}

- (void)clearAdResources
{
    [self.containerView removeFromSuperview];
    self.containerView = nil;
    [self.splashAd stop];
    self.splashAd = nil;
}

@end
