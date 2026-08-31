//
//  ADXAdManager.m
//  AdWinX
//
//  Created by AdWinX on 2026/08/29.
//

#import "ADXAdManager.h"
#import "ADXSlotConfig.h"
#import "ADXAdSourceInfo.h"
#import "ADXBidResult.h"
#import "ADXAuctionResult.h"
#import "ADXAdapter.h"
#import "ADXAuctionEngine.h"
#import "ADXAdapterRegistry.h"
#import "ADXConfigManager.h"
#import "ADXConfig.h"
#import "ADXAdEvent.h"
#import "ADXAdEventDispatcher.h"
#import "ADXLogger.h"
#import <objc/message.h>

/// SDK 就绪等待超时：超时后不再等待未就绪的 ADN，按现状继续（冷启动不能被单个 ADN 卡死）
static NSTimeInterval const kADXSDKReadyTimeout = 2.5;

/// 预载条目：拍卖结果 + 展示所需的 Adapter 实例缓存
///
/// show 系列方法依赖 Adapter 实例内部持有的 ADN 广告对象（重新创建实例无法展示已加载的广告），
/// 因此预载持有时必须连同 adapters 一起存，take 时再恢复到展示缓存。
@interface ADXPreloadEntry : NSObject

@property (nonatomic, strong, nullable) ADXAuctionResult *result;
@property (nonatomic, strong, nullable) NSDictionary<NSString *, id<ADXAdapter>> *adapters;

@end

@implementation ADXPreloadEntry
@end

@interface ADXAdManager ()

@property (nonatomic, strong) ADXAuctionEngine *engine;
/// 缓存 loadSplashAdOnly 模式下的 Adapter 实例，供展示时复用
/// key: sourceId, value: Adapter 实例
@property (nonatomic, strong, nullable) NSDictionary<NSString *, id<ADXAdapter>> *cachedAdapters;
/// 缓存 loadRewardVideoAd 模式下的 Adapter 实例，供展示时复用（与开屏分键，避免多 slot 冲突）
/// key: sourceId, value: Adapter 实例
@property (nonatomic, strong, nullable) NSDictionary<NSString *, id<ADXAdapter>> *cachedRewardAdapters;
/// 缓存 loadNativeAd 模式下的 Adapter 实例，供渲染时复用（与开屏/激励分键，避免多 slot 冲突）
/// key: sourceId, value: Adapter 实例
@property (nonatomic, strong, nullable) NSDictionary<NSString *, id<ADXAdapter>> *cachedNativeAdapters;
/// 缓存 loadInterstitialAd 模式下的 Adapter 实例，供展示时复用（与其他类型分键，避免多 slot 冲突）
/// key: sourceId, value: Adapter 实例
@property (nonatomic, strong, nullable) NSDictionary<NSString *, id<ADXAdapter>> *cachedInterstitialAdapters;

/// 展示事件上报用的 slotName（load 系列方法入口记录；多形态并存时记录最后一次 load 的 slot）
@property (nonatomic, copy, nullable) NSString *currentEventSlotName;
/// 展示事件上报用的赢家 sourceId（拍卖结算后记录，降级判断用）
@property (nonatomic, copy, nullable) NSString *currentEventWinnerSourceId;

/// 激励视频预载缓存（key: slotName，取走即清）
@property (nonatomic, strong) NSMutableDictionary<NSString *, ADXPreloadEntry *> *rewardPreloads;
/// 插屏预载缓存（key: slotName，取走即清）
@property (nonatomic, strong) NSMutableDictionary<NSString *, ADXPreloadEntry *> *interstitialPreloads;
/// 预载进行中的 slot（防重复发起；slotName 全局唯一，激励/插屏共用一个集合即可）
@property (nonatomic, strong) NSMutableSet<NSString *> *preloadingSlots;

@end

@implementation ADXAdManager

+ (instancetype)sharedManager
{
    static ADXAdManager *instance = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        instance = [[ADXAdManager alloc] init];
    });
    return instance;
}

- (instancetype)init
{
    self = [super init];
    if (self) {
        _engine = [[ADXAuctionEngine alloc] init];
        _rewardPreloads = [NSMutableDictionary dictionary];
        _interstitialPreloads = [NSMutableDictionary dictionary];
        _preloadingSlots = [NSMutableSet set];
    }
    return self;
}

- (void)registerAdapterClass:(Class)adapterClass forAdnName:(NSString *)adnName
{
    [ADXAdapterRegistry registerAdapterClass:adapterClass forAdnName:adnName];
}

- (void)setAdEventHandler:(ADXAdEventObserver)handler
{
    [ADXAdEventDispatcher setEventHandler:handler];
}

- (void)registerAdapterClass:(Class)adapterClass forAdnName:(NSString *)adnName adType:(ADXAdType)adType
{
    [ADXAdapterRegistry registerAdapterClass:adapterClass forAdnName:adnName adType:adType];
}

/// 自动发现注册已安装的 Adapter
///
/// 按约定类名（ADX{ADN}{Type}Adapter）运行时探测：已安装的 adapter pod 中类存在即注册，
/// 未安装的 subspec 中类不参与链接、NSClassFromString 返回 nil 自然跳过。
/// 已手动注册过的（ADN + 广告类型）组合不覆盖，手动注册优先。
/// 新增 ADN 时只需在此追加 adnName，并保持 adapter 类名遵守上述约定。
- (void)autoRegisterInstalledAdapters
{
    // 支持的 ADN 标识（与配置 JSON 内 adnName 一致）
    NSArray<NSString *> *adnNames = @[@"GDT", @"CSJ", @"Sigmob", @"Baidu"];
    // 广告类型 → Adapter 类名后缀（Banner 暂无 Adapter，不参与探测）
    NSDictionary<NSNumber *, NSString *> *typeSuffixes = @{
        @(ADXAdTypeSplash): @"Splash",
        @(ADXAdTypeRewardVideo): @"RewardVideo",
        @(ADXAdTypeInterstitial): @"Interstitial",
        @(ADXAdTypeNativeExpress): @"NativeExpress",
    };

    for (NSString *adnName in adnNames) {
        [typeSuffixes enumerateKeysAndObjectsUsingBlock:^(NSNumber *type, NSString *suffix, BOOL *stop) {
            ADXAdType adType = type.integerValue;
            // 已手动注册的组合不覆盖
            if ([ADXAdapterRegistry hasRegisteredAdapterForAdnName:adnName adType:adType]) {
                return;
            }
            NSString *className = [NSString stringWithFormat:@"ADX%@%@Adapter", adnName, suffix];
            Class adapterClass = NSClassFromString(className);
            if (adapterClass) {
                [ADXAdapterRegistry registerAdapterClass:adapterClass forAdnName:adnName adType:adType];
                ADXLogInfo(@"自动注册 Adapter：%@（%@）", adnName, className);
            }
        }];
    }
}

- (void)setupSDKWithAdnConfigs:(NSDictionary<NSString *, NSDictionary *> *)adnConfigs
{
    [self setupSDKWithAdnConfigs:adnConfigs completion:NULL];
}

- (void)setupSDKWithAdnConfigs:(NSDictionary<NSString *, NSDictionary *> *)adnConfigs
                    completion:(void (^)(BOOL timedOut))completion
{
    // 自动发现注册：按已安装的 Adapter pod 探测注册（未安装的 subspec 类不存在，自然跳过）。
    // 之后接入方仅需引 pod + 配置 JSON，无需手动 register；手动注册过的组合不覆盖。
    [self autoRegisterInstalledAdapters];

    NSDictionary<NSString *, Class> *adapterClasses = [ADXAdapterRegistry allRegisteredAdapterClasses];
    if (adapterClasses.count == 0) {
        if (completion) {
            completion(NO);
        }
        return;
    }

    // 后台异步拉取远程配置：不阻塞初始化与广告链路，成功后下次请求生效
    //（remoteConfigURL 未配置时内部直接跳过，零开销）
    [[ADXConfigManager sharedManager] fetchRemoteConfigWithCompletion:nil];

    // 就绪计数：所有 ADN 的初始化回调（成功/失败均计）到齐后触发 completion；
    // 同步初始化的 Adapter（如 Sigmob）会在调用栈内直接回调，先加计数再调用防止提前触发
    __block NSUInteger pendingCount = adapterClasses.count;
    __block BOOL finished = NO;
    NSMutableSet<NSString *> *pendingAdns = [NSMutableSet setWithArray:adapterClasses.allKeys];

    void (^finish)(BOOL) = ^(BOOL timedOut) {
        dispatch_async(dispatch_get_main_queue(), ^{
            if (finished) {
                return;
            }
            finished = YES;
            if (timedOut) {
                ADXLogInfo(@"SDK 就绪等待超时（%.1fs），未就绪：%@，按现状继续", kADXSDKReadyTimeout, [pendingAdns allObjects]);
            } else {
                ADXLogInfo(@"所有 ADN SDK 就绪（%lu 个）", (unsigned long)adapterClasses.count);
            }
            if (completion) {
                completion(timedOut);
            }
        });
    };

    // 超时兜底：个别 ADN 初始化卡死（如断网时服务注册无回调）也不能拖住冷启动
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(kADXSDKReadyTimeout * NSEC_PER_SEC)),
                   dispatch_get_main_queue(), ^{
        if (pendingCount > 0) {
            finish(YES);
        }
    });

    [adapterClasses enumerateKeysAndObjectsUsingBlock:^(NSString *adnName, Class adapterClass, BOOL *stop) {
        SEL readySelector = NSSelectorFromString(@"setupSDKWithConfig:completion:");
        if ([adapterClass respondsToSelector:readySelector]) {
            void (^onReady)(BOOL) = ^(BOOL success) {
                dispatch_async(dispatch_get_main_queue(), ^{
                    [pendingAdns removeObject:adnName];
                    if (pendingCount > 0) {
                        pendingCount -= 1;
                    }
                    if (pendingCount == 0) {
                        finish(NO);
                    }
                });
            };

            ((void (*)(id, SEL, NSDictionary *, void (^)(BOOL)))objc_msgSend)
                (adapterClass, readySelector, adnConfigs[adnName], onReady);
        } else if ([adapterClass respondsToSelector:@selector(setupSDKWithConfig:)]) {
            // 兼容旧 Adapter（未实现就绪回调版本）：无法感知就绪，立即视为就绪
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Warc-performSelector-leaks"
            [adapterClass performSelector:@selector(setupSDKWithConfig:)
                               withObject:adnConfigs[adnName]];
#pragma clang diagnostic pop
            dispatch_async(dispatch_get_main_queue(), ^{
                [pendingAdns removeObject:adnName];
                if (pendingCount > 0) {
                    pendingCount -= 1;
                }
                if (pendingCount == 0) {
                    finish(NO);
                }
            });
        } else {
            // 未实现任何初始化方法：直接视为就绪
            dispatch_async(dispatch_get_main_queue(), ^{
                [pendingAdns removeObject:adnName];
                if (pendingCount > 0) {
                    pendingCount -= 1;
                }
                if (pendingCount == 0) {
                    finish(NO);
                }
            });
        }
    }];
}

- (void)loadSplashAdWithConfig:(ADXSlotConfig *)config
                        window:(UIWindow *)window
                    completion:(ADXAdLoadCompletion)completion
{
    // 分发应用级 ADN 配置（appId 等）到各广告源：源级 appId 缺失时用应用级兜底
    [self fillAppIdsForConfig:config];

    // 为本次拍卖的所有广告源创建 Adapter 实例
    NSMutableDictionary<NSString *, id<ADXAdapter>> *adapters = [NSMutableDictionary dictionary];
    for (ADXAdSourceInfo *source in config.adSources) {
        id<ADXAdapter> adapter = [ADXAdapterRegistry adapterForSourceInfo:source];
        if (adapter) {
            adapters[source.sourceId] = adapter;
        }
    }

    [self.engine runAuctionWithConfig:config
                              adapters:adapters
                            completion:^(ADXAuctionResult *result) {
        // 展示赢家广告（引擎已完成 Win/Loss 结算通知）
        ADXBidResult *winner = result.winnerResult;
        if (winner) {
            id<ADXAdapter> adapter = adapters[winner.sourceId];
            if (adapter && [adapter respondsToSelector:@selector(showSplashAdWithResult:window:completion:)]) {
                ADXLogInfo(@"展示开屏：%@", winner.sourceId);
                [adapter showSplashAdWithResult:winner window:window completion:NULL];
            }
        }

        if (completion) {
            completion(result);
        }
    }];
}

- (void)loadSplashAdOnlyWithSlotName:(NSString *)slotName
                          completion:(ADXAdLoadCompletion)completion
{
    ADXSlotConfig *config = [[ADXConfigManager sharedManager] slotConfigWithName:slotName];
    if (!config) {
        ADXLogError(@"广告位不存在：%@（当前配置无此 slotName）", slotName);
        if (completion) {
            completion(nil);
        }
        return;
    }

    // 分发应用级 ADN 配置
    [self fillAppIdsForConfig:config];

    // 为本次拍卖的所有广告源创建 Adapter 实例
    NSMutableDictionary<NSString *, id<ADXAdapter>> *adapters = [NSMutableDictionary dictionary];
    for (ADXAdSourceInfo *source in config.adSources) {
        id<ADXAdapter> adapter = [ADXAdapterRegistry adapterForSourceInfo:source];
        if (adapter) {
            adapters[source.sourceId] = adapter;
        }
    }

    // 仅加载，不展示。展示由业务通过 showSplashAdWithResult:window: 控制。
    // Adapter 实例需缓存：showSplashAdWithResult 依赖实例内部持有的 ADN 广告对象（如 splashAd），
    // 重新创建实例无法展示已加载的广告。
    [self.engine runAuctionWithConfig:config
                              adapters:adapters
                            completion:^(ADXAuctionResult *result) {
        self.cachedAdapters = adapters;
        [self recordEventContextWithSlotName:slotName winnerResult:result.winnerResult];
        if (completion) {
            completion(result);
        }
    }];
}

- (void)showSplashAdWithResult:(ADXAuctionResult *)result
                        window:(UIWindow *)window
                    completion:(nullable void (^)(BOOL shown, NSString * _Nullable shownSourceId))completion
{
    if (!result || !self.cachedAdapters || self.cachedAdapters.count == 0) {
        if (completion) {
            completion(NO, nil);
        }
        return;
    }

    // 降级候选：所有成功候选按价格降序（赢家即价格最高者，天然排第一）。
    // 次高价候选此前已收到引擎的 notifyLoss，部分 Adapter（如 Sigmob/百度）已释放广告对象，
    // 其展示预检会直接失败并跳过，链式尝试自然兼容。
    NSMutableArray<ADXBidResult *> *candidates = [NSMutableArray array];
    for (ADXBidResult *candidate in result.allCandidates) {
        if (candidate.success && candidate.price > 0) {
            [candidates addObject:candidate];
        }
    }
    [candidates sortUsingComparator:^NSComparisonResult(ADXBidResult *a, ADXBidResult *b) {
        if (a.price == b.price) {
            return NSOrderedSame;
        }
        return a.price > b.price ? NSOrderedAscending : NSOrderedDescending;
    }];

    if (candidates.count == 0) {
        if (completion) {
            completion(NO, nil);
        }
        return;
    }

    __weak typeof(self) weakSelf = self;
    void (^tryCandidateAtIndex)(NSUInteger) = nil;
    tryCandidateAtIndex = ^(NSUInteger index) {
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (!strongSelf) {
            return;
        }

        if (index >= candidates.count) {
            ADXLogInfo(@"所有候选展示失败，无可降级广告");
            strongSelf.cachedAdapters = nil;
            if (completion) {
                completion(NO, nil);
            }
            return;
        }

        ADXBidResult *candidate = candidates[index];
        id<ADXAdapter> adapter = strongSelf.cachedAdapters[candidate.sourceId];
        if (!adapter) {
            // 无 Adapter 实例（理论上不会发生），跳过尝试下一个
            tryCandidateAtIndex(index + 1);
            return;
        }

        ADXLogInfo(@"展示开屏：%@", candidate.sourceId);
        [adapter showSplashAdWithResult:candidate
                                 window:window
                             completion:^(BOOL success, NSError * _Nullable error) {
            [self emitShowEventWithSourceId:candidate.sourceId
                                      adType:ADXAdTypeSplash
                                     success:success
                                       error:error
                              winnerSourceId:self.currentEventWinnerSourceId];
            if (success) {
                strongSelf.cachedAdapters = nil;
                if (completion) {
                    completion(YES, candidate.sourceId);
                }
                return;
            }

            ADXLogInfo(@"%@ 展示失败（%@），降级尝试下一候选", candidate.sourceId,
                       error.localizedDescription ?: @"未知原因");
            tryCandidateAtIndex(index + 1);
        }];
    };

    tryCandidateAtIndex(0);
}

- (void)showSplashAdWithResult:(ADXAuctionResult *)result
                        window:(UIWindow *)window
{
    [self showSplashAdWithResult:result window:window completion:NULL];
}

- (void)loadRewardVideoAdWithSlotName:(NSString *)slotName
                            completion:(ADXAdLoadCompletion)completion
{
    [self auctionRewardVideoWithSlotName:slotName
                          auctionComplete:^(ADXAuctionResult *result, NSDictionary<NSString *, id<ADXAdapter>> *adapters) {
        // 仅加载，不展示。展示由业务通过 showRewardVideoAdWithResult: 控制。
        // Adapter 实例需缓存：show 依赖实例内部持有的 ADN 广告对象，重新创建实例无法展示已加载的广告。
        self.cachedRewardAdapters = adapters;
        if (completion) {
            completion(result);
        }
    }];
}

/// 激励视频统一加载入口：跑完整拍卖（竞价 + 瀑布 + 结算），完成后把 result 与 adapters
/// 交给调用方决定去向（直接 load 存展示缓存，preload 存预载缓存）
- (void)auctionRewardVideoWithSlotName:(NSString *)slotName
                        auctionComplete:(void (^)(ADXAuctionResult *result,
                                                  NSDictionary<NSString *, id<ADXAdapter>> *adapters))block
{
    ADXSlotConfig *config = [[ADXConfigManager sharedManager] slotConfigWithName:slotName];
    if (!config) {
        ADXLogError(@"广告位不存在：%@（当前配置无此 slotName）", slotName);
        if (block) {
            block(nil, nil);
        }
        return;
    }

    // 分发应用级 ADN 配置
    [self fillAppIdsForConfig:config];

    // 为本次拍卖的所有广告源创建 Adapter 实例（按 adnName + adType 复合键取激励视频 Adapter）
    NSMutableDictionary<NSString *, id<ADXAdapter>> *adapters = [NSMutableDictionary dictionary];
    for (ADXAdSourceInfo *source in config.adSources) {
        id<ADXAdapter> adapter = [ADXAdapterRegistry adapterForSourceInfo:source];
        if (adapter) {
            adapters[source.sourceId] = adapter;
        }
    }

    [self.engine runAuctionWithConfig:config
                              adapters:adapters
                            completion:^(ADXAuctionResult *result) {
        [self recordEventContextWithSlotName:slotName winnerResult:result.winnerResult];
        if (block) {
            block(result, adapters);
        }
    }];
}

- (void)showRewardVideoAdWithResult:(ADXAuctionResult *)result
                  fromViewController:(UIViewController *)rootViewController
                       rewardCallback:(nullable void (^)(BOOL granted))rewardCallback
                           completion:(nullable void (^)(BOOL shown, NSString * _Nullable shownSourceId))completion
{
    if (!result || !self.cachedRewardAdapters || self.cachedRewardAdapters.count == 0) {
        if (completion) {
            completion(NO, nil);
        }
        return;
    }

    // 降级候选：所有成功候选按价格降序（赢家即价格最高者，天然排第一）。
    // 次高价候选此前已收到引擎的 notifyLoss，部分 Adapter 已释放广告对象，
    // 其展示预检会直接失败并跳过，链式尝试自然兼容。
    NSMutableArray<ADXBidResult *> *candidates = [NSMutableArray array];
    for (ADXBidResult *candidate in result.allCandidates) {
        if (candidate.success && candidate.price > 0) {
            [candidates addObject:candidate];
        }
    }
    [candidates sortUsingComparator:^NSComparisonResult(ADXBidResult *a, ADXBidResult *b) {
        if (a.price == b.price) {
            return NSOrderedSame;
        }
        return a.price > b.price ? NSOrderedAscending : NSOrderedDescending;
    }];

    if (candidates.count == 0) {
        if (completion) {
            completion(NO, nil);
        }
        return;
    }

    __weak typeof(self) weakSelf = self;
    void (^tryCandidateAtIndex)(NSUInteger) = nil;
    tryCandidateAtIndex = ^(NSUInteger index) {
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (!strongSelf) {
            return;
        }

        if (index >= candidates.count) {
            ADXLogInfo(@"所有候选展示失败，无可降级广告");
            strongSelf.cachedRewardAdapters = nil;
            if (completion) {
                completion(NO, nil);
            }
            return;
        }

        ADXBidResult *candidate = candidates[index];
        id<ADXAdapter> adapter = strongSelf.cachedRewardAdapters[candidate.sourceId];
        if (!adapter || ![adapter respondsToSelector:@selector(showRewardVideoAdWithResult:fromViewController:rewardCallback:completion:)]) {
            // 无 Adapter 实例或未实现激励视频展示方法，跳过尝试下一个
            tryCandidateAtIndex(index + 1);
            return;
        }

        ADXLogInfo(@"展示激励视频：%@", candidate.sourceId);
        [adapter showRewardVideoAdWithResult:candidate
                          fromViewController:rootViewController
                               rewardCallback:rewardCallback
                                   completion:^(BOOL success, NSError * _Nullable error) {
            [self emitShowEventWithSourceId:candidate.sourceId
                                      adType:ADXAdTypeRewardVideo
                                     success:success
                                       error:error
                              winnerSourceId:self.currentEventWinnerSourceId];
            if (success) {
                strongSelf.cachedRewardAdapters = nil;
                if (completion) {
                    completion(YES, candidate.sourceId);
                }
                return;
            }

            ADXLogInfo(@"%@ 展示失败（%@），降级尝试下一候选", candidate.sourceId,
                       error.localizedDescription ?: @"未知原因");
            tryCandidateAtIndex(index + 1);
        }];
    };

    tryCandidateAtIndex(0);
}

- (void)loadNativeAdWithSlotName:(NSString *)slotName
                         adWidth:(CGFloat)adWidth
                       completion:(ADXAdLoadCompletion)completion
{
    ADXSlotConfig *config = [[ADXConfigManager sharedManager] slotConfigWithName:slotName];
    if (!config) {
        ADXLogError(@"广告位不存在：%@（当前配置无此 slotName）", slotName);
        if (completion) {
            completion(nil);
        }
        return;
    }

    // 分发应用级 ADN 配置
    [self fillAppIdsForConfig:config];

    // 分发信息流期望宽度到各广告源（渲染取宽/请求尺寸共用）
    if (adWidth > 0) {
        for (ADXAdSourceInfo *source in config.adSources) {
            source.adWidth = adWidth;
        }
    }

    // 为本次拍卖的所有广告源创建 Adapter 实例（按 adnName + adType 复合键取信息流 Adapter）
    NSMutableDictionary<NSString *, id<ADXAdapter>> *adapters = [NSMutableDictionary dictionary];
    for (ADXAdSourceInfo *source in config.adSources) {
        id<ADXAdapter> adapter = [ADXAdapterRegistry adapterForSourceInfo:source];
        if (adapter) {
            adapters[source.sourceId] = adapter;
        }
    }

    // 仅加载，不渲染。渲染由业务通过 renderNativeAdViewWithResult: 控制。
    // Adapter 实例需缓存：render 依赖实例内部持有的 ADN 广告视图，重新创建实例无法渲染已加载的广告。
    [self.engine runAuctionWithConfig:config
                              adapters:adapters
                            completion:^(ADXAuctionResult *result) {
        self.cachedNativeAdapters = adapters;
        [self recordEventContextWithSlotName:slotName winnerResult:result.winnerResult];
        if (completion) {
            completion(result);
        }
    }];
}

- (void)renderNativeAdViewWithResult:(ADXAuctionResult *)result
                    rootViewController:(UIViewController *)rootViewController
                          completion:(nullable void (^)(UIView * _Nullable adView, NSString * _Nullable shownSourceId))completion
{
    if (!result || !self.cachedNativeAdapters || self.cachedNativeAdapters.count == 0) {
        if (completion) {
            completion(nil, nil);
        }
        return;
    }

    // 降级候选：所有成功候选按价格降序（赢家即价格最高者，天然排第一）。
    // 次高价候选此前已收到引擎的 notifyLoss，部分 Adapter 已释放广告视图，
    // 其渲染预检会直接失败并跳过，链式尝试自然兼容。
    NSMutableArray<ADXBidResult *> *candidates = [NSMutableArray array];
    for (ADXBidResult *candidate in result.allCandidates) {
        if (candidate.success && candidate.price > 0) {
            [candidates addObject:candidate];
        }
    }
    [candidates sortUsingComparator:^NSComparisonResult(ADXBidResult *a, ADXBidResult *b) {
        if (a.price == b.price) {
            return NSOrderedSame;
        }
        return a.price > b.price ? NSOrderedAscending : NSOrderedDescending;
    }];

    if (candidates.count == 0) {
        if (completion) {
            completion(nil, nil);
        }
        return;
    }

    __weak typeof(self) weakSelf = self;
    void (^tryCandidateAtIndex)(NSUInteger) = nil;
    tryCandidateAtIndex = ^(NSUInteger index) {
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (!strongSelf) {
            return;
        }

        if (index >= candidates.count) {
            ADXLogInfo(@"所有候选渲染失败，无可降级广告");
            strongSelf.cachedNativeAdapters = nil;
            if (completion) {
                completion(nil, nil);
            }
            return;
        }

        ADXBidResult *candidate = candidates[index];
        id<ADXAdapter> adapter = strongSelf.cachedNativeAdapters[candidate.sourceId];
        if (!adapter || ![adapter respondsToSelector:@selector(renderNativeAdViewWithResult:rootViewController:completion:)]) {
            // 无 Adapter 实例或未实现信息流渲染方法，跳过尝试下一个
            tryCandidateAtIndex(index + 1);
            return;
        }

        ADXLogInfo(@"渲染信息流：%@", candidate.sourceId);
        [adapter renderNativeAdViewWithResult:candidate
                             rootViewController:rootViewController
                                 completion:^(UIView * _Nullable adView, NSError * _Nullable error) {
            [self emitShowEventWithSourceId:candidate.sourceId
                                      adType:ADXAdTypeNativeExpress
                                     success:adView != nil
                                       error:error
                              winnerSourceId:self.currentEventWinnerSourceId];
            if (adView) {
                strongSelf.cachedNativeAdapters = nil;
                if (completion) {
                    completion(adView, candidate.sourceId);
                }
                return;
            }

            ADXLogInfo(@"%@ 渲染失败（%@），降级尝试下一候选", candidate.sourceId,
                       error.localizedDescription ?: @"未知原因");
            tryCandidateAtIndex(index + 1);
        }];
    };

    tryCandidateAtIndex(0);
}

- (void)loadInterstitialAdWithSlotName:(NSString *)slotName
                             completion:(ADXAdLoadCompletion)completion
{
    [self auctionInterstitialWithSlotName:slotName
                           auctionComplete:^(ADXAuctionResult *result, NSDictionary<NSString *, id<ADXAdapter>> *adapters) {
        // 仅加载，不展示。展示由业务通过 showInterstitialAdWithResult: 控制。
        // Adapter 实例需缓存：show 依赖实例内部持有的 ADN 广告对象，重新创建实例无法展示已加载的广告。
        self.cachedInterstitialAdapters = adapters;
        if (completion) {
            completion(result);
        }
    }];
}

/// 插屏统一加载入口：跑完整拍卖（竞价 + 瀑布 + 结算），完成后把 result 与 adapters
/// 交给调用方决定去向（直接 load 存展示缓存，preload 存预载缓存）
- (void)auctionInterstitialWithSlotName:(NSString *)slotName
                         auctionComplete:(void (^)(ADXAuctionResult *result,
                                                   NSDictionary<NSString *, id<ADXAdapter>> *adapters))block
{
    ADXSlotConfig *config = [[ADXConfigManager sharedManager] slotConfigWithName:slotName];
    if (!config) {
        ADXLogError(@"广告位不存在：%@（当前配置无此 slotName）", slotName);
        if (block) {
            block(nil, nil);
        }
        return;
    }

    // 分发应用级 ADN 配置
    [self fillAppIdsForConfig:config];

    // 为本次拍卖的所有广告源创建 Adapter 实例（按 adnName + adType 复合键取插屏 Adapter）
    NSMutableDictionary<NSString *, id<ADXAdapter>> *adapters = [NSMutableDictionary dictionary];
    for (ADXAdSourceInfo *source in config.adSources) {
        id<ADXAdapter> adapter = [ADXAdapterRegistry adapterForSourceInfo:source];
        if (adapter) {
            adapters[source.sourceId] = adapter;
        }
    }

    [self.engine runAuctionWithConfig:config
                              adapters:adapters
                            completion:^(ADXAuctionResult *result) {
        [self recordEventContextWithSlotName:slotName winnerResult:result.winnerResult];
        if (block) {
            block(result, adapters);
        }
    }];
}

- (void)showInterstitialAdWithResult:(ADXAuctionResult *)result
                   fromViewController:(UIViewController *)rootViewController
                          completion:(nullable void (^)(BOOL shown, NSString * _Nullable shownSourceId))completion
{
    if (!result || !self.cachedInterstitialAdapters || self.cachedInterstitialAdapters.count == 0) {
        if (completion) {
            completion(NO, nil);
        }
        return;
    }

    // 降级候选：所有成功候选按价格降序（赢家即价格最高者，天然排第一）。
    // 次高价候选此前已收到引擎的 notifyLoss，部分 Adapter 已释放广告对象，
    // 其展示预检会直接失败并跳过，链式尝试自然兼容。
    NSMutableArray<ADXBidResult *> *candidates = [NSMutableArray array];
    for (ADXBidResult *candidate in result.allCandidates) {
        if (candidate.success && candidate.price > 0) {
            [candidates addObject:candidate];
        }
    }
    [candidates sortUsingComparator:^NSComparisonResult(ADXBidResult *a, ADXBidResult *b) {
        if (a.price == b.price) {
            return NSOrderedSame;
        }
        return a.price > b.price ? NSOrderedAscending : NSOrderedDescending;
    }];

    if (candidates.count == 0) {
        if (completion) {
            completion(NO, nil);
        }
        return;
    }

    __weak typeof(self) weakSelf = self;
    void (^tryCandidateAtIndex)(NSUInteger) = nil;
    tryCandidateAtIndex = ^(NSUInteger index) {
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (!strongSelf) {
            return;
        }

        if (index >= candidates.count) {
            ADXLogInfo(@"所有候选展示失败，无可降级广告");
            strongSelf.cachedInterstitialAdapters = nil;
            if (completion) {
                completion(NO, nil);
            }
            return;
        }

        ADXBidResult *candidate = candidates[index];
        id<ADXAdapter> adapter = strongSelf.cachedInterstitialAdapters[candidate.sourceId];
        if (!adapter || ![adapter respondsToSelector:@selector(showInterstitialAdWithResult:fromViewController:completion:)]) {
            // 无 Adapter 实例或未实现插屏展示方法，跳过尝试下一个
            tryCandidateAtIndex(index + 1);
            return;
        }

        ADXLogInfo(@"展示插屏：%@", candidate.sourceId);
        [adapter showInterstitialAdWithResult:candidate
                           fromViewController:rootViewController
                                 completion:^(BOOL success, NSError * _Nullable error) {
            [self emitShowEventWithSourceId:candidate.sourceId
                                      adType:ADXAdTypeInterstitial
                                     success:success
                                       error:error
                              winnerSourceId:self.currentEventWinnerSourceId];
            if (success) {
                strongSelf.cachedInterstitialAdapters = nil;
                if (completion) {
                    completion(YES, candidate.sourceId);
                }
                return;
            }

            ADXLogInfo(@"%@ 展示失败（%@），降级尝试下一候选", candidate.sourceId,
                       error.localizedDescription ?: @"未知原因");
            tryCandidateAtIndex(index + 1);
        }];
    };

    tryCandidateAtIndex(0);
}

- (void)loadSplashAdWithSlotName:(NSString *)slotName
                          window:(UIWindow *)window
                      completion:(ADXAdLoadCompletion)completion
{
    ADXSlotConfig *config = [[ADXConfigManager sharedManager] slotConfigWithName:slotName];
    if (!config) {
        ADXLogError(@"广告位不存在：%@（当前配置无此 slotName）", slotName);
        if (completion) {
            completion(nil);
        }
        return;
    }

    [self loadSplashAdWithConfig:config window:window completion:completion];
}

#pragma mark - 预加载（激励视频 / 插屏）

- (void)preloadRewardVideoAdWithSlotName:(NSString *)slotName
                              completion:(nullable ADXAdLoadCompletion)completion
{
    if (slotName.length == 0) {
        if (completion) {
            completion(nil);
        }
        return;
    }

    // 已有未取走的预载：跳过请求，直接回调已有结果（「确保有预载」语义，重复调用无损耗）
    ADXPreloadEntry *existing = self.rewardPreloads[slotName];
    if (existing) {
        ADXLogInfo(@"激励视频预载已存在，跳过请求：%@（winner=%@）", slotName, existing.result.winnerResult.sourceId);
        if (completion) {
            completion(existing.result);
        }
        return;
    }

    // 预载进行中：跳过，避免同一短窗口内重复发起整场拍卖
    if ([self.preloadingSlots containsObject:slotName]) {
        ADXLogInfo(@"激励视频预载进行中，跳过重复请求：%@", slotName);
        if (completion) {
            completion(nil);
        }
        return;
    }

    [self.preloadingSlots addObject:slotName];
    ADXLogInfo(@"激励视频预载开始：%@", slotName);
    __weak typeof(self) weakSelf = self;
    [self auctionRewardVideoWithSlotName:slotName
                          auctionComplete:^(ADXAuctionResult *result, NSDictionary<NSString *, id<ADXAdapter>> *adapters) {
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (!strongSelf) {
            return;
        }
        [strongSelf.preloadingSlots removeObject:slotName];

        // 无可用广告不持有：take 返回 nil，业务走现场 load 兜底
        if (result && result.winnerResult) {
            ADXPreloadEntry *entry = [[ADXPreloadEntry alloc] init];
            entry.result = result;
            entry.adapters = adapters;
            strongSelf.rewardPreloads[slotName] = entry;
            ADXLogInfo(@"激励视频预载成功：%@（winner=%@，price=%ld 分）",
                       slotName, result.winnerResult.sourceId, (long)result.winnerResult.price);
        } else {
            ADXLogInfo(@"激励视频预载无可用广告：%@", slotName);
        }

        if (completion) {
            completion(result);
        }
    }];
}

- (nullable ADXAuctionResult *)takeRewardVideoAdWithSlotName:(NSString *)slotName
{
    ADXPreloadEntry *entry = slotName.length > 0 ? self.rewardPreloads[slotName] : nil;
    if (!entry) {
        return nil;
    }
    [self.rewardPreloads removeObjectForKey:slotName];

    // 恢复展示所需的 Adapter 实例（showRewardVideoAdWithResult: 依赖 cachedRewardAdapters）
    self.cachedRewardAdapters = entry.adapters;
    // 预载与展示之间可能隔着其他位的 load，重记事件归因上下文，展示事件以本位为准
    [self recordEventContextWithSlotName:slotName winnerResult:entry.result.winnerResult];
    return entry.result;
}

- (void)preloadInterstitialAdWithSlotName:(NSString *)slotName
                               completion:(nullable ADXAdLoadCompletion)completion
{
    if (slotName.length == 0) {
        if (completion) {
            completion(nil);
        }
        return;
    }

    ADXPreloadEntry *existing = self.interstitialPreloads[slotName];
    if (existing) {
        ADXLogInfo(@"插屏预载已存在，跳过请求：%@（winner=%@）", slotName, existing.result.winnerResult.sourceId);
        if (completion) {
            completion(existing.result);
        }
        return;
    }

    if ([self.preloadingSlots containsObject:slotName]) {
        ADXLogInfo(@"插屏预载进行中，跳过重复请求：%@", slotName);
        if (completion) {
            completion(nil);
        }
        return;
    }

    [self.preloadingSlots addObject:slotName];
    ADXLogInfo(@"插屏预载开始：%@", slotName);
    __weak typeof(self) weakSelf = self;
    [self auctionInterstitialWithSlotName:slotName
                           auctionComplete:^(ADXAuctionResult *result, NSDictionary<NSString *, id<ADXAdapter>> *adapters) {
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (!strongSelf) {
            return;
        }
        [strongSelf.preloadingSlots removeObject:slotName];

        if (result && result.winnerResult) {
            ADXPreloadEntry *entry = [[ADXPreloadEntry alloc] init];
            entry.result = result;
            entry.adapters = adapters;
            strongSelf.interstitialPreloads[slotName] = entry;
            ADXLogInfo(@"插屏预载成功：%@（winner=%@，price=%ld 分）",
                       slotName, result.winnerResult.sourceId, (long)result.winnerResult.price);
        } else {
            ADXLogInfo(@"插屏预载无可用广告：%@", slotName);
        }

        if (completion) {
            completion(result);
        }
    }];
}

- (nullable ADXAuctionResult *)takeInterstitialAdWithSlotName:(NSString *)slotName
{
    ADXPreloadEntry *entry = slotName.length > 0 ? self.interstitialPreloads[slotName] : nil;
    if (!entry) {
        return nil;
    }
    [self.interstitialPreloads removeObjectForKey:slotName];

    // 恢复展示所需的 Adapter 实例（showInterstitialAdWithResult: 依赖 cachedInterstitialAdapters）
    self.cachedInterstitialAdapters = entry.adapters;
    // 重记事件归因上下文，展示事件以本位为准
    [self recordEventContextWithSlotName:slotName winnerResult:entry.result.winnerResult];
    return entry.result;
}

- (void)discardPreloadedAdWithSlotName:(NSString *)slotName
{
    if (slotName.length == 0) {
        return;
    }
    [self.rewardPreloads removeObjectForKey:slotName];
    [self.interstitialPreloads removeObjectForKey:slotName];
    ADXLogInfo(@"已丢弃预载结果：%@", slotName);
}

#pragma mark - Private

/// 展示结果事件发射（4 个降级链共用）
///
/// @param sourceId 实际尝试展示的源
/// @param adType 广告类型
/// @param success 展示成败
/// @param error 失败原因
/// @param winnerSourceId 拍卖赢家（降级判断：sourceId ≠ winnerSourceId 即降级发生）
- (void)emitShowEventWithSourceId:(NSString *)sourceId
                           adType:(ADXAdType)adType
                          success:(BOOL)success
                            error:(nullable NSError *)error
                   winnerSourceId:(NSString *)winnerSourceId
{
    [ADXAdEventDispatcher emitEventWithType:ADXAdEventTypeShowResult
                                   slotName:self.currentEventSlotName ?: @""
                                     adType:adType
                                   sourceId:sourceId
                                      price:0
                            priceIsRealtime:NO
                             waterfallLayer:0
                                    success:success
                                      error:error
                              winnerSourceId:winnerSourceId
                                totalDuration:0];
}

/// load 入口记录 slotName / 拍卖结算后记录赢家（展示事件上报用）
- (void)recordEventContextWithSlotName:(NSString *)slotName
                          winnerResult:(nullable ADXBidResult *)winner
{
    if (slotName.length > 0) {
        self.currentEventSlotName = slotName;
    }
    self.currentEventWinnerSourceId = winner.sourceId;
}

/// 源级 appId 缺失时，用应用级 adnApps 配置兜底
- (void)fillAppIdsForConfig:(ADXSlotConfig *)config
{
    NSDictionary<NSString *, NSDictionary *> *adnApps = [ADXConfigManager sharedManager].currentConfig.adnApps;
    if (adnApps.count == 0) {
        return;
    }

    for (ADXAdSourceInfo *source in config.adSources) {
        if (source.appId.length == 0) {
            NSString *appId = adnApps[source.adnName][@"appId"];
            if ([appId isKindOfClass:[NSString class]] && appId.length > 0) {
                source.appId = appId;
            }
        }
    }
}

@end