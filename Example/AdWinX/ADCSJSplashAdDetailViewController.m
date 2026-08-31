//
//  ADCSJSplashAdDetailViewController.m
//  AdWinX
//
//  Created by Trae on 08/16/2026.
//

#import "ADCSJSplashAdDetailViewController.h"
#import <BUAdSDK/BUAdSDK.h>

@interface ADCSJSplashAdDetailViewController () <BUSplashAdDelegate>

@property (nonatomic, strong) BUSplashAd *splashAd;
@property (nonatomic, strong) UIViewController *splashContainerViewController;

@end

@implementation ADCSJSplashAdDetailViewController

- (void)loadAd
{
    CGSize adSize = [UIScreen mainScreen].bounds.size;
    self.splashAd = [[BUSplashAd alloc] initWithSlotID:self.placementId adSize:adSize];
    self.splashAd.delegate = self;
    self.splashAd.tolerateTimeout = 5.0;
    self.splashAd.hideSkipButton = NO;
    [self.splashAd loadAdData];
}

- (void)splashAdLoadSuccess:(BUSplashAd *)splashAd
{
    NSLog(@"ecpm:%@", splashAd.mediaExt);
    [self updateStatus:@"穿山甲开屏广告加载成功，准备渲染" loading:NO];
    [self presentSplashContainerAndShowAd:splashAd];
}

- (void)splashAdLoadFail:(BUSplashAd *)splashAd error:(BUAdError *)error
{
    [self updateStatus:[self statusTextForError:error prefix:@"穿山甲开屏广告加载失败"] loading:NO];
}

- (void)splashAdRenderSuccess:(BUSplashAd *)splashAd
{
    [self updateStatus:@"穿山甲开屏广告渲染成功，开始展示" loading:NO];
}

- (void)splashAdRenderFail:(BUSplashAd *)splashAd error:(BUAdError *)error
{
    [self updateStatus:[self statusTextForError:error prefix:@"穿山甲开屏广告渲染失败"] loading:NO];
}

- (void)splashAdWillShow:(BUSplashAd *)splashAd
{
    [self updateStatus:@"穿山甲开屏广告即将展示" loading:NO];
}

- (void)splashAdDidShow:(BUSplashAd *)splashAd
{
    [self updateStatus:@"穿山甲开屏广告已展示" loading:NO];
}

- (void)splashAdDidClick:(BUSplashAd *)splashAd
{
    [self updateStatus:@"穿山甲开屏广告已点击" loading:NO];
}

- (void)splashAdDidClose:(BUSplashAd *)splashAd closeType:(BUSplashAdCloseType)closeType
{
    [self updateStatus:[NSString stringWithFormat:@"穿山甲开屏广告已关闭，关闭类型：%ld", (long)closeType] loading:NO];
    [self dismissSplashContainerIfNeeded];
    self.splashAd = nil;
}

- (void)splashAdViewControllerDidClose:(BUSplashAd *)splashAd
{
    [self dismissSplashContainerIfNeeded];
    self.splashAd = nil;
}

- (void)splashDidCloseOtherController:(BUSplashAd *)splashAd interactionType:(BUInteractionType)interactionType
{
    [self updateStatus:@"穿山甲开屏广告落地页已关闭" loading:NO];
}

- (void)splashVideoAdDidPlayFinish:(BUSplashAd *)splashAd didFailWithError:(NSError *)error
{
    if (error) {
        [self updateStatus:[self statusTextForError:error prefix:@"穿山甲开屏视频播放失败"] loading:NO];
    }
}

#pragma mark - Private

- (void)presentSplashContainerAndShowAd:(BUSplashAd *)splashAd
{
    UIViewController *containerViewController = [[UIViewController alloc] initWithNibName:nil bundle:nil];
    containerViewController.view.backgroundColor = [UIColor whiteColor];
    containerViewController.modalPresentationStyle = UIModalPresentationFullScreen;
    self.splashContainerViewController = containerViewController;

    __weak typeof(self) weakSelf = self;
    [self presentViewController:containerViewController animated:NO completion:^{
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (!strongSelf) {
            return;
        }
        [splashAd showSplashViewInRootViewController:containerViewController];
    }];
}

- (void)dismissSplashContainerIfNeeded
{
    UIViewController *containerViewController = self.splashContainerViewController;
    self.splashContainerViewController = nil;
    if (containerViewController.presentingViewController) {
        [containerViewController dismissViewControllerAnimated:NO completion:nil];
    }
}

@end
