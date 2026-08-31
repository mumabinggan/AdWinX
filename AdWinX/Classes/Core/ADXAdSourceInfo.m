//
//  ADXAdSourceInfo.m
//  AdWinX
//
//  Created by AdWinX on 2026/08/23.
//

#import "ADXAdSourceInfo.h"

@implementation ADXAdSourceInfo

+ (instancetype)sourceWithId:(NSString *)sourceId
                         adn:(NSString *)adnName
                        mode:(ADXRuntimeMode)mode
                      adType:(ADXAdType)adType
                  floorEcpm:(NSInteger)floorEcpm
                    realEcpm:(NSInteger)realEcpm
                     timeout:(NSTimeInterval)timeout
                placementId:(NSString *)placementId
                      appId:(NSString *)appId
                extraParams:(NSDictionary *)extraParams
{
    ADXAdSourceInfo *info = [[ADXAdSourceInfo alloc] init];
    info.sourceId = sourceId;
    info.adnName = adnName;
    info.runtimeMode = mode;
    info.adType = adType;
    info.floorEcpm = floorEcpm;
    info.realEcpm = realEcpm;
    info.timeout = timeout;
    info.placementId = placementId;
    info.appId = appId;
    info.extraParams = extraParams;
    return info;
}

- (NSString *)description
{
    return [NSString stringWithFormat:@"<ADXAdSourceInfo: sourceId=%@, adn=%@, mode=%@, adType=%@, floorEcpm=%ld, realEcpm=%ld, priority=%ld, timeout=%.1f, placementId=%@, appId=%@>",
            self.sourceId,
            self.adnName,
            self.runtimeMode == ADXRuntimeModeBidding ? @"bidding" : @"waterfall",
            [self adTypeString],
            (long)self.floorEcpm,
            (long)self.realEcpm,
            (long)self.priority,
            self.timeout,
            self.placementId,
            self.appId];
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