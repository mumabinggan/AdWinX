//
//  ADXConfig.m
//  AdWinX
//
//  Created by AdWinX on 2026/08/29.
//

#import "ADXConfig.h"

NSString * const ADXSDKVersion = @"0.1.0";

@implementation ADXConfig

- (instancetype)init
{
    self = [super init];
    if (self) {
        _configVersion = 0;
        _adnApps = @{};
        _slots = @[];
        _logLevel = -1; // 未设置：不干预 ADXLogger 的本地默认
    }
    return self;
}

- (nullable ADXSlotConfig *)slotConfigWithName:(NSString *)slotName
{
    for (ADXSlotConfig *slot in self.slots) {
        if ([slot.slotName isEqualToString:slotName]) {
            return slot;
        }
    }
    return nil;
}

@end
