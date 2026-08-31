#
# Sigmob Adapter pod：开屏 / 激励视频 / 插屏
#
# 依赖范围 ~> 5.1：允许 5.x 内的小版本与 bugfix 升级，大版本（6.0）升级需等本 pod 适配发版
#

Pod::Spec.new do |s|
  s.name             = 'AdWinX-Sigmob'
  s.version          = '0.1.0'
  s.summary          = 'AdWinX adapter for Sigmob.'

  s.description      = <<-DESC
AdWinX 聚合 SDK 的 Sigmob Adapter，覆盖开屏/激励视频/插屏广告类型。
与 AdWinX/Core 组合使用，setupSDK 时自动发现注册。
                       DESC

  s.homepage         = 'https://github.com/mumabinggan/AdWinX'
  s.license          = { :type => 'MIT', :file => 'LICENSE' }
  s.author           = { 'mumabinggan' => 'mumabinggan@163.com' }
  s.source           = { :git => 'https://github.com/mumabinggan/AdWinX.git', :tag => "#{s.name}/#{s.version}" }

  s.ios.deployment_target = '12.0'

  s.source_files = 'Classes/**/*'
  s.dependency 'AdWinX/Core'
  s.dependency 'SigmobAd-iOS', '~> 5.1'
end
