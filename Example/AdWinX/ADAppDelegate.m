//
//  ADAppDelegate.m
//  AdWinX
//
//  Created by mumabinggan on 08/12/2026.
//  Copyright (c) 2026 mumabinggan. All rights reserved.
//

#import "ADAppDelegate.h"
#import "ADAdDemoConstants.h"
#import "ADSigmobGlobalAdManager.h"
#import <BaiduMobAdSDK/BaiduMobAdManager.h>
#import <BaiduMobAdSDK/BaiduMobAdSetting.h>
#import <AdWinX/AdWinX.h>

@implementation ADAppDelegate

- (BOOL)application:(UIApplication *)application didFinishLaunchingWithOptions:(NSDictionary *)launchOptions
{
    // 回捞上次「无调试器冷启动」的落盘日志（分析冷启动耗时必须脱离 Xcode，调试器 NSLog I/O 会拖慢主线程）。
    // 必须在写"入口"锚点之前执行：drain 会读走并删除文件，若先写锚点，
    // 本次启动自己的锚点会被 drain 读出来（出现在"上次日志"末尾），而冷启动的锚点又被它自己的 drain 吃掉，
    // 导致落盘日志里永远缺"入口"这条。先 drain 再写锚点，下次回捞就能看到本次会话完整的入口锚点。
    NSString *previousLog = [ADXLogger drainLogFile];
    if (previousLog.length > 0) {
        // 分行打印：一次性 NSLog 整个文件会被控制台截断（曾截断在 [AdW 处，导致误判日志缺失）
        NSLog(@"===== 上次冷启动落盘日志 =====");
        for (NSString *line in [previousLog componentsSeparatedByString:@"\n"]) {
            if (line.length > 0) {
                NSLog(@"%@", line);
            }
        }
        NSLog(@"===== 上次日志结束 =====");
    }

    // 冷启动耗时锚点：用于切分「启动 → SDK 就绪 → 拍卖」各阶段耗时（走 ADXLogger 以便落盘回捞）
    ADXLogInfo(@"didFinishLaunching 入口");

    NSString *bundleId = [[NSBundle mainBundle] bundleIdentifier];
    NSLog(@"✅ BundleID(包名): %@", bundleId);
    [self setupBaiduMobAdSDK];
    [self setupSigmobSDK];

    // window 创建与 AdWinX 聚合开屏链路（兜底图/拍卖均依赖 window）
    // 已迁移至 ADSceneDelegate scene:willConnectToSession:options:（UIScene 生命周期）

    return YES;
}

- (void)setupBaiduMobAdSDK
{
    // 百度 debug 日志默认开启且主线程大量打印，会挤占主线程拖慢竞价回包，保持关闭
    // （AdWinX 的 ADXBaiduSplashAdapter 内部也会关一次，此处双保险）
    [[BaiduMobAdSetting sharedInstance] setDebugLogEnable:NO];
    [BaiduMobAdManager setAppsid:ADBaiduAppId];
    [[BaiduMobAdSetting sharedInstance] setLimitBaiduPersonalAds:NO];
    [BaiduMobAdManager startWithCompletionHandler:^(BOOL success, NSError * _Nullable error) {
        if (success) {
            NSLog(@"百度广告 SDK 启动成功，AppID: %@, SDKVersion: %@", ADBaiduAppId, [BaiduMobAdManager getSDKVersion]);
        } else {
            NSLog(@"百度广告 SDK 启动失败，AppID: %@, error: %@", ADBaiduAppId, error);
        }
    }];
}

- (void)setupSigmobSDK
{
    [[ADSigmobGlobalAdManager sharedManager] setupSDK];
}

@end
