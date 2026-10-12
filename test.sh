#!/bin/bash
# 用法：bash test.sh
# 輸出：.build/core-tests 與各項檢查結果，任一項失敗即停止。
# 本腳本驗證程式與資源，耳機實際操作另以硬體測試確認。
set -euo pipefail
cd "$(dirname "$0")"
source scripts/developer-environment.sh
mkdir -p .build

# 編譯純邏輯測試使用的來源，逐行列出以便確認測試範圍。
xcrun swiftc -sdk "$BUDS_SDK_PATH" \
    Sources/Models/DeviceProfile.swift \
    Sources/Models/BudsModel.swift \
    Sources/Models/QuickControl.swift \
    Sources/Models/AdditionalSetting.swift \
    Sources/Bluetooth/CRC16.swift \
    Sources/Bluetooth/MessageID.swift \
    Sources/Bluetooth/SppMessage.swift \
    Sources/Models/BudsStatus.swift \
    Sources/Models/NoiseControlMode.swift \
    Sources/Models/EqualizerPreset.swift \
    Sources/Models/TouchControls.swift \
    Sources/Firmware/FirmwareBinary.swift \
    Sources/Firmware/FirmwareCatalog.swift \
    Sources/Firmware/FirmwareUpdater.swift \
    Sources/Diagnostics/DiagnosticsLog.swift \
    Sources/Audio/SpatialAudioController.swift \
    Sources/Views/SettingsNavigation.swift \
    Tests/AudioTests.swift \
    Tests/FirmwareTests.swift \
    Tests/ProfileTests.swift \
    Tests/ProtocolTests.swift \
    Tests/StatusTests.swift \
    Tests/NavigationTests.swift \
    Tests/main.swift \
    -o .build/core-tests

# 執行核心測試，再驗證產品圖片、翻譯與文件連結。
.build/core-tests "$PWD/Sources/Resources/Profiles"
python3 scripts/product-assets.py
python3 scripts/check-resources.py
