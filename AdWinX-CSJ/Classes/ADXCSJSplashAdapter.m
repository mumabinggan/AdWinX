//
//  ADXCSJSplashAdapter.m
//  AdWinX
//
//  Created by AdWinX on 2026/08/29.
//

#import "ADXCSJSplashAdapter.h"
#import "ADXAdSourceInfo.h"
#import "ADXBidResult.h"
#import "ADXLogger.h"
#import <BUAdSDK/BUAdSDK.h>

static BOOL _csjSDKInitialized = NO;

@interface ADXCSJSplashAdapter () <BUSplashAdDelegate>

@property (nonatomic, strong) BUSplashAd *splashAd;
@property (nonatomic, copy) void (^loadCompletion)(ADXBidResult *result);
@property (nonatomic, strong) ADXAdSourceInfo *currentSourceInfo;

@end

@implementation ADXCSJSplashAdapter

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

    if (_csjSDKInitialized) {
        if (completion) {
            completion(YES);
        }
        return;
    }

    BUAdSDKConfiguration *configuration = [BUAdSDKConfiguration configuration];
    configuration.appID = appId;

    [BUAdSDKManager startWithAsyncCompletionHandler:^(BOOL success, NSError *error) {
        _csjSDKInitialized = success;
        if (success) {
            ADXLogInfo(@"穿山甲 SDK 启动成功，appId: %@", appId);
        } else {
            ADXLogError(@"穿山甲 SDK 启动失败，error: %@", error);
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

    CGSize adSize = [UIScreen mainScreen].bounds.size;
    self.splashAd = [[BUSplashAd alloc] initWithSlotID:sourceInfo.placementId adSize:adSize];
    self.splashAd.delegate = self;
    self.splashAd.tolerateTimeout = sourceInfo.timeout;
    [self.splashAd loadAdData];
}

- (void)notifyWinWithCostPrice:(NSInteger)costPrice
                     lossPrice:(NSInteger)lossPrice
{
    if (!self.splashAd) {
        return;
    }

    // 穿山甲 BUAdClientBiddingProtocol：先设置实际结算价，再通知竞胜（传第二名出价）
    [self.splashAd setPrice:@(costPrice)];
    [self.splashAd win:@(lossPrice)];
}

- (void)notifyLossWithWinPrice:(NSInteger)winPrice
                    lossReason:(NSInteger)lossReason
                   winnerAdnId:(NSString *)winnerAdnId
{
    if (!self.splashAd) {
        return;
    }

    // 穿山甲 lossReason 为字符串，直接透传引擎的原因码
    NSString *reason = [NSString stringWithFormat:@"%ld", (long)lossReason];
    [self.splashAd loss:@(winPrice) lossReason:reason winBidder:winnerAdnId];
}

- (void)showSplashAdWithResult:(ADXBidResult *)result
                        window:(UIWindow *)window
                    completion:(void (^)(BOOL success, NSError * _Nullable error))completion
{
    // 预检：splashView 在加载/渲染成功时才有值，关闭后被 SDK 置 nil，
    // 可作为广告有效性判断（新版 Ads-CN SDK 无 isAdValid 方法）
    if (!self.splashAd || !self.splashAd.splashView) {
        ADXLogError(@"%@ 展示失败：广告对象已释放或已失效", result.sourceId);
        completion(NO, [NSError errorWithDomain:@"ADXCSJSplashAdapter"
                                            code:-1
                                        userInfo:@{NSLocalizedDescriptionKey: @"广告对象已释放或已失效"}]);
        return;
    }

    UIViewController *rootViewController = window.rootViewController;
    if (!rootViewController) {
        completion(NO, [NSError errorWithDomain:@"ADXCSJSplashAdapter"
                                            code:-2
                                        userInfo:@{NSLocalizedDescriptionKey: @"window 无 rootViewController"}]);
        return;
    }

    // 穿山甲无独立的展示失败回调：预检通过、展示发起成功即视为成功
    [self.splashAd showSplashViewInRootViewController:rootViewController];
    completion(YES, nil);
}

#pragma mark - BUSplashAdDelegate

- (void)splashAdLoadSuccess:(BUSplashAd *)splashAd
{
    if (!self.loadCompletion) {
        return;
    }

    // 穿山甲瀑布源无实时价格，使用预设 floorEcpm 作为比价价格
    ADXLogInfo(@"%@ 加载成功：无实时价，使用 floor=%ld（瀑布源）",
               self.currentSourceInfo.sourceId, (long)self.currentSourceInfo.floorEcpm);
    ADXBidResult *result = [ADXBidResult resultWithSourceId:self.currentSourceInfo.sourceId
                                                     adType:self.currentSourceInfo.adType
                                                      price:self.currentSourceInfo.floorEcpm
                                                   adObject:splashAd
                                                    success:YES
                                                      error:nil];
    self.loadCompletion(result);
    self.loadCompletion = nil;
}

- (void)splashAdLoadFail:(BUSplashAd *)splashAd error:(BUAdError *)error
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
}

- (void)splashAdRenderSuccess:(BUSplashAd *)splashAd
{
}

- (void)splashAdRenderFail:(BUSplashAd *)splashAd error:(BUAdError *)error
{
    ADXLogError(@"%@ 渲染失败：%@", self.currentSourceInfo.sourceId, error);
}

- (void)splashAdWillShow:(BUSplashAd *)splashAd
{
}

- (void)splashAdDidShow:(BUSplashAd *)splashAd
{
    ADXLogInfo(@"%@ 开屏已展示（穿山甲）", self.currentSourceInfo.sourceId);
}

- (void)splashAdDidClick:(BUSplashAd *)splashAd
{
    ADXLogInfo(@"%@ 开屏被点击（穿山甲）", self.currentSourceInfo.sourceId);
}

- (void)splashAdDidClose:(BUSplashAd *)splashAd closeType:(BUSplashAdCloseType)closeType
{
    ADXLogInfo(@"%@ 开屏已关闭（穿山甲，closeType=%ld）", self.currentSourceInfo.sourceId, (long)closeType);
}

- (void)splashAdViewControllerDidClose:(BUSplashAd *)splashAd
{
}

- (void)splashDidCloseOtherController:(BUSplashAd *)splashAd interactionType:(BUInteractionType)interactionType
{
}

- (void)splashVideoAdDidPlayFinish:(BUSplashAd *)splashAd didFailWithError:(NSError *)error
{
}

- (void)splashCardReadyToShow:(BUSplashAd *)splashAd
{
}

- (void)splashCardViewDidClick:(BUSplashAd *)splashAd
{
}

- (void)splashCardViewDidClose:(BUSplashAd *)splashAd
{
}

@end