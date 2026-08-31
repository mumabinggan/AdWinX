#!/bin/bash
#
# AdWinX 二进制打包脚本（自包含：临时 Podfile + pod install + xcodebuild 直编 Pods 工程）
#
# 用法：
#   ./Package/build.sh                # 打包全部 5 个 pod
#   ./Package/build.sh AdWinX-GDT     # 只打包 GDT（改一家发一家）
#
# 链路：
#   1. 临时目录生成 Podfile（目标 pod 以 :path 引本地源码，Core 依赖同样 :path，
#      未提交的工作区改动也会被打入产物）
#   2. pod install → xcodebuild 分别编译 iphoneos(arm64) / iphonesimulator(x86_64)
#   3. xcodebuild -create-xcframework 合成标准 xcframework
#
# 产物（Binary/<Pod>/）：
#   <Pod>.xcframework        静态 xcframework（真机 arm64 + 模拟器 x86_64）
#   <Pod>.podspec            二进制版 podspec（版本号与源码版同步）
#   <Pod>.xcframework.zip    Release 上传用（解压即 pod 根目录布局）
#
# 发版后续步骤（手动）：
#   1. Example/Podfile 里 use_binary 改 true → pod install → 真机验证 → 改回 false
#   2. GitHub 网页建 Release（tag：<Pod>/<version>）→ 拖入 Binary/<Pod>/ 下的 zip
#   3. pod repo push adwinx-specs Binary/<Pod>/<Pod>.podspec
#   4. git commit + tag <Pod>/<version> + push
#
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

ALL_PODS="AdWinX AdWinX-CSJ AdWinX-GDT AdWinX-Sigmob AdWinX-Baidu"
PODS="${@:-$ALL_PODS}"
BUILD_ROOT="$ROOT/Package/.build"

command -v pod >/dev/null 2>&1 || { echo "❌ 未找到 pod 命令，请先安装 CocoaPods"; exit 1; }

fail() { echo "❌ $1"; exit 1; }

for POD in $PODS; do
  SPEC="$ROOT/$POD/$POD.podspec"
  TEMPLATE="$ROOT/Package/templates/$POD.podspec.template"
  [ -f "$SPEC" ]     || fail "找不到 $SPEC"
  [ -f "$TEMPLATE" ] || fail "找不到模板 $TEMPLATE"

  # 从源码 podspec 读版本号（唯一真实版本源）
  VER=$(pod ipc spec "$SPEC" | ruby -rjson -e "puts JSON.parse(STDIN.read)['version']")
  echo ""
  echo "==> 打包 $POD $VER"

  # ------------------------------------------------------------------
  # 1. 临时 Podfile：目标 pod 与 Core 依赖全部走 :path 本地源码，
  #    三方 SDK（GDTMobSDK 等）从 CDN 解析（仅用于编译期提供头文件）
  # ------------------------------------------------------------------
  WORK="$BUILD_ROOT/$POD"
  rm -rf "$WORK"
  mkdir -p "$WORK"

  {
    echo "platform :ios, '12.0'"
    echo "install! 'cocoapods', :integrate_targets => false"
    echo "use_frameworks! :linkage => :static"
    echo ""
    echo "target 'AdWinX-Package' do"
    if [ "$POD" = "AdWinX" ]; then
      echo "  pod 'AdWinX/Core', :path => '$ROOT/AdWinX'"
    else
      echo "  pod 'AdWinX/Core', :path => '$ROOT/AdWinX'"
      echo "  pod '$POD', :path => '$ROOT/$POD'"
    fi
    echo "end"
  } > "$WORK/Podfile"

  (cd "$WORK" && pod install)

  PODS_PROJ="$WORK/Pods/Pods.xcodeproj"
  [ -d "$PODS_PROJ" ] || fail "pod install 未生成 $PODS_PROJ"

  # ------------------------------------------------------------------
  # 2. xcodebuild 双平台编译（静态 framework target，无需签名）
  # ------------------------------------------------------------------
  xcodebuild -project "$PODS_PROJ" -target "$POD" -configuration Release \
    -sdk iphoneos ARCHS=arm64 ONLY_ACTIVE_ARCH=NO \
    CODE_SIGNING_ALLOWED=NO \
    CONFIGURATION_BUILD_DIR="$WORK/out/iphoneos" -quiet build

  xcodebuild -project "$PODS_PROJ" -target "$POD" -configuration Release \
    -sdk iphonesimulator ARCHS=x86_64 ONLY_ACTIVE_ARCH=NO \
    CODE_SIGNING_ALLOWED=NO \
    CONFIGURATION_BUILD_DIR="$WORK/out/simulator" -quiet build

  # Xcode 生成产物时会把 target 名中的连字符替换为下划线（AdWinX-GDT → AdWinX_GDT）
  FW_NAME="${POD//-/_}"

  FW_DEV=$(find "$WORK/out/iphoneos" -name "$FW_NAME.framework" -type d | head -1)
  FW_SIM=$(find "$WORK/out/simulator" -name "$FW_NAME.framework" -type d | head -1)
  [ -n "$FW_DEV" ] || fail "未产出真机 framework（iphoneos 构建目录无 $FW_NAME.framework）"
  [ -n "$FW_SIM" ] || fail "未产出模拟器 framework（simulator 构建目录无 $FW_NAME.framework）"

  # 清理 framework 内嵌资源 bundle（资源由二进制 podspec 的 resource_bundles 分发，避免重名冲突）
  find "$FW_DEV" "$FW_SIM" -name "*.bundle" -type d -exec rm -rf {} + 2>/dev/null || true
  find "$FW_DEV" "$FW_SIM" -name "*.dSYM" -exec rm -rf {} + 2>/dev/null || true

  # ------------------------------------------------------------------
  # 3. 合成 xcframework
  # ------------------------------------------------------------------
  DEST="$ROOT/Binary/$POD"
  rm -rf "$DEST"
  mkdir -p "$DEST"
  xcodebuild -create-xcframework \
    -framework "$FW_DEV" \
    -framework "$FW_SIM" \
    -output "$DEST/$POD.xcframework" >/dev/null

  # ------------------------------------------------------------------
  # 4. Core 特例：内置配置 JSON 等资源不进 framework，随 pod 目录分发
  # ------------------------------------------------------------------
  if [ "$POD" = "AdWinX" ]; then
    mkdir -p "$DEST/Assets"
    cp "$ROOT"/AdWinX/Assets/* "$DEST/Assets/" 2>/dev/null || true
  fi

  # ------------------------------------------------------------------
  # 5. 渲染二进制 podspec（模板占位符 → 实际值）
  # ------------------------------------------------------------------
  RELEASE_TAG="$POD/$VER"
  if [ "$POD" = "AdWinX" ]; then
    RELEASE_TAG="$VER"   # Core 的 tag 无前缀，与源码 podspec 约定一致
  fi
  sed -e "s/__VERSION__/$VER/g" \
      -e "s|__RELEASE_TAG__|$RELEASE_TAG|g" \
      "$TEMPLATE" > "$DEST/$POD.podspec"

  # ------------------------------------------------------------------
  # 6. 产出 Release 上传用 zip（含 podspec + xcframework [+ Assets]，
  #    解压后即 pod 根目录布局，与 podspec 内 s.source 的 :http 直链对应）
  # ------------------------------------------------------------------
  (cd "$DEST" && zip -qry "$POD.xcframework.zip" "$POD.xcframework" "$POD.podspec" $( [ "$POD" = "AdWinX" ] && echo Assets ))
  rm -rf "$WORK"

  echo "✅ $POD $VER → $DEST/"
  echo "   下一步："
  echo "   ① 验证：Example/Podfile 改 use_binary = true → pod install → 真机跑"
  echo "   ② 上传：GitHub Release（tag: ${RELEASE_TAG}）拖入 $DEST/$POD.xcframework.zip"
  echo "   ③ 发布：pod repo push adwinx-specs $DEST/$POD.podspec"
done

echo ""
echo "全部完成。产物目录：$ROOT/Binary/"
