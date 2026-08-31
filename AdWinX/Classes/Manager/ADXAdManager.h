//
//  ADXAdManager.h
//  AdWinX
//
//  Created by AdWinX on 2026/08/29.
//

#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>

@class ADXSlotConfig;
@class ADXAuctionResult;
#import "ADXAdSourceInfo.h"

NS_ASSUME_NONNULL_BEGIN

@class ADXAdEvent;

/// 广告请求完成回调
///
/// @param result 拍卖结果，winnerResult 为 nil 表示无可用广告
typedef void (^ADXAdLoadCompletion)(ADXAuctionResult * _Nullable result);

/// 广告链路事件观察回调（主线程）
///
/// 事件流覆盖拍卖与展示全链路（开始/竞价回包/瀑布层/回包/结算/展示结果），
/// 用于漏斗诊断（瀑布深度分布、降级链触发率、展示失败率、超时率）。
/// 可转投自有统计系统；不设置时零开销。
typedef void (^ADXAdEventObserver)(ADXAdEvent *event);

/// AdWinX 聚合 SDK 统一入口
///
/// 使用流程（推荐，零手动注册）：
///   1. Podfile 按需引入：pod 'AdWinX/Core' + 各 ADN 的 Adapter pod（如 pod 'AdWinX-CSJ'）
///   2. 调用 setupSDKWithAdnConfigs: —— 内部自动发现注册已安装的 Adapter 并统一初始化
///   3. 按广告位名称调用 load 系列方法（配置来自内存/磁盘缓存/内置兜底 JSON）
///
/// 特殊场景（如替换某 ADN 为自研 Adapter）可手动调用 registerAdapterClass: 覆盖，
/// 手动注册的组合优先于自动发现，不会被覆盖。
@interface ADXAdManager : NSObject

+ (instancetype)sharedManager;

/// 设置广告链路事件观察回调（传 nil 移除）
///
/// 观察拍卖/展示全链路事件（ADXAdEvent），主线程回调。
/// 用于漏斗诊断与统计上报：瀑布深度分布、降级链触发率、展示失败率、超时率等。
- (void)setAdEventHandler:(nullable ADXAdEventObserver)handler;

/// 注册 Adapter 类（按 ADN 名称，需与 ADXAdSourceInfo.adnName 一致）
///
/// 可选：setupSDK 时会按已安装的 Adapter pod 自动发现注册，正常接入无需手动调用；
/// 仅替换某 ADN 为自研 Adapter 等特殊场景使用。手动注册优先于自动发现。
- (void)registerAdapterClass:(Class)adapterClass forAdnName:(NSString *)adnName;

/// 注册 Adapter 类（按 ADN 名称 + 广告类型复合键）
///
/// 同一 ADN 的开屏/激励视频等 Adapter 分别注册，互不覆盖。
///
/// @param adapterClass 实现 ADXAdapter 协议的类
/// @param adnName 与 ADXAdSourceInfo.adnName 对应的 ADN 名称
/// @param adType 广告类型，与广告源配置的 adType 对应
- (void)registerAdapterClass:(Class)adapterClass forAdnName:(NSString *)adnName adType:(ADXAdType)adType;

/// 统一初始化所有已注册 ADN 的 SDK
///
/// 遍历已注册 Adapter，调用各 Adapter 的 +setupSDKWithConfig:。
///
/// @param adnConfigs ADN 应用级配置，key 为 adnName，value 为该 ADN 的配置字典（如 @{@"appId": @"xxx"}）。
///                   传 nil 时各 Adapter 使用内置默认配置。后续接入服务端配置下发后，由本方法分发。
- (void)setupSDKWithAdnConfigs:(nullable NSDictionary<NSString *, NSDictionary *> *)adnConfigs;

/// 统一初始化所有已注册 ADN 的 SDK，并在就绪后回调（冷启动「就绪即开拍卖」推荐入口）
///
/// 全部 ADN 就绪（各 Adapter 的 +setupSDKWithConfig:completion: 均已回调，
/// 无论成功失败）后回调 completion；任一 ADN 初始化超过 2.5s 也不再等待，
/// 按已就绪状态回调（completion 的 timedOut=YES）。
/// 替代接入方「固定延迟 N 秒等 SDK 初始化」的猜测式等待。
///
/// @param adnConfigs ADN 应用级配置，同 setupSDKWithAdnConfigs:
/// @param completion 就绪回调（主线程），timedOut=YES 表示有 ADN 超时未就绪
- (void)setupSDKWithAdnConfigs:(nullable NSDictionary<NSString *, NSDictionary *> *)adnConfigs
                    completion:(nullable void (^)(BOOL timedOut))completion;

/// 请求并展示开屏广告
///
/// 完整流程：拍卖（竞价并行 + 瀑布串行 + 结算通知）→ 赢家展示。
///
/// @param config 广告位配置
/// @param window 开屏展示容器
/// @param completion 完成回调（主线程），无论是否有广告都会回调
- (void)loadSplashAdWithConfig:(ADXSlotConfig *)config
                        window:(UIWindow *)window
                    completion:(ADXAdLoadCompletion)completion;

/// 请求并展示开屏广告（配置化入口）
///
/// 按广告位名称从配置体系（内存 → 磁盘缓存 → 内置兜底）取配置，
/// 并把应用级 ADN 配置（appId 等）分发到各广告源。
///
/// @param slotName 配置内的广告位标识，如 "splash_main"
/// @param window 开屏展示容器
/// @param completion 完成回调（主线程），无论是否有广告都会回调
- (void)loadSplashAdWithSlotName:(NSString *)slotName
                          window:(UIWindow *)window
                      completion:(ADXAdLoadCompletion)completion;

/// 请求开屏广告但不自动展示（仅加载，展示由业务自行控制）
///
/// 用于冷启动兜底场景：业务先展示自家品牌图，同时后台请求广告，
/// 广告返回后再调用 showSplashAdWithResult:window: 展示。
///
/// @param slotName 配置内的广告位标识，如 "splash_main"
/// @param completion 完成回调（主线程），无论是否有广告都会回调。
///                   winnerResult 非 nil 时可通过 showSplashAdWithResult:window: 展示
- (void)loadSplashAdOnlyWithSlotName:(NSString *)slotName
                          completion:(ADXAdLoadCompletion)completion;

/// 展示已加载的开屏广告赢家（含展示失败降级）
///
/// 配合 loadSplashAdOnlyWithSlotName:completion: 使用。
/// 赢家展示失败时（如广告过期、对象被清理），自动按价格从高到低降级尝试其余成功候选，
/// 全部失败则回调 shown=NO，由业务兜底（展示自家品牌图或进首页）。
///
/// @param result 拍卖结果（winnerResult 非 nil 时可展示）
/// @param window 展示容器
/// @param completion 展示结果回调：shown=成功展示（shownSourceId 为实际展示的源，
///                   可能因降级与赢家不同）；shown=NO 表示所有候选均展示失败
- (void)showSplashAdWithResult:(ADXAuctionResult *)result
                        window:(UIWindow *)window
                    completion:(nullable void (^)(BOOL shown, NSString * _Nullable shownSourceId))completion;

/// 展示已加载的开屏广告赢家（兼容入口，无展示结果回调）
///
/// @param result 拍卖结果（winnerResult 非 nil 时可展示）
/// @param window 展示容器
- (void)showSplashAdWithResult:(ADXAuctionResult *)result
                        window:(UIWindow *)window;

/// 请求激励视频广告但不自动展示（仅加载，展示由业务自行控制）
///
/// 按广告位名称从配置体系取配置并发起拍卖，广告加载完成后由业务调用
/// showRewardVideoAdWithResult:fromViewController:rewardCallback:completion: 展示。
///
/// @param slotName 配置内的广告位标识，如 "reward_main"
/// @param completion 完成回调（主线程），无论是否有广告都会回调。
///                   winnerResult 非 nil 时可通过 show 系列方法展示
- (void)loadRewardVideoAdWithSlotName:(NSString *)slotName
                            completion:(ADXAdLoadCompletion)completion;

/// 展示已加载的激励视频广告赢家（含展示失败降级）
///
/// 配合 loadRewardVideoAdWithSlotName:completion: 使用。
/// 赢家展示失败时（如广告过期、对象被清理），自动按价格从高到低降级尝试其余成功候选，
/// 全部失败则回调 shown=NO，由业务兜底。
///
/// @param result 拍卖结果（winnerResult 非 nil 时可展示）
/// @param rootViewController 展示容器控制器
/// @param rewardCallback 激励达成回调：granted=YES 表示达到激励条件（业务发奖）；
///                       用户提前关闭未看完时 granted=NO；不关心可传 nil
/// @param completion 展示结果回调：shown=成功展示（shownSourceId 为实际展示的源，
///                   可能因降级与赢家不同）；shown=NO 表示所有候选均展示失败
- (void)showRewardVideoAdWithResult:(ADXAuctionResult *)result
                  fromViewController:(UIViewController *)rootViewController
                       rewardCallback:(nullable void (^)(BOOL granted))rewardCallback
                           completion:(nullable void (^)(BOOL shown, NSString * _Nullable shownSourceId))completion;

/// 请求信息流广告但不渲染（仅加载，渲染由业务自行控制）
///
/// 按广告位名称从配置体系取配置并发起拍卖（竞价 + 瀑布 + 结算通知），
/// 加载完成后由业务调用 renderNativeAdViewWithResult:rootViewController:completion: 渲染，
/// 再将返回的广告视图 add 到信息流容器。
///
/// @param slotName 配置内的广告位标识，如 "native_main"
/// @param adWidth 信息流期望宽度（如屏宽 - 边距）；0 表示由各 ADN 自行取屏宽
/// @param completion 完成回调（主线程），无论是否有广告都会回调。
///                   winnerResult 非 nil 时可通过 renderNativeAdView... 渲染
- (void)loadNativeAdWithSlotName:(NSString *)slotName
                         adWidth:(CGFloat)adWidth
                       completion:(ADXAdLoadCompletion)completion;

/// 请求插屏广告但不自动展示（仅加载，展示由业务自行控制）
///
/// 按广告位名称从配置体系取配置并发起拍卖（竞价 + 瀑布 + 结算通知），
/// 加载完成后由业务调用 showInterstitialAdWithResult:fromViewController:completion: 展示。
///
/// @param slotName 配置内的广告位标识，如 "interstitial_main"
/// @param completion 完成回调（主线程），无论是否有广告都会回调。
///                   winnerResult 非 nil 时可通过 show 系列方法展示
- (void)loadInterstitialAdWithSlotName:(NSString *)slotName
                             completion:(ADXAdLoadCompletion)completion;

/// 展示已加载的插屏广告赢家（含展示失败降级）
///
/// 配合 loadInterstitialAdWithSlotName:completion: 使用。
/// 赢家展示失败时（如广告过期、对象被清理），自动按价格从高到低降级尝试其余成功候选，
/// 全部失败则回调 shown=NO，由业务兜底。
///
/// @param result 拍卖结果（winnerResult 非 nil 时可展示）
/// @param rootViewController 展示容器控制器
/// @param completion 展示结果回调：shown=成功展示（shownSourceId 为实际展示的源，
///                   可能因降级与赢家不同）；shown=NO 表示所有候选均展示失败
- (void)showInterstitialAdWithResult:(ADXAuctionResult *)result
                   fromViewController:(UIViewController *)rootViewController
                          completion:(nullable void (^)(BOOL shown, NSString * _Nullable shownSourceId))completion;

/// 渲染已加载的信息流广告赢家（含渲染失败降级）
///
/// 配合 loadNativeAdWithSlotName:adWidth:completion: 使用。
/// 赢家渲染失败时（如广告过期、视图被清理），自动按价格从高到低降级重渲染其余成功候选，
/// 全部失败则回调 adView=nil，由业务兜底（占位图或隐藏广告 cell）。
///
/// @param result 拍卖结果（winnerResult 非 nil 时可渲染）
/// @param rootViewController 落地页弹出容器控制器
/// @param completion 渲染结果回调：adView 非 nil 为渲染完成的广告视图（高度已确定，
///                   业务自行布局；shownSourceId 为实际渲染的源，可能因降级与赢家不同）；
///                   adView=nil 表示所有候选渲染失败
- (void)renderNativeAdViewWithResult:(ADXAuctionResult *)result
                    rootViewController:(UIViewController *)rootViewController
                          completion:(nullable void (^)(UIView * _Nullable adView, NSString * _Nullable shownSourceId))completion;

#pragma mark - 预加载（激励视频 / 插屏）

/// 预加载激励视频广告（SDK 按广告位持有拍卖结果）
///
/// 适用于「用户触发点等不起」的场景（如死亡复活、双倍奖励）：在进入关卡等低感知时机
/// 预载，内部走完整拍卖（竞价 + 瀑布 + 结算），成功后按 slotName 持有结果与 Adapter 实例；
/// 用户触发点调用 takeRewardVideoAdWithSlotName: 取走并立即展示，展示毫秒级。
///
/// 该位已有未取走的预载结果或正在预载时跳过请求（completion 直接回调已有结果）；
/// 本次拍卖无可用广告时不持有（take 返回 nil）。广告过期的兜底由展示降级链
/// 与业务现场 load 两层承接。
///
/// @param slotName 配置内的广告位标识，如 "reward_revive"
/// @param completion 可选预载结果回调（主线程）：result.winnerResult 非 nil 表示预载成功
- (void)preloadRewardVideoAdWithSlotName:(NSString *)slotName
                              completion:(nullable ADXAdLoadCompletion)completion;

/// 取走已预加载的激励视频拍卖结果（取走即清，重复取返回 nil）
///
/// 返回非 nil 后应立即调用 showRewardVideoAdWithResult:fromViewController:rewardCallback:completion:
/// 展示（内部已恢复对应的 Adapter 实例与事件归因上下文，无需业务干预）。
/// 返回 nil 表示无可用预载（未预载 / 无填充 / 已被取走），业务可现场 load 兜底。
- (nullable ADXAuctionResult *)takeRewardVideoAdWithSlotName:(NSString *)slotName;

/// 预加载插屏广告（机制同激励视频预载，适用于关卡结算等触发点前移场景）
///
/// @param slotName 配置内的广告位标识，如 "interstitial_main"
/// @param completion 可选预载结果回调（主线程）：result.winnerResult 非 nil 表示预载成功
- (void)preloadInterstitialAdWithSlotName:(NSString *)slotName
                               completion:(nullable ADXAdLoadCompletion)completion;

/// 取走已预加载的插屏拍卖结果（取走即清，重复取返回 nil）
///
/// 返回非 nil 后应立即调用 showInterstitialAdWithResult:fromViewController:completion: 展示。
- (nullable ADXAuctionResult *)takeInterstitialAdWithSlotName:(NSString *)slotName;

/// 丢弃指定广告位的预载结果（退出关卡等场景释放内存，激励/插屏一并清除）
///
/// 仅清除已持有的预载结果；正在进行中的预载请求无法取消，其完成后的结果仍会存入。
- (void)discardPreloadedAdWithSlotName:(NSString *)slotName;

@end

NS_ASSUME_NONNULL_END