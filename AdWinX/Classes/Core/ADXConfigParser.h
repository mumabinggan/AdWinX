//
//  ADXConfigParser.h
//  AdWinX
//
//  Created by AdWinX on 2026/08/29.
//

#import <Foundation/Foundation.h>

@class ADXConfig;

NS_ASSUME_NONNULL_BEGIN

/// JSON 配置解析器
///
/// 将 JSON 数据解析为 ADXConfig 模型。容错策略：
///   - 整体结构非法（非字典/缺少必要字段）→ 返回 nil
///   - 单个广告位/广告源字段非法 → 跳过该条，不影响其他条目
@interface ADXConfigParser : NSObject

/// 解析 JSON 数据
///
/// @param data JSON 数据（UTF-8 编码）
/// @return 解析失败返回 nil
+ (nullable ADXConfig *)parseConfigWithData:(NSData *)data;

/// 解析内置兜底配置（AdWinX.bundle/adx_default_config.json）
///
/// @return Bundle 内无该文件或解析失败返回 nil
+ (nullable ADXConfig *)parseBundledDefaultConfig;

@end

NS_ASSUME_NONNULL_END
