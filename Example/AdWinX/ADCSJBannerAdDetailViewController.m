//
//  ADCSJBannerAdDetailViewController.m
//  AdWinX
//
//  Created by Trae on 08/16/2026.
//

#import "ADCSJBannerAdDetailViewController.h"
#import <BUAdSDK/BUAdSDK.h>
#import <Masonry/Masonry.h>

@interface ADCSJBannerAdDetailViewController () <BUNativeExpressBannerViewDelegate>

@property (nonatomic, strong) BUNativeExpressBannerView *bannerView;

@end

@implementation ADCSJBannerAdDetailViewController

- (void)loadAd
{
    CGSize adSize = CGSizeMake(CGRectGetWidth(self.view.bounds) - 40.0, 150.0);
    self.bannerView = [[BUNativeExpressBannerView alloc] initWithSlotID:self.placementId rootViewController:self adSize:adSize];
    self.bannerView.delegate = self;
    [self.bannerView loadAdData];
}

- (void)clearAdContainer
{
    [super clearAdContainer];
    self.bannerView = nil;
}

- (void)nativeExpressBannerAdViewDidLoad:(BUNativeExpressBannerView *)bannerAdView
{
    [self updateStatus:@"穿山甲 Banner 广告加载成功，等待渲染" loading:YES];
}

- (void)nativeExpressBannerAdView:(BUNativeExpressBannerView *)bannerAdView didLoadFailWithError:(NSError *)error
{
    [self updateStatus:[self statusTextForError:error prefix:@"穿山甲 Banner 广告加载失败"] loading:NO];
}

- (void)nativeExpressBannerAdViewRenderSuccess:(BUNativeExpressBannerView *)bannerAdView
{
    [self.adContainerView addSubview:bannerAdView];
    [bannerAdView mas_makeConstraints:^(MASConstraintMaker *make) {
        make.top.leading.trailing.equalTo(self.adContainerView);
        make.height.mas_equalTo(CGRectGetHeight(bannerAdView.bounds) > 0.0 ? CGRectGetHeight(bannerAdView.bounds) : 150.0);
    }];
    [self updateStatus:@"穿山甲 Banner 广告渲染并展示成功" loading:NO];
}

- (void)nativeExpressBannerAdViewRenderFail:(BUNativeExpressBannerView *)bannerAdView error:(NSError *)error
{
    [self updateStatus:[self statusTextForError:error prefix:@"穿山甲 Banner 广告渲染失败"] loading:NO];
}

- (void)nativeExpressBannerAdViewWillBecomVisible:(BUNativeExpressBannerView *)bannerAdView
{
    [self updateStatus:@"穿山甲 Banner 广告已曝光" loading:NO];
}

- (void)nativeExpressBannerAdViewDidClick:(BUNativeExpressBannerView *)bannerAdView
{
    [self updateStatus:@"穿山甲 Banner 广告已点击" loading:NO];
}

- (void)nativeExpressBannerAdViewDidRemoved:(BUNativeExpressBannerView *)bannerAdView
{
    [self updateStatus:@"穿山甲 Banner 广告已移除" loading:NO];
    self.bannerView = nil;
}

@end
