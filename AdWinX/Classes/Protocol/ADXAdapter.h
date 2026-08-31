//
//  ADXAdapter.h
//  AdWinX
//
//  Created by AdWinX on 2026/08/29.
//

#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>

@class ADXAdSourceInfo;
@class ADXBidResult;

NS_ASSUME_NONNULL_BEGIN

/// 竞败原因
typedef NS_ENUM(NSInteger, ADXLossReason) {
    ADXLossReasonLowPrice = 1,     // 出价竞争力不足
    ADXLossReasonTimeout = 2,      // 加载超时
    ADXLossReasonNoAd = 3,         // 无广告回包
    ADXLossReasonOther = 10001,    // 其他
};

/// 广告源适配器协议
///
/// 所有下游 ADN（优量汇、穿山甲等）的 Adapter 必须实现此协议。
/// Adapter 内部负责：
///   - SDK 初始化
///   - 广告加载
///   - eCPM 提取
///   - 超时处理
///   - 将 ADN 特定回调桥接为统一的 ADXBidResult
@protocol ADXAdapter <NSObject>

@required

/// 根据广告源配置加载广告
///
/// @param sourceInfo 广告源配置（含 runtimeMode、adType、placementId 等）
/// @param completion 加载完成回调
- (void)loadAdWithSourceInfo:(ADXAdSourceInfo *)sourceInfo
                  completion:(void (^)(ADXBidResult *result))completion;

/// 通知竞胜，Adapter 收到后可准备展示广告
///
/// 竞价源和瀑布源都需要调用：只要该广告源加载成功且最终被展示，引擎就会调用此方法。
/// Adapter 内部决定如何映射到 ADN 的 API（如无对应 API 可空实现）。
///
/// @param costPrice 竞胜价格（实际扣费），单位：分
/// @param lossPrice 最高失败出价，单位：分
- (void)notifyWinWithCostPrice:(NSInteger)costPrice
                     lossPrice:(NSInteger)lossPrice;

/// 通知竞败，Adapter 收到后应释放广告资源
///
/// 竞价源和瀑布源都需要调用：只要该广告源加载成功但最终未被展示，引擎就会调用此方法。
/// 加载失败的广告源不会收到本通知。Adapter 内部决定如何映射到 ADN 的 API。
///
/// @param winPrice 竞胜价格，单位：分
/// @param lossReason 竞败原因码
/// @param winnerAdnId 竞胜方渠道标识
- (void)notifyLossWithWinPrice:(NSInteger)winPrice
                    lossReason:(NSInteger)lossReason
                   winnerAdnId:(NSString *)winnerAdnId;

@optional

/// 初始化 ADN SDK（类方法，由 ADXAdManager setupSDK 统一调度）
///
/// @param adnConfig ADN 应用级配置（如 appId），P0 阶段可传 nil 使用内置默认值
+ (void)setupSDKWithConfig:(nullable NSDictionary *)adnConfig;

/// 初始化 ADN SDK 并回调就绪状态（推荐实现，冷启动「就绪即开拍卖」依赖此方法）
///
/// 与 setupSDKWithConfig: 的区别：SDK 初始化完成（无论成功失败）后必须回调 completion，
/// 同步初始化的 ADN 在方法返回前直接回调即可。
/// ADXAdManager 通过该方法计数所有 ADN 就绪情况，全就绪或超时后立即发起拍卖，
/// 替代接入方原先「固定延迟 1s 等初始化」的猜测式等待。
///
/// @param adnConfig ADN 应用级配置（如 appId）
/// @param completion 就绪回调（success 为 SDK 初始化结果），必须恰好回调一次
+ (void)setupSDKWithConfig:(nullable NSDictionary *)adnConfig
                completion:(nullable void (^)(BOOL success))completion;

/// 展示开屏广告（开屏类型 Adapter 实现）
///
/// 引擎结算（含 notifyWin）完成后由入口层调用。
///
/// @param result 竞胜结果（adObject 为 ADN 广告对象）
/// @param window 展示容器
- (void)showSplashAdWithResult:(ADXBidResult *)result
                        window:(UIWindow *)window;

/// 展示开屏广告并回调展示结果（推荐实现，展示失败降级依赖此方法）
///
/// 与 showSplashAdWithResult:window: 的区别：展示发起前校验广告有效性（过期/已释放等），
/// 无效时立即回调 completion(NO)；有效则发起展示，并尽早在「曝光成功/展示失败」
/// 回调 completion。上层据此做失败降级（换次高价候选或退回兜底图）。
/// 无法感知展示结果的 ADN，在展示发起成功后即可回调 YES。
///
/// @param result 竞胜结果（adObject 为 ADN 广告对象）
/// @param window 展示容器
/// @param completion 展示结果回调，必须恰好回调一次；success=NO 时 error 附带原因
- (void)showSplashAdWithResult:(ADXBidResult *)result
                        window:(UIWindow *)window
                    completion:(void (^)(BOOL success, NSError * _Nullable error))completion;

/// 展示激励视频广告并回调展示结果（激励视频类型 Adapter 实现）
///
/// 展示发起前校验广告有效性（过期/已释放等），无效时立即回调 completion(NO)，
/// 上层据此做失败降级（换次高价候选）。有效则发起展示，在「曝光成功/展示失败」时回调 completion。
///
/// @param result 竞胜结果（adObject 为 ADN 广告对象）
/// @param rootViewController 展示容器控制器
/// @param rewardCallback 激励达成回调（业务发奖用）：granted=YES 表示达到激励条件；
///                       可能早于/晚于 completion，业务无需在 completion 内等待此回调
/// @param completion 展示结果回调，必须恰好回调一次；success=NO 时 error 附带原因
- (void)showRewardVideoAdWithResult:(ADXBidResult *)result
                 fromViewController:(UIViewController *)rootViewController
                      rewardCallback:(nullable void (^)(BOOL granted))rewardCallback
                          completion:(void (^)(BOOL success, NSError * _Nullable error))completion;

/// 展示插屏广告并回调展示结果（插屏类型 Adapter 实现）
///
/// 展示发起前校验广告有效性（过期/已释放等），无效时立即回调 completion(NO)，
/// 上层据此做失败降级（换次高价候选）。有效则发起展示，在「曝光成功/展示失败」时回调 completion。
/// 无法感知展示结果的 ADN，在展示发起成功后即可回调 YES。
///
/// @param result 竞胜结果（adObject 为 ADN 广告对象）
/// @param rootViewController 展示容器控制器
/// @param completion 展示结果回调，必须恰好回调一次；success=NO 时 error 附带原因
- (void)showInterstitialAdWithResult:(ADXBidResult *)result
                  fromViewController:(UIViewController *)rootViewController
                          completion:(void (^)(BOOL success, NSError * _Nullable error))completion;

/// 渲染信息流广告视图并回调结果（信息流类型 Adapter 实现）
///
/// 信息流的"展示"= 渲染出模板视图，由业务自行 add 到信息流容器。
/// 渲染发起前校验广告有效性（过期/已释放/竞败清理），无效时立即回调 completion(nil, error)，
/// 上层据此做失败降级（换次高价候选重渲染）。有效则发起渲染，
/// 在「渲染成功」时回调 completion(adView)（此时视图高度已确定）；
/// 渲染失败回调 completion(nil, error)。
///
/// @param result 竞胜结果（adObject 为 ADN 广告视图）
/// @param rootViewController 落地页弹出容器控制器
/// @param completion 渲染结果回调，必须恰好回调一次；adView 为渲染完成的广告视图
- (void)renderNativeAdViewWithResult:(ADXBidResult *)result
                    rootViewController:(UIViewController *)rootViewController
                            completion:(void (^)(UIView * _Nullable adView, NSError * _Nullable error))completion;

@end

NS_ASSUME_NONNULL_END