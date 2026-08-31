//
//  ADXBaiduNativeExpressAdapter.h
//  AdWinX
//
//  Created by AdWinX on 2026/08/31.
//

#import <Foundation/Foundation.h>
#import "ADXAdapter.h"

NS_ASSUME_NONNULL_BEGIN

/// 百度信息流优选模板广告 Adapter
///
/// 竞价源：BaiduMobAdNative（isExpressNativeAds=YES）拉取 BaiduMobAdExpressNativeView，
/// 实时价 getPECPM，三级降级（getPECPM → getECPMLevel 档位中值 → 失败）。
/// 渲染：view.baseViewController + render，成功回调 nativeAdExpressSuccessRender（高度此时确定）。
@interface ADXBaiduNativeExpressAdapter : NSObject <ADXAdapter>

@end

NS_ASSUME_NONNULL_END
