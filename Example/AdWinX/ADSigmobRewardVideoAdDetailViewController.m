//
//  ADSigmobRewardVideoAdDetailViewController.m
//  AdWinX
//
//  Created by Trae on 08/16/2026.
//

#import "ADSigmobRewardVideoAdDetailViewController.h"
#import "ADSigmobGlobalAdManager.h"

@implementation ADSigmobRewardVideoAdDetailViewController

- (void)loadAd
{
    __weak typeof(self) weakSelf = self;
    [[ADSigmobGlobalAdManager sharedManager] loadAndShowRewardWithPlacementId:self.placementId
                                                           rootViewController:self
                                                                statusHandler:^(NSString *status, BOOL loading) {
        [weakSelf updateStatus:status loading:loading];
    }];
}

@end
