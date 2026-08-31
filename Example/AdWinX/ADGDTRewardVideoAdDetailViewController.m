//
//  ADGDTRewardVideoAdDetailViewController.m
//  AdWinX
//
//  Created by Trae on 08/13/2026.
//

#import "ADGDTRewardVideoAdDetailViewController.h"
#import "GDTRewardVideoAd.h"
#import "GDTAdProtocol.h"

@interface ADGDTRewardVideoAdDetailViewController () <GDTRewardedVideoAdDelegate>

@property (nonatomic, strong) GDTRewardVideoAd *rewardVideoAd;

@end

@implementation ADGDTRewardVideoAdDetailViewController

- (void)loadAd
{
    self.rewardVideoAd = [[GDTRewardVideoAd alloc] initWithPlacementId:self.placementId];
    self.rewardVideoAd.delegate = self;
    [self.rewardVideoAd loadAd];
}

- (void)gdt_rewardVideoAdDidLoad:(GDTRewardVideoAd *)rewardedVideoAd
{
    NSLog(@"%ld:%@:%@", rewardedVideoAd.eCPM, rewardedVideoAd.eCPMLevel, rewardedVideoAd.extraInfo);
    [self updateStatus:@"激励视频广告数据加载成功" loading:YES];
}

- (void)gdt_rewardVideoAdVideoDidLoad:(GDTRewardVideoAd *)rewardedVideoAd
{
    [self updateStatus:@"激励视频素材加载成功，准备展示" loading:NO];
    [rewardedVideoAd showAdFromRootViewController:self];
}

- (void)gdt_rewardVideoAd:(GDTRewardVideoAd *)rewardedVideoAd didFailWithError:(NSError *)error
{
    [self updateStatus:[self statusTextForError:error prefix:@"激励视频失败"] loading:NO];
}

- (void)gdt_rewardVideoAdDidClose:(GDTRewardVideoAd *)rewardedVideoAd
{
    [self updateStatus:@"激励视频已关闭" loading:NO];
}

- (void)gdt_adDidRewardEffective:(id<GDTAdProtocol>)adInstance info:(NSDictionary *)info
{
    [self updateStatus:[NSString stringWithFormat:@"激励达成：%@", info] loading:NO];
}

@end
