//
//  ADBaiduInterstitialAdDetailViewController.m
//  AdWinX
//
//  Created by Trae on 08/15/2026.
//

#import "ADBaiduInterstitialAdDetailViewController.h"
#import <BaiduMobAdSDK/BaiduMobAdExpressInterstitial.h>

@interface ADBaiduInterstitialAdDetailViewController () <BaiduMobAdExpressIntDelegate>

@property (nonatomic, strong) BaiduMobAdExpressInterstitial *interstitialAd;

@end

@implementation ADBaiduInterstitialAdDetailViewController

- (void)loadAd
{
    self.interstitialAd = [[BaiduMobAdExpressInterstitial alloc] init];
    self.interstitialAd.delegate = self;
    self.interstitialAd.publisherId = self.appId;
    self.interstitialAd.adUnitTag = self.placementId;
    self.interstitialAd.timeout = 20.0;
    self.interstitialAd.enableLocation = true;
    [self.interstitialAd load];
}

- (void)interstitialAdLoaded:(BaiduMobAdExpressInterstitial *)interstitial
{
    NSLog(@"Ecmp:%@:%@", interstitial.getPECPM, interstitial.getECPMLevel);
    [self updateStatus:@"插屏广告加载成功，准备展示" loading:NO];
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(3 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        NSLog(@"Ecmp:==:%@:%d:%@", interstitial.getECPMLevel, [interstitial isReady], interstitial);
        [interstitial showFromViewController:self];
    });
    
//    if ([interstitial isReady]) {
//        NSLog(@"isReady");
//        [interstitial show];
////        [interstitial showFromViewController:self];
//    }
}

- (void)interstitialAdLoadFailCode:(NSString *)errCode message:(NSString *)message interstitialAd:(BaiduMobAdExpressInterstitial *)interstitial
{
    NSLog(@"Ecmp:%@:%@:%@", errCode, message, interstitial);
    [self updateStatus:[self baiduFailStatusWithPrefix:@"插屏广告加载失败" code:errCode message:message] loading:NO];
}

- (void)interstitialAdExposure:(BaiduMobAdExpressInterstitial *)interstitial
{
    [self updateStatus:@"插屏广告曝光成功" loading:NO];
}

- (void)interstitialAdExposureFail:(BaiduMobAdExpressInterstitial *)interstitial withError:(int)reason
{
    [self updateStatus:[NSString stringWithFormat:@"插屏广告展示失败：reason=%d", reason] loading:NO];
}

- (void)interstitialAdDidClick:(BaiduMobAdExpressInterstitial *)interstitial
{
    [self updateStatus:@"插屏广告被点击" loading:NO];
}

- (void)interstitialAdDidClose:(BaiduMobAdExpressInterstitial *)interstitial
{
    [self updateStatus:@"插屏广告已关闭" loading:NO];
}

@end
