//
//  ADSigmobInterstitialAdDetailViewController.m
//  AdWinX
//
//  Created by Trae on 08/16/2026.
//

#import "ADSigmobInterstitialAdDetailViewController.h"
#import "ADSigmobGlobalAdManager.h"
#import <WindSDK/WindSDK.h>

@interface ADSigmobInterstitialAdDetailViewController () <WindNewIntersititialAdDelegate>

@property (nonatomic, strong) WindNewIntersititialAd *interstitialAd;

@end

@implementation ADSigmobInterstitialAdDetailViewController

- (void)loadAd
{
    [[ADSigmobGlobalAdManager sharedManager] setupSDK];
    WindAdRequest *request = [WindAdRequest request];
    request.placementId = self.placementId;
    self.interstitialAd = [[WindNewIntersititialAd alloc] initWithRequest:request];
    self.interstitialAd.delegate = self;
    [self.interstitialAd loadAdData];
}

- (void)intersititialAdDidLoad:(WindNewIntersititialAd *)intersititialAd
{
    NSLog(@"ecpm==%@", [intersititialAd getEcpm]);
    [self updateStatus:@"插屏广告加载成功，准备展示" loading:NO];
    if (intersititialAd.isAdReady) {
        [intersititialAd showAdFromRootViewController:self options:nil];
    }
}

- (void)intersititialAdDidLoad:(WindNewIntersititialAd *)intersititialAd didFailWithError:(NSError *)error
{
    [self updateStatus:[self statusTextForError:error prefix:@"插屏广告加载失败"] loading:NO];
}

- (void)intersititialAdDidShowFailed:(WindNewIntersititialAd *)intersititialAd error:(NSError *)error
{
    [self updateStatus:[self statusTextForError:error prefix:@"插屏广告展示失败"] loading:NO];
}

- (void)intersititialAdDidVisible:(WindNewIntersititialAd *)intersititialAd
{
    [self updateStatus:@"插屏广告已曝光" loading:NO];
}

- (void)intersititialAdDidClick:(WindNewIntersititialAd *)intersititialAd
{
    [self updateStatus:@"插屏广告已点击" loading:NO];
}

- (void)intersititialAdDidClose:(WindNewIntersititialAd *)intersititialAd
{
    [self updateStatus:@"插屏广告已关闭" loading:NO];
    self.interstitialAd = nil;
}

@end
