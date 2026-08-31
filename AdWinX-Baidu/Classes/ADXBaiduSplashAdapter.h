//
//  ADXBaiduSplashAdapter.h
//  AdWinX
//
//  Created by AdWinX on 2026/08/29.
//

#import <Foundation/Foundation.h>
#import "ADXAdapter.h"

NS_ASSUME_NONNULL_BEGIN

/// 百度联盟（BaiduMobAdSDK）开屏广告适配器
///
/// 实现 ADXAdapter 协议，封装 BaiduMobAdSplash 的加载和竞胜/竞败通知。
/// 百度开屏支持「仅请求不展示」（load / showInContainerView:），天然契合拍卖模型。
/// SDK 初始化由 ADXAdManager setupSDK 统一调度 +setupSDKWithConfig: 完成。
@interface ADXBaiduSplashAdapter : NSObject <ADXAdapter>

@end

NS_ASSUME_NONNULL_END
