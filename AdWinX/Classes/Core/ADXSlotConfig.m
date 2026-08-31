//
//  ADXSlotConfig.m
//  AdWinX
//
//  Created by AdWinX on 2026/08/23.
//

#import "ADXSlotConfig.h"

@implementation ADXSlotConfig

- (NSString *)description
{
    return [NSString stringWithFormat:@"<ADXSlotConfig: adType=%@, bidTimeout=%.1f, waterfallTimeout=%.1f, adSources=%lu>",
            [self adTypeString],
            self.bidTimeout,
            self.waterfallTimeout,
            (unsigned long)self.adSources.count];
}

- (NSString *)adTypeString
{
    switch (self.adType) {
        case ADXAdTypeSplash: return @"splash";
        case ADXAdTypeRewardVideo: return @"rewardVideo";
        case ADXAdTypeInterstitial: return @"interstitial";
        case ADXAdTypeBanner: return @"banner";
        case ADXAdTypeNativeExpress: return @"nativeExpress";
    }
}

@end