#!/bin/zsh
# 編譯並安裝 AssetBook.app 到「應用程式」資料夾（不需要 Xcode）。
# 用法：./build-app.sh            編譯並安裝
#       ./build-app.sh --no-install 只編譯到 build/AssetBook.app
set -euo pipefail
cd "${0:A:h}"

APP_NAME="AssetBook"
DISPLAY_NAME="資產簿"
BUNDLE_ID="com.james101511.assetbook"
VERSION="1.0"
BUILD="$(date +%Y%m%d%H%M)"
APP="build/$APP_NAME.app"

# 部分 Command Line Tools 版本同時有 module.modulemap 與 bridging.modulemap，
# 會造成 "redefinition of module 'SwiftBridging'"。用 VFS overlay 遮掉重複的那一個。
SWIFT_INCLUDE="$(xcode-select -p)/usr/include/swift"
EXTRA_FLAGS=()
if [[ -f "$SWIFT_INCLUDE/module.modulemap" && -f "$SWIFT_INCLUDE/bridging.modulemap" ]]; then
    mkdir -p build/vfs
    : > build/vfs/empty.modulemap
    cat > build/vfs/overlay.yaml <<YAML
{ "version": 0, "case-sensitive": "false", "roots": [ { "type": "directory", "name": "$SWIFT_INCLUDE",
  "contents": [ { "type": "file", "name": "module.modulemap", "external-contents": "$PWD/build/vfs/empty.modulemap" } ] } ] }
YAML
    EXTRA_FLAGS=(-vfsoverlay build/vfs/overlay.yaml -Xcc -ivfsoverlay -Xcc build/vfs/overlay.yaml)
fi

echo "▸ 編譯中（約 1 分鐘）…"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
swiftc -O -parse-as-library -target "$(uname -m)-apple-macosx15.0" \
    "${EXTRA_FLAGS[@]}" Sources/AssetBook/*.swift -o "$APP/Contents/MacOS/$APP_NAME"

cp Resources/AppIcon.icns "$APP/Contents/Resources/"
cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key><string>$APP_NAME</string>
    <key>CFBundleIdentifier</key><string>$BUNDLE_ID</string>
    <key>CFBundleName</key><string>$APP_NAME</string>
    <key>CFBundleDisplayName</key><string>$DISPLAY_NAME</string>
    <key>CFBundleIconFile</key><string>AppIcon</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>$VERSION</string>
    <key>CFBundleVersion</key><string>$BUILD</string>
    <key>CFBundleDevelopmentRegion</key><string>zh_TW</string>
    <key>LSApplicationCategoryType</key><string>public.app-category.finance</string>
    <key>LSMinimumSystemVersion</key><string>15.0</string>
    <key>NSHighResolutionCapable</key><true/>
    <key>NSHumanReadableCopyright</key><string>James</string>
</dict>
</plist>
PLIST

echo "▸ 本機簽章…"
codesign --force --deep --sign - "$APP"

if [[ "${1:-}" == "--no-install" ]]; then
    echo "✓ 完成：$APP"
    exit 0
fi

DEST="/Applications"
[[ -w "$DEST" ]] || DEST="$HOME/Applications"
pkill -x "$APP_NAME" 2>/dev/null || true
rm -rf "$DEST/$APP_NAME.app"
cp -R "$APP" "$DEST/"
touch "$DEST/$APP_NAME.app"   # 讓 Finder / Launchpad 更新圖示
echo "✓ 已安裝到 $DEST/$APP_NAME.app"
open "$DEST/$APP_NAME.app"
