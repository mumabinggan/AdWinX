//
//  ADCSJInterstitialAdDetailViewController.m
//  AdWinX
//
//  Created by Trae on 08/16/2026.
//

#import "ADCSJInterstitialAdDetailViewController.h"
#import <BUAdSDK/BUAdSDK.h>

@interface ADCSJInterstitialAdDetailViewController () <BUNativeExpressFullscreenVideoAdDelegate>

@property (nonatomic, strong) BUNativeExpressFullscreenVideoAd *fullscreenVideoAd;

@end

@implementation ADCSJInterstitialAdDetailViewController

- (void)loadAd
{
    self.fullscreenVideoAd = [[BUNativeExpressFullscreenVideoAd alloc] initWithSlotID:self.placementId];
    self.fullscreenVideoAd.delegate = self;
    [self.fullscreenVideoAd loadAdData];
}

- (void)nativeExpressFullscreenVideoAdDidLoad:(BUNativeExpressFullscreenVideoAd *)fullscreenVideoAd
{
    [self updateStatus:@"穿山甲插屏广告素材加载成功，等待缓存" loading:YES];
}

- (void)nativeExpressFullscreenVideoAd:(BUNativeExpressFullscreenVideoAd *)fullscreenVideoAd didFailWithError:(NSError *)error
{
    [self updateStatus:[self statusTextForError:error prefix:@"穿山甲插屏广告加载失败"] loading:NO];
}

- (void)nativeExpressFullscreenVideoAdDidDownLoadVideo:(BUNativeExpressFullscreenVideoAd *)fullscreenVideoAd
{
    [self updateStatus:@"穿山甲插屏广告缓存成功，准备展示" loading:NO];
    BOOL shown = [fullscreenVideoAd showAdFromRootViewController:self];
    if (!shown) {
        [self updateStatus:@"穿山甲插屏广告展示失败" loading:NO];
    }
}

- (void)nativeExpressFullscreenVideoAdViewRenderSuccess:(BUNativeExpressFullscreenVideoAd *)fullscreenVideoAd
{
    [self updateStatus:@"穿山甲插屏广告渲染成功" loading:NO];
}

- (void)nativeExpressFullscreenVideoAdViewRenderFail:(BUNativeExpressFullscreenVideoAd *)fullscreenVideoAd error:(NSError *)error
{
    [self updateStatus:[self statusTextForError:error prefix:@"穿山甲插屏广告渲染失败"] loading:NO];
}

- (void)nativeExpressFullscreenVideoAdWillVisible:(BUNativeExpressFullscreenVideoAd *)fullscreenVideoAd
{
    [self updateStatus:@"穿山甲插屏广告即将展示" loading:NO];
}

- (void)nativeExpressFullscreenVideoAdDidVisible:(BUNativeExpressFullscreenVideoAd *)fullscreenVideoAd
{
    [self updateStatus:@"穿山甲插屏广告已展示" loading:NO];
}

- (void)nativeExpressFullscreenVideoAdDidClick:(BUNativeExpressFullscreenVideoAd *)fullscreenVideoAd
{
    [self updateStatus:@"穿山甲插屏广告已点击" loading:NO];
}

- (void)nativeExpressFullscreenVideoAdDidPlayFinish:(BUNativeExpressFullscreenVideoAd *)fullscreenVideoAd didFailWithError:(NSError *)error
{
    NSString *status = error ? [self statusTextForError:error prefix:@"穿山甲插屏广告播放失败"] : @"穿山甲插屏广告播放完成";
    [self updateStatus:status loading:NO];
}

- (void)nativeExpressFullscreenVideoAdDidClose:(BUNativeExpressFullscreenVideoAd *)fullscreenVideoAd
{
    [self updateStatus:@"穿山甲插屏广告已关闭" loading:NO];
    self.fullscreenVideoAd = nil;
}

@end
