//
//  ADXCSJNativeExpressAdapter.h
//  AdWinX
//
//  Created by AdWinX on 2026/08/31.
//

#import <Foundation/Foundation.h>
#import "ADXAdapter.h"

NS_ASSUME_NONNULL_BEGIN

/// 穿山甲（CSJ）信息流模板广告 Adapter
///
/// 瀑布源：BUNativeExpressAdManager 拉取模板视图，无实时价 API，比价使用预设 floorEcpm。
/// 渲染：view.rootViewController + render，成功回调 nativeExpressAdViewRenderSuccess（高度此时确定）。
@interface ADXCSJNativeExpressAdapter : NSObject <ADXAdapter>

@end

NS_ASSUME_NONNULL_END
