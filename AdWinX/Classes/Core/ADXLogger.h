//
//  ADXLogger.h
//  AdWinX
//
//  Created by AdWinX on 2026/08/29.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/// 日志级别
typedef NS_ENUM(NSInteger, ADXLogLevel) {
    ADXLogLevelOff = 0,    // 关闭日志
    ADXLogLevelError = 1,  // 仅错误
    ADXLogLevelInfo = 2,   // 关键流程：竞价/瀑布/结算
    ADXLogLevelDebug = 3,  // 全部细节
};

/// 日志转发回调
///
/// @param level 日志级别
/// @param message 日志内容（不含 [AdWinX] 前缀）
typedef void (^ADXLogHandler)(ADXLogLevel level, NSString *message);

/// 聚合 SDK 统一日志组件
///
/// 默认行为按构建环境自适应：
///   - Debug 构建：Info 级别，NSLog 输出（带 [AdWinX] 前缀）
///   - Release 构建：默认关闭（Off），可通过 setLogLevel: 显式打开
///     （线上诊断场景：由服务端配置下发开关，临时点亮指定设备的日志）
///
/// 设置 logHandler 后改由回调转发（接入方可转投 CocoaLumberjack 等自有日志体系），
/// SDK 自身不再 NSLog 输出。
@interface ADXLogger : NSObject

/// 日志级别（显式调用可覆盖环境默认值）
+ (void)setLogLevel:(ADXLogLevel)level;

/// 当前日志级别
+ (ADXLogLevel)logLevel;

/// 日志转发回调（设置后不再 NSLog，由接入方自行处理；传 nil 恢复默认 NSLog）
+ (void)setLogHandler:(nullable ADXLogHandler)handler;

/// 输出日志（级别高于当前设置时丢弃）
+ (void)logWithLevel:(ADXLogLevel)level
            message:(NSString *)format, ... NS_FORMAT_FUNCTION(2, 3);

/// 读取并清空落盘日志文件
///
/// Info 及以下级别的日志会同步写入沙盒 Caches/adx_debug.log，
/// 用于「无调试器冷启动」后回捞分析（调试器下的 NSLog I/O 会干扰冷启动耗时测量）。
/// 读取后文件即删除，返回 nil 表示无上次日志。
+ (nullable NSString *)drainLogFile;

@end

/// 便捷日志宏（调用处使用，免写 level 参数）
#define ADXLogError(...)   [ADXLogger logWithLevel:ADXLogLevelError message:__VA_ARGS__]
#define ADXLogInfo(...)    [ADXLogger logWithLevel:ADXLogLevelInfo  message:__VA_ARGS__]
#define ADXLogDebug(...)   [ADXLogger logWithLevel:ADXLogLevelDebug message:__VA_ARGS__]

NS_ASSUME_NONNULL_END
