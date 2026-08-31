//
//  ADXLogger.m
//  AdWinX
//
//  Created by AdWinX on 2026/08/29.
//

#import "ADXLogger.h"

static ADXLogLevel _logLevel = ADXLogLevelOff;
static ADXLogHandler _logHandler = nil;

// 落盘专用后台串行队列：主线程只做一次入队，文件 I/O 全部移出主线程
static dispatch_queue_t _fileLogQueue = nil;
// 内存缓冲：批量写盘，摊薄 I/O 次数（每次 flush 一次 open/write/close）
static NSMutableArray<NSString *> *_fileLogBuffer = nil;
static const NSUInteger kADXFileLogFlushThreshold = 20; // 缓冲满 20 条即刷盘
static const NSTimeInterval kADXFileLogFlushInterval = 1.0; // 定时兜底刷盘，保证进程被杀前日志尽量落盘

@implementation ADXLogger

+ (void)initialize
{
    if (self != [ADXLogger class]) {
        return;
    }
#if DEBUG
    // Debug 构建：默认打印关键流程日志（本地调试需要看全竞价→瀑布链路）
    _logLevel = ADXLogLevelInfo;
#else
    // Release 构建：默认关闭（线上通过 setLogLevel: 由远程开关临时点亮）
    _logLevel = ADXLogLevelOff;
#endif
    _fileLogQueue = dispatch_queue_create("com.adwinx.filelog", DISPATCH_QUEUE_SERIAL);
    _fileLogBuffer = [NSMutableArray array];
}

+ (dispatch_queue_t)fileLogQueue
{
    return _fileLogQueue;
}

+ (void)flushFileLogBuffer
{
    if (_fileLogBuffer.count == 0) {
        return;
    }
    NSArray *lines = [_fileLogBuffer copy];
    [_fileLogBuffer removeAllObjects];
    NSString *content = [lines componentsJoinedByString:@""];
    NSData *data = [content dataUsingEncoding:NSUTF8StringEncoding];

    NSString *path = [self logFilePath];
    NSFileHandle *handle = [NSFileHandle fileHandleForWritingAtPath:path];
    if (!handle) {
        [data writeToFile:path atomically:YES];
    } else {
        [handle seekToEndOfFile];
        [handle writeData:data];
        [handle closeFile];
    }
}

+ (void)setLogLevel:(ADXLogLevel)level
{
    _logLevel = level;
}

+ (ADXLogLevel)logLevel
{
    return _logLevel;
}

+ (void)setLogHandler:(ADXLogHandler)handler
{
    _logHandler = [handler copy];
}

+ (void)logWithLevel:(ADXLogLevel)level message:(NSString *)format, ...
{
    // 级别过滤：Off 时全丢弃；level 高于当前级别时丢弃
    if (_logLevel == ADXLogLevelOff || level > _logLevel) {
        return;
    }

    // 格式化可变参数
    va_list args;
    va_start(args, format);
    NSString *message = [[NSString alloc] initWithFormat:format arguments:args];
    va_end(args);

    // 已设置转发回调：交给接入方，SDK 自身不再输出
    if (_logHandler) {
        _logHandler(level, message);
        return;
    }

    // 默认走 NSLog，统一前缀方便控制台过滤；带时间戳便于分析冷启动各阶段耗时
    NSString *line = [NSString stringWithFormat:@"[AdWinX][%@] %@\n", [NSDate date], message];
    NSLog(@"[AdWinX][%@] %@", [NSDate date], message);

    // 异步落盘（沙盒）：主线程仅做一次入队，文件 I/O 在后台串行队列批量执行。
    // 仅 Info 及以下级别才落盘，Debug 级别高频日志不写文件避免 I/O 开销。
    // 缓冲满 20 条或距上次 flush 超过 1s 即刷盘（时间戳在入队时生成，顺序不受 flush 时机影响）。
    if (level <= ADXLogLevelInfo) {
        dispatch_async(_fileLogQueue, ^{
            [_fileLogBuffer addObject:line];
            if (_fileLogBuffer.count >= kADXFileLogFlushThreshold) {
                [self flushFileLogBuffer];
            } else if (_fileLogBuffer.count == 1) {
                // 缓冲区从空到有：安排一次 1s 后的定时兜底 flush，
                // 低频日志（如冷启动锚点）不会长期滞留内存
                dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(kADXFileLogFlushInterval * NSEC_PER_SEC)), _fileLogQueue, ^{
                    [self flushFileLogBuffer];
                });
            }
        });
    }
}

#pragma mark - File Log（无调试器冷启动分析用）

+ (NSString *)logFilePath
{
    static NSString *path = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        NSString *cachesDirectory = [NSSearchPathForDirectoriesInDomains(NSCachesDirectory, NSUserDomainMask, YES) firstObject];
        path = [cachesDirectory stringByAppendingPathComponent:@"adx_debug.log"];
    });
    return path;
}

/// 读取并清空落盘日志（供接入方下次启动时回捞上次无调试器的日志）
+ (nullable NSString *)drainLogFile
{
    // 先同步刷出缓冲（drain 在 didFinishLaunching 最早期调用，此时基本无缓冲，防御性 flush）
    dispatch_sync(_fileLogQueue, ^{
        [self flushFileLogBuffer];
    });

    NSString *path = [self logFilePath];
    NSString *content = [NSString stringWithContentsOfFile:path encoding:NSUTF8StringEncoding error:nil];
    if (content.length > 0) {
        [[NSFileManager defaultManager] removeItemAtPath:path error:nil];
    }
    return content;
}

@end
