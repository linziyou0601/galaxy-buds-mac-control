#!/bin/bash
# 用法：bash package.sh
# 輸出：dist/ 下的版本化 DMG 與 .sha256，每次取代同名產物。
# 先建置 App，封裝暫存目錄於腳本結束時清理。
set -euo pipefail
cd "$(dirname "$0")"

# 本機與 pipeline 使用同一個建置入口，版本由來源 plist 提供。
bash build.sh

APP_NAME=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleName' Sources/Resources/Info.plist)
APP="dist/$APP_NAME.app"
VERSION=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP/Contents/Info.plist")
ARCH=$(lipo -archs "$APP/Contents/MacOS/BudsApp" | tr ' ' '-')
DMG="dist/Galaxy-Buds-Mac-Control-$VERSION-macOS-$ARCH.dmg"

# 暫存內容限定於此次封裝，離開時清理，App 產物保留供檢查。
STAGE=$(mktemp -d .build/dmg-stage.XXXXXX)
trap 'rm -rf "$STAGE"' EXIT
ditto "$APP" "$STAGE/$APP_NAME.app"
ln -s /Applications "$STAGE/Applications"

# Apple 原生磁碟映像保存 App 與 Applications 捷徑，封裝後檢查完整性。
hdiutil create \
    -volname "$APP_NAME" \
    -srcfolder "$STAGE" \
    -ov -format UDZO \
    "$DMG"
hdiutil verify "$DMG"
shasum -a 256 "$DMG" > "$DMG.sha256"
printf 'Packaged: %s\n' "$DMG"
