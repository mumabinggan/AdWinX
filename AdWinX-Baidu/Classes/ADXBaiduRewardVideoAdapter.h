//
//  ADXBaiduRewardVideoAdapter.h
//  AdWinX
//
//  Created by AdWinX on 2026/08/30.
//

#import <Foundation/Foundation.h>
#import "ADXAdapter.h"

NS_ASSUME_NONNULL_BEGIN

/// 百度激励视频广告适配器
///
/// 实现 ADXAdapter 协议，封装百度 BaiduMobAdRewardVideo 的加载和竞胜/竞败通知。
/// SDK 初始化由 ADXAdManager setupSDK 统一调度 +setupSDKWithConfig: 完成。
@interface ADXBaiduRewardVideoAdapter : NSObject <ADXAdapter>

@end

NS_ASSUME_NONNULL_END
