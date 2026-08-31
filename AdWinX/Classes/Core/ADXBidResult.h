//
//  ADXBidResult.h
//  AdWinX
//
//  Created by AdWinX on 2026/08/23.
//

#import <Foundation/Foundation.h>
#import "ADXAdSourceInfo.h"

NS_ASSUME_NONNULL_BEGIN

/// 竞价/加载结果模型
@interface ADXBidResult : NSObject

/// 来源广告源 ID
@property (nonatomic, copy) NSString *sourceId;

/// 广告类型
@property (nonatomic, assign) ADXAdType adType;

/// 出价，单位：分。竞价源 = 实时出价，瀑布源 = realEcpm（预设或真实 eCPM）
@property (nonatomic, assign) NSInteger price;

/// 广告对象，用于后续展示
@property (nonatomic, strong, nullable) id adObject;

/// 是否成功获取到广告
@property (nonatomic, assign) BOOL success;

/// 失败时的错误信息
@property (nonatomic, strong, nullable) NSError *error;

/// 便捷构造方法
+ (instancetype)resultWithSourceId:(NSString *)sourceId
                            adType:(ADXAdType)adType
                             price:(NSInteger)price
                          adObject:(nullable id)adObject
                           success:(BOOL)success
                             error:(nullable NSError *)error;

@end

NS_ASSUME_NONNULL_END