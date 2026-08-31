#
# Be sure to run `pod lib lint AdWinX.podspec' to ensure this is a
# valid spec before submitting.
#
# Any lines starting with a # are optional, but their use is encouraged
# To learn more about a Podspec see https://guides.cocoapods.org/syntax/podspec.html
#

Pod::Spec.new do |s|
  s.name             = 'AdWinX'
  s.version          = '0.1.0'
  s.summary          = 'A short description of AdWinX.'

# This description is used to generate tags and improve search results.
#   * Think: What does it do? Why did you write it? What is the focus?
#   * Try to keep it short, snappy and to the point.
#   * Write the description between the DESC delimiters below.
#   * Finally, don't worry about the indent, CocoaPods strips it!

  s.description      = <<-DESC
TODO: Add long description of the pod here.
                       DESC

  s.homepage         = 'https://github.com/mumabinggan/AdWinX'
  # s.screenshots     = 'www.example.com/screenshots_1', 'www.example.com/screenshots_2'
  s.license          = { :type => 'MIT', :file => 'LICENSE' }
  s.author           = { 'mumabinggan' => 'mumabinggan@163.com' }
  s.source           = { :git => 'https://github.com/mumabinggan/AdWinX.git', :tag => s.version.to_s }
  # s.social_media_url  = 'https://twitter.com/<TWITHUB_USERNAME>'

  s.ios.deployment_target = '12.0'

  # 聚合核心（本 pod 仅含 Core）：
  # 数据模型 / 配置体系 / 拍卖引擎 / 统一入口 / Adapter 自动发现注册，零 ADN SDK 依赖。
  # 各 ADN 的 Adapter 在独立 pod 中（AdWinX-CSJ / AdWinX-GDT / AdWinX-Sigmob / AdWinX-Baidu），
  # 接入方按需组合：
  #   pod 'AdWinX/Core'
  #   pod 'AdWinX-CSJ'
  #   pod 'AdWinX-Baidu'
  # 装了哪些 ADN 的 Adapter，setupSDK 时就自动注册并初始化哪些，无需手动 register。
  s.subspec 'Core' do |ss|
    ss.source_files = 'Classes/*.h', 'Classes/{Core,Protocol,Engine,Manager}/**/*'
    # 内置兜底配置等资源，单独打 bundle 避免与接入方资源冲突
    ss.resource_bundles = {
      'AdWinX' => ['Assets/**/*']
    }
  end
end
