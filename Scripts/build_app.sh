#!/bin/bash
# HealthReaderLite 一键构建脚本：编译 + 打包 .app + 图标 + 签名
set -euo pipefail
cd "$(dirname "$0")/.."

CONFIG="${1:-release}"
BUILD_DIR="build"
APP="$BUILD_DIR/HealthReaderLite.app"

echo "== 1/5 编译（-c ${CONFIG}）=="
swift build -c "${CONFIG}" --scratch-path ".build-${CONFIG}" \
    --cache-path .spm/cache --config-path .spm/config --security-path .spm/security

BIN=".build-${CONFIG}/${CONFIG}/HealthReaderLite"

echo "== 2/5 生成应用图标 =="
mkdir -p Scripts/out
swift Scripts/gen_icon.swift Scripts/out/icon_1024.png >/dev/null
ICONSET="Scripts/out/AppIcon.iconset"
rm -rf "$ICONSET"; mkdir -p "$ICONSET"
for spec in "16:16" "32:32" "128:128" "256:256" "512:512"; do
  s="${spec%%:*}"; d="${spec##*:}"
  sips -z "$s" "$s" Scripts/out/icon_1024.png --out "$ICONSET/icon_${d}x${d}.png" >/dev/null
  d2=$((d * 2))
  sips -z "$s" "$s" Scripts/out/icon_1024.png --out "$ICONSET/icon_${d}x${d}@2x.png" >/dev/null
done
# 修正 retina 尺寸（@2x 需要是 2x 像素）
sips -z 32 32 Scripts/out/icon_1024.png --out "$ICONSET/icon_16x16.png" >/dev/null
sips -z 64 64 Scripts/out/icon_1024.png --out "$ICONSET/icon_16x16@2x.png" >/dev/null
sips -z 64 64 Scripts/out/icon_1024.png --out "$ICONSET/icon_32x32.png" >/dev/null
sips -z 128 128 Scripts/out/icon_1024.png --out "$ICONSET/icon_32x32@2x.png" >/dev/null
sips -z 256 256 Scripts/out/icon_1024.png --out "$ICONSET/icon_128x128.png" >/dev/null
sips -z 512 512 Scripts/out/icon_1024.png --out "$ICONSET/icon_128x128@2x.png" >/dev/null
sips -z 512 512 Scripts/out/icon_1024.png --out "$ICONSET/icon_256x256.png" >/dev/null
sips -z 1024 1024 Scripts/out/icon_1024.png --out "$ICONSET/icon_256x256@2x.png" >/dev/null
sips -z 1024 1024 Scripts/out/icon_1024.png --out "$ICONSET/icon_512x512.png" >/dev/null
sips -z 1024 1024 Scripts/out/icon_1024.png --out "$ICONSET/icon_512x512@2x.png" >/dev/null
iconutil -c icns "$ICONSET" -o Scripts/out/AppIcon.icns
echo "  AppIcon.icns 已生成"

echo "== 3/5 组装 .app 包 =="
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/HealthReaderLite"
cp Scripts/out/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
cp Scripts/Info.plist "$APP/Contents/Info.plist"
chmod +x "$APP/Contents/MacOS/HealthReaderLite"

echo "== 4/5 代码签名（ad-hoc）=="
codesign --force --deep --sign - "$APP" 2>/dev/null || codesign --force --sign - "$APP"

echo "== 5/5 完成 =="
echo "📦 $APP"
echo "运行: open $APP"