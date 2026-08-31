//
//  ADSigmobGlobalAdManager.m
//  AdWinX
//
//  Created by Trae on 08/16/2026.
//

#import "ADSigmobGlobalAdManager.h"
#import "ADAdDemoConstants.h"
#import <WindSDK/WindSDK.h>

@interface ADSigmobGlobalAdManager () <WindSplashAdViewDelegate, WindRewardVideoAdDelegate>

@property (nonatomic, assign) BOOL sdkStarted;
@property (nonatomic, assign) BOOL splashAdLoading;
@property (nonatomic, strong) WindSplashAdView *splashAdView;
@property (nonatomic, strong) WindRewardVideoAd *rewardVideoAd;
@property (nonatomic, copy) ADSigmobAdStatusHandler splashStatusHandler;
@property (nonatomic, copy) ADSigmobAdStatusHandler rewardStatusHandler;
@property (nonatomic, strong) UIWindow *splashWindow;
@property (nonatomic, weak) UIViewController *rewardRootViewController;

@end

@implementation ADSigmobGlobalAdManager

+ (instancetype)sharedManager
{
    static ADSigmobGlobalAdManager *manager;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        manager = [[ADSigmobGlobalAdManager alloc] init];
    });
    return manager;
}

- (void)setupSDK
{
    if (self.sdkStarted) {
        return;
    }

    [WindAds setDebugEnable:YES];
    WindAdOptions *options = [[WindAdOptions alloc] initWithAppId:ADSigmobAppId appKey:ADSigmobAppKey];
    [WindAds startWithOptions:options];
    self.sdkStarted = YES;
    NSLog(@"Sigmob SDK 启动完成，AppID: %@, SDKVersion: %@", ADSigmobAppId, [WindAds sdkVersion]);
}

- (void)loadAndShowSplashWithPlacementId:(NSString *)placementId
                      rootViewController:(UIViewController *)rootViewController
                                  window:(UIWindow *)window
                           statusHandler:(ADSigmobAdStatusHandler)statusHandler
{
    [self setupSDK];
    self.splashStatusHandler = statusHandler;
    if (self.splashAdLoading) {
        [self updateSplashStatus:@"开屏广告已有请求进行中，忽略重复请求" loading:YES];
        return;
    }

    self.splashWindow = window ?: rootViewController.view.window ?: [UIApplication sharedApplication].keyWindow;
    if (placementId.length == 0 || !self.splashWindow) {
        [self updateSplashStatus:@"开屏广告缺少广告位或展示窗口" loading:NO];
        return;
    }

    [self clearSplashAd];
    WindAdRequest *request = [WindAdRequest request];
    request.placementId = placementId;
    self.splashAdView = [[WindSplashAdView alloc] initWithRequest:request];
    self.splashAdView.delegate = self;
    self.splashAdView.rootViewController = rootViewController;
    self.splashAdView.fetchDelay = 8;
    self.splashAdView.frame = self.splashWindow.bounds;
    self.splashAdView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    [self.splashWindow addSubview:self.splashAdView];
    [self.splashWindow bringSubviewToFront:self.splashAdView];
    self.splashAdLoading = YES;
    NSString *source = statusHandler ? @"detail" : @"launch";
    NSLog(@"Sigmob 开屏开始请求 source=%@ placementId=%@ fetchDelay=%d splashAdView=%@ superview=%@ window=%@ rootVC=%@", source, placementId, self.splashAdView.fetchDelay, self.splashAdView, self.splashAdView.superview, self.splashWindow, rootViewController);
    [self updateSplashStatus:@"开屏广告加载中..." loading:YES];
    [self.splashAdView loadAdData];
}

- (void)loadAndShowRewardWithPlacementId:(NSString *)placementId
                       rootViewController:(UIViewController *)rootViewController
                            statusHandler:(ADSigmobAdStatusHandler)statusHandler
{
    [self setupSDK];
    self.rewardStatusHandler = statusHandler;
    self.rewardRootViewController = rootViewController;
    if (placementId.length == 0 || !rootViewController) {
        [self updateRewardStatus:@"激励视频缺少广告位或展示控制器" loading:NO];
        return;
    }

    WindAdRequest *request = [WindAdRequest request];
    request.placementId = placementId;
    request.userId = @"AdWinXUser";
    self.rewardVideoAd = [[WindRewardVideoAd alloc] initWithRequest:request];
    self.rewardVideoAd.delegate = self;
    [self updateRewardStatus:@"激励视频加载中..." loading:YES];
    [self.rewardVideoAd loadAdData];
}

#pragma mark - WindSplashAdViewDelegate

- (void)onSplashAdDidLoad:(WindSplashAdView *)splashAdView
{
    NSLog(@"ecpm==%@", [splashAdView getEcpm]);
    self.splashAdLoading = NO;
    UIWindow *window = self.splashWindow ?: splashAdView.window ?: [UIApplication sharedApplication].keyWindow;
    if (splashAdView.isAdValid && window) {
        self.splashWindow = window;
        splashAdView.hidden = NO;
        splashAdView.alpha = 1.0;
        splashAdView.userInteractionEnabled = YES;
        splashAdView.frame = window.bounds;
        if (splashAdView.superview != window) {
            [splashAdView removeFromSuperview];
            [window addSubview:splashAdView];
        }
        [window bringSubviewToFront:splashAdView];
        [window layoutIfNeeded];
    } else if (!splashAdView.isAdValid) {
        [self clearSplashAd];
    }
    [self updateSplashStatus:[NSString stringWithFormat:@"开屏广告加载成功，准备展示 isAdValid=%@ superview=%@ window=%@ frame=%@ hidden=%@ alpha=%.2f", splashAdView.isAdValid ? @"YES" : @"NO", splashAdView.superview, window, NSStringFromCGRect(splashAdView.frame), splashAdView.hidden ? @"YES" : @"NO", splashAdView.alpha] loading:NO];
}

- (void)onSplashAdLoadFail:(WindSplashAdView *)splashAdView error:(NSError *)error
{
    [self updateSplashStatus:[self statusTextForError:error prefix:@"开屏广告加载失败"] loading:NO];
    [self clearSplashAd];
}

- (void)onSplashAdSuccessPresentScreen:(WindSplashAdView *)splashAdView
{
    [self updateSplashStatus:@"开屏广告已曝光" loading:NO];
}

- (void)onSplashAdFailToPresent:(WindSplashAdView *)splashAdView withError:(NSError *)error
{
    [self updateSplashStatus:[self statusTextForError:error prefix:@"开屏广告展示失败"] loading:NO];
    [self clearSplashAd];
}

- (void)onSplashAdClicked:(WindSplashAdView *)splashAdView
{
    [self updateSplashStatus:@"开屏广告已点击" loading:NO];
}

- (void)onSplashAdSkiped:(WindSplashAdView *)splashAdView
{
    [self updateSplashStatus:@"开屏广告已跳过" loading:NO];
}

- (void)onSplashAdClosed:(WindSplashAdView *)splashAdView
{
    [self updateSplashStatus:@"开屏广告已关闭" loading:NO];
    [self clearSplashAd];
}

#pragma mark - WindRewardVideoAdDelegate

- (void)rewardVideoAdServerResponse:(WindRewardVideoAd *)rewardVideoAd isFillAd:(BOOL)isFillAd {
    NSLog(@"response ecpm==%@:%d", [rewardVideoAd getEcpm], isFillAd);
}

- (void)rewardVideoAdDidLoad:(WindRewardVideoAd *)rewardVideoAd
{
    NSLog(@"ecpm==%@", [rewardVideoAd getEcpm]);
    [self updateRewardStatus:@"激励视频加载成功，准备展示" loading:NO];
    if (rewardVideoAd.isAdReady) {
        [rewardVideoAd showAdFromRootViewController:self.rewardRootViewController options:nil];
    }
}

- (void)rewardVideoAdDidLoad:(WindRewardVideoAd *)rewardVideoAd didFailWithError:(NSError *)error
{
    [self updateRewardStatus:[self statusTextForError:error prefix:@"激励视频加载失败"] loading:NO];
    self.rewardVideoAd = nil;
}

- (void)rewardVideoAdDidShowFailed:(WindRewardVideoAd *)rewardVideoAd error:(NSError *)error
{
    [self updateRewardStatus:[self statusTextForError:error prefix:@"激励视频展示失败"] loading:NO];
    self.rewardVideoAd = nil;
}

- (void)rewardVideoAdDidVisible:(WindRewardVideoAd *)rewardVideoAd
{
    [self updateRewardStatus:@"激励视频已曝光" loading:NO];
}

- (void)rewardVideoAdDidClick:(WindRewardVideoAd *)rewardVideoAd
{
    [self updateRewardStatus:@"激励视频已点击" loading:NO];
}

- (void)rewardVideoAd:(WindRewardVideoAd *)rewardVideoAd reward:(WindRewardInfo *)reward
{
    [self updateRewardStatus:[NSString stringWithFormat:@"激励达成：%@", reward] loading:NO];
}

- (void)rewardVideoAdDidPlayFinish:(WindRewardVideoAd *)rewardVideoAd didFailWithError:(NSError *)error
{
    NSString *status = error ? [self statusTextForError:error prefix:@"激励视频播放失败"] : @"激励视频播放完成";
    [self updateRewardStatus:status loading:NO];
}

- (void)rewardVideoAdDidClose:(WindRewardVideoAd *)rewardVideoAd
{
    [self updateRewardStatus:@"激励视频已关闭" loading:NO];
    self.rewardVideoAd = nil;
}

#pragma mark - Private

- (void)updateSplashStatus:(NSString *)status loading:(BOOL)loading
{
    if (!self.splashStatusHandler) {
        NSLog(@"Sigmob 开屏 %@", status);
    }
    if (self.splashStatusHandler) {
        self.splashStatusHandler(status, loading);
    }
}

- (void)updateRewardStatus:(NSString *)status loading:(BOOL)loading
{
    NSLog(@"Sigmob 激励 %@", status);
    if (self.rewardStatusHandler) {
        self.rewardStatusHandler(status, loading);
    }
}

- (void)clearSplashAd
{
    self.splashAdLoading = NO;
    [self.splashAdView removeFromSuperview];
    self.splashAdView = nil;
    self.splashWindow = nil;
}

- (NSString *)statusTextForError:(NSError *)error prefix:(NSString *)prefix
{
    if (!error) {
        return prefix;
    }

    NSString *message = error.localizedDescription.length > 0 ? error.localizedDescription : @"无描述";
    if ([error.domain isEqualToString:@"Wind"] && error.code == 600010) {
        message = [message stringByAppendingString:@"，已将测试阶段开屏超时时间调整为 8 秒，请同时检查网络、后台填充和测试设备白名单"];
    }
    return [NSString stringWithFormat:@"%@：domain=%@ code=%ld message=%@ userInfo=%@", prefix, error.domain, (long)error.code, message, error.userInfo];
}

@end
