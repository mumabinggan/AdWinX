//
//  ADSigmobGlobalAdManager.h
//  AdWinX
//
//  Created by Trae on 08/16/2026.
//

#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>

typedef void(^ADSigmobAdStatusHandler)(NSString *status, BOOL loading);

@interface ADSigmobGlobalAdManager : NSObject

+ (instancetype)sharedManager;

- (void)setupSDK;
- (void)loadAndShowSplashWithPlacementId:(NSString *)placementId
                      rootViewController:(UIViewController *)rootViewController
                                  window:(UIWindow *)window
                           statusHandler:(ADSigmobAdStatusHandler)statusHandler;
- (void)loadAndShowRewardWithPlacementId:(NSString *)placementId
                       rootViewController:(UIViewController *)rootViewController
                            statusHandler:(ADSigmobAdStatusHandler)statusHandler;

@end
