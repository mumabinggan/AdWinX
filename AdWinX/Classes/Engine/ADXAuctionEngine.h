//
//  ADXAuctionEngine.h
//  AdWinX
//
//  Created by AdWinX on 2026/08/29.
//

#import <Foundation/Foundation.h>

@class ADXSlotConfig;
@class ADXAuctionResult;
@protocol ADXAdapter;

NS_ASSUME_NONNULL_BEGIN

/// 拍卖完成回调
typedef void (^ADXAuctionCompletion)(ADXAuctionResult * _Nullable result);

/// 拍卖引擎
///
/// 负责执行完整的混合拍卖流程，对所有广告类型通用：
///   1. 竞价阶段：并行请求所有竞价源，整体受 bidTimeout 约束
///   2. 瀑布阶段：floorEcpm >= 竞价最高价的瀑布层，按底价从高到低串行请求
///   3. 结算阶段：竞价最高价与瀑布成功层比价，选出赢家并统一通知 Win/Loss
///
/// Adapter 由调用方（入口层）创建并注入，引擎自身不感知具体 ADN。
@interface ADXAuctionEngine : NSObject

/// 执行一次拍卖
///
/// @param config 广告位配置
/// @param adapters sourceId -> Adapter 实例（由入口层通过注册中心创建）
/// @param completion 拍卖完成回调（主线程），无可用广告时 result.winnerResult 为 nil
- (void)runAuctionWithConfig:(ADXSlotConfig *)config
                     adapters:(NSDictionary<NSString *, id<ADXAdapter>> *)adapters
                   completion:(ADXAuctionCompletion)completion;

@end

NS_ASSUME_NONNULL_END