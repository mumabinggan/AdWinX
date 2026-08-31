//
//  ADSigmobSplashAdDetailViewController.m
//  AdWinX
//
//  Created by Trae on 08/16/2026.
//

#import "ADSigmobSplashAdDetailViewController.h"
#import "ADSigmobGlobalAdManager.h"

@implementation ADSigmobSplashAdDetailViewController

- (void)loadAd
{
    __weak typeof(self) weakSelf = self;
    [[ADSigmobGlobalAdManager sharedManager] loadAndShowSplashWithPlacementId:self.placementId
                                                           rootViewController:self
                                                                       window:[self adPresentationWindow]
                                                                statusHandler:^(NSString *status, BOOL loading) {
        [weakSelf updateStatus:status loading:loading];
    }];
}

@end
