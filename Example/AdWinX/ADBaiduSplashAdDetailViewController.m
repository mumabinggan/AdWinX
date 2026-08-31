//
//  ADBaiduSplashAdDetailViewController.m
//  AdWinX
//
//  Created by Trae on 08/15/2026.
//

#import "ADBaiduSplashAdDetailViewController.h"
#import <BaiduMobAdSDK/BaiduMobAdSplash.h>

@interface ADBaiduSplashAdDetailViewController () <BaiduMobAdSplashDelegate>

@property (nonatomic, strong) BaiduMobAdSplash *splashAd;
@property (nonatomic, strong) UIView *splashContainerView;
@property (nonatomic, assign) BOOL splashAdDisplayed;

@end

@implementation ADBaiduSplashAdDetailViewController

- (void)loadAd
{
    self.splashAdDisplayed = NO;
    [self prepareSplashContainerView];
    self.splashAd = [[BaiduMobAdSplash alloc] init];
    self.splashAd.delegate = self;
    self.splashAd.publisherId = self.appId;
    self.splashAd.adUnitTag = self.placementId;
    self.splashAd.presentAdViewController = self;
    self.splashAd.timeout = 5.0;
    [self.splashAd loadAndDisplayUsingContainerView:self.splashContainerView];
}

- (void)splashAdLoadSuccess:(BaiduMobAdSplash *)splash
{
    NSLog(@"pecmp:%@:%@:%@", splash.getPECPM, splash.getECPMLevel, splash.getExtData);
    [self updateStatus:@"开屏广告请求成功，等待缓存完成" loading:YES];
}

- (void)splashDidReady:(BaiduMobAdSplash *)splash AndAdType:(NSString *)adType VideoDuration:(NSInteger)videoDuration
{
    self.splashAdDisplayed = YES;
    [self updateStatus:[NSString stringWithFormat:@"开屏广告已准备并展示，类型=%@，视频时长=%ldms", adType ?: @"unknown", (long)videoDuration] loading:NO];
}

- (void)splashAdCacheSuccess:(BaiduMobAdSplash *)splash
{
    [self updateStatus:@"开屏广告缓存成功，等待 SDK 展示" loading:YES];
}

- (void)splashAdLoadFailCode:(NSString *)errCode message:(NSString *)message splashAd:(BaiduMobAdSplash *)splashAd
{
    [self removeSplashContainerView];
    [self updateStatus:[self baiduFailStatusWithPrefix:@"开屏广告请求失败" code:errCode message:message] loading:NO];
}

- (void)splashlFailPresentScreen:(BaiduMobAdSplash *)splash withError:(BaiduMobFailReason)reason
{
    [self removeSplashContainerView];
    self.splashAdDisplayed = NO;
    [self updateStatus:[NSString stringWithFormat:@"开屏广告展示失败：reason=%ld", (long)reason] loading:NO];
}

- (void)splashDidExposure:(BaiduMobAdSplash *)splash
{
    [self updateStatus:@"开屏广告曝光成功" loading:NO];
}

- (void)splashDidClicked:(BaiduMobAdSplash *)splash
{
    [self updateStatus:@"开屏广告被点击" loading:NO];
}

- (void)splashDidDismissScreen:(BaiduMobAdSplash *)splash
{
    [self removeSplashContainerView];
    [self updateStatus:@"开屏广告已关闭" loading:NO];
}

- (void)clearAdContainer
{
    [super clearAdContainer];
    [self removeSplashContainerView];
    [self.splashAd stop];
    self.splashAd = nil;
    self.splashAdDisplayed = NO;
}

- (void)prepareSplashContainerView
{
    [self removeSplashContainerView];

    UIWindow *window = [self adPresentationWindow];
    if (!window) {
        [self updateStatus:@"开屏广告展示失败：当前没有可用窗口" loading:NO];
        return;
    }

    UIView *containerView = [[UIView alloc] initWithFrame:window.bounds];
    containerView.backgroundColor = [UIColor blackColor];
    containerView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    [window addSubview:containerView];
    self.splashContainerView = containerView;
}

- (void)removeSplashContainerView
{
    [self.splashContainerView removeFromSuperview];
    self.splashContainerView = nil;
}

@end
