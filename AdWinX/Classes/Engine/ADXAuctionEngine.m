//
//  ADXAuctionEngine.m
//  AdWinX
//
//  Created by AdWinX on 2026/08/29.
//

#import "ADXAuctionEngine.h"
#import "ADXSlotConfig.h"
#import "ADXAdSourceInfo.h"
#import "ADXBidResult.h"
#import "ADXAuctionResult.h"
#import "ADXAdapter.h"
#import "ADXAdEventDispatcher.h"
#import "ADXLogger.h"

/// 剩余预算低于该阈值时，跳过中间瀑布层直取 realEcpm=0 兜底组，单位：秒
static NSTimeInterval const ADXWaterfallFallbackThreshold = 1.5;

#pragma mark - Auction Context（单次拍卖的状态容器）

/// 一次拍卖的全部上下文状态，生命周期与本次拍卖一致
@interface ADXAuctionContext : NSObject

@property (nonatomic, strong) ADXSlotConfig *config;
@property (nonatomic, strong) NSDate *startDate;

@property (nonatomic, copy) NSArray<ADXAdSourceInfo *> *bidSources;        // 竞价源
@property (nonatomic, copy) NSArray<ADXAdSourceInfo *> *waterfallSources;  // 瀑布源（按 floorEcpm 降序）

@property (nonatomic, assign) BOOL finished;                                // 拍卖是否已结束

@property (nonatomic, strong) NSMutableArray<ADXBidResult *> *allCandidates;  // 所有加载结果（含失败）
@property (nonatomic, strong) NSMutableDictionary<NSString *, id<ADXAdapter>> *adapters; // sourceId -> adapter

// 拍卖状态推进专用串行队列：回包收集、超时兜底、瀑布流转都在此队列 FIFO 执行，
// 与主队列解耦——启动期主线程拥堵不再推迟超时判定和阶段流转；仅最终回调回主线程
@property (nonatomic, strong) dispatch_queue_t stateQueue;

@property (nonatomic, assign) NSInteger pendingBidCount;                    // 竞价阶段未返回的源数量
@property (nonatomic, assign) BOOL bidPhaseFinished;                        // 竞价阶段是否已结束（防迟到回包重入）
@property (nonatomic, strong, nullable) ADXBidResult *bestBidResult;        // 竞价阶段最高出价

@property (nonatomic, assign) NSTimeInterval totalBudget;                   // 拍卖总预算（竞价+瀑布），单位：秒

/// 成交时正在请求的瀑布层位（从 1 计；竞价胜出保持 0），事件上报用
@property (nonatomic, assign) NSUInteger settledWaterfallLayer;

@property (nonatomic, copy, nullable) ADXAuctionCompletion completion;

@end

@implementation ADXAuctionContext
@end

#pragma mark - Waterfall Group State（单个瀑布并行组的加载状态）

/// 排序键（realEcpm、priority）完全相同的一组瀑布源，组内并行请求。
/// 状态生命周期与该组请求一致，访问需持有 auction context 锁。
@interface ADXWaterfallGroupState : NSObject

@property (nonatomic, copy) NSArray<ADXAdSourceInfo *> *group;      // 组内源（已按优先级序）
@property (nonatomic, assign) NSUInteger pendingCount;              // 未回包的源数量
@property (nonatomic, assign) BOOL settled;                         // 组是否已结算（全部回包或超时）
@property (nonatomic, strong) NSMutableArray<ADXBidResult *> *results;      // 已回包结果
@property (nonatomic, strong) NSMutableSet<NSString *> *respondedSourceIds; // 已回包的 sourceId

@end

@implementation ADXWaterfallGroupState
@end

#pragma mark - Auction Engine

@implementation ADXAuctionEngine

- (void)runAuctionWithConfig:(ADXSlotConfig *)config
                     adapters:(NSDictionary<NSString *, id<ADXAdapter>> *)adapters
                   completion:(ADXAuctionCompletion)completion
{
    ADXAuctionContext *context = [[ADXAuctionContext alloc] init];
    context.config = config;
    context.startDate = [NSDate date];
    context.totalBudget = config.totalTimeout > 0 ? config.totalTimeout : 5;
    context.completion = completion;
    context.allCandidates = [NSMutableArray array];
    context.adapters = [NSMutableDictionary dictionaryWithDictionary:adapters];
    context.stateQueue = dispatch_queue_create("com.adwinx.auction.state", DISPATCH_QUEUE_SERIAL);

    // 按运行时模式分组，瀑布源按（realEcpm 降序、priority 降序）排列；
    // 排序键完全相同的相邻源在请求阶段归为并行组
    NSMutableArray *bidSources = [NSMutableArray array];
    NSMutableArray *waterfallSources = [NSMutableArray array];
    for (ADXAdSourceInfo *source in config.adSources) {
        if (source.runtimeMode == ADXRuntimeModeBidding) {
            [bidSources addObject:source];
        } else {
            [waterfallSources addObject:source];
        }
    }
    [waterfallSources sortUsingComparator:^NSComparisonResult(ADXAdSourceInfo *a, ADXAdSourceInfo *b) {
        if (a.realEcpm != b.realEcpm) {
            return [@(b.realEcpm) compare:@(a.realEcpm)];
        }
        return [@(b.priority) compare:@(a.priority)];
    }];
    context.bidSources = bidSources;
    context.waterfallSources = waterfallSources;

    ADXLogInfo(@"拍卖开始：共 %lu 个源（竞价 %lu / 瀑布 %lu），bidTimeout=%.1fs",
               (unsigned long)config.adSources.count,
               (unsigned long)bidSources.count,
               (unsigned long)waterfallSources.count,
               config.bidTimeout);

    [ADXAdEventDispatcher emitEventWithType:ADXAdEventTypeAuctionStart
                                   slotName:config.slotName
                                     adType:config.adType
                                   sourceId:@""
                                      price:0
                            priceIsRealtime:NO
                             waterfallLayer:0
                                    success:YES
                                      error:nil
                              winnerSourceId:nil
                                totalDuration:0];

    // 状态推进切入专用队列：后续所有回包收集、超时兜底、瀑布流转都在该队列串行执行
    dispatch_async(context.stateQueue, ^{
        [self startBiddingPhaseWithContext:context];
    });
}

#pragma mark - Phase 1: Bidding（竞价并行）

- (void)startBiddingPhaseWithContext:(ADXAuctionContext *)context
{
    context.pendingBidCount = context.bidSources.count;

    // 竞价池无源，直接进入瀑布
    if (context.pendingBidCount == 0) {
        [self startWaterfallPhaseWithContext:context];
        return;
    }

    // 竞价整体超时兜底（Adapter 内部还有单源超时）；挂专用队列，主队列拥堵不影响判定时刻
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(context.config.bidTimeout * NSEC_PER_SEC)),
                   context.stateQueue, ^{
        [self finishBiddingPhaseWithContext:context timeout:YES];
    });

    for (ADXAdSourceInfo *source in context.bidSources) {
        id<ADXAdapter> adapter = context.adapters[source.sourceId];
        if (!adapter) {
            // 未注册的 ADN，按失败记录
            ADXBidResult *result = [ADXBidResult resultWithSourceId:source.sourceId
                                                             adType:source.adType
                                                              price:0
                                                           adObject:nil
                                                            success:NO
                                                              error:[NSError errorWithDomain:@"ADXAuctionEngine"
                                                                                        code:-1
                                                                                    userInfo:@{NSLocalizedDescriptionKey:
                                                                                               [NSString stringWithFormat:@"未注册 ADN: %@ 的 Adapter", source.adnName]}]];
            [self collectBidResult:result source:source context:context];
            continue;
        }

        // Adapter 加载切回主线程：开屏等广告类型需创建/挂载 UIView，UI 操作禁止在后台队列执行
        dispatch_async(dispatch_get_main_queue(), ^{
            [adapter loadAdWithSourceInfo:source completion:^(ADXBidResult *result) {
                [self collectBidResult:result source:source context:context];
            }];
        });

        ADXLogInfo(@"竞价请求：%@（%@，placement=%@）", source.sourceId, source.adnName, source.placementId);
    }
}

/// 收集单个竞价源的结果，全部返回后结束竞价阶段
/// 回调线程不定（多为 ADN 的主线程回调），统一切入专用队列处理，保证到达顺序即处理顺序
- (void)collectBidResult:(ADXBidResult *)result
                  source:(ADXAdSourceInfo *)source
                 context:(ADXAuctionContext *)context
{
    dispatch_async(context.stateQueue, ^{
        [self handleBidResult:result source:source context:context];
    });
}

- (void)handleBidResult:(ADXBidResult *)result
                 source:(ADXAdSourceInfo *)source
                context:(ADXAuctionContext *)context
{
    if (result.success) {
        ADXLogInfo(@"竞价回包：%@ 成功 price=%ld",
                   result.sourceId, (long)result.price);
    } else {
        ADXLogError(@"竞价回包：%@ 失败 error=%@",
                    result.sourceId, result.error.localizedDescription);
    }

    [ADXAdEventDispatcher emitEventWithType:ADXAdEventTypeBidResponse
                                   slotName:context.config.slotName
                                     adType:source.adType
                                   sourceId:result.sourceId
                                      price:result.price
                            priceIsRealtime:result.price > 0
                             waterfallLayer:0
                                    success:result.success
                                      error:result.error
                              winnerSourceId:nil
                                totalDuration:0];

    @synchronized (context) {
        [context.allCandidates addObject:result];

        // 竞价阶段已结束（超时兜底触发过）：迟到回包不重入竞价/瀑布流程，
        // 但成功出价仍更新 bestBidResult——拍卖尚未结算时，迟到的好价仍应在最终比价中胜出
        // （迟到常因主线程拥堵而非网络慢，直接丢弃会导致「有广告却结算为无」）
        if (context.bidPhaseFinished) {
            if (result.success && (!context.bestBidResult || result.price > context.bestBidResult.price)) {
                context.bestBidResult = result;
            }
            return;
        }

        if (result.success) {
            if (!context.bestBidResult || result.price > context.bestBidResult.price) {
                context.bestBidResult = result;
            }
        }

        context.pendingBidCount -= 1;
        if (context.pendingBidCount > 0) {
            return;
        }
    }

    [self finishBiddingPhaseWithContext:context timeout:NO];
}

- (void)finishBiddingPhaseWithContext:(ADXAuctionContext *)context
                              timeout:(BOOL)timeout
{
    BOOL shouldContinue = NO;
    @synchronized (context) {
        // 已结束过（超时兜底或全部回包），迟到触发直接忽略，防止瀑布阶段重入
        if (context.bidPhaseFinished) {
            return;
        }
        if (context.pendingBidCount <= 0) {
            context.bidPhaseFinished = YES;
            shouldContinue = YES;
        } else if (timeout) {
            // 超时：未返回的竞价源不再等待，直接进入下一阶段
            context.pendingBidCount = 0;
            context.bidPhaseFinished = YES;
            shouldContinue = YES;
        }
    }
    if (!shouldContinue) {
        return;
    }

    // 竞价阶段结束日志
    @synchronized (context) {
        if (context.bestBidResult) {
            ADXLogInfo(@"竞价阶段结束（%@）：最高出价 %ld（%@）",
                       timeout ? @"整体超时" : @"全部回包",
                       (long)context.bestBidResult.price, context.bestBidResult.sourceId);
        } else {
            ADXLogInfo(@"竞价阶段结束（%@）：无有效出价", timeout ? @"整体超时" : @"全部回包");
        }
    }

    [self startWaterfallPhaseWithContext:context];
}

#pragma mark - Phase 2: Waterfall（瀑布：组间串行，组内并行）

- (void)startWaterfallPhaseWithContext:(ADXAuctionContext *)context
{
    // 瀑布过滤：仅请求 realEcpm >= 竞价最高价的源；竞价无出价时（0）请求全部
    NSInteger bestBidPrice = 0;
    @synchronized (context) {
        bestBidPrice = context.bestBidResult.price;
    }

    NSMutableArray *eligibleSources = [NSMutableArray array];
    for (ADXAdSourceInfo *source in context.waterfallSources) {
        if (source.realEcpm >= bestBidPrice) {
            [eligibleSources addObject:source];
        }
    }

    ADXLogInfo(@"瀑布过滤：realEcpm ≥ %ld 的源 %lu 个 / 共 %lu 个",
               (long)bestBidPrice,
               (unsigned long)eligibleSources.count,
               (unsigned long)context.waterfallSources.count);

    NSArray *groups = [self parallelGroupsFromSources:eligibleSources];
    [self loadWaterfallGroupAtIndex:0 groups:groups context:context];
}

/// 排序键（realEcpm、priority）完全相同的相邻源归为一组：组间串行、组内并行
- (NSArray<NSArray<ADXAdSourceInfo *> *> *)parallelGroupsFromSources:(NSArray<ADXAdSourceInfo *> *)sources
{
    NSMutableArray<NSArray<ADXAdSourceInfo *> *> *groups = [NSMutableArray array];
    NSMutableArray<ADXAdSourceInfo *> *current = [NSMutableArray array];
    for (ADXAdSourceInfo *source in sources) {
        ADXAdSourceInfo *last = current.lastObject;
        if (last && (last.realEcpm != source.realEcpm || last.priority != source.priority)) {
            [groups addObject:[current copy]];
            current = [NSMutableArray array];
        }
        [current addObject:source];
    }
    if (current.count > 0) {
        [groups addObject:[current copy]];
    }
    return groups;
}

/// 串行加载瀑布组：组内并行请求，等待全部回包（或组超时）后按实际价取最优结算，无成功则进入下一组。
/// 超时预算：总预算耗尽直接结算；剩余不足阈值且当前非兜底组时，跳过中间层直取 realEcpm=0 兜底组
- (void)loadWaterfallGroupAtIndex:(NSUInteger)index
                           groups:(NSArray<NSArray<ADXAdSourceInfo *> *> *)groups
                          context:(ADXAuctionContext *)context
{
    if (index >= groups.count) {
        [self finishAuctionWithContext:context waterfallResult:nil];
        return;
    }

    // 超时预算：总预算耗尽 → 按已有候选直接结算
    NSTimeInterval remaining = [self remainingBudgetWithContext:context];
    if (remaining <= 0) {
        ADXLogInfo(@"瀑布终止：总预算 %.0fs 已耗尽，按已有候选结算", context.totalBudget);
        [self finishAuctionWithContext:context waterfallResult:nil];
        return;
    }

    NSArray<ADXAdSourceInfo *> *group = groups[index];
    // 剩余预算不足且当前不是兜底组 → 跳过中间层直取 realEcpm=0 兜底组
    if (group.firstObject.realEcpm > 0 && remaining < ADXWaterfallFallbackThreshold) {
        NSUInteger fallbackIndex = [self fallbackGroupIndexInGroups:groups];
        if (fallbackIndex != NSNotFound) {
            ADXLogInfo(@"瀑布跳档：剩余 %.2fs < %.1fs，跳过中间层直取兜底组",
                       remaining, ADXWaterfallFallbackThreshold);
            index = fallbackIndex;
            group = groups[index];
        }
    }

    ADXAdSourceInfo *firstSource = group.firstObject;
    ADXLogInfo(@"瀑布第 %lu 组请求（%lu 个源并行，realEcpm=%ld，priority=%ld，剩余预算 %.2fs）：%@",
               (unsigned long)(index + 1),
               (unsigned long)group.count,
               (long)firstSource.realEcpm,
               (long)firstSource.priority,
               remaining,
               [[group valueForKeyPath:@"sourceId"] componentsJoinedByString:@", "]);

    // 记录当前层位：结算事件用（跳档后 index 已是兜底组下标，层位如实反映）
    context.settledWaterfallLayer = index + 1;
    [ADXAdEventDispatcher emitEventWithType:ADXAdEventTypeWaterfallLayer
                                   slotName:context.config.slotName
                                     adType:firstSource.adType
                                   sourceId:[[group valueForKeyPath:@"sourceId"] componentsJoinedByString:@","]
                                      price:firstSource.realEcpm
                            priceIsRealtime:NO
                             waterfallLayer:index + 1
                                    success:YES
                                      error:nil
                              winnerSourceId:nil
                                totalDuration:0];

    ADXWaterfallGroupState *state = [[ADXWaterfallGroupState alloc] init];
    state.group = group;
    state.pendingCount = group.count;
    state.results = [NSMutableArray array];
    state.respondedSourceIds = [NSMutableSet set];

    // 组整体超时兜底：未回包的源记超时，按已有回包结算；组超时不得超过剩余预算
    NSTimeInterval groupTimeout = MIN(context.config.waterfallTimeout, remaining);
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(groupTimeout * NSEC_PER_SEC)),
                   context.stateQueue, ^{
        BOOL shouldSettle = NO;
        @synchronized (context) {
            if (state.settled) {
                return;
            }
            state.settled = YES;
            for (ADXAdSourceInfo *source in group) {
                if (![state.respondedSourceIds containsObject:source.sourceId]) {
                    ADXLogError(@"瀑布组超时：%@（%.0fs）", source.sourceId, groupTimeout);
                    [ADXAdEventDispatcher emitEventWithType:ADXAdEventTypeWaterfallResponse
                                                   slotName:context.config.slotName
                                                     adType:source.adType
                                                   sourceId:source.sourceId
                                                      price:0
                                            priceIsRealtime:NO
                                             waterfallLayer:index + 1
                                                    success:NO
                                                      error:[NSError errorWithDomain:@"ADXAuctionEngine"
                                                                                code:-2
                                                                        userInfo:@{NSLocalizedDescriptionKey:
                                                                                   [NSString stringWithFormat:@"瀑布层加载超时（%.0fs）", groupTimeout]}]
                                              winnerSourceId:nil
                                                totalDuration:0];
                    [self recordWaterfallTimeoutForSource:source context:context];
                }
            }
            shouldSettle = YES;
        }
        if (shouldSettle) {
            [self settleGroupState:state index:index groups:groups context:context];
        }
    });

    for (ADXAdSourceInfo *source in group) {
        id<ADXAdapter> adapter = context.adapters[source.sourceId];
        if (!adapter) {
            ADXBidResult *result = [ADXBidResult resultWithSourceId:source.sourceId
                                                             adType:source.adType
                                                              price:0
                                                           adObject:nil
                                                            success:NO
                                                              error:[NSError errorWithDomain:@"ADXAuctionEngine"
                                                                                        code:-1
                                                                                    userInfo:@{NSLocalizedDescriptionKey:
                                                                                               [NSString stringWithFormat:@"未注册 ADN: %@ 的 Adapter", source.adnName]}]];
            [self collectGroupResult:result source:source state:state context:context index:index groups:groups];
            continue;
        }

        // 同竞价阶段：Adapter 加载切回主线程执行 UI 安全操作
        dispatch_async(dispatch_get_main_queue(), ^{
            [adapter loadAdWithSourceInfo:source completion:^(ADXBidResult *result) {
                [self collectGroupResult:result source:source state:state context:context index:index groups:groups];
            }];
        });
    }
}

/// 收集组内单个源的回包，全部回包后触发组结算
/// 回调线程不定（多为 ADN 的主线程回调），统一切入专用队列处理
- (void)collectGroupResult:(ADXBidResult *)result
                    source:(ADXAdSourceInfo *)source
                      state:(ADXWaterfallGroupState *)state
                     context:(ADXAuctionContext *)context
                       index:(NSUInteger)index
                      groups:(NSArray<NSArray<ADXAdSourceInfo *> *> *)groups
{
    dispatch_async(context.stateQueue, ^{
        [self handleGroupResult:result source:source state:state context:context index:index groups:groups];
    });
}

- (void)handleGroupResult:(ADXBidResult *)result
                   source:(ADXAdSourceInfo *)source
                     state:(ADXWaterfallGroupState *)state
                    context:(ADXAuctionContext *)context
                      index:(NSUInteger)index
                     groups:(NSArray<NSArray<ADXAdSourceInfo *> *> *)groups
{
    BOOL shouldSettle = NO;
    @synchronized (context) {
        if (state.settled) {
            ADXLogDebug(@"迟到回包作废：%@（组已按超时结算）", result.sourceId);
            return;
        }

        [context.allCandidates addObject:result];

        [ADXAdEventDispatcher emitEventWithType:ADXAdEventTypeWaterfallResponse
                                       slotName:context.config.slotName
                                         adType:source.adType
                                       sourceId:result.sourceId
                                          price:result.price
                                priceIsRealtime:result.price > 0 && result.price != source.floorEcpm
                                 waterfallLayer:index + 1
                                        success:result.success
                                          error:result.error
                                  winnerSourceId:nil
                                    totalDuration:0];

        [state.results addObject:result];
        [state.respondedSourceIds addObject:source.sourceId];
        state.pendingCount -= 1;

        if (state.pendingCount == 0) {
            state.settled = YES;
            shouldSettle = YES;
        }
    }

    if (shouldSettle) {
        [self settleGroupState:state index:index groups:groups context:context];
    }
}

/// 组结算：有成功回包取实际价最高者结束拍卖（平价取先到者），全部失败进入下一组
- (void)settleGroupState:(ADXWaterfallGroupState *)state
                   index:(NSUInteger)index
                  groups:(NSArray<NSArray<ADXAdSourceInfo *> *> *)groups
                 context:(ADXAuctionContext *)context
{
    ADXBidResult *best = nil;
    @synchronized (context) {
        for (ADXBidResult *result in state.results) {
            if (!result.success) {
                continue;
            }
            if (!best || result.price > best.price) {
                best = result;
            }
        }
    }

    if (best) {
        ADXLogInfo(@"瀑布组结算：最优 %@ price=%ld（组内 %lu 个候选）",
                   best.sourceId, (long)best.price, (unsigned long)state.results.count);
        [self finishAuctionWithContext:context waterfallResult:best];
        return;
    }

    [self loadWaterfallGroupAtIndex:index + 1 groups:groups context:context];
}

/// 剩余预算 = 总预算 - 已耗时
- (NSTimeInterval)remainingBudgetWithContext:(ADXAuctionContext *)context
{
    return context.totalBudget - [[NSDate date] timeIntervalSinceDate:context.startDate];
}

/// 兜底组位置：第一个 realEcpm=0 的组（瀑布按 realEcpm 降序，0 档天然在尾部）
- (NSUInteger)fallbackGroupIndexInGroups:(NSArray<NSArray<ADXAdSourceInfo *> *> *)groups
{
    for (NSUInteger i = 0; i < groups.count; i++) {
        if (groups[i].firstObject.realEcpm == 0) {
            return i;
        }
    }
    return NSNotFound;
}

- (void)recordWaterfallTimeoutForSource:(ADXAdSourceInfo *)source
                                context:(ADXAuctionContext *)context
{
    ADXBidResult *result = [ADXBidResult resultWithSourceId:source.sourceId
                                                     adType:source.adType
                                                      price:0
                                                   adObject:nil
                                                    success:NO
                                                      error:[NSError errorWithDomain:@"ADXAuctionEngine"
                                                                                code:-2
                                                                            userInfo:@{NSLocalizedDescriptionKey: @"瀑布层加载超时"}]];
    @synchronized (context) {
        [context.allCandidates addObject:result];
    }
}

#pragma mark - Phase 3: Settle（结算）

- (void)finishAuctionWithContext:(ADXAuctionContext *)context
                  waterfallResult:(nullable ADXBidResult *)waterfallResult
{
    ADXAuctionCompletion completion = nil;
    @synchronized (context) {
        if (context.finished) {
            return;
        }
        context.finished = YES;
        completion = context.completion;
    }

    // 最终比价：瀑布成功层（floorEcpm >= bidPrice，天然占优）vs 竞价最高出价
    ADXBidResult *bidResult = nil;
    @synchronized (context) {
        bidResult = context.bestBidResult;
    }

    ADXBidResult *winner = nil;
    NSString *winReason = nil;
    if (waterfallResult && bidResult) {
        // 瀑布过滤只保证 realEcpm ≥ 竞价价（编排值），实际回包价可能更低，最终按实际价比
        if (waterfallResult.price >= bidResult.price) {
            winner = waterfallResult;
            winReason = [NSString stringWithFormat:@"瀑布源胜出（实际价 %ld ≥ 竞价最高价 %ld）",
                         (long)waterfallResult.price, (long)bidResult.price];
        } else {
            winner = bidResult;
            winReason = [NSString stringWithFormat:@"竞价胜出（出价 %ld > 瀑布实际价 %ld）",
                         (long)bidResult.price, (long)waterfallResult.price];
        }
    } else if (waterfallResult) {
        winner = waterfallResult;
        winReason = @"瀑布源填充（无竞价出价）";
    } else if (bidResult) {
        winner = bidResult;
        winReason = @"竞价出价胜出（瀑布源全部未填充）";
    }

    if (winner) {
        ADXLogInfo(@"拍卖结算：赢家 %@ price=%ld（%@），总耗时 %.2fs",
                   winner.sourceId, (long)winner.price, winReason,
                   [[NSDate date] timeIntervalSinceDate:context.startDate]);
    } else {
        ADXLogInfo(@"拍卖结算：无可用广告，总耗时 %.2fs",
                   [[NSDate date] timeIntervalSinceDate:context.startDate]);
    }

    {
        NSUInteger settledLayer = 0;
        @synchronized (context) {
            // 瀑布成交：成交层位=当前层；竞价胜出：保持 0
            if (waterfallResult) {
                settledLayer = context.settledWaterfallLayer;
            }
        }
        [ADXAdEventDispatcher emitEventWithType:ADXAdEventTypeAuctionSettle
                                       slotName:context.config.slotName
                                         adType:context.config.adType
                                       sourceId:winner.sourceId ?: @""
                                          price:winner.price
                                priceIsRealtime:winner.price > 0
                                 waterfallLayer:settledLayer
                                        success:winner != nil
                                          error:nil
                                  winnerSourceId:winner.sourceId
                                    totalDuration:[[NSDate date] timeIntervalSinceDate:context.startDate]];
    }

    // 构造拍卖结果
    ADXAuctionResult *auctionResult = [[ADXAuctionResult alloc] init];
    auctionResult.winnerResult = winner;
    auctionResult.winReason = winReason ?: @"无可用广告";
    auctionResult.totalDuration = [[NSDate date] timeIntervalSinceDate:context.startDate];
    @synchronized (context) {
        auctionResult.allCandidates = [context.allCandidates copy];
    }

    [self notifyAuctionOutcomeWithContext:context winner:winner];

    if (completion) {
        dispatch_async(dispatch_get_main_queue(), ^{
            completion(auctionResult);
        });
    }
}

/// 统一通知 Win/Loss：加载成功且展示的源 notifyWin，加载成功但未展示的源 notifyLoss
- (void)notifyAuctionOutcomeWithContext:(ADXAuctionContext *)context
                                 winner:(nullable ADXBidResult *)winner
{
    if (!winner) {
        return;
    }

    NSArray<ADXBidResult *> *successResults;
    NSDictionary<NSString *, id<ADXAdapter>> *adapters;
    @synchronized (context) {
        successResults = [context.allCandidates filteredArrayUsingPredicate:
                          [NSPredicate predicateWithFormat:@"success == YES"]];
        adapters = [context.adapters copy];
    }

    // 第二高价：除赢家外所有成功候选的最高出价
    NSInteger secondPrice = 0;
    for (ADXBidResult *result in successResults) {
        if ([result.sourceId isEqualToString:winner.sourceId]) {
            continue;
        }
        if (result.price > secondPrice) {
            secondPrice = result.price;
        }
    }

    for (ADXBidResult *result in successResults) {
        id<ADXAdapter> adapter = adapters[result.sourceId];
        if (!adapter) {
            continue;
        }

        // Win/Loss 通知切主线程：竞败方 Adapter 可能执行 removeFromSuperview 等 UI 清理操作
        if ([result.sourceId isEqualToString:winner.sourceId]) {
            dispatch_async(dispatch_get_main_queue(), ^{
                [adapter notifyWinWithCostPrice:winner.price lossPrice:secondPrice];
            });
            ADXLogInfo(@"通知竞胜：%@（cost=%ld loss=%ld）",
                       result.sourceId, (long)winner.price, (long)secondPrice);
        } else {
            dispatch_async(dispatch_get_main_queue(), ^{
                [adapter notifyLossWithWinPrice:winner.price
                                  lossReason:ADXLossReasonLowPrice
                                 winnerAdnId:winner.sourceId];
            });
            ADXLogInfo(@"通知竞败：%@（win=%ld reason=LowPrice winner=%@）",
                       result.sourceId, (long)winner.price, winner.sourceId);
        }
    }
}

@end