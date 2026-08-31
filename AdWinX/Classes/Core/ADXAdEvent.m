//
//  ADXAdEvent.m
//  AdWinX
//
//  Created by AdWinX on 2026/08/31.
//

#import "ADXAdEvent.h"

@implementation ADXAdEvent

- (instancetype)init
{
    self = [super init];
    if (self) {
        _timestamp = [[NSDate date] timeIntervalSince1970] * 1000;
        _slotName = @"";
        _sourceId = @"";
        _adType = ADXAdTypeSplash;
    }
    return self;
}

@end
