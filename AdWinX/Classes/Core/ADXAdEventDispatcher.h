//
//  ADXAdEventDispatcher.h
//  AdWinX
//
//  Created by AdWinX on 2026/08/31.
//

#import <Foundation/Foundation.h>
#import "ADXAdEvent.h"

NS_ASSUME_NONNULL_BEGIN

/// 事件观察回调（主线程）
typedef void (^ADXAdEventHandler)(ADXAdEvent *event);

/// 广告事件分发器：SDK 内部各链路节点 → 业务方观察回调
///
/// 无 handler 时发射零开销（单指针判空）；handler 统一在主线程回调。
/// 4a 阶段仅本地分发；4b 上报通道（落盘队列 + 批量上传）将来挂在本分发器上，事件源不变。
@interface ADXAdEventDispatcher : NSObject

+ (instancetype)sharedDispatcher;

/// 设置/移除事件观察回调（传 nil 移除）
+ (void)setEventHandler:(nullable ADXAdEventHandler)handler;

/// 发射事件（SDK 内部调用；线程安全，handler 未设置时直接返回）
- (void)dispatchEvent:(ADXAdEvent *)event;

/// 便捷发射：内部构建事件并分发，字段按需传（未用字段传 0/nil/空串）
+ (void)emitEventWithType:(ADXAdEventType)type
                 slotName:(NSString *)slotName
                   adType:(ADXAdType)adType
                 sourceId:(NSString *)sourceId
                    price:(NSInteger)price
          priceIsRealtime:(BOOL)priceIsRealtime
           waterfallLayer:(NSUInteger)waterfallLayer
                  success:(BOOL)success
                    error:(nullable NSError *)error
          winnerSourceId:(nullable NSString *)winnerSourceId
            totalDuration:(NSTimeInterval)totalDuration;

@end

NS_ASSUME_NONNULL_END
