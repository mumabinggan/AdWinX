//
//  ADBaiduNativeExpressAdDetailViewController.m
//  AdWinX
//
//  Created by Trae on 08/15/2026.
//

#import "ADBaiduNativeExpressAdDetailViewController.h"
#import <BaiduMobAdSDK/BaiduMobAdNative.h>
#import <BaiduMobAdSDK/BaiduMobAdExpressNativeView.h>
#import <Masonry/Masonry.h>

@interface ADBaiduNativeExpressAdDetailViewController () <BaiduMobAdNativeAdDelegate, BaiduMobAdNativeInterationDelegate>

@property (nonatomic, strong) BaiduMobAdNative *nativeAd;
@property (nonatomic, strong) BaiduMobAdExpressNativeView *nativeAdView;

@end

@implementation ADBaiduNativeExpressAdDetailViewController

- (void)loadAd
{
    CGFloat adWidth = CGRectGetWidth(self.view.bounds) - 60.0;
    self.nativeAd = [[BaiduMobAdNative alloc] init];
    self.nativeAd.publisherId = self.appId;
    self.nativeAd.adUnitTag = self.placementId;
    self.nativeAd.adDelegate = self;
    self.nativeAd.presentAdViewController = self;
    self.nativeAd.adType = BaiduMobAdTypeFeed;
    self.nativeAd.isExpressNativeAds = YES;
    self.nativeAd.baiduMobAdsWidth = @(adWidth);
    self.nativeAd.baiduMobAdsHeight = @(0.0);
    self.nativeAd.timeout = 20.0;
    [self.nativeAd load];
}

- (void)nativeAdObjectsSuccessLoad:(NSArray *)nativeAds nativeAd:(BaiduMobAdNative *)nativeAd
{
    BaiduMobAdExpressNativeView *expressView = nativeAds.firstObject;
    NSLog(@"pecmp:%@:%@", expressView.getPECPM, expressView.getECPMLevel);
    if (![expressView isKindOfClass:[BaiduMobAdExpressNativeView class]]) {
        [self updateStatus:@"列表广告返回数据不是优选模板视图" loading:NO];
        return;
    }

    self.nativeAdView = expressView;
    self.nativeAdView.baseViewController = self;
    self.nativeAdView.interationDelegate = self;
    self.nativeAdView.width = CGRectGetWidth(self.view.bounds) - 60.0;
    [self.nativeAdView setExpressTheme:BaiduMobAdExpressNativeNormalTheme];
    [self updateStatus:@"列表广告加载成功，开始渲染" loading:YES];
    [self.nativeAdView render];
}

- (void)nativeAdsFailLoadCode:(NSString *)errCode message:(NSString *)message nativeAd:(BaiduMobAdNative *)nativeAd adObject:(BaiduMobAdNativeAdObject *)adObject
{
    [self updateStatus:[self baiduFailStatusWithPrefix:@"列表广告加载失败" code:errCode message:message] loading:NO];
}

- (NSNumber *)baiduMobAdsWidth
{
    return @(CGRectGetWidth(self.view.bounds) - 60.0);
}

- (NSNumber *)baiduMobAdsHeight
{
    return @(0.0);
}

- (void)nativeAdExpressSuccessRender:(BaiduMobAdExpressNativeView *)express nativeAd:(BaiduMobAdNative *)nativeAd
{
    [self.adContainerView addSubview:express];
    CGFloat adHeight = express.height > 0.0 ? express.height : 260.0;
    [express mas_makeConstraints:^(MASConstraintMaker *make) {
        make.top.leading.trailing.equalTo(self.adContainerView);
        make.height.mas_equalTo(adHeight);
    }];
    [self updateStatus:@"列表广告渲染并展示成功" loading:NO];
}

- (void)nativeAdExposure:(UIView *)nativeAdView nativeAdDataObject:(BaiduMobAdNativeAdObject *)object
{
    [self updateStatus:@"列表广告曝光成功" loading:NO];
}

- (void)nativeAdClicked:(UIView *)nativeAdView nativeAdDataObject:(BaiduMobAdNativeAdObject *)object
{
    [self updateStatus:@"列表广告被点击" loading:NO];
}

- (void)nativeAdCloseClick:(UIView *)adView
{
    [adView removeFromSuperview];
    [self updateStatus:@"列表广告关闭按钮被点击" loading:NO];
}

- (void)clearAdContainer
{
    [super clearAdContainer];
    [self.nativeAdView destroyExpressView];
    self.nativeAdView = nil;
}

@end
