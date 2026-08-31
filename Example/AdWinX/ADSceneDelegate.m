//
//  ADSceneDelegate.m
//  AdWinX
//
//  Created by AdWinX on 08/30/2026.
//  Copyright (c) 2026 mumabinggan. All rights reserved.
//

#import "ADSceneDelegate.h"
#import "ADAdDemoConstants.h"
#import "ADSigmobGlobalAdManager.h"
#import <AdWinX/AdWinX.h>

static NSTimeInterval const kADFallbackSplashMaxWait = 6.0;   // 兜底图最长展示时间（略大于 totalTimeout 5s）
static NSTimeInterval const kADFallbackSplashMinDuration = 1.5; // 兜底图最短展示时间（避免闪烁）

/// 【验证专用】模拟「加载成功 → 展示间隔过长」导致广告过期（如 Sigmob 600180）：
/// 拍卖完成后延迟 N 秒才调 show，令广告对象过期，验证预检拦截 + 展示失败降级链。
/// 0 = 关闭（正常链路）；40 ≈ 仅 Sigmob 过期（GDT 有效期较长仍有效，可观察降级成功）；
/// 120 = 所有候选都过期（可观察全失败回调业务兜底）。验证完改回 0
static NSTimeInterval const kADXExpiryTestDelayShow = 0.0;

@interface ADSceneDelegate ()

@property (nonatomic, assign) BOOL didRequestSigmobLaunchSplash;
/// 冷启动兜底开屏容器（自家品牌图，等广告返回后替换或关闭）
@property (nonatomic, strong, nullable) UIView *fallbackSplashView;
@property (nonatomic, strong, nullable) NSDate *fallbackShowDate;
/// 广告展示流程进行中：兜底图保底移除定时器遇到此标记时让路，避免广告出现前兜底图先被撤走露出首页
@property (nonatomic, assign) BOOL adShowInProgress;

@end

@implementation ADSceneDelegate

- (void)scene:(UIScene *)scene willConnectToSession:(UISceneSession *)session options:(UISceneConnectionOptions *)connectionOptions
{
    // 场景生命周期下的冷启动锚点：window 在此才存在，与 didFinishLaunching 锚点配合可测量
    // 「进程入口 → 场景连接」的系统开销
    ADXLogInfo(@"scene willConnect（window 创建）");

    // 原 AppDelegate 的 storyboard 逻辑迁移：Main.storyboard 初始 VC 包一层 UINavigationController
    UIStoryboard *storyboard = [UIStoryboard storyboardWithName:@"Main" bundle:nil];
    UIViewController *rootViewController = [storyboard instantiateInitialViewController];
    NSAssert(rootViewController != nil, @"Main.storyboard 缺少 Initial ViewController");

    if (![rootViewController isKindOfClass:[UINavigationController class]]) {
        UINavigationController *navigationController = [[UINavigationController alloc] initWithRootViewController:rootViewController];
        rootViewController = navigationController;
    }

    UIWindowScene *windowScene = (UIWindowScene *)scene;
    self.window = [[UIWindow alloc] initWithWindowScene:windowScene];
    self.window.rootViewController = rootViewController;
    [self.window makeKeyAndVisible];

    // ===== AdWinX 聚合开屏（P0 验证链路）=====
    // 依赖 window（兜底图挂载、广告展示），故从 didFinishLaunching 迁移至此；
    // 时序仍在首帧前，与迁移前等效
    [self loadSplashAdWithAdWinX];
}

#pragma mark - UISceneLifecycleCallbacks

- (void)sceneDidBecomeActive:(UIScene *)scene
{
//    if (self.didRequestSigmobLaunchSplash) {
//        return;
//    }
//    self.didRequestSigmobLaunchSplash = YES;
//    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.8 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
//        [self showGlobalSigmobSplashAd];
//    });
}

- (void)sceneWillResignActive:(UIScene *)scene
{
}

- (void)sceneDidEnterBackground:(UIScene *)scene
{
}

- (void)sceneWillEnterForeground:(UIScene *)scene
{
}

#pragma mark - AdWinX 聚合开屏

/// AdWinX 聚合开屏：注册 Adapter → 初始化 SDK → 兜底图 + 仅加载 → 赢家替换展示
///
/// 冷启动策略：开屏广告对象无法跨进程缓存，预加载无效。故采用
/// 「自家品牌兜底图先秒出 + 后台发起拍卖」：广告有赢家则替换展示，
/// 无广告或超时则兜底图展示满最短时长后关闭进首页，绝不让用户干等白屏。
- (void)loadSplashAdWithAdWinX
{
    // 1. Adapter 无需手动注册：setupSDK 内部按已安装的 Adapter pod 自动发现注册
    //    （Podfile 引了 AdWinX-CSJ/GDT/Sigmob/Baidu，对应 Adapter 自动生效；
    //     只想接其中几家时，从 Podfile 删掉对应行 + 配置 JSON 移除对应广告源即可）

    // 2. 统一初始化所有已注册 ADN 的 SDK（appId 优先取配置体系，Adapter 内置默认值兜底）
    //    注意：各 ADN 的 SDK 初始化是异步的（如百度 startWithCompletionHandler 返回后仍在后台注册设备），
    //    就绪后回调再发起拍卖，替代原先「固定延迟 1s 猜初始化完成」的方案

    // 3. 先秒出自家品牌兜底图（不依赖任何网络/SDK，不等就绪，用户零白屏）
    [self showFallbackSplash];

    // 广告链路事件观察（4a 埋点验证）：转投日志即可观察完整漏斗事件流
    [[ADXAdManager sharedManager] setAdEventHandler:^(ADXAdEvent *event) {
        NSLog(@"[AdWinX][Event] type=%ld slot=%@ source=%@ price=%ld realtime=%d layer=%lu success=%d error=%@ winner=%@ duration=%.2fs",
              (long)event.type, event.slotName, event.sourceId, (long)event.price,
              event.priceIsRealtime, (unsigned long)event.waterfallLayer,
              event.success, event.error.localizedDescription, event.winnerSourceId,
              event.totalDuration);
    }];

    [[ADXAdManager sharedManager] setupSDKWithAdnConfigs:[ADXConfigManager sharedManager].currentConfig.adnApps
                                              completion:^(BOOL timedOut) {
        // 4. SDK 就绪（或超时兜底）即发起拍卖，仅加载不展示
        //    （配置：内存 → 磁盘缓存 → 内置兜底 JSON）
        __weak typeof(self) weakSelf = self;
        [[ADXAdManager sharedManager] loadSplashAdOnlyWithSlotName:@"splash_main"
                                                        completion:^(ADXAuctionResult *result) {
            __strong typeof(weakSelf) strongSelf = weakSelf;
            if (!strongSelf) {
                return;
            }

            if (!result) {
                NSLog(@"[AdWinX] 配置中无 splash_main 广告位");
                [strongSelf dismissFallbackSplash];
                return;
            }

            NSLog(@"[AdWinX] 拍卖完成：%@，耗时 %.2fs，候选数 %lu",
                  result.winReason,
                  result.totalDuration,
                  (unsigned long)result.allCandidates.count);

            if (result.winnerResult) {
                NSLog(@"[AdWinX] 拍卖赢家：%@（price=%ld 分），尝试展示（失败自动降级次高价候选）",
                      result.winnerResult.sourceId, (long)result.winnerResult.price);
                // 展示含失败降级：赢家失败 → 按价格降序换次高价候选 → 全失败回 NO

                void (^showAd)(void) = ^{
                    strongSelf.adShowInProgress = YES;
                    [[ADXAdManager sharedManager] showSplashAdWithResult:result
                                                                    window:strongSelf.window
                                                                completion:^(BOOL shown, NSString * _Nullable shownSourceId) {
                        strongSelf.adShowInProgress = NO;
                        if (shown) {
                            NSLog(@"[AdWinX] 展示成功：%@（%@）",
                                  shownSourceId,
                                  [shownSourceId isEqualToString:result.winnerResult.sourceId] ? @"原赢家" : @"降级候选");
                            // 等广告视图真正盖住兜底图后再撤（轮询视图层级，最多 1.5s）：
                            // 曝光回调可能早于广告首帧渲染完成，提前撤会露出首页一瞬（闪烁）
                            [strongSelf removeFallbackSplashAfterAdCoveredWithMaxWait:1.5];
                        } else {
                            NSLog(@"[AdWinX] 所有候选展示失败，兜底图展示满最短时长后关闭");
                            [strongSelf dismissFallbackSplash];
                        }
                    }];
                };

                if (kADXExpiryTestDelayShow > 0) {
                    NSLog(@"[AdWinX] 【过期验证】延迟 %.0fs 后才展示，模拟加载→展示间隔过长", kADXExpiryTestDelayShow);
                    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(kADXExpiryTestDelayShow * NSEC_PER_SEC)),
                                   dispatch_get_main_queue(), showAd);
                } else {
                    showAd();
                }
            } else {
                NSLog(@"[AdWinX] 本次无可用广告，兜底图展示满最短时长后关闭");
                [strongSelf dismissFallbackSplash];
            }
        }];
    }];
}

- (void)showGlobalSigmobSplashAd
{
    [[ADSigmobGlobalAdManager sharedManager] loadAndShowSplashWithPlacementId:ADSigmobSplashPlacementId
                                                           rootViewController:self.window.rootViewController
                                                                       window:self.window
                                                                statusHandler:nil];
}

#pragma mark - 冷启动兜底开屏（自家品牌图）

/// 展示自家品牌兜底图：开屏请求期间的用户体验保底，无广告时也由它兜底展示
- (void)showFallbackSplash
{
    if (self.fallbackSplashView) {
        return;
    }

    UIView *container = [[UIView alloc] initWithFrame:self.window.bounds];
    container.backgroundColor = [UIColor whiteColor];
    container.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;

    // 品牌占位：logo + 名称（正式接入替换为品牌闪屏图/LaunchScreen 同款素材）
    UILabel *logoLabel = [[UILabel alloc] init];
    logoLabel.text = @"AdWinX";
    logoLabel.font = [UIFont boldSystemFontOfSize:32];
    logoLabel.textColor = [UIColor colorWithRed:0.20 green:0.45 blue:0.95 alpha:1.0];
    logoLabel.textAlignment = NSTextAlignmentCenter;
    logoLabel.frame = CGRectMake(0, 0, 200, 40);
    logoLabel.center = CGPointMake(CGRectGetMidX(container.bounds), CGRectGetMidY(container.bounds));
    logoLabel.autoresizingMask = UIViewAutoresizingFlexibleLeftMargin | UIViewAutoresizingFlexibleRightMargin
                               | UIViewAutoresizingFlexibleTopMargin | UIViewAutoresizingFlexibleBottomMargin;
    [container addSubview:logoLabel];

    UILabel *sloganLabel = [[UILabel alloc] init];
    sloganLabel.text = @"聚合广告 Demo";
    sloganLabel.font = [UIFont systemFontOfSize:14];
    sloganLabel.textColor = [UIColor grayColor];
    sloganLabel.textAlignment = NSTextAlignmentCenter;
    sloganLabel.frame = CGRectMake(0, CGRectGetMaxY(logoLabel.frame) + 12, 200, 20);
    sloganLabel.center = CGPointMake(CGRectGetMidX(container.bounds), CGRectGetMaxY(logoLabel.frame) + 22);
    sloganLabel.autoresizingMask = UIViewAutoresizingFlexibleLeftMargin | UIViewAutoresizingFlexibleRightMargin
                                 | UIViewAutoresizingFlexibleTopMargin | UIViewAutoresizingFlexibleBottomMargin;
    [container addSubview:sloganLabel];

    [self.window addSubview:container];
    self.fallbackSplashView = container;
    self.fallbackShowDate = [NSDate date];

    // 保底超时：拍卖回调因异常未触发时（如引擎线程问题），兜底图也不至于永远盖着。
    // 广告展示流程进行中则让路（此时由展示 completion 负责移除），
    // 避免慢路径下兜底图先被撤走、首页露出后广告才出现的闪烁
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(kADFallbackSplashMaxWait * NSEC_PER_SEC)),
                   dispatch_get_main_queue(), ^{
        if (!self.adShowInProgress) {
            [self dismissFallbackSplash];
            return;
        }
        // 展示流程进行中：让路，但追加最终保底——若展示回调异常丢失（delegate 丢失等），
        // 也不能让兜底图永远盖着首页
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(4.0 * NSEC_PER_SEC)),
                       dispatch_get_main_queue(), ^{
            [self dismissFallbackSplash];
        });
    });
}

/// 关闭兜底图：保证最短展示时长（避免广告秒回时兜底图一闪而过造成闪烁）
- (void)dismissFallbackSplash
{
    if (!self.fallbackSplashView) {
        return;
    }

    // 计算还需展示多久才满最短时长
    NSTimeInterval elapsed = -[self.fallbackShowDate timeIntervalSinceNow];
    NSTimeInterval remaining = kADFallbackSplashMinDuration - elapsed;
    if (remaining > 0) {
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(remaining * NSEC_PER_SEC)),
                       dispatch_get_main_queue(), ^{
            [self removeFallbackSplashView];
        });
    } else {
        [self removeFallbackSplashView];
    }
}

/// 兜底图之上是否已被广告视图实际盖住：检查同级视图层中排在兜底图之后、
/// 未隐藏、不透明且 frame 覆盖全屏的视图（ADN 的广告容器）。
/// 用于替代固定延迟猜测——曝光回调时机 ≠ 广告视图渲染完成时机
- (BOOL)isFallbackCoveredByAdView
{
    UIView *fallback = self.fallbackSplashView;
    if (!fallback || !fallback.superview) {
        return NO;
    }

    UIView *window = fallback.window;
    if (!window) {
        return NO;
    }

    NSArray<UIView *> *siblings = fallback.superview.subviews;
    NSUInteger fallbackIndex = [siblings indexOfObject:fallback];
    if (fallbackIndex == NSNotFound) {
        return NO;
    }

    for (NSUInteger i = fallbackIndex + 1; i < siblings.count; i++) {
        UIView *view = siblings[i];
        if (view.hidden || view.alpha < 0.99) {
            continue;
        }
        if (CGRectContainsRect(window.bounds, view.frame)) {
            return YES;
        }
    }
    return NO;
}

/// 等广告视图真正盖住兜底图后再撤（最多等 maxWait 秒，超时强制撤保底）：
/// 曝光回调后 ADN 视图可能仍在渲染首帧，此时撤兜底图会露出首页造成闪烁
- (void)removeFallbackSplashAfterAdCoveredWithMaxWait:(NSTimeInterval)maxWait
{
    __block NSInteger attemptsLeft = (NSInteger)(maxWait / 0.05);
    __weak typeof(self) weakSelf = self;
    void (^check)(void) = nil;
    check = ^{
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (!strongSelf || !strongSelf.fallbackSplashView) {
            return;
        }
        if ([strongSelf isFallbackCoveredByAdView] || attemptsLeft <= 0) {
            [strongSelf dismissFallbackSplash];
            return;
        }
        attemptsLeft--;
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.05 * NSEC_PER_SEC)),
                       dispatch_get_main_queue(), check);
    };
    check();
}

- (void)removeFallbackSplashView
{
    [self.fallbackSplashView removeFromSuperview];
    self.fallbackSplashView = nil;
    self.fallbackShowDate = nil;
}

@end
