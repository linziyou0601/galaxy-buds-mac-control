#!/bin/bash
# 由 build.sh 與 test.sh 使用 source 載入，共用工具鏈選擇。
# DEVELOPER_DIR 與 BUDS_SDK_PATH 可由呼叫端指定。
# 選擇結果保留於呼叫端 shell，SDK 查詢失敗由呼叫端停止執行。

# 呼叫端未指定工具鏈，且標準位置有完整 Xcode 時，選擇其 Developer 目錄。
if [ -z "${DEVELOPER_DIR:-}" ] && [ -d /Applications/Xcode.app/Contents/Developer ]; then
    export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
fi

# SDK 覆寫保留原值，其餘情況使用所選工具鏈的預設 macOS SDK。
BUDS_SDK_PATH=${BUDS_SDK_PATH:-$(xcrun --show-sdk-path)}
