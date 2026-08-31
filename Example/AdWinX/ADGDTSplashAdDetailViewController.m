//
//  ADGDTSplashAdDetailViewController.m
//  AdWinX
//
//  Created by Trae on 08/13/2026.
//

#import "ADGDTSplashAdDetailViewController.h"
#import "GDTSplashAd.h"

@interface ADGDTSplashAdDetailViewController () <GDTSplashAdDelegate>

@property (nonatomic, strong) GDTSplashAd *splashAd;

@end

@implementation ADGDTSplashAdDetailViewController

- (void)loadAd
{
    self.splashAd = [[GDTSplashAd alloc] initWithPlacementId:self.placementId];
    self.splashAd.delegate = self;
    self.splashAd.fetchDelay = 5.0;
    [self.splashAd loadAd];
}

- (void)splashAdDidLoad:(GDTSplashAd *)splashAd
{
    NSLog(@"%ld:%@:%@", splashAd.eCPM, splashAd.eCPMLevel, splashAd.extraInfo);
    [self updateStatus:@"开屏广告加载成功，准备展示" loading:NO];
    if ([splashAd isAdValid]) {
        [splashAd showAdInWindow:[self adPresentationWindow] withBottomView:nil skipView:nil];
    }
}

- (void)splashAdFailToPresent:(GDTSplashAd *)splashAd withError:(NSError *)error
{
    [self updateStatus:[self statusTextForError:error prefix:@"开屏广告失败"] loading:NO];
}

- (void)splashAdClosed:(GDTSplashAd *)splashAd
{
    [self updateStatus:@"开屏广告已关闭" loading:NO];
}

@end
