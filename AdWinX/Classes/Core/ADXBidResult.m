//
//  ADXBidResult.m
//  AdWinX
//
//  Created by AdWinX on 2026/08/23.
//

#import "ADXBidResult.h"

@implementation ADXBidResult

+ (instancetype)resultWithSourceId:(NSString *)sourceId
                            adType:(ADXAdType)adType
                             price:(NSInteger)price
                          adObject:(id)adObject
                           success:(BOOL)success
                             error:(NSError *)error
{
    ADXBidResult *result = [[ADXBidResult alloc] init];
    result.sourceId = sourceId;
    result.adType = adType;
    result.price = price;
    result.adObject = adObject;
    result.success = success;
    result.error = error;
    return result;
}

- (NSString *)description
{
    return [NSString stringWithFormat:@"<ADXBidResult: sourceId=%@, price=%ld, success=%@, error=%@>",
            self.sourceId,
            (long)self.price,
            self.success ? @"YES" : @"NO",
            self.error ?: @"nil"];
}

@end