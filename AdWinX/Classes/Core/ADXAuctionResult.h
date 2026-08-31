//
//  ADXAuctionResult.h
//  AdWinX
//
//  Created by AdWinX on 2026/08/23.
//

#import <Foundation/Foundation.h>
#import "ADXBidResult.h"

NS_ASSUME_NONNULL_BEGIN

/// 拍卖结果模型
@interface ADXAuctionResult : NSObject

/// 最终赢家
@property (nonatomic, strong, nullable) ADXBidResult *winnerResult;

/// 所有参与拍卖的候选结果（含失败的）
@property (nonatomic, copy) NSArray<ADXBidResult *> *allCandidates;

/// 赢的原因，如 "瀑布高价层填上" / "竞价出价高于所有瀑布层"
@property (nonatomic, copy) NSString *winReason;

/// 整次拍卖总耗时，单位：秒
@property (nonatomic, assign) NSTimeInterval totalDuration;

@end

NS_ASSUME_NONNULL_END