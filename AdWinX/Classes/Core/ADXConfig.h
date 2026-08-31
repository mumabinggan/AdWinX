//
//  ADXConfig.h
//  AdWinX
//
//  Created by AdWinX on 2026/08/29.
//

#import <Foundation/Foundation.h>
#import "ADXSlotConfig.h"

NS_ASSUME_NONNULL_BEGIN

/// 聚合 SDK 版本号（与 podspec 的 s.version 同步维护）
///
/// 用途：日志排障标识、远程配置请求携带（服务端按 SDK 版本下发）、问题回溯。
FOUNDATION_EXPORT NSString * const ADXSDKVersion;

/// 聚合 SDK 全量配置模型（JSON 解析产物）
///
/// 结构分两层：
///   - adnApps：应用级 ADN 配置（appId 等），整个 App 只有一份
///   - slots：广告位级配置（瀑布/竞价源列表），按 slotName 索引
@interface ADXConfig : NSObject

/// 配置版本号，单调递增；服务端版本 ≤ 本地版本时不覆盖
@property (nonatomic, assign) NSInteger configVersion;

/// 应用级 ADN 配置，key 为 ADN 标识（"GDT"/"CSJ"），value 为该 ADN 配置字典（如 appId）
@property (nonatomic, copy) NSDictionary<NSString *, NSDictionary *> *adnApps;

/// 远程日志级别（可选全局键 "logLevel"，0=Off/1=Error/2=Info/3=Debug）
/// 缺省 -1 表示配置未设置：维持 ADXLogger 的环境默认值，不干预本地 setLogLevel: 的显式设置
@property (nonatomic, assign) NSInteger logLevel;

/// 广告位配置列表
@property (nonatomic, copy) NSArray<ADXSlotConfig *> *slots;

/// 按 slotName 查找广告位配置，找不到返回 nil
- (nullable ADXSlotConfig *)slotConfigWithName:(NSString *)slotName;

@end

NS_ASSUME_NONNULL_END
