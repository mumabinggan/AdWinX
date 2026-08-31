//
//  ADXSigmobSplashAdapter.h
//  AdWinX
//
//  Created by AdWinX on 2026/08/29.
//

#import <Foundation/Foundation.h>
#import "ADXAdapter.h"

NS_ASSUME_NONNULL_BEGIN

/// Sigmob（WindSDK）开屏广告适配器
///
/// 实现 ADXAdapter 协议，封装 WindSplashAdView 的加载和竞胜/竞败通知。
/// Sigmob 开屏为自渲染 view：加载阶段预挂载到窗口并隐藏，
/// 竞胜后显示、竞败后移除释放，保证不破坏拍卖决策。
/// SDK 初始化由 ADXAdManager setupSDK 统一调度 +setupSDKWithConfig: 完成。
@interface ADXSigmobSplashAdapter : NSObject <ADXAdapter>

@end

NS_ASSUME_NONNULL_END
