# AGENTS.md

本檔是 Galaxy Buds Mac Control 跨 agent 與維護者的入口頁，定義文件權威順序、主題權威來源、鐵律與工作流導航。

產品與使用方式位於 [README.md](README.md)，開發與發佈流程位於 [CONTRIBUTING.md](CONTRIBUTING.md)，視覺規範位於 [DESIGN.md](DESIGN.md)。

<br>

## 文件權威順序

依任務讀取負責該主題的文件。程式行為以原始碼、測試與實機證據判讀，文件衝突依下表定位權威來源。

| 優先順序 | 文件 | 職責 |
|---:|---|---|
| 1 | [AGENTS.md](AGENTS.md) | 協作入口、權威順序、鐵律 |
| 2 | [DESIGN.md](DESIGN.md) | 原生視覺、元件與互動 |
| 3 | [README.md](README.md) | 產品、支援範圍、安裝與使用 |
| 4 | [CONTRIBUTING.md](CONTRIBUTING.md) | 分層、開發、驗證與發佈 |
| 5 | [Package.swift](Package.swift) | 套件、部署目標與框架相依 |
| 6 | [DeviceProfile.swift](Sources/Models/DeviceProfile.swift) | 配置 schema 與驗證 |
| 7 | [THIRD_PARTY.md](THIRD_PARTY.md) | 程式與素材來源及授權 |

<br>

## 主題權威來源

| 主題 | 權威來源 |
|---|---|
| App 與服務生命週期 | [AppDelegate.swift](Sources/App/AppDelegate.swift) |
| 選單列、popover、設定視窗 | [StatusBarController.swift](Sources/App/StatusBarController.swift) |
| 藍牙連線與耳機命令 | [BluetoothManager.swift](Sources/Bluetooth/BluetoothManager.swift) |
| 封包、長度、CRC 與串流 | [SppMessage.swift](Sources/Bluetooth/SppMessage.swift)、[CRC16.swift](Sources/Bluetooth/CRC16.swift) |
| 狀態、ACK 與未回報語意 | [BudsStatus.swift](Sources/Models/BudsStatus.swift) |
| 系統空間音訊 | [SpatialAudioController.swift](Sources/Audio/SpatialAudioController.swift) |
| 韌體目錄、映像與傳輸 | [FirmwareCatalog.swift](Sources/Firmware/FirmwareCatalog.swift)、[FirmwareBinary.swift](Sources/Firmware/FirmwareBinary.swift)、[FirmwareUpdater.swift](Sources/Firmware/FirmwareUpdater.swift) |
| 權限狀態與設定入口 | [PermissionsView.swift](Sources/Views/PermissionsView.swift) |
| 系統輸出音量 | [AudioOutputController.swift](Sources/Audio/AudioOutputController.swift) |
| Buds3 Pro 能力與素材 | [buds3Pro.json](Sources/Resources/Profiles/buds3Pro.json) |
| Buds4 Pro 能力與素材 | [buds4Pro.json](Sources/Resources/Profiles/buds4Pro.json) |
| 分類選取與導覽歷史 | [SettingsNavigation.swift](Sources/Views/SettingsNavigation.swift) |
| 原生側欄與資料列 | [NativeSidebar.swift](Sources/Views/NativeSidebar.swift) |
| 功能分類與原生表單 | [NativeSettingsView.swift](Sources/Views/NativeSettingsView.swift) |
| 共用版面尺寸 | [InterfaceMetrics.swift](Sources/Views/InterfaceMetrics.swift) |
| 聆聽模式共用元件 | [ListenModePicker.swift](Sources/Views/ListenModePicker.swift) |
| 正體中文 | [Localizable.strings](Sources/Resources/zh-Hant.lproj/Localizable.strings) |
| 英文 | [Localizable.strings](Sources/Resources/en.lproj/Localizable.strings) |
| App 版本與識別 | [Info.plist](Sources/Resources/Info.plist) |
| 素材來源與雜湊 | [sources.json](Sources/Resources/Products/sources.json) |
| 程式撰寫風格 | [rule-native](.ai/skills/rule-native/SKILL.md) |
| 文件撰寫規範 | [rule-documentation](.ai/skills/rule-documentation/SKILL.md) |
| 文字與註解用語 | [rule-article-humanizer](.ai/skills/rule-article-humanizer/SKILL.md) |
| 精簡與反過度設計 | [rule-minimalism](.ai/skills/rule-minimalism/SKILL.md) |

<br>

## 鐵律

| 領域 | 規則 |
|---|---|
| 原生優先 | 優先使用 SwiftUI、AppKit、CoreAudio 與 IOBluetooth 的公開 API，操作元件遵循系統明暗、焦點與可存取性 |
| 分層邊界 | View 透過服務送出操作，封包解析與配置驗證維持獨立的 Foundation 邏輯 |
| 共享狀態 | 耳機狀態由 BluetoothManager 持有，系統音量由 AudioOutputController 持有，UI 狀態在 MainActor 更新 |
| 機型配置 | 目標為 Buds3 Pro 與 Buds4 Pro，能力、服務 UUID、欄位差異、圖片及範圍由 JSON 載入 |
| 相容性 | 執行判斷採用耳機能力與協定回報，禁止以特定使用者、手機、位址或手機版本繞過流程 |
| 傳輸結果 | 分別判斷控制通道、Mac 音訊輸出、命令送出、耳機確認與實際功能驗收 |
| 未回報值 | 使用 optional 與未回報文案表達，禁止把未知設定當成關閉或成功 |
| i18n | 使用者可見文字使用原生翻譯資源，正體中文與英文同步維護 |
| 資源生命週期 | Task、Timer、callback 與監聽器具備取消或移除邊界，音量通知不反覆註冊監聽 |
| 來源與授權 | 加工程式符合專案規則，必要授權與 Samsung 圖片來源保留於 THIRD_PARTY |
| Git | 不自動 stage、commit、push、merge、stash、reset 或刪除使用者資料 |
| 發佈 | 版本、標籤、簽章憑證及對外發佈由使用者明確要求後執行 |
| 新增實體 | 新增函式、欄位、型別、檔案或相依前，先按照 rule-minimalism 搜尋與選用既有能力 |
| 註解 | 描述責任、資料流、單位、副作用與邊界，正文維持終態用語 |

<br>

## 工作流入口

| 任務 | 入口 |
|---|---|
| 新增設定頁 | 依 DESIGN 的原生元件與功能分類，沿用 NativeSettingsView 的 Form 結構 |
| 新增耳機能力 | 先確認命令與回報，再修改機型配置、模型、服務、翻譯及測試 |
| 協定變更 | 對照實際資料來源，更新編解碼、狀態解析與短資料、未知值的測試 |
| 音量與系統服務 | 檢查公開 API、執行緒、事件合併、監聽生命週期與快速操作 |
| 新增 i18n 字串 | 兩個 Localizable.strings 同步維護，執行資源檢查 |
| 視覺調整 | 對照 DESIGN，檢查兩款機型、明暗、啟用與未啟用視窗、長文字及螢幕邊界 |
| 素材更新 | 更新 sources.json 與機型可見矩形，驗證全部圖片、雜湊與來源 |
| Commit / PR | 依 CONTRIBUTING 的格式與驗證要求，取得明確操作指示 |
| 發佈 | 依 CONTRIBUTING 的版本、封裝、簽章及硬體驗收流程 |

<br>

## 跨 agent 協作

共享規則與產品現況保存於 repository。`.ai/skills/` 保存可攜的實體規則，`.claude`、`.agents`、`.codex` 是指向 `.ai` 的相對符號連結，參考文件依任務漸進讀取。

交接時更新對應文件的現況，實機證據明確列出裝置、操作、回報與尚未驗證的範圍。

| 路徑 | 用途 |
|---|---|
| AGENTS.md | 權威、規則與工作流導航 |
| README.md | 使用者入口與支援範圍 |
| CONTRIBUTING.md | 開發、測試、架構與發佈 |
| DESIGN.md | 視覺與互動權威 |
| THIRD_PARTY.md | 授權與來源 |
| .ai/skills/ | 可重複使用的技能與參考文件 |
| .build/ | 本機建置、研究與驗證產物，排除於版本控制 |
| dist/ | App 與封裝產物，排除於版本控制 |

<br>

## 其他

- 使用者可見文字以正體中文為主，技術識別子、檔名與 API 保留英文。
- 文件及註解使用終態寫法，編輯過程記錄於版本紀錄。
- 藍牙診斷在本機保存，分享前檢查裝置識別與序號。
- 本機測試成功與公開發行完成分別判定。
