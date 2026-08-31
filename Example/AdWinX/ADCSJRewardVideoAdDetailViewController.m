//
//  ADCSJRewardVideoAdDetailViewController.m
//  AdWinX
//
//  Created by Trae on 08/16/2026.
//

#import "ADCSJRewardVideoAdDetailViewController.h"
#import <BUAdSDK/BUAdSDK.h>

@interface ADCSJRewardVideoAdDetailViewController () <BUNativeExpressRewardedVideoAdDelegate>

@property (nonatomic, strong) BUNativeExpressRewardedVideoAd *rewardedVideoAd;

@end

@implementation ADCSJRewardVideoAdDetailViewController

- (void)loadAd
{
    BURewardedVideoModel *model = [[BURewardedVideoModel alloc] init];
    model.userId = @"AdWinXDemoUser";
    model.extra = @"AdWinXDemoReward";
//    model.allowPlayAgain = NO;

    self.rewardedVideoAd = [[BUNativeExpressRewardedVideoAd alloc] initWithSlotID:self.placementId rewardedVideoModel:model];
    self.rewardedVideoAd.delegate = self;
    [self.rewardedVideoAd loadAdData];
}

- (void)nativeExpressRewardedVideoAdDidLoad:(BUNativeExpressRewardedVideoAd *)rewardedVideoAd
{
    [self updateStatus:@"穿山甲激励视频素材加载成功，等待缓存" loading:YES];
}

- (void)nativeExpressRewardedVideoAd:(BUNativeExpressRewardedVideoAd *)rewardedVideoAd didFailWithError:(NSError *)error
{
    [self updateStatus:[self statusTextForError:error prefix:@"穿山甲激励视频加载失败"] loading:NO];
}

- (void)nativeExpressRewardedVideoAdDidDownLoadVideo:(BUNativeExpressRewardedVideoAd *)rewardedVideoAd
{
    [self updateStatus:@"穿山甲激励视频缓存成功，准备展示" loading:NO];
    BOOL shown = [rewardedVideoAd showAdFromRootViewController:self];
    if (!shown) {
        [self updateStatus:@"穿山甲激励视频展示失败" loading:NO];
    }
}

- (void)nativeExpressRewardedVideoAdViewRenderSuccess:(BUNativeExpressRewardedVideoAd *)rewardedVideoAd
{
    [self updateStatus:@"穿山甲激励视频渲染成功" loading:NO];
}

- (void)nativeExpressRewardedVideoAdViewRenderFail:(BUNativeExpressRewardedVideoAd *)rewardedVideoAd error:(NSError *)error
{
    [self updateStatus:[self statusTextForError:error prefix:@"穿山甲激励视频渲染失败"] loading:NO];
}

- (void)nativeExpressRewardedVideoAdWillVisible:(BUNativeExpressRewardedVideoAd *)rewardedVideoAd
{
    [self updateStatus:@"穿山甲激励视频即将展示" loading:NO];
}

- (void)nativeExpressRewardedVideoAdDidVisible:(BUNativeExpressRewardedVideoAd *)rewardedVideoAd
{
    [self updateStatus:@"穿山甲激励视频已展示" loading:NO];
}

- (void)nativeExpressRewardedVideoAdDidClick:(BUNativeExpressRewardedVideoAd *)rewardedVideoAd
{
    [self updateStatus:@"穿山甲激励视频已点击" loading:NO];
}

- (void)nativeExpressRewardedVideoAdDidPlayFinish:(BUNativeExpressRewardedVideoAd *)rewardedVideoAd didFailWithError:(NSError *)error
{
    NSString *status = error ? [self statusTextForError:error prefix:@"穿山甲激励视频播放失败"] : @"穿山甲激励视频播放完成";
    [self updateStatus:status loading:NO];
}

- (void)nativeExpressRewardedVideoAdServerRewardDidSucceed:(BUNativeExpressRewardedVideoAd *)rewardedVideoAd verify:(BOOL)verify
{
    [self updateStatus:[NSString stringWithFormat:@"穿山甲激励视频奖励回调成功，verify：%@", verify ? @"YES" : @"NO"] loading:NO];
}

- (void)nativeExpressRewardedVideoAdServerRewardDidFail:(BUNativeExpressRewardedVideoAd *)rewardedVideoAd error:(NSError *)error
{
    [self updateStatus:[self statusTextForError:error prefix:@"穿山甲激励视频奖励回调失败"] loading:NO];
}

- (void)nativeExpressRewardedVideoAdDidClose:(BUNativeExpressRewardedVideoAd *)rewardedVideoAd
{
    [self updateStatus:@"穿山甲激励视频已关闭" loading:NO];
    self.rewardedVideoAd = nil;
}

@end
