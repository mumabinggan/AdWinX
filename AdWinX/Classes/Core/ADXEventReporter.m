//
//  ADXEventReporter.m
//  AdWinX
//
//  Created by AdWinX on 2026/08/31.
//

#import "ADXEventReporter.h"
#import "ADXAdEventDispatcher.h"
#import "ADXConfig.h"
#import "ADXLogger.h"
#import <UIKit/UIKit.h>

/// 缓冲容量上限：超出丢弃最旧事件（防内存无限增长）
static NSUInteger const kADXReporterMaxBuffer = 500;
/// 数量触发阈值：满即上传
static NSUInteger const kADXReporterFlushThreshold = 20;
/// 周期触发间隔：定时上传非空缓冲
static NSTimeInterval const kADXReporterFlushInterval = 30.0;

@interface ADXEventReporter ()

@property (nonatomic, strong) NSMutableArray<ADXAdEvent *> *buffer;
@property (nonatomic, strong) NSTimer *flushTimer;

@end

@implementation ADXEventReporter

+ (instancetype)sharedReporter
{
    static ADXEventReporter *instance = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        instance = [[ADXEventReporter alloc] init];
    });
    return instance;
}

- (instancetype)init
{
    self = [super init];
    if (self) {
        _buffer = [NSMutableArray array];

        // 定时 flush：挂主 RunLoop；target 用 self（单例常驻，与 timer 的引用环无实际影响）
        _flushTimer = [NSTimer timerWithTimeInterval:kADXReporterFlushInterval
                                              target:self
                                            selector:@selector(flush)
                                            userInfo:nil
                                             repeats:YES];
        [[NSRunLoop mainRunLoop] addTimer:_flushTimer forMode:NSRunLoopCommonModes];

        // 退后台补传：抓住最后一次上传窗口（App 被杀前的缓冲不落盘，尽力冲掉）
        [[NSNotificationCenter defaultCenter] addObserver:self
                                                 selector:@selector(flush)
                                                     name:UIApplicationDidEnterBackgroundNotification
                                                   object:nil];
    }
    return self;
}

- (void)dealloc
{
    [[NSNotificationCenter defaultCenter] removeObserver:self];
    [_flushTimer invalidate];
}

#pragma mark - Collect

- (void)collectEvent:(ADXAdEvent *)event
{
    if (!event) {
        return;
    }

    BOOL shouldFlush = NO;
    @synchronized (self) {
        [self.buffer addObject:event];
        if (self.buffer.count > kADXReporterMaxBuffer) {
            // 丢弃最旧：诊断统计容忍少量丢失，保内存上限
            [self.buffer removeObjectsInRange:NSMakeRange(0, self.buffer.count - kADXReporterMaxBuffer)];
        }
        shouldFlush = (self.buffer.count >= kADXReporterFlushThreshold);
    }

    if (shouldFlush) {
        [self flush];
    }
}

#pragma mark - Flush

- (void)flush
{
    // 取走缓冲快照并清空（锁内原子完成），网络/打印在锁外执行
    NSArray<ADXAdEvent *> *events = nil;
    @synchronized (self) {
        if (self.buffer.count == 0) {
            return;
        }
        events = [self.buffer copy];
        [self.buffer removeAllObjects];
    }

    NSDictionary *payload = [self payloadWithEvents:events];

    if (!self.reportURL) {
        // 无接收端（服务端未就绪）：打印完整上传载荷，供调试与接口联调参考
        [self logPayload:payload eventCount:events.count];
        return;
    }

    [self uploadPayload:payload events:events];
}

#pragma mark - Payload

/// 组装上传载荷：公共头 + 事件数组
- (NSDictionary *)payloadWithEvents:(NSArray<ADXAdEvent *> *)events
{
    NSMutableArray *eventDicts = [NSMutableArray arrayWithCapacity:events.count];
    for (ADXAdEvent *event in events) {
        NSMutableDictionary *dict = [NSMutableDictionary dictionary];
        dict[@"type"] = @(event.type);
        dict[@"slotName"] = event.slotName;
        dict[@"adType"] = @(event.adType);
        dict[@"sourceId"] = event.sourceId;
        dict[@"price"] = @(event.price);
        dict[@"priceIsRealtime"] = @(event.priceIsRealtime);
        dict[@"waterfallLayer"] = @(event.waterfallLayer);
        dict[@"settledLayer"] = @(event.settledLayer);
        dict[@"success"] = @(event.success);
        if (event.error) {
            dict[@"errorDomain"] = event.error.domain;
            dict[@"errorCode"] = @(event.error.code);
            dict[@"errorDesc"] = event.error.localizedDescription;
        }
        if (event.winnerSourceId.length > 0) {
            dict[@"winnerSourceId"] = event.winnerSourceId;
        }
        dict[@"timestamp"] = @(event.timestamp);
        dict[@"totalDuration"] = @(event.totalDuration);
        [eventDicts addObject:dict];
    }

    NSTimeInterval nowMs = [[NSDate date] timeIntervalSince1970] * 1000;
    NSDictionary *header = @{
        @"sdkVersion": ADXSDKVersion,
        @"eventCount": @(events.count),
        @"reportTime": @(nowMs),
    };
    return @{ @"header": header, @"events": eventDicts };
}

- (void)logPayload:(NSDictionary *)payload eventCount:(NSUInteger)count
{
    NSData *json = [NSJSONSerialization dataWithJSONObject:payload
                                                   options:NSJSONWritingSortedKeys | NSJSONWritingPrettyPrinted
                                                     error:nil];
    NSString *body = json ? [[NSString alloc] initWithData:json encoding:NSUTF8StringEncoding]
                          : [payload description];
    ADXLogInfo(@"事件上报（未配置 reportURL，仅打印，共 %lu 条）：%@",
               (unsigned long)count, body);
}

#pragma mark - Upload

- (void)uploadPayload:(NSDictionary *)payload events:(NSArray<ADXAdEvent *> *)events
{
    NSData *body = [NSJSONSerialization dataWithJSONObject:payload options:0 error:nil];
    if (!body) {
        ADXLogError(@"事件上报失败：载荷序列化失败，丢弃 %lu 条", (unsigned long)events.count);
        return;
    }

    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:self.reportURL];
    request.HTTPMethod = @"POST";
    request.HTTPBody = body;
    request.timeoutInterval = 10;
    [request setValue:@"application/json" forHTTPHeaderField:@"Content-Type"];

    NSURLSessionDataTask *task = [[NSURLSession sharedSession] dataTaskWithRequest:request
                                                                   completionHandler:^(NSData * _Nullable data, NSURLResponse * _Nullable response, NSError * _Nullable error) {
        if (error) {
            // 失败回插队头：事件不丢，下个 flush 周期自然重传（不做复杂重试/退避）
            @synchronized (self) {
                NSIndexSet *indexes = [NSIndexSet indexSetWithIndexesInRange:NSMakeRange(0, events.count)];
                [self.buffer insertObjects:events atIndexes:indexes];
            }
            ADXLogError(@"事件上报失败（%lu 条已回插队列，待下周期重传）：%@",
                        (unsigned long)events.count, error.localizedDescription);
            return;
        }

        NSHTTPURLResponse *httpResponse = (NSHTTPURLResponse *)response;
        if (httpResponse.statusCode >= 200 && httpResponse.statusCode < 300) {
            ADXLogInfo(@"事件上报成功：%lu 条", (unsigned long)events.count);
        } else {
            // 非 2xx 视为服务端拒绝（重传大概率同样被拒），丢弃并记录
            ADXLogError(@"事件上报被拒绝（HTTP %ld，丢弃 %lu 条）",
                        (long)httpResponse.statusCode, (unsigned long)events.count);
        }
    }];
    [task resume];
}

@end
