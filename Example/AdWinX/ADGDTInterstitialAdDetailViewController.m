//
//  ADGDTInterstitialAdDetailViewController.m
//  AdWinX
//
//  Created by Trae on 08/13/2026.
//

#import "ADGDTInterstitialAdDetailViewController.h"
#import "GDTUnifiedInterstitialAd.h"

@interface ADGDTInterstitialAdDetailViewController () <GDTUnifiedInterstitialAdDelegate>

@property (nonatomic, strong) GDTUnifiedInterstitialAd *interstitialAd;

@end

@implementation ADGDTInterstitialAdDetailViewController

- (void)loadAd
{
    self.interstitialAd = [[GDTUnifiedInterstitialAd alloc] initWithPlacementId:self.placementId];
    self.interstitialAd.delegate = self;
    [self.interstitialAd loadAd];
}

- (void)unifiedInterstitialSuccessToLoadAd:(GDTUnifiedInterstitialAd *)unifiedInterstitial
{
    NSLog(@"%ld:%@:%@", unifiedInterstitial.eCPM, unifiedInterstitial.eCPMLevel, unifiedInterstitial.extraInfo);
    [self updateStatus:@"插屏广告加载成功，等待渲染" loading:YES];
}

- (void)unifiedInterstitialRenderSuccess:(GDTUnifiedInterstitialAd *)unifiedInterstitial
{
    [self updateStatus:@"插屏广告渲染成功，准备展示" loading:NO];
    [unifiedInterstitial presentAdFromRootViewController:self];
}

- (void)unifiedInterstitialFailToLoadAd:(GDTUnifiedInterstitialAd *)unifiedInterstitial error:(NSError *)error
{
    [self updateStatus:[self statusTextForError:error prefix:@"插屏广告加载失败"] loading:NO];
}

- (void)unifiedInterstitialRenderFail:(GDTUnifiedInterstitialAd *)unifiedInterstitial error:(NSError *)error
{
    [self updateStatus:[self statusTextForError:error prefix:@"插屏广告渲染失败"] loading:NO];
}

- (void)unifiedInterstitialDidDismissScreen:(GDTUnifiedInterstitialAd *)unifiedInterstitial
{
    [self updateStatus:@"插屏广告已关闭" loading:NO];
}

@end
