//
//  ADXSlotConfig.h
//  AdWinX
//
//  Created by AdWinX on 2026/08/23.
//

#import <Foundation/Foundation.h>
#import "ADXAdSourceInfo.h"

NS_ASSUME_NONNULL_BEGIN

/// 广告位配置模型
@interface ADXSlotConfig : NSObject

/// 广告位名称（配置内唯一标识，如 "splash_main"）
@property (nonatomic, copy) NSString *slotName;

/// 广告类型
@property (nonatomic, assign) ADXAdType adType;

/// 竞价池总超时，单位：秒
@property (nonatomic, assign) NSTimeInterval bidTimeout;

/// 拍卖总预算（竞价 + 瀑布），单位：秒。剩余不足阈值时直取 realEcpm=0 兜底组
@property (nonatomic, assign) NSTimeInterval totalTimeout;

/// 瀑布流单层超时，单位：秒
@property (nonatomic, assign) NSTimeInterval waterfallTimeout;

/// 广告源列表
@property (nonatomic, copy) NSArray<ADXAdSourceInfo *> *adSources;

@end

NS_ASSUME_NONNULL_END