//
//  ADGDTNativeExpressAdDetailViewController.m
//  AdWinX
//
//  Created by Trae on 08/13/2026.
//

#import "ADGDTNativeExpressAdDetailViewController.h"
#import "GDTNativeExpressAd.h"
#import "GDTNativeExpressAdView.h"
#import <Masonry/Masonry.h>

@interface ADGDTNativeExpressAdDetailViewController () <GDTNativeExpressAdDelegete>

@property (nonatomic, strong) GDTNativeExpressAd *nativeExpressAd;
@property (nonatomic, strong) GDTNativeExpressAdView *nativeExpressAdView;

@end

@implementation ADGDTNativeExpressAdDetailViewController

- (void)loadAd
{
    CGSize adSize = CGSizeMake(CGRectGetWidth(self.view.bounds) - 40.0, 0.0);
    self.nativeExpressAd = [[GDTNativeExpressAd alloc] initWithPlacementId:self.placementId adSize:adSize];
    self.nativeExpressAd.delegate = self;
    [self.nativeExpressAd loadAd:1];
}

- (void)clearAdContainer
{
    [super clearAdContainer];
    self.nativeExpressAdView = nil;
}

- (void)nativeExpressAdSuccessToLoad:(GDTNativeExpressAd *)nativeExpressAd views:(NSArray<__kindof GDTNativeExpressAdView *> *)views
{
//    NSLog(@"%ld:%@:%@", nativeExpressAd.eCPM, nativeExpressAd.eCPMLevel, nativeExpressAd.extraInfo);
    self.nativeExpressAdView = views.firstObject;
    NSLog(@"%ld:%@:%@", self.nativeExpressAdView.eCPM, self.nativeExpressAdView.eCPMLevel, self.nativeExpressAdView.extraInfo);
    self.nativeExpressAdView.controller = self;
    [self updateStatus:@"信息流广告加载成功，开始渲染" loading:YES];
    [self.nativeExpressAdView render];
}

- (void)nativeExpressAdFailToLoad:(GDTNativeExpressAd *)nativeExpressAd error:(NSError *)error
{
    [self updateStatus:[self statusTextForError:error prefix:@"信息流广告加载失败"] loading:NO];
}

- (void)nativeExpressAdViewRenderSuccess:(GDTNativeExpressAdView *)nativeExpressAdView
{
    [self.adContainerView addSubview:nativeExpressAdView];
    CGFloat adHeight = CGRectGetHeight(nativeExpressAdView.bounds) > 0.0 ? CGRectGetHeight(nativeExpressAdView.bounds) : 260.0;
    [nativeExpressAdView mas_makeConstraints:^(MASConstraintMaker *make) {
        make.top.leading.trailing.equalTo(self.adContainerView);
        make.height.mas_equalTo(adHeight);
    }];
    [self updateStatus:@"信息流广告渲染并展示成功" loading:NO];
}

- (void)nativeExpressAdViewRenderFail:(GDTNativeExpressAdView *)nativeExpressAdView
{
    [self updateStatus:@"信息流广告渲染失败" loading:NO];
}

@end
