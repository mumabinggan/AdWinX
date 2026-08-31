//
//  ADXCSJRewardVideoAdapter.m
//  AdWinX
//
//  Created by AdWinX on 2026/08/30.
//

#import "ADXCSJRewardVideoAdapter.h"
#import "ADXAdSourceInfo.h"
#import "ADXBidResult.h"
#import "ADXLogger.h"
#import <BUAdSDK/BUAdSDK.h>

static BOOL _csjRewardSDKInitialized = NO;

@interface ADXCSJRewardVideoAdapter () <BUNativeExpressRewardedVideoAdDelegate>

@property (nonatomic, strong, nullable) BUNativeExpressRewardedVideoAd *rewardedVideoAd;
@property (nonatomic, copy, nullable) void (^loadCompletion)(ADXBidResult *result);
@property (nonatomic, strong, nullable) ADXAdSourceInfo *currentSourceInfo;
/// 激励达成回调（业务发奖用）
@property (nonatomic, copy, nullable) void (^rewardCallback)(BOOL granted);

@end

@implementation ADXCSJRewardVideoAdapter

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

    // 与开屏 Adapter 各自持有静态去重变量，但底层 BUAdSDKManager 启动幂等，
    // 双注册场景下（开屏 + 激励视频）由注册中心去重保证只调度一次
    if (_csjRewardSDKInitialized) {
        if (completion) {
            completion(YES);
        }
        return;
    }

    BUAdSDKConfiguration *configuration = [BUAdSDKConfiguration configuration];
    configuration.appID = appId;

    [BUAdSDKManager startWithAsyncCompletionHandler:^(BOOL success, NSError *error) {
        _csjRewardSDKInitialized = success;
        if (success) {
            ADXLogInfo(@"穿山甲 SDK 启动成功（激励视频 Adapter），appId: %@", appId);
        } else {
            ADXLogError(@"穿山甲 SDK 启动失败（激励视频 Adapter），error: %@", error);
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

    BURewardedVideoModel *model = [[BURewardedVideoModel alloc] init];
    model.userId = @"adwinx_user";

    self.rewardedVideoAd = [[BUNativeExpressRewardedVideoAd alloc] initWithSlotID:sourceInfo.placementId
                                                              rewardedVideoModel:model];
    self.rewardedVideoAd.delegate = self;
    [self.rewardedVideoAd loadAdData];
}

- (void)notifyWinWithCostPrice:(NSInteger)costPrice
                     lossPrice:(NSInteger)lossPrice
{
    if (!self.rewardedVideoAd) {
        return;
    }

    // 穿山甲 BUAdClientBiddingProtocol：先设置实际结算价，再通知竞胜（传第二名出价）
    [self.rewardedVideoAd setPrice:@(costPrice)];
    [self.rewardedVideoAd win:@(lossPrice)];
}

- (void)notifyLossWithWinPrice:(NSInteger)winPrice
                    lossReason:(NSInteger)lossReason
                   winnerAdnId:(NSString *)winnerAdnId
{
    if (!self.rewardedVideoAd) {
        return;
    }

    // 穿山甲 lossReason 为字符串，直接透传引擎的原因码
    NSString *reason = [NSString stringWithFormat:@"%ld", (long)lossReason];
    [self.rewardedVideoAd loss:@(winPrice) lossReason:reason winBidder:winnerAdnId];
}

- (void)showRewardVideoAdWithResult:(ADXBidResult *)result
                 fromViewController:(UIViewController *)rootViewController
                      rewardCallback:(nullable void (^)(BOOL granted))rewardCallback
                          completion:(void (^)(BOOL success, NSError * _Nullable error))completion
{
    // 预检：广告对象已释放（可能已被竞败清理）或展示控制器为空
    if (!self.rewardedVideoAd || !rootViewController) {
        ADXLogError(@"%@ 展示失败：广告对象已释放或展示控制器为空", result.sourceId);
        completion(NO, [NSError errorWithDomain:@"ADXCSJRewardVideoAdapter"
                                            code:-1
                                        userInfo:@{NSLocalizedDescriptionKey: @"广告对象已释放或展示控制器为空"}]);
        return;
    }

    self.rewardCallback = rewardCallback;

    // showAdFromRootViewController 返回 NO 即展示发起失败（未加载完/已过期），
    // 返回 YES 视为展示成功（穿山甲无独立的展示失败回调）
    BOOL shown = [self.rewardedVideoAd showAdFromRootViewController:rootViewController];
    if (shown) {
        ADXLogInfo(@"%@ 激励视频展示发起成功（穿山甲）", result.sourceId);
        completion(YES, nil);
    } else {
        ADXLogError(@"%@ 展示发起失败（穿山甲，showAd 返回 NO）", result.sourceId);
        completion(NO, [NSError errorWithDomain:@"ADXCSJRewardVideoAdapter"
                                            code:-2
                                        userInfo:@{NSLocalizedDescriptionKey: @"展示发起失败（showAd 返回 NO）"}]);
    }
}

#pragma mark - BUNativeExpressRewardedVideoAdDelegate

- (void)nativeExpressRewardedVideoAdDidLoad:(BUNativeExpressRewardedVideoAd *)rewardedVideoAd
{
    if (!self.loadCompletion) {
        return;
    }

    // 穿山甲瀑布源无实时价格 API，使用预设 floorEcpm 作为比价价格（与开屏 Adapter 一致）
    ADXLogInfo(@"%@ 加载成功：无实时价，使用 floor=%ld（瀑布源）",
               self.currentSourceInfo.sourceId, (long)self.currentSourceInfo.floorEcpm);
    ADXBidResult *result = [ADXBidResult resultWithSourceId:self.currentSourceInfo.sourceId
                                                     adType:self.currentSourceInfo.adType
                                                      price:self.currentSourceInfo.floorEcpm
                                                   adObject:rewardedVideoAd
                                                    success:YES
                                                      error:nil];
    self.loadCompletion(result);
    self.loadCompletion = nil;
}

- (void)nativeExpressRewardedVideoAd:(BUNativeExpressRewardedVideoAd *)rewardedVideoAd didFailWithError:(NSError *)error
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

- (void)nativeExpressRewardedVideoAdDidDownLoadVideo:(BUNativeExpressRewardedVideoAd *)rewardedVideoAd
{
    ADXLogInfo(@"%@ 视频缓存完成（穿山甲）", self.currentSourceInfo.sourceId);
}

- (void)nativeExpressRewardedVideoAdDidVisible:(BUNativeExpressRewardedVideoAd *)rewardedVideoAd
{
    ADXLogInfo(@"%@ 激励视频已曝光（穿山甲）", self.currentSourceInfo.sourceId);
}

- (void)nativeExpressRewardedVideoAdDidClick:(BUNativeExpressRewardedVideoAd *)rewardedVideoAd
{
    ADXLogInfo(@"%@ 激励视频被点击（穿山甲）", self.currentSourceInfo.sourceId);
}

- (void)nativeExpressRewardedVideoAdDidPlayFinish:(BUNativeExpressRewardedVideoAd *)rewardedVideoAd didFailWithError:(NSError *)error
{
    if (error) {
        ADXLogError(@"%@ 激励视频播放失败（穿山甲）：%@", self.currentSourceInfo.sourceId, error);
    } else {
        ADXLogInfo(@"%@ 激励视频播放完成（穿山甲）", self.currentSourceInfo.sourceId);
    }
}

- (void)nativeExpressRewardedVideoAdServerRewardDidSucceed:(BUNativeExpressRewardedVideoAd *)rewardedVideoAd verify:(BOOL)verify
{
    ADXLogInfo(@"%@ 激励达成（穿山甲，服务端校验 verify=%@）",
               self.currentSourceInfo.sourceId, verify ? @"YES" : @"NO");
    if (self.rewardCallback) {
        self.rewardCallback(YES);
        self.rewardCallback = nil;
    }
}

- (void)nativeExpressRewardedVideoAdServerRewardDidFail:(BUNativeExpressRewardedVideoAd *)rewardedVideoAd error:(NSError *)error
{
    ADXLogError(@"%@ 服务端激励校验失败（穿山甲）：%@", self.currentSourceInfo.sourceId, error);
    if (self.rewardCallback) {
        self.rewardCallback(NO);
        self.rewardCallback = nil;
    }
}

- (void)nativeExpressRewardedVideoAdDidClose:(BUNativeExpressRewardedVideoAd *)rewardedVideoAd
{
    ADXLogInfo(@"%@ 激励视频已关闭（穿山甲）", self.currentSourceInfo.sourceId);
    // 关闭时若激励回调尚未触发（用户提前关闭未看完），补发 granted=NO 供业务区分
    if (self.rewardCallback) {
        self.rewardCallback(NO);
        self.rewardCallback = nil;
    }
    [self cleanupAd];
}

#pragma mark - Private

- (void)cleanupAd
{
    self.rewardedVideoAd.delegate = nil;
    self.rewardedVideoAd = nil;
}

@end
