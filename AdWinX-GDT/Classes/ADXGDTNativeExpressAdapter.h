//
//  ADXGDTNativeExpressAdapter.h
//  AdWinX
//
//  Created by AdWinX on 2026/08/31.
//

#import <Foundation/Foundation.h>
#import "ADXAdapter.h"

NS_ASSUME_NONNULL_BEGIN

/// 优量汇（GDT）信息流模板广告 Adapter
///
/// 竞价源：GDTNativeExpressAd 拉取模板视图，实时价取 GDTNativeExpressAdView.eCPM。
/// 渲染：view.controller + render，成功回调 nativeExpressAdViewRenderSuccess（高度此时确定）。
@interface ADXGDTNativeExpressAdapter : NSObject <ADXAdapter>

@end

NS_ASSUME_NONNULL_END
