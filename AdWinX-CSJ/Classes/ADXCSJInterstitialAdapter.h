//
//  ADXCSJInterstitialAdapter.h
//  AdWinX
//
//  Created by AdWinX on 2026/08/31.
//

#import <Foundation/Foundation.h>
#import "ADXAdapter.h"

NS_ASSUME_NONNULL_BEGIN

/// 穿山甲插屏广告适配器
///
/// 实现 ADXAdapter 协议，封装穿山甲 BUNativeExpressFullscreenVideoAd 的加载和竞胜/竞败通知。
/// SDK 初始化由 ADXAdManager setupSDK 统一调度 +setupSDKWithConfig: 完成。
@interface ADXCSJInterstitialAdapter : NSObject <ADXAdapter>

@end

NS_ASSUME_NONNULL_END
