//
//  ADXAdEventDispatcher.m
//  AdWinX
//
//  Created by AdWinX on 2026/08/31.
//

#import "ADXAdEventDispatcher.h"
#import "ADXEventReporter.h"

static ADXAdEventHandler _eventHandler = nil;

@implementation ADXAdEventDispatcher

+ (instancetype)sharedDispatcher
{
    static ADXAdEventDispatcher *instance = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        instance = [[ADXAdEventDispatcher alloc] init];
    });
    return instance;
}

+ (void)setEventHandler:(nullable ADXAdEventHandler)handler
{
    @synchronized (self) {
        _eventHandler = [handler copy];
    }
}

- (void)dispatchEvent:(ADXAdEvent *)event
{
    if (!event) {
        return;
    }

    // 事件先入上报缓冲（4b：无论业务方是否设置观察回调，上报通道独立工作）
    [[ADXEventReporter sharedReporter] collectEvent:event];

    ADXAdEventHandler handler = nil;
    @synchronized ([self class]) {
        handler = _eventHandler;
    }
    if (!handler) {
        return;
    }

    dispatch_async(dispatch_get_main_queue(), ^{
        handler(event);
    });
}

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
            totalDuration:(NSTimeInterval)totalDuration
{
    ADXAdEvent *event = [[ADXAdEvent alloc] init];
    event.type = type;
    event.slotName = slotName ?: @"";
    event.adType = adType;
    event.sourceId = sourceId ?: @"";
    event.price = price;
    event.priceIsRealtime = priceIsRealtime;
    event.waterfallLayer = waterfallLayer;
    event.settledLayer = 0;
    event.success = success;
    event.error = error;
    event.winnerSourceId = winnerSourceId;
    event.totalDuration = totalDuration;

    [[self sharedDispatcher] dispatchEvent:event];
}

@end
