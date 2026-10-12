#!/bin/bash
# 用法：bash build.sh
# 輸出：dist/<App 名稱>.app，每次建置取代同名產物。
# 版本來自來源 Info.plist，BUDS_RELEASE_TAG 僅供發行一致性檢查。
# BUDS_SIGN_IDENTITY 指定簽章身分，預設使用 ad-hoc。
set -euo pipefail
cd "$(dirname "$0")"

# 來源版本在編譯前驗證，發行標籤僅用於比對已提交的版本。
python3 - <<'PY_VERSION'
import os
import plistlib
import re
from pathlib import Path

info = plistlib.loads(Path("Sources/Resources/Info.plist").read_bytes())
version = info["CFBundleShortVersionString"]
build = info["CFBundleVersion"]
# 發行版本與建置編號維持單一可比較格式，錯誤輸入立即停止。
if not re.fullmatch(r"(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)", version):
    raise SystemExit("App 版本必須為 X.Y.Z")
if not re.fullmatch(r"[1-9][0-9]*", build):
    raise SystemExit("建置編號必須為正整數")
tag = os.environ.get("BUDS_RELEASE_TAG", "v" + version)
# 標籤驗證只比對來源，來源與產物的版本均不由 pipeline 改寫。
if tag != "v" + version:
    raise SystemExit(f"標籤 {tag} 與 App 版本 {version} 不一致")
print(f"Building version {version} ({build})")
PY_VERSION

# 選擇工具鏈與 SDK，再編譯 release 執行檔。
source scripts/developer-environment.sh
SDK_VERSION=$(xcrun --sdk "$BUDS_SDK_PATH" --show-sdk-version)
MINIMUM_VERSION=$(/usr/libexec/PlistBuddy -c 'Print :LSMinimumSystemVersion' Sources/Resources/Info.plist)
# 將實際 SDK 與部署下限交給 linker，供 AppKit 選用對應的原生介面行為。
xcrun swift build --sdk "$BUDS_SDK_PATH" -c release \
    -Xlinker -platform_version -Xlinker macos -Xlinker "$MINIMUM_VERSION" -Xlinker "$SDK_VERSION"
BINARY_DIR=$(xcrun swift build --sdk "$BUDS_SDK_PATH" -c release --show-bin-path)
APP_NAME=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleName' Sources/Resources/Info.plist)
APP="dist/$APP_NAME.app"

# 建立標準 App bundle，來源 plist 提供名稱、版本與權限說明。
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BINARY_DIR/BudsApp" "$APP/Contents/MacOS/BudsApp"
cp Sources/Resources/Info.plist "$APP/Contents/Info.plist"

# 原生 .icon 由 Apple 資產編譯器產生當代資產與舊系統 ICNS，外框由系統套用。
xcrun actool Sources/Resources/AppIcon.icon \
    --compile "$APP/Contents/Resources" --platform macosx \
    --minimum-deployment-target "$MINIMUM_VERSION" --app-icon AppIcon \
    --output-partial-info-plist .build/app-icon-info.plist

# 編譯器提供的圖示 metadata 合併至 bundle，名稱與權限仍由來源 plist 管理。
python3 - "$APP/Contents/Info.plist" .build/app-icon-info.plist <<'PY_ICON'
import plistlib
import sys
from pathlib import Path


bundle_path, icon_metadata_path = map(Path, sys.argv[1:])
info = plistlib.loads(bundle_path.read_bytes())
info.update(plistlib.loads(icon_metadata_path.read_bytes()))
bundle_path.write_bytes(plistlib.dumps(info, sort_keys=False))
PY_ICON

# 翻譯、機型配置、產品圖片與授權檔隨 App 一併提供。
cp -R Sources/Resources/en.lproj Sources/Resources/zh-Hant.lproj "$APP/Contents/Resources/"
cp -R Sources/Resources/Profiles Sources/Resources/Products Sources/Resources/Licenses "$APP/Contents/Resources/"

# 全部資源複製完成後才簽章，確保簽章涵蓋最終內容。
SIGNING_IDENTITY="${BUDS_SIGN_IDENTITY:--}"
BUNDLE_ID=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$APP/Contents/Info.plist")

# ad-hoc 與具名簽章使用各自必要的 codesign 參數。
if [ "$SIGNING_IDENTITY" = "-" ]; then
    codesign --force --sign - --identifier "$BUNDLE_ID" "$APP"
else
    codesign --force --sign "$SIGNING_IDENTITY" --identifier "$BUNDLE_ID" --options runtime --timestamp "$APP"
fi
codesign --verify --verbose "$APP"
printf 'Built: %s/%s\n' "$PWD" "$APP"
