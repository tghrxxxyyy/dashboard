#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"

INSTALL_APP=false
if [[ "${1:-}" == "--install" ]]; then
    INSTALL_APP=true
fi

ICON_MASTER="Resources/AppIcon-1024.png"
ICONSET_DIR=".build/AppIcon.iconset"
ICON_FILE="Resources/AppIcon.icns"

echo "==> 生成 Workbench 应用图标"
swift Tools/GenerateAppIcon.swift "$ICON_MASTER"
rm -rf "$ICONSET_DIR"
mkdir -p "$ICONSET_DIR"
sips -z 16 16 "$ICON_MASTER" --out "$ICONSET_DIR/icon_16x16.png" >/dev/null
sips -z 32 32 "$ICON_MASTER" --out "$ICONSET_DIR/icon_16x16@2x.png" >/dev/null
sips -z 32 32 "$ICON_MASTER" --out "$ICONSET_DIR/icon_32x32.png" >/dev/null
sips -z 64 64 "$ICON_MASTER" --out "$ICONSET_DIR/icon_32x32@2x.png" >/dev/null
sips -z 128 128 "$ICON_MASTER" --out "$ICONSET_DIR/icon_128x128.png" >/dev/null
sips -z 256 256 "$ICON_MASTER" --out "$ICONSET_DIR/icon_128x128@2x.png" >/dev/null
sips -z 256 256 "$ICON_MASTER" --out "$ICONSET_DIR/icon_256x256.png" >/dev/null
sips -z 512 512 "$ICON_MASTER" --out "$ICONSET_DIR/icon_256x256@2x.png" >/dev/null
sips -z 512 512 "$ICON_MASTER" --out "$ICONSET_DIR/icon_512x512.png" >/dev/null
cp "$ICON_MASTER" "$ICONSET_DIR/icon_512x512@2x.png"
iconutil -c icns "$ICONSET_DIR" -o "$ICON_FILE"

echo "==> 编译 Release 版本"
swift build -c release

BIN=".build/release/Workbench"
APP="dist/Workbench.app"

echo "==> 打包 $APP"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/Workbench"
cp "$ICON_FILE" "$APP/Contents/Resources/AppIcon.icns"

cat > "$APP/Contents/Info.plist" <<'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key><string>Workbench</string>
    <key>CFBundleDisplayName</key><string>Workbench</string>
    <key>CFBundleIdentifier</key><string>com.workbench.app</string>
    <key>CFBundleVersion</key><string>2</string>
    <key>CFBundleShortVersionString</key><string>2.0</string>
    <key>CFBundleExecutable</key><string>Workbench</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleIconFile</key><string>AppIcon</string>
    <key>LSApplicationCategoryType</key><string>public.app-category.utilities</string>
    <key>LSMinimumSystemVersion</key><string>14.0</string>
    <key>NSPrincipalClass</key><string>NSApplication</string>
    <key>NSHighResolutionCapable</key><true/>
    <key>NSRequiresAquaSystemAppearance</key><false/>
</dict>
</plist>
EOF

echo "==> Ad-hoc 签名"
codesign --force --deep --sign - "$APP"

if [[ "$INSTALL_APP" == true ]]; then
    echo "==> 安装到 /Applications/Workbench.app"
    ditto "$APP" "/Applications/Workbench.app"
    /usr/bin/touch "/Applications/Workbench.app"
fi

echo "==> 完成：$APP"
