//
//  ADXAdSourceInfo.h
//  AdWinX
//
//  Created by AdWinX on 2026/08/23.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/// 广告类型
typedef NS_ENUM(NSInteger, ADXAdType) {
    ADXAdTypeSplash = 0,        // 开屏
    ADXAdTypeRewardVideo,       // 激励视频
    ADXAdTypeInterstitial,      // 插屏
    ADXAdTypeBanner,            // Banner
    ADXAdTypeNativeExpress,     // 信息流
};

/// 广告源运行时模式
typedef NS_ENUM(NSInteger, ADXRuntimeMode) {
    ADXRuntimeModeBidding = 0,  // 竞价
    ADXRuntimeModeWaterfall,    // 瀑布流
};

/// 广告源配置模型
@interface ADXAdSourceInfo : NSObject

/// 广告源唯一标识，如 "ylh_bid"、"csj_80"
@property (nonatomic, copy) NSString *sourceId;

/// ADN 标识（逻辑用，字母缩写），如 "GDT"、"CSJ"；需与注册 Adapter 时的 adnName 一致
@property (nonatomic, copy) NSString *adnName;

/// 运行时模式：竞价 或 瀑布流
@property (nonatomic, assign) ADXRuntimeMode runtimeMode;

/// 广告类型
@property (nonatomic, assign) ADXAdType adType;

/// 预设底价，单位：分。竞价源为 0；瀑布源作为拿不到实时价时回包价格的兜底
@property (nonatomic, assign) NSInteger floorEcpm;

/// 编排 eCPM，单位：分。瀑布排序/分组/过滤的唯一依据：
/// 初期无数据时 = floorEcpm，后期由服务端下发统计值。运行时实际回包价见 ADXBidResult.price
@property (nonatomic, assign) NSInteger realEcpm;

/// 优先级，数值越大越高。realEcpm 相同时优先级高的先请求；
/// 排序键（realEcpm + priority）完全相同的源在引擎中并行请求
@property (nonatomic, assign) NSInteger priority;

/// 该广告源单次请求超时，单位：秒
@property (nonatomic, assign) NSTimeInterval timeout;

/// 信息流广告期望宽度（运行时由入口层填充，如屏宽 - 边距）；0 表示未指定，Adapter 自行取屏宽
@property (nonatomic, assign) CGFloat adWidth;

/// 下游 ADN 的广告位/代码位 ID
@property (nonatomic, copy) NSString *placementId;

/// 下游 ADN 的 AppID
@property (nonatomic, copy) NSString *appId;

/// 扩展参数，如 Sigmob 的 appKey
@property (nonatomic, copy, nullable) NSDictionary *extraParams;

/// 便捷构造方法
+ (instancetype)sourceWithId:(NSString *)sourceId
                         adn:(NSString *)adnName
                        mode:(ADXRuntimeMode)mode
                      adType:(ADXAdType)adType
                  floorEcpm:(NSInteger)floorEcpm
                    realEcpm:(NSInteger)realEcpm
                     timeout:(NSTimeInterval)timeout
                placementId:(NSString *)placementId
                      appId:(NSString *)appId
                extraParams:(nullable NSDictionary *)extraParams;

@end

NS_ASSUME_NONNULL_END