//
//  ADXAdEvent.h
//  AdWinX
//
//  Created by AdWinX on 2026/08/31.
//

#import <Foundation/Foundation.h>
#import "ADXAdSourceInfo.h"

NS_ASSUME_NONNULL_BEGIN

/// 广告链路事件类型（漏斗诊断数据源）
///
/// 一次完整拍卖的事件流示例（插屏，瀑布第 3 层成交后降级展示）：
///   auctionStart → bidResponse(失败/超时) → waterfallLayer(第1层)
///   → waterfallLayer(第2层) → waterfallLayer(第3层) → loadResult(成功)
///   → auctionSettle(赢家=A) → showResult(A 失败,600180) → showResult(降级 B 成功)
typedef NS_ENUM(NSInteger, ADXAdEventType) {
    /// 拍卖开始（一个 slot 一次请求一条）
    ADXAdEventTypeAuctionStart = 0,
    /// 单个竞价源回包（成功=出价 / 失败=无填充或超时）
    ADXAdEventTypeBidResponse,
    /// 瀑布某层开始请求（waterfallLayer 从 1 计）
    ADXAdEventTypeWaterfallLayer,
    /// 单个瀑布源回包（成功/失败/超时）
    ADXAdEventTypeWaterfallResponse,
    /// 拍卖结算（赢家 / 无可用广告；含成交层位与总耗时）
    ADXAdEventTypeAuctionSettle,
    /// 展示结果（赢家展示失败降级时，每个候选各发一条）
    ADXAdEventTypeShowResult,
};

/// 广告链路事件模型
///
/// 事件由 SDK 内部在拍卖/展示链路节点自动发射，业务方通过
/// ADXAdManager 的 setAdEventHandler: 观察，可转投自有统计系统。
/// 4a 阶段仅本地分发；4b（服务端就绪后）在同一事件源上扩上报通道，本模型不变。
@interface ADXAdEvent : NSObject

/// 事件类型
@property (nonatomic, assign) ADXAdEventType type;

/// 广告位标识，如 "splash_main"
@property (nonatomic, copy) NSString *slotName;

/// 广告类型
@property (nonatomic, assign) ADXAdType adType;

/// 相关广告源 ID（auctionStart/auctionSettle 为空串）
@property (nonatomic, copy) NSString *sourceId;

/// 价格，单位：分。竞价回包=实时出价；瀑布回包=实际价；结算=成交价；其余 0
/// priceSource 标记该价格的来源质量
@property (nonatomic, assign) NSInteger price;

/// 价格来源：YES=客户端实时价（GDT eCPM/百度 getPECPM/竞价出价），
/// NO=floorEcpm 近似（Sigmob/CSJ 瀑布源拿不到实时价）
@property (nonatomic, assign) BOOL priceIsRealtime;

/// 瀑布层位，从 1 计；仅 waterfallLayer/waterfallResponse/auctionSettle 有值，其余 0
@property (nonatomic, assign) NSUInteger waterfallLayer;

/// 成交层位（拍卖结算时）；0 表示竞价胜出或无成交
@property (nonatomic, assign) NSUInteger settledLayer;

/// 是否成功（bidResponse/waterfallResponse/showResult 的成败）
@property (nonatomic, assign) BOOL success;

/// 失败原因（成功时为 nil）
@property (nonatomic, strong, nullable) NSError *error;

/// 事件时间戳（unix 毫秒）
@property (nonatomic, assign) NSTimeInterval timestamp;

/// 竞争对手：结算事件的赢家 sourceId（判断降级：showResult 的 sourceId ≠ 赢家即降级发生）
@property (nonatomic, copy, nullable) NSString *winnerSourceId;

/// 总耗时，单位：秒（仅 auctionSettle 有值）
@property (nonatomic, assign) NSTimeInterval totalDuration;

@end

NS_ASSUME_NONNULL_END
