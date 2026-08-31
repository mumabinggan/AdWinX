//
//  ADXEventReporter.h
//  AdWinX
//
//  Created by AdWinX on 2026/08/31.
//

#import <Foundation/Foundation.h>
#import "ADXAdEvent.h"

NS_ASSUME_NONNULL_BEGIN

/// 事件上报通道（4b）：内存缓冲 → 批量上传
///
/// 事件由 ADXAdEventDispatcher 自动喂入，业务方无需干预。
/// 上传节奏：满 20 条 或 每 30s；App 退后台补传一次。
/// 缓冲为纯内存（不落盘）：统计场景下杀 App 丢失末尾少量事件可接受，
/// 换取零持久化复杂度（无文件损坏/去重/删除原子性问题）。
///
/// reportURL 未配置时不发起任何网络请求，仅打印上传载荷（调试期行为）；
/// URL 将来由服务端通过远程配置下发，业务方也可先行手动注入。
@interface ADXEventReporter : NSObject

+ (instancetype)sharedReporter;

/// 上报接收端点（HTTPS）。nil = 不上传，仅打印载荷
@property (nonatomic, strong, nullable) NSURL *reportURL;

/// SDK 内部调用：事件入缓冲队列（线程安全；满 20 条自动触发 flush）
- (void)collectEvent:(ADXAdEvent *)event;

/// 立即上传（或无 URL 时打印）当前缓冲的全部事件
- (void)flush;

@end

NS_ASSUME_NONNULL_END
