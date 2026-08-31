//
//  ADBaiduRewardVideoAdDetailViewController.m
//  AdWinX
//
//  Created by Trae on 08/15/2026.
//

#import "ADBaiduRewardVideoAdDetailViewController.h"
#import "ADAdDemoConstants.h"
#import <BaiduMobAdSDK/BaiduMobAdManager.h>
#import <BaiduMobAdSDK/BaiduMobAdRewardVideo.h>

@interface ADBaiduRewardVideoAdDetailViewController () <BaiduMobAdRewardVideoDelegate>

@property (nonatomic, strong) BaiduMobAdRewardVideo *rewardVideoAd;

@end

@implementation ADBaiduRewardVideoAdDetailViewController

- (void)loadAd
{
//    NSString *appId = self.appId.length > 0 ? self.appId : ADBaiduAppId;
//    [BaiduMobAdManager setAppsid:appId];

    self.rewardVideoAd = [[BaiduMobAdRewardVideo alloc] init];
    self.rewardVideoAd.delegate = self;
    self.rewardVideoAd.publisherId = ADBaiduAppId;
    self.rewardVideoAd.adUnitTag = self.placementId;
//    self.rewardVideoAd.userID = @"adwinx-demo-user";
//    self.rewardVideoAd.extraInfo = @"adwinx_baidu_reward";
    self.rewardVideoAd.useSkipAlertView = true;
//    self.rewardVideoAd.timeout = 20.0;
    self.rewardVideoAd.enableLocation = true;
    [self updateStatus:[NSString stringWithFormat:@"激励视频请求中，AppID=%@，广告位=%@", ADBaiduAppId, self.placementId] loading:YES];
    [self.rewardVideoAd load];
}

- (void)rewardedAdLoadSuccess:(BaiduMobAdRewardVideo *)video
{
    NSLog(@"Success Ecmp:====%@:%@", video.getPECPM, video.getECPMLevel);
    [self updateStatus:@"激励视频请求成功，等待视频缓存" loading:YES];
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(3 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        NSLog(@"Success Ecmp:==:%@:%d:%@", video.getECPMLevel, [video isReady], video);
        [video showFromViewController:self];
    });
}

- (void)rewardedVideoAdLoaded:(BaiduMobAdRewardVideo *)video
{
    NSLog(@"Loaded Ecmp:====%@:%@", video.getPECPM, video.getECPMLevel);
    [self updateStatus:@"激励视频缓存成功，准备展示" loading:NO];
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(3 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        NSLog(@"Loaded Ecmp:==:%@:%d:%@", video.getECPMLevel, [video isReady], video);
        [video showFromViewController:self];
    });
}

- (void)rewardedAdLoadFailCode:(NSString *)errCode message:(NSString *)message rewardedAd:(BaiduMobAdRewardVideo *)video
{
    NSString *status = [NSString stringWithFormat:@"%@，AppID=%@，广告位=%@", [self baiduFailStatusWithPrefix:@"激励视频请求失败" code:errCode message:message], video.publisherId ?: @"", video.adUnitTag ?: @""];
    [self updateStatus:status loading:NO];
}

- (void)rewardedVideoAdLoadFailed:(BaiduMobAdRewardVideo *)video withError:(BaiduMobFailReason)reason
{
    [self updateStatus:[NSString stringWithFormat:@"激励视频缓存失败：reason=%ld", (long)reason] loading:NO];
}

- (void)rewardedVideoAdDidStarted:(BaiduMobAdRewardVideo *)video
{
    [self updateStatus:@"激励视频开始播放" loading:NO];
}

- (void)rewardedVideoAdShowFailed:(BaiduMobAdRewardVideo *)video withError:(BaiduMobFailReason)reason
{
    [self updateStatus:[NSString stringWithFormat:@"激励视频展示失败：reason=%ld", (long)reason] loading:NO];
}

- (void)rewardedVideoAdRewardDidSuccess:(BaiduMobAdRewardVideo *)video verify:(BOOL)verify rewardInfo:(NSDictionary *)rewardInfo
{
    [self updateStatus:[NSString stringWithFormat:@"激励达成：verify=%@ info=%@", verify ? @"YES" : @"NO", rewardInfo ?: @{}] loading:NO];
}

- (void)rewardedVideoAdDidClose:(BaiduMobAdRewardVideo *)video withPlayingProgress:(CGFloat)progress
{
    [self updateStatus:[NSString stringWithFormat:@"激励视频已关闭，播放进度 %.1f%%", progress] loading:NO];
}

@end
