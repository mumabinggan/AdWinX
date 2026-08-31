//
//  ADXAdapterRegistry.h
//  AdWinX
//
//  Created by AdWinX on 2026/08/29.
//

#import <Foundation/Foundation.h>
#import "ADXAdapter.h"
#import "ADXAdSourceInfo.h"

NS_ASSUME_NONNULL_BEGIN

/// Adapter 注册中心
///
/// 引擎通过注册中心创建 Adapter 实例，自身不感知任何具体 ADN。
/// 接入新的 ADN 时，只需实现一个 ADXAdapter 并注册，引擎和其他代码无需改动。
/// 注册键为（adnName + adType）复合键：同一 ADN 可同时注册开屏/激励视频等多个 Adapter。
@interface ADXAdapterRegistry : NSObject

/// 注册 Adapter 类（按 ADN 标识 + 广告类型，如 "GDT" + ADXAdTypeSplash）
///
/// @param adapterClass 实现 ADXAdapter 协议的类
/// @param adnName 与 ADXAdSourceInfo.adnName 对应的 ADN 名称
/// @param adType 广告类型，与广告源配置的 adType 对应
+ (void)registerAdapterClass:(Class)adapterClass forAdnName:(NSString *)adnName adType:(ADXAdType)adType;

/// 注册 Adapter 类（兼容入口，等价于 adType=ADXAdTypeSplash）
+ (void)registerAdapterClass:(Class)adapterClass forAdnName:(NSString *)adnName;

/// 查询（ADN + 广告类型）组合是否已注册 Adapter
///
/// 供自动注册流程避让手动注册：已注册的组合不覆盖。
+ (BOOL)hasRegisteredAdapterForAdnName:(NSString *)adnName adType:(ADXAdType)adType;

/// 根据广告源配置创建 Adapter 实例（每次调用返回新实例）
///
/// @param sourceInfo 广告源配置
/// @return 未注册对应（ADN + 广告类型）组合时返回 nil
+ (nullable id<ADXAdapter>)adapterForSourceInfo:(ADXAdSourceInfo *)sourceInfo;

/// 获取所有已注册的 Adapter 类（供 setupSDK 统一初始化 ADN）
///
/// 同一 ADN 注册了多个广告类型的 Adapter 时按 adnName 去重只保留一个
/// （各 Adapter 的 +setupSDKWithConfig: 内部均有静态去重，初始化语义一致）。
///
/// @return key 为 adnName，value 为对应 Adapter 类
+ (NSDictionary<NSString *, Class> *)allRegisteredAdapterClasses;

@end

NS_ASSUME_NONNULL_END