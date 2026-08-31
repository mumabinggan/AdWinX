# AdWinX

[![CI Status](https://img.shields.io/travis/mumabinggan/AdWinX.svg?style=flat)](https://travis-ci.org/mumabinggan/AdWinX)
[![Version](https://img.shields.io/cocoapods/v/AdWinX.svg?style=flat)](https://cocoapods.org/pods/AdWinX)
[![License](https://img.shields.io/cocoapods/l/AdWinX.svg?style=flat)](https://cocoapods.org/pods/AdWinX)
[![Platform](https://img.shields.io/cocoapods/p/AdWinX.svg?style=flat)](https://cocoapods.org/pods/AdWinX)

## Example

To run the example project, clone the repo, and run `pod install` from the Example directory first.

## Requirements

## Installation

AdWinX 采用「核心 + 按需 Adapter」的多 pod 结构（核心零 ADN 依赖），
按需组合你想聚合的 ADN，未引入的 ADN 及其三方 SDK 完全不进包：

```ruby
# 例：只聚合穿山甲和百度
pod 'AdWinX/Core'     # 聚合核心：配置体系 / 拍卖引擎 / 统一入口
pod 'AdWinX-CSJ'      # 穿山甲 Adapter（自动带入 Ads-CN）
pod 'AdWinX-Baidu'    # 百度 Adapter（自动带入 BaiduMobAdSDK）

# 其它可选：AdWinX-GDT（优量汇）/ AdWinX-Sigmob
```

接入代码只需一行初始化——SDK 按已安装的 Adapter pod 自动发现注册并初始化，
无需手动 register：

```objc
[[ADXAdManager sharedManager] setupSDKWithAdnConfigs:nil completion:^(BOOL timedOut) {
    // 就绪即请求广告
    [[ADXAdManager sharedManager] loadSplashAdOnlyWithSlotName:@"splash_main"
                                                    completion:nil];
}];
```

说明：

- **三方 SDK 版本**由各 Adapter podspec 约束（如 `Ads-CN ~> 7.7`，允许小版本与
  bugfix 升级，大版本需等 Adapter 适配发版）；想在业务侧钉死某个验证过的组合，
  可在 Podfile 显式声明（如 `pod 'Ads-CN', '7.7.0.7'`，交集生效）
- **配置与包体解耦**：配置 JSON（内置或远程下发）里出现未安装 ADN 的广告源时，
  引擎按「未注册 ADN」同步失败跳过，不发请求不拖预算，日志/报表可见
- **按需裁剪**：想下掉某个 ADN，删 Podfile 对应行 + 配置移除对应广告源即可
- 特殊场景（如替换某 ADN 为自研 Adapter）仍可手动调用
  `registerAdapterClass:forAdnName:adType:`，手动注册优先于自动发现
- ADN 的 adapter 各自独立发版：改一家只发布对应 adapter pod（tag 格式
  `AdWinX-CSJ/0.1.0`），核心与其余 adapter 不受牵连

## 远程配置（可选）

SDK 默认使用内置配置（`AdWinX/Assets/adx_default_config.json`），开箱即用。
如需服务端动态下发配置（调档位 / 调超时 / 调 realEcpm），按以下方式接入：

### 1. 准备配置文件

在任意静态 HTTPS 文件托管（如阿里云 OSS）放一份 JSON，结构与内置配置完全一致，
`configVersion` 必须**大于**当前生效版本才会被接受（只升不降）。

### 2. 注入地址（setupSDK 之前）

```objc
[ADXConfigManager sharedManager].remoteConfigURL =
    [NSURL URLWithString:@"https://your-cdn.com/adx_config.json"];
```

### 3. 生效机制

- `setupSDKWithAdnConfigs:` 内部会自动后台拉取一次；也可随时手动调用：
  ```objc
  [[ADXConfigManager sharedManager] fetchRemoteConfigWithCompletion:^(BOOL updated, NSError *error) {
      // updated=YES：新版本已落盘并更新内存，下次广告请求生效
  }];
  ```
- 拉取为后台异步，**不阻塞** SDK 初始化与广告请求（冷启动开屏不等网络）
- 拉到新配置：校验（HTTPS / HTTP 200 / 结构解析 / 逐源必要字段）→ 版本比对 → 写磁盘 → 下次请求生效
- 拉取失败 / 未配置地址：静默降级，本地三层配置（内存 → 磁盘缓存 → 内置兜底）始终可用
- 内置防重入：上一次拉取未结束时重复调用直接跳过

### 远程日志开关

正式环境日志默认关闭（Release 构建 `Off`）。排障时在配置 JSON 的**全局层**加 `logLevel` 键下发：

```json
{
  "configVersion": 13,
  "logLevel": 2,
  "...": "..."
}
```

取值：`0`=Off / `1`=Error / `2`=Info / `3`=Debug（越界或缺失 = 不干预本地默认）。

- 生效时机：配置加载（冷启动）或远程更新落地时立即应用
- 配置不带该键时，维持本地默认（Debug 构建 Info / Release 构建 Off），
  也不影响业务方 `setLogLevel:` 的显式设置
- 配合 `drainLogFile`（Info 及以下同步落盘 `Caches/adx_debug.log`）实现无调试器回捞

### 错误码（domain: `com.adwinx.config`）

| code | 含义 |
|------|------|
| 1001 | 地址非 HTTPS |
| 1002 | HTTP 状态码非 200 |
| 1003 | 响应体为空 |
| 1004 | 配置校验失败（解析被拒绝，本地配置不受影响） |

> 版本比对规则：远程版本 ≤ 当前版本（含磁盘缓存）时忽略；SDK 发版升级内置配置时，
> 内置版本若高于磁盘缓存则自动覆盖旧缓存。

## 预加载（激励视频 / 插屏）

死亡复活、双倍奖励、关卡结算插屏等场景，用户在触发点等不起 4~6s 拍卖。
预加载把拍卖耗时前移到低感知时机（进关卡 / 关卡快结束），触发点毫秒级展示：

```objc
// 1. 进关卡时预载（内部走完整拍卖：竞价 + 瀑布 + 结算，SDK 按 slotName 持有）
[[ADXAdManager sharedManager] preloadRewardVideoAdWithSlotName:@"reward_revive"
                                                    completion:nil];

// 2. 死亡点复活时取走并立即展示（毫秒级）
ADXAuctionResult *result = [[ADXAdManager sharedManager] takeRewardVideoAdWithSlotName:@"reward_revive"];
if (result) {
    [[ADXAdManager sharedManager] showRewardVideoAdWithResult:result
        fromViewController:self
             rewardCallback:^(BOOL granted) { /* granted=YES 发奖复活 */ }
                 completion:nil];
} else {
    // 3. 无预载（未预载/无填充/已被取走）：现场 load 兜底（给用户 loading 提示）
}

// 4. 退出关卡时清理（释放 SDK 持有的广告对象）
[[ADXAdManager sharedManager] discardPreloadedAdWithSlotName:@"reward_revive"];
```

机制说明：

- **同一 slot 重复 preload 无损耗**：已有未取走的预载或正在预载时跳过请求；
  展示结束后补一次 preload 即完成「下次触发点」的轮换
- **取走即清**：`take...` 返回非 nil 后应立即调用对应 show 方法展示；
  重复 take 返回 nil
- **过期兜底两层**：SDK 展示降级链（按价格从高到低试其余候选）→ 全挂时业务现场 load
- **事件归因不失真**：预载与展示之间即使隔着其他位的 load，展示事件仍归因到预载的 slot
- 插屏同构：`preloadInterstitialAdWithSlotName:` / `takeInterstitialAdWithSlotName:`
- 开屏（冷启动已有品牌图垫底方案）与信息流（滚动时机驱动）不提供预载

## Author

mumabinggan, mumabinggan@163.com

## License

AdWinX is available under the MIT license. See the LICENSE file for more info.
