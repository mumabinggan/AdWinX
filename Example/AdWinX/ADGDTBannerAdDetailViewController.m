//
//  ADGDTBannerAdDetailViewController.m
//  AdWinX
//
//  Created by Trae on 08/13/2026.
//

#import "ADGDTBannerAdDetailViewController.h"
#import "GDTUnifiedBannerView.h"
#import <Masonry/Masonry.h>

@interface ADGDTBannerAdDetailViewController () <GDTUnifiedBannerViewDelegate>

@property (nonatomic, strong) GDTUnifiedBannerView *bannerView;

@end

@implementation ADGDTBannerAdDetailViewController

- (void)loadAd
{
    self.bannerView = [[GDTUnifiedBannerView alloc] initWithPlacementId:self.placementId viewController:self];
    self.bannerView.delegate = self;
    self.bannerView.autoSwitchInterval = 0;
    [self.adContainerView addSubview:self.bannerView];
    [self.bannerView mas_makeConstraints:^(MASConstraintMaker *make) {
        make.leading.trailing.centerY.equalTo(self.adContainerView);
        make.height.mas_equalTo(100.0);
    }];
    [self.bannerView loadAdAndShow];
}

- (void)clearAdContainer
{
    [super clearAdContainer];
    self.bannerView = nil;
}

- (void)unifiedBannerViewDidLoad:(GDTUnifiedBannerView *)unifiedBannerView
{
    NSLog(@"%ld:%@:%@", unifiedBannerView.eCPM, unifiedBannerView.eCPMLevel, unifiedBannerView.extraInfo);
    [self updateStatus:@"Banner 广告加载并展示成功" loading:NO];
}

- (void)unifiedBannerViewFailedToLoad:(GDTUnifiedBannerView *)unifiedBannerView error:(NSError *)error
{
    [self updateStatus:[self statusTextForError:error prefix:@"Banner 广告失败"] loading:NO];
}

@end
