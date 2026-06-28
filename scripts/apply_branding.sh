#!/bin/bash
# =============================================================================
# apply_branding.sh — 从环境变量生成各平台品牌配置
#
# 用法:

# Prerequisite check: svg2png.py needs Pillow
python3 -c "from PIL import Image" 2>/dev/null || {
  echo "❌ Pillow (Python Imaging Library) is required for icon generation."
  echo "   Install: pip3 install Pillow"
  echo "   Or:      brew install pillow"
  echo "   Or:      sudo apt-get install python3-pil"
  exit 1
}
#   export APP_NAME="梯云纵"
#   export BUNDLE_ID="com.tiyunzong.app"
#   export COPYRIGHT="Copyright © 2024 梯云纵. All rights reserved."
#   ./scripts/apply_branding.sh
#
#   或者一次设置:
#   APP_NAME="梯云纵" BUNDLE_ID="com.tiyunzong.app" ./scripts/apply_branding.sh
#
#   也可以配合 flutter build:
#   flutter build macos --dart-define=APP_NAME=梯云纵 --dart-define=BUNDLE_ID=com.tiyunzong.app
#   然后在 Xcode Run Script 阶段调用此脚本（需从 FLUTTER_DART_DEFINES 中解码）.
# =============================================================================

set -euo pipefail

: "${APP_NAME:=梯云纵}"
: "${BUNDLE_ID:=com.tiyunzong.app}"
: "${COPYRIGHT:=Copyright © $(date +%Y) ${APP_NAME}. All rights reserved.}"
: "${APP_EXE_NAME:=hiddify}"           # Windows exe name (ASCII only)
: "${APP_PUBLISHER:=${APP_NAME}}"        # MSIX/Inno Setup publisher
: "${PUBLISHER_URL:=https://github.com/hiddify/hiddify-app}"  # Publisher URL (exe YAML)

# -------------------------------------------------------------------------
# 加载 config/.env（如有，覆盖默认值）
# -------------------------------------------------------------------------
CONFIG_FILE="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/config/.env"
if [ -f "$CONFIG_FILE" ]; then
  set -a
  source "$CONFIG_FILE"
  set +a
  echo "==> Loaded config/.env"
fi

# ── 版本号 ─────────────────────────────────────────────────────────────
# APP_VERSION 格式：X.Y.Z（如 1.0.0），同时影响 Flutter BUILD_NAME 和原生 MARKETING_VERSION
# APP_BUILD_NUMBER 为递增的构建号，影响 Flutter BUILD_NUMBER 和原生 CURRENT_PROJECT_VERSION
: "${APP_VERSION:=1.0.0}"
: "${APP_BUILD_NUMBER:=1}"
: "${URL_SCHEME:=hiddify}"

# ── --dart-defines 模式：输出所有 AppConfig 共用值的构建参数 ──
# 用法: flutter build ios --release \$(./scripts/apply_branding.sh --dart-defines)
# ──────────────────────────────────────────────────────────────────────────
if [ "${1:-}" = "--dart-defines" ]; then
  for key in APP_NAME BUNDLE_ID PRIVACY_URL TERMS_URL CONTACT_EMAIL APP_VERSION APP_BUILD_NUMBER PUBLISHER_URL CHAT_WIDGET_ID URL_SCHEME; do
    val="${!key:-}"
    [ -n "$val" ] && printf -- "--dart-define=%s=%s " "$key" "$val"
  done
  echo
  exit 0
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

echo "==> Applying branding: APP_NAME=$APP_NAME, BUNDLE_ID=$BUNDLE_ID"

# 跨平台 sed -i（macOS vs Linux）
sed_inplace() {
 if sed --version 2>/dev/null | head -1 | grep -q GNU; then
 sed -i "$@"
 else
 sed -i '' "$@"
 fi
}

# -------------------------------------------------------------------------
# macOS — 生成 BrandingOverride.xcconfig
# -------------------------------------------------------------------------
MACOS_OVERRIDE="$PROJECT_DIR/macos/Runner/Configs/BrandingOverride.xcconfig"
cat > "$MACOS_OVERRIDE" << EOF
// BrandingOverride.xcconfig — 由 apply_branding.sh 自动生成，请勿手动编辑
APP_NAME = $APP_NAME
PRODUCT_NAME = $APP_NAME
PRODUCT_BUNDLE_IDENTIFIER = $BUNDLE_ID
PRODUCT_COPYRIGHT = $COPYRIGHT
EOF
echo "  ✓ macOS override: $MACOS_OVERRIDE"

# -------------------------------------------------------------------------
# iOS — 更新 Base.xcconfig
# -------------------------------------------------------------------------
# iOS 用 Base.xcconfig（已纳入版本管理），直接覆写
IOS_BASE="$PROJECT_DIR/ios/Base.xcconfig"
sed_inplace "s|^APP_NAME=.*|APP_NAME=$APP_NAME|" "$IOS_BASE"
sed_inplace "s|^BASE_BUNDLE_IDENTIFIER=.*|BASE_BUNDLE_IDENTIFIER=$BUNDLE_ID|" "$IOS_BASE"
sed_inplace "s|^SERVICE_IDENTIFIER=.*|SERVICE_IDENTIFIER=\$(BASE_BUNDLE_IDENTIFIER).extension|" "$IOS_BASE"
echo "  ✓ iOS base: $IOS_BASE"

# -------------------------------------------------------------------------
# iOS Info.plist — 更新 CFBundleURLName（URL 所有者标识）
# 仅 macOS 构建机需要，Windows/Linux runner 自动跳过
# -------------------------------------------------------------------------
if [ "$(uname)" = "Darwin" ] && [ -f "$PROJECT_DIR/ios/Runner/Info.plist" ]; then
  IOS_URL_NAME=$(echo "$BUNDLE_ID" | sed 's/\.[^.]*$/.ios/')
  python3 << PYEOF
import plistlib
path = '$PROJECT_DIR/ios/Runner/Info.plist'
with open(path, 'rb') as f:
    pl = plistlib.load(f)
for i, t in enumerate(pl.get('CFBundleURLTypes', [])):
    if t.get('CFBundleURLName', '').startswith('com.'):
        pl['CFBundleURLTypes'][i]['CFBundleURLName'] = '$IOS_URL_NAME'
with open(path, 'wb') as f:
    plistlib.dump(pl, f)
print('  ✓ iOS URLName -> $IOS_URL_NAME')
PYEOF
fi

# =============================================================================
# 图标生成 — 从 assets/images/logo.svg 生成所有平台的 App Icon PNG
# 唯一源文件: assets/images/logo.svg（换 Logo 只改这一个，跑本脚本即同步全平台）
# =============================================================================
LOGO_SRC="$PROJECT_DIR/assets/images/logo.svg"
SVG2PNG="$PROJECT_DIR/scripts/svg2png.py"

if [ -f "$LOGO_SRC" ]; then
  echo "  ℹ Generating platform icons from $LOGO_SRC ..."

  # ── macOS AppIcon.appiconset ──────────────────────────────────────────
  MACOS_ICONSET="$PROJECT_DIR/macos/Runner/Assets.xcassets/AppIcon.appiconset"
  mkdir -p "$MACOS_ICONSET"

  python3 "$SVG2PNG" "$LOGO_SRC" "$MACOS_ICONSET/icon_16x16.png"       16
  python3 "$SVG2PNG" "$LOGO_SRC" "$MACOS_ICONSET/icon_16x16@2x.png"    32
  python3 "$SVG2PNG" "$LOGO_SRC" "$MACOS_ICONSET/icon_32x32.png"       32
  python3 "$SVG2PNG" "$LOGO_SRC" "$MACOS_ICONSET/icon_32x32@2x.png"    64
  python3 "$SVG2PNG" "$LOGO_SRC" "$MACOS_ICONSET/icon_128x128.png"    128
  python3 "$SVG2PNG" "$LOGO_SRC" "$MACOS_ICONSET/icon_128x128@2x.png" 256
  python3 "$SVG2PNG" "$LOGO_SRC" "$MACOS_ICONSET/icon_256x256.png"    256
  python3 "$SVG2PNG" "$LOGO_SRC" "$MACOS_ICONSET/icon_256x256@2x.png" 512
  python3 "$SVG2PNG" "$LOGO_SRC" "$MACOS_ICONSET/icon_512x512.png"    512
  python3 "$SVG2PNG" "$LOGO_SRC" "$MACOS_ICONSET/icon_512x512@2x.png" 1024

  python3 - "$MACOS_ICONSET" << 'ICONSET_JSON'
import json, sys
macos_iconset = sys.argv[1]
images = []
for fname,size,scale in [
  ('icon_16x16.png',    '16x16',   '1x'), ('icon_16x16@2x.png',    '16x16',   '2x'),
  ('icon_32x32.png',    '32x32',   '1x'), ('icon_32x32@2x.png',    '32x32',   '2x'),
  ('icon_128x128.png',  '128x128', '1x'), ('icon_128x128@2x.png',  '128x128', '2x'),
  ('icon_256x256.png',  '256x256', '1x'), ('icon_256x256@2x.png',  '256x256', '2x'),
  ('icon_512x512.png',  '512x512', '1x'), ('icon_512x512@2x.png',  '512x512', '2x'),
]:
  images.append({'size':size,'idiom':'mac','filename':fname,'scale':scale})
with open(f'{macos_iconset}/Contents.json','w') as f:
  json.dump({'images':images,'info':{'author':'xcode','version':1}}, f, indent=2)
ICONSET_JSON
  echo "  ✓ macOS AppIcon.appiconset (10 PNGs)"

  # ── iOS AppIcon.appiconset ────────────────────────────────────────────
  # iOS: one 1024×1024 PNG + Xcode auto-generates all smaller sizes
  # This matches the official HiddifyWithPanels approach — simpler and more reliable
  IOS_ICONSET="$PROJECT_DIR/ios/Runner/Assets.xcassets/AppIcon.appiconset"
  mkdir -p "$IOS_ICONSET"
  # Clean stale multi-size PNGs from old approach (but NOT the 1024 we're about to write)
  rm -f "$IOS_ICONSET"/app-icon-20*.png "$IOS_ICONSET"/app-icon-29*.png \
        "$IOS_ICONSET"/app-icon-40*.png "$IOS_ICONSET"/app-icon-60*.png \
        "$IOS_ICONSET"/app-icon-76*.png "$IOS_ICONSET"/app-icon-83*.png 2>/dev/null
  python3 "$SVG2PNG" "$LOGO_SRC" "$IOS_ICONSET/app-icon-1024.png"  1024
  cat > "$IOS_ICONSET/Contents.json" << 'ICONS_JSON'
{
  "images" : [
    {
      "filename" : "app-icon-1024.png",
      "idiom" : "universal",
      "platform" : "ios",
      "size" : "1024x1024"
    }
  ],
  "info" : {
    "author" : "xcode",
    "version" : 1
  }
}
ICONS_JSON
  echo "  ✓ iOS AppIcon (1 PNG, Xcode auto-generates sizes)"

  # ── Android mipmap icons ──────────────────────────────────────────────
  #    mdpi=48  hdpi=72  xhdpi=96  xxhdpi=144  xxxhdpi=192
  ANDROID_RES="$PROJECT_DIR/android/app/src/main/res"
  for pair in mdpi:48 hdpi:72 xhdpi:96 xxhdpi:144 xxxhdpi:192; do
    density="${pair%%:*}"; icon_size="${pair##*:}"
    res_dir="$ANDROID_RES/mipmap-${density}"
    mkdir -p "$res_dir"
    python3 "$SVG2PNG" "$LOGO_SRC" "$res_dir/ic_launcher.png"        "$icon_size" "$icon_size"
    python3 "$SVG2PNG" "$LOGO_SRC" "$res_dir/ic_launcher_round.png"  "$icon_size" "$icon_size"
  done
  echo "  ✓ Android mipmap ic_launcher / ic_launcher_round (10 PNGs)"

  # ── Linux generic icon (for DEB/AppImage packaging) ──────────────
  mkdir -p "$PROJECT_DIR/assets/images"
  python3 "$SVG2PNG" "$LOGO_SRC" "$PROJECT_DIR/assets/images/icon.png" 512 512
  echo "  ✓ Linux packaging icon (assets/images/icon.png)"

  # ── System tray icons (Windows / macOS / Linux) ──────────────────
  TRAYGEN="$PROJECT_DIR/scripts/generate_tray_icons.py"
  if [ -f "$TRAYGEN" ]; then
    python3 "$TRAYGEN" "$LOGO_SRC" "$PROJECT_DIR/assets/images"
  else
    echo "  ⚠ $TRAYGEN not found, skipping tray icons"
  fi

else
  echo "  ⚠ $LOGO_SRC not found, skipping icon generation"
fi

# -------------------------------------------------------------------------
# Android — 更新 build.gradle（applicationId + manifestPlaceholders）
# -------------------------------------------------------------------------
ANDROID_GRADLE="$PROJECT_DIR/android/app/build.gradle"
sed_inplace "s|applicationId \".*\"|applicationId \"$BUNDLE_ID\"|" "$ANDROID_GRADLE"
sed_inplace "s|appName: \".*\"|appName: \"$APP_NAME\"|" "$ANDROID_GRADLE"
echo "  ✓ Android gradle: $ANDROID_GRADLE"
# 注意：namespace 未自动修改，因为 Kotlin 源码中大量引用 R / BuildConfig，
# 需要同时移动 android/app/src/main/kotlin/ 目录结构才能生效。
# 如果要修改 namespace，手动执行：
#   mv com/hiddify/hiddify com/tiyunzong/app 并更新所有 import

# -------------------------------------------------------------------------
# Windows — 导出环境变量供 CMake 读取（branding.cmake 通过 $ENV{} 获取）
# -------------------------------------------------------------------------
export APP_NAME
export APP_EXE_NAME
export APP_COPYRIGHT="$COPYRIGHT"
export APP_PUBLISHER
export BUNDLE_ID
echo "  ✓ Windows env vars exported: APP_NAME=$APP_NAME, APP_EXE_NAME=$APP_EXE_NAME"

# -------------------------------------------------------------------------
# Windows — 生成 BrandingOverride.cmake（覆盖 branding.cmake 默认值）
# -------------------------------------------------------------------------
WINDOWS_OVERRIDE="$PROJECT_DIR/windows/BrandingOverride.cmake"
cat > "$WINDOWS_OVERRIDE" << EOF
# BrandingOverride.cmake — 由 apply_branding.sh 自动生成，请勿手动编辑
set(APP_NAME "$APP_NAME")
set(APP_EXE_NAME "$APP_EXE_NAME")
set(APP_COPYRIGHT "$COPYRIGHT")
set(APP_PUBLISHER "$APP_PUBLISHER")
set(APP_IDENTITY_NAME "${APP_EXE_NAME}.HiddifyNext")
set(APP_ALIAS "${APP_EXE_NAME}")
set(APP_SERVICE_NAME "${APP_EXE_NAME}TunnelService")
set(APP_USERDATA_DIR "${APP_NAME}")
EOF
echo "  ✓ Windows override: $WINDOWS_OVERRIDE"

# -------------------------------------------------------------------------
# Windows — 更新 BINARY_NAME（msix 包用正则解析 CMakeLists.txt，不识别变量）
# https://github.com/YehudaKremer/msix/blob/master/lib/src/configuration.dart
# -------------------------------------------------------------------------
WINDOWS_CMAKE="$PROJECT_DIR/windows/CMakeLists.txt"
sed_inplace "s|^set(BINARY_NAME \".*\")$|set(BINARY_NAME \"$APP_EXE_NAME\")|" "$WINDOWS_CMAKE"
echo "  ✓ Windows BINARY_NAME -> $APP_EXE_NAME in $WINDOWS_CMAKE"

# -------------------------------------------------------------------------
# pubspec.yaml — 更新版本号（影响 Flutter BUILD_NAME/BUILD_NUMBER)
# -------------------------------------------------------------------------
# Flutter 从 pubspec.yaml 读取 version: X.Y.Z+N 作为 FLUTTER_BUILD_NAME / FLUTTER_BUILD_NUMBER
# 然后写入 iOS/macOS Info.plist 的 CFBundleShortVersionString / CFBundleVersion
PUBSPEC="$PROJECT_DIR/pubspec.yaml"
sed_inplace "s|^version: .*|version: ${APP_VERSION}+${APP_BUILD_NUMBER}|" "$PUBSPEC"
echo "  ✓ pubspec.yaml version -> ${APP_VERSION}+${APP_BUILD_NUMBER}"

# -------------------------------------------------------------------------
# iOS pbxproj — 更新 MARKETING_VERSION / CURRENT_PROJECT_VERSION
# 仅 macOS 构建机需要，Windows/Linux runner 自动跳过
# -------------------------------------------------------------------------
if [ "$(uname)" = "Darwin" ] && [ -f "$PROJECT_DIR/ios/Runner.xcodeproj/project.pbxproj" ]; then
  sed_inplace "s|MARKETING_VERSION = [0-9.]*;|MARKETING_VERSION = $APP_VERSION;|g" "$PROJECT_DIR/ios/Runner.xcodeproj/project.pbxproj"
  sed_inplace "s|CURRENT_PROJECT_VERSION = [0-9]*;|CURRENT_PROJECT_VERSION = $APP_BUILD_NUMBER;|g" "$PROJECT_DIR/ios/Runner.xcodeproj/project.pbxproj"
  echo "  ✓ iOS pbxproj MARKETING_VERSION -> $APP_VERSION, CURRENT_PROJECT_VERSION -> $APP_BUILD_NUMBER"
fi

# -------------------------------------------------------------------------
# macOS pbxproj — 更新 MARKETING_VERSION / CURRENT_PROJECT_VERSION
# 仅 macOS 构建机需要，Windows/Linux runner 自动跳过
# -------------------------------------------------------------------------
if [ "$(uname)" = "Darwin" ] && [ -f "$PROJECT_DIR/macos/Runner.xcodeproj/project.pbxproj" ]; then
  sed_inplace "s|MARKETING_VERSION = [0-9.]*;|MARKETING_VERSION = $APP_VERSION;|g" "$PROJECT_DIR/macos/Runner.xcodeproj/project.pbxproj"
  sed_inplace "s|CURRENT_PROJECT_VERSION = [0-9]*;|CURRENT_PROJECT_VERSION = $APP_BUILD_NUMBER;|g" "$PROJECT_DIR/macos/Runner.xcodeproj/project.pbxproj"
  echo "  ✓ macOS pbxproj MARKETING_VERSION -> $APP_VERSION, CURRENT_PROJECT_VERSION -> $APP_BUILD_NUMBER"
fi

# -------------------------------------------------------------------------
# Packaging YAML — 从 .tmpl 模板生成（不修改 git 跟踪的文件）
# -------------------------------------------------------------------------

echo ""
echo "==> Generating packaging YAMLs from templates..."

# Template substitution: 读取 .tmpl，替换占位符，写入 .yaml
brand_template() {
  local tmpl="$1"
  local out="$2"
  mkdir -p "$(dirname "$out")"
  sed \
    -e "s|{{APP_NAME}}|$APP_NAME|g" \
    -e "s|{{APP_EXE_NAME}}|$APP_EXE_NAME|g" \
    -e "s|{{APP_PUBLISHER}}|$APP_PUBLISHER|g" \
    -e "s|{{PUBLISHER_URL}}|$PUBLISHER_URL|g" \
    "$tmpl" > "$out"
  echo "  ✓ $out"
}

brand_template "$PROJECT_DIR/windows/packaging/msix/make_config.yaml.tmpl" \
  "$PROJECT_DIR/windows/packaging/msix/make_config.yaml"

brand_template "$PROJECT_DIR/windows/packaging/exe/make_config.yaml.tmpl" \
  "$PROJECT_DIR/windows/packaging/exe/make_config.yaml"

brand_template "$PROJECT_DIR/macos/packaging/dmg/make_config.yaml.tmpl" \
  "$PROJECT_DIR/macos/packaging/dmg/make_config.yaml"

brand_template "$PROJECT_DIR/ios/packaging/ios/make_config.yaml.tmpl" \
  "$PROJECT_DIR/ios/packaging/ios/make_config.yaml"

brand_template "$PROJECT_DIR/linux/packaging/deb/make_config.yaml.tmpl" \
  "$PROJECT_DIR/linux/packaging/deb/make_config.yaml"

brand_template "$PROJECT_DIR/linux/packaging/appimage/make_config.yaml.tmpl" \
  "$PROJECT_DIR/linux/packaging/appimage/make_config.yaml"

brand_template "$PROJECT_DIR/linux/packaging/rpm/make_config.yaml.tmpl" \
  "$PROJECT_DIR/linux/packaging/rpm/make_config.yaml"

echo ""
echo "==> Branding complete. Run 'make <target>' to build."
