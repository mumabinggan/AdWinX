//
//  ADXAuctionResult.m
//  AdWinX
//
//  Created by AdWinX on 2026/08/23.
//

#import "ADXAuctionResult.h"

@implementation ADXAuctionResult

- (NSString *)description
{
    return [NSString stringWithFormat:@"<ADXAuctionResult: winner=%@, reason=%@, candidates=%lu, duration=%.2f>",
            self.winnerResult ? self.winnerResult.sourceId : @"nil",
            self.winReason ?: @"nil",
            (unsigned long)self.allCandidates.count,
            self.totalDuration];
}

@end