//
//  ADXConfigManager.h
//  AdWinX
//
//  Created by AdWinX on 2026/08/29.
//

#import <Foundation/Foundation.h>

@class ADXConfig;
@class ADXSlotConfig;

NS_ASSUME_NONNULL_BEGIN

/// 配置管理器：三层配置存取调度 + 远程拉取
///
/// 读取优先级：内存 → 磁盘缓存 → 内置兜底
/// 全部为本地 IO（毫秒级），开屏等启动关键路径零网络依赖。
///
/// 远程拉取为后台异步（fetchRemoteConfigWithCompletion:），不阻塞任何广告链路：
/// 拉到新配置后 校验 → 版本比对 → 写磁盘 → 更新内存，下次请求生效。
/// 拉取失败静默降级，本地三层配置始终可用。
@interface ADXConfigManager : NSObject

+ (instancetype)sharedManager;

/// 当前生效的全量配置（懒加载：内存 → 磁盘 → 内置兜底）
@property (nonatomic, strong, readonly) ADXConfig *currentConfig;

/// 远程配置地址（业务方在 setupSDK 前设置；nil 时跳过远程拉取）
///
/// 仅支持 HTTPS。SDK 默认不内置地址，由业务方注入自己的配置服务地址，
/// 拉取时机由 SDK 内部决定（setupSDK 后自动触发一次）。
@property (nonatomic, copy, nullable) NSURL *remoteConfigURL;

/// 按广告位名称取配置
///
/// @param slotName 配置内的广告位标识，如 "splash_main"
/// @return 当前配置中无该广告位时返回 nil
- (nullable ADXSlotConfig *)slotConfigWithName:(NSString *)slotName;

/// 用新配置替换当前配置并写入磁盘缓存
///
/// 供远程拉取流程调用。版本号 ≤ 当前版本时忽略。
///
/// @param config 已解析校验的配置
/// @return 是否替换成功（版本更旧则 NO）
- (BOOL)updateConfig:(ADXConfig *)config;

/// 清除磁盘缓存（调试用）
- (void)clearDiskCache;

/// 后台异步拉取远程配置
///
/// 完整链路：HTTPS GET → 状态码/数据校验 → Parser 解析校验（结构/必要字段）→
/// 版本比对（updateConfig，只升不降）→ 写磁盘 → 更新内存，下次请求生效。
/// 任何一步失败均不影响本地三层配置；进行中的广告请求也不受影响。
///
/// 内置防重入：上一次拉取未结束时再次调用直接跳过。
/// remoteConfigURL 未设置时同样跳过（不视为错误）。
///
/// @param completion 结果回调（主线程，可不传）：
///                   updated=YES 新版本配置已生效；
///                   updated=NO 且 error=nil：未配置地址 / 拉取进行中 / 服务端版本不更新；
///                   updated=NO 且 error 非 nil：网络失败或配置校验失败
- (void)fetchRemoteConfigWithCompletion:(nullable void (^)(BOOL updated, NSError * _Nullable error))completion;

@end

NS_ASSUME_NONNULL_END
