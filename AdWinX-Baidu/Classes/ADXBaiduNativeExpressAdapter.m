//
//  ADXBaiduNativeExpressAdapter.m
//  AdWinX
//
//  Created by AdWinX on 2026/08/31.
//

#import "ADXBaiduNativeExpressAdapter.h"
#import "ADXAdSourceInfo.h"
#import "ADXBidResult.h"
#import "ADXLogger.h"
#import <BaiduMobAdSDK/BaiduMobAdSDK.h>
#import <UIKit/UIKit.h>

static BOOL _baiduNativeSDKInitialized = NO;
static NSString *_baiduNativeAppId = nil;

@interface ADXBaiduNativeExpressAdapter () <BaiduMobAdNativeAdDelegate, BaiduMobAdNativeInterationDelegate>

@property (nonatomic, strong, nullable) BaiduMobAdNative *nativeAd;
@property (nonatomic, strong, nullable) BaiduMobAdExpressNativeView *nativeAdView;
@property (nonatomic, copy, nullable) void (^loadCompletion)(ADXBidResult *result);
/// 渲染结果回调（render 异步，成功/失败时各回调一次后清空）
@property (nonatomic, copy, nullable) void (^renderCompletion)(UIView * _Nullable adView, NSError * _Nullable error);
@property (nonatomic, strong, nullable) ADXAdSourceInfo *currentSourceInfo;

@end

@implementation ADXBaiduNativeExpressAdapter

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
    _baiduNativeAppId = adnConfig[kAppIdKey] ?: @"ca18a163";

    // 与开屏/激励 Adapter 各自持有静态去重变量，但底层 BaiduMobAdManager 启动幂等，
    // 多注册场景下由注册中心去重保证只调度一次
    if (_baiduNativeSDKInitialized) {
        if (completion) {
            completion(YES);
        }
        return;
    }

    // 关闭百度 SDK 内置 debug 日志（默认开启）。
    // 百度 debug 日志会在主线程大量打印，实测会挤占主线程拖慢竞价回包，生产环境一律关闭
    [[BaiduMobAdSetting sharedInstance] setDebugLogEnable:NO];

    [BaiduMobAdManager setAppsid:_baiduNativeAppId];
    [BaiduMobAdManager startWithCompletionHandler:^(BOOL success, NSError * _Nullable error) {
        _baiduNativeSDKInitialized = success;
        if (success) {
            ADXLogInfo(@"百度 SDK 启动成功（信息流 Adapter），appId: %@", _baiduNativeAppId);
        } else {
            ADXLogError(@"百度 SDK 启动失败（信息流 Adapter），error: %@", error);
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

    BaiduMobAdNative *nativeAd = [[BaiduMobAdNative alloc] init];
    nativeAd.publisherId = _baiduNativeAppId ?: @"ca18a163";
    nativeAd.adUnitTag = sourceInfo.placementId;
    nativeAd.adDelegate = self;
    nativeAd.adType = BaiduMobAdTypeFeed;
    // 优选模板（信息流模板）模式：delegate 返回 BaiduMobAdExpressNativeView 数组
    nativeAd.isExpressNativeAds = YES;
    nativeAd.baiduMobAdsWidth = @(adWidth);
    nativeAd.baiduMobAdsHeight = @(0.0);
    nativeAd.timeout = sourceInfo.timeout;
    nativeAd.bidFloor = (int)sourceInfo.floorEcpm;
    self.nativeAd = nativeAd;

    [nativeAd load];
}

- (void)notifyWinWithCostPrice:(NSInteger)costPrice
                     lossPrice:(NSInteger)lossPrice
{
    if (!self.nativeAdView) {
        return;
    }

    // 竞胜上报：上报竞败方（排名第二）的出价，单位：分
    NSDictionary *secondInfo = @{@"ecpm": @(lossPrice)};
    [self.nativeAdView biddingSuccessWithSecondInfo:secondInfo
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
    if (!self.nativeAdView) {
        return;
    }

    // 竞败上报：上报竞胜方出价，单位：分
    NSDictionary *winInfo = @{@"ecpm": @(winPrice)};
    [self.nativeAdView biddingFailWithWinInfo:winInfo
                                   completion:^(BOOL success, NSString *errorInfo) {
        if (!success) {
            ADXLogError(@"百度竞败上报失败：%@", errorInfo);
        }
    }];

    // 竞败释放资源
    [self cleanupAd];
}

- (void)renderNativeAdViewWithResult:(ADXBidResult *)result
                    rootViewController:(UIViewController *)rootViewController
                            completion:(void (^)(UIView * _Nullable adView, NSError * _Nullable error))completion
{
    // 预检：广告视图已释放（可能已被竞败清理）或渲染控制器为空
    if (!self.nativeAdView || !rootViewController) {
        ADXLogError(@"%@ 渲染失败：广告视图已释放或渲染控制器为空", result.sourceId);
        completion(nil, [NSError errorWithDomain:@"ADXBaiduNativeExpressAdapter"
                                            code:-1
                                        userInfo:@{NSLocalizedDescriptionKey: @"广告视图已释放或渲染控制器为空"}]);
        return;
    }
    // 预检：广告过期（默认 2h 有效期，过期需重新请求）
    if ([self.nativeAdView isExpired]) {
        ADXLogError(@"%@ 渲染失败：广告已过期", result.sourceId);
        completion(nil, [NSError errorWithDomain:@"ADXBaiduNativeExpressAdapter"
                                            code:-2
                                        userInfo:@{NSLocalizedDescriptionKey: @"广告已过期"}]);
        return;
    }

    self.renderCompletion = completion;
    // 百度模板广告落地页由视图内部处理，baseViewController 必须在 render 前设置
    self.nativeAdView.baseViewController = rootViewController;
    self.nativeAdView.interationDelegate = self;
    self.nativeAdView.width = self.currentSourceInfo.adWidth > 0 ? self.currentSourceInfo.adWidth : CGRectGetWidth([UIScreen mainScreen].bounds);
    [self.nativeAdView setExpressTheme:BaiduMobAdExpressNativeNormalTheme];
    [self.nativeAdView render];
}

#pragma mark - BaiduMobAdNativeAdDelegate

- (void)nativeAdObjectsSuccessLoad:(NSArray *)nativeAds nativeAd:(BaiduMobAdNative *)nativeAd
{
    if (!self.loadCompletion) {
        return;
    }

    BaiduMobAdExpressNativeView *expressView = [nativeAds.firstObject isKindOfClass:[BaiduMobAdExpressNativeView class]] ? nativeAds.firstObject : nil;
    if (!expressView) {
        ADXLogError(@"%@ 请求成功但返回数据不是优选模板视图（百度）", self.currentSourceInfo.sourceId);
        [self deliverResultWithSuccess:NO price:0 error:[NSError errorWithDomain:@"ADXBaiduNativeExpressAdapter"
                                                                             code:-1
                                                                         userInfo:@{NSLocalizedDescriptionKey: @"请求成功但返回数据不是优选模板视图"}]];
        return;
    }
    self.nativeAdView = expressView;

    NSString *pecpm = [expressView getPECPM];
    NSString *ecpmLevel = [expressView getECPMLevel];
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
                [self deliverResultWithSuccess:NO price:0 error:[NSError errorWithDomain:@"ADXBaiduNativeExpressAdapter"
                                                                                     code:-3
                                                                                 userInfo:@{NSLocalizedDescriptionKey: @"竞价源实时 eCPM 获取失败"}]];
                return;
            }
        } else {
            price = pecpm.integerValue;
            ADXLogInfo(@"%@ 实时 eCPM=%@（竞价源，百度）", self.currentSourceInfo.sourceId, pecpm);
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

- (void)nativeAdsFailLoadCode:(NSString *)errCode
                      message:(NSString *)message
                     nativeAd:(BaiduMobAdNative *)nativeAd
                     adObject:(BaiduMobAdNativeAdObject *)adObject
{
    if (!self.loadCompletion) {
        return;
    }

    ADXLogError(@"%@ 请求失败（百度）：[%@] %@", self.currentSourceInfo.sourceId, errCode, message);
    [self deliverResultWithSuccess:NO price:0 error:[NSError errorWithDomain:@"ADXBaiduNativeExpressAdapter"
                                                                        code:-1
                                                                    userInfo:@{NSLocalizedDescriptionKey: [NSString stringWithFormat:@"[%@] %@", errCode, message ?: @""]}]];
}

// 模板宽高：请求参数由 BaiduMobAdNative 属性传入，这里返回同值保持一致
- (NSNumber *)baiduMobAdsWidth
{
    return @(self.currentSourceInfo.adWidth > 0 ? self.currentSourceInfo.adWidth : CGRectGetWidth([UIScreen mainScreen].bounds));
}

- (NSNumber *)baiduMobAdsHeight
{
    return @(0.0);
}

#pragma mark - BaiduMobAdNativeInterationDelegate

- (void)nativeAdExpressSuccessRender:(BaiduMobAdExpressNativeView *)express
                            nativeAd:(BaiduMobAdNative *)nativeAd
{
    if (!self.renderCompletion) {
        return;
    }

    ADXLogInfo(@"%@ 信息流渲染成功（百度），高度 %.0f", self.currentSourceInfo.sourceId, express.height);
    self.renderCompletion(express, nil);
    self.renderCompletion = nil;
}

- (void)nativeAdExposure:(UIView *)nativeAdView nativeAdDataObject:(BaiduMobAdNativeAdObject *)object
{
    ADXLogInfo(@"%@ 信息流已曝光（百度）", self.currentSourceInfo.sourceId);
}

- (void)nativeAdClicked:(UIView *)nativeAdView nativeAdDataObject:(BaiduMobAdNativeAdObject *)object
{
    ADXLogInfo(@"%@ 信息流被点击（百度）", self.currentSourceInfo.sourceId);
}

- (void)nativeAdCloseClick:(UIView *)adView
{
    ADXLogInfo(@"%@ 信息流关闭按钮被点击（百度）", self.currentSourceInfo.sourceId);
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
                                                   adObject:success ? self.nativeAdView : nil
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
    self.nativeAd.adDelegate = nil;
    self.nativeAd = nil;
    if (self.nativeAdView) {
        [self.nativeAdView destroyExpressView];
    }
    self.nativeAdView = nil;
}

@end
