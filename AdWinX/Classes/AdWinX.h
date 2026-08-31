//
//  AdWinX.h
//  AdWinX
//
//  Created by AdWinX on 2026/08/29.
//

#import <UIKit/UIKit.h>

//! Project version number for AdWinX.
FOUNDATION_EXPORT double AdWinXVersionNumber;

//! Project version string for AdWinX.
FOUNDATION_EXPORT const unsigned char AdWinXVersionString[];

// Core
#import <AdWinX/ADXAdSourceInfo.h>
#import <AdWinX/ADXSlotConfig.h>
#import <AdWinX/ADXBidResult.h>
#import <AdWinX/ADXAuctionResult.h>
#import <AdWinX/ADXLogger.h>
#import <AdWinX/ADXConfig.h>
#import <AdWinX/ADXConfigParser.h>
#import <AdWinX/ADXConfigManager.h>
#import <AdWinX/ADXAdEvent.h>
#import <AdWinX/ADXAdEventDispatcher.h>
#import <AdWinX/ADXEventReporter.h>

// Protocol
#import <AdWinX/ADXAdapter.h>

// Adapter（按安装的 subspec 条件引入，接入方可按需组合 ADN）
#if __has_include(<AdWinX/ADXGDTSplashAdapter.h>)
#import <AdWinX/ADXGDTSplashAdapter.h>
#endif
#if __has_include(<AdWinX/ADXCSJSplashAdapter.h>)
#import <AdWinX/ADXCSJSplashAdapter.h>
#endif
#if __has_include(<AdWinX/ADXSigmobSplashAdapter.h>)
#import <AdWinX/ADXSigmobSplashAdapter.h>
#endif
#if __has_include(<AdWinX/ADXBaiduSplashAdapter.h>)
#import <AdWinX/ADXBaiduSplashAdapter.h>
#endif
#if __has_include(<AdWinX/ADXCSJRewardVideoAdapter.h>)
#import <AdWinX/ADXCSJRewardVideoAdapter.h>
#endif
#if __has_include(<AdWinX/ADXSigmobRewardVideoAdapter.h>)
#import <AdWinX/ADXSigmobRewardVideoAdapter.h>
#endif
#if __has_include(<AdWinX/ADXGDTRewardVideoAdapter.h>)
#import <AdWinX/ADXGDTRewardVideoAdapter.h>
#endif
#if __has_include(<AdWinX/ADXBaiduRewardVideoAdapter.h>)
#import <AdWinX/ADXBaiduRewardVideoAdapter.h>
#endif
#if __has_include(<AdWinX/ADXGDTInterstitialAdapter.h>)
#import <AdWinX/ADXGDTInterstitialAdapter.h>
#endif
#if __has_include(<AdWinX/ADXCSJInterstitialAdapter.h>)
#import <AdWinX/ADXCSJInterstitialAdapter.h>
#endif
#if __has_include(<AdWinX/ADXSigmobInterstitialAdapter.h>)
#import <AdWinX/ADXSigmobInterstitialAdapter.h>
#endif
#if __has_include(<AdWinX/ADXBaiduInterstitialAdapter.h>)
#import <AdWinX/ADXBaiduInterstitialAdapter.h>
#endif
#if __has_include(<AdWinX/ADXGDTNativeExpressAdapter.h>)
#import <AdWinX/ADXGDTNativeExpressAdapter.h>
#endif
#if __has_include(<AdWinX/ADXCSJNativeExpressAdapter.h>)
#import <AdWinX/ADXCSJNativeExpressAdapter.h>
#endif
#if __has_include(<AdWinX/ADXBaiduNativeExpressAdapter.h>)
#import <AdWinX/ADXBaiduNativeExpressAdapter.h>
#endif

// Engine
#import <AdWinX/ADXAuctionEngine.h>
#import <AdWinX/ADXAdapterRegistry.h>

// Manager
#import <AdWinX/ADXAdManager.h>
