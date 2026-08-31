#
# 穿山甲（CSJ）Adapter pod：开屏 / 激励视频 / 插屏 / 信息流
#
# 依赖范围 ~> 7.7：允许 7.x 内的小版本与 bugfix 升级，大版本（8.0）升级需等本 pod 适配发版
#

Pod::Spec.new do |s|
  s.name             = 'AdWinX-CSJ'
  s.version          = '0.1.0'
  s.summary          = 'AdWinX adapter for CSJ (穿山甲).'

  s.description      = <<-DESC
AdWinX 聚合 SDK 的穿山甲（CSJ）Adapter，覆盖开屏/激励视频/插屏/信息流广告类型。
与 AdWinX/Core 组合使用，setupSDK 时自动发现注册。
                       DESC

  s.homepage         = 'https://github.com/mumabinggan/AdWinX'
  s.license          = { :type => 'MIT', :file => 'LICENSE' }
  s.author           = { 'mumabinggan' => 'mumabinggan@163.com' }
  s.source           = { :git => 'https://github.com/mumabinggan/AdWinX.git', :tag => "#{s.name}/#{s.version}" }

  s.ios.deployment_target = '12.0'

  s.source_files = 'Classes/**/*'
  s.dependency 'AdWinX/Core'
  s.dependency 'Ads-CN', '~> 7.7'
end
