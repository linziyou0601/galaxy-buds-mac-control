# Galaxy Buds Mac Control

Samsung Galaxy Buds 的原生 macOS 選單列控制 App，提供電量、聆聽模式、音質、耳機操作與連線設定。

<br>

## 功能特色

快捷面板以四圓橫排切換聆聽模式，詳細設定依 Samsung 的功能語意分類，操作元件使用 SwiftUI、AppKit 與 macOS 原生服務。

- 左右耳電量、充電盒電量與產品配色辨識
- 關閉、環境音效、最佳化、主動式降噪及五段 ANC
- 系統輸出音量及 CoreAudio 變更通知同步
- 語音偵測、警報偵測、通話環境音與自身聲音
- 預設 EQ、自訂九段 EQ、左右音量平衡
- 左右耳長按設定、至少兩種模式的輪替與個別操作開關
- Buds3 Pro 燈效樣式
- Buds4 Pro 頭部動作偵測方向與事件
- 語音指令開關、音量標準化、強化人聲與適應性音量
- 流暢耳機連線、摘耳暫停、尋找音效與密合度測試
- 裝置韌體、序號、充電盒資料與本機診斷
- 官方更新資訊入口、第三方韌體封存目錄、映像驗證、裝置驅動傳輸與重啟後版本確認
- 韌體自我測試與頭部追蹤資料診斷
- 選用 Mac 系統音訊擷取與原生 HRTF 空間音訊
- 正體中文、英文、系統明暗及官方產品圖片

<br>

## 支援範圍

本專案為開發中的非官方工具，目前針對下列環境與耳機提供功能。

| 項目 | 範圍 |
|---|---|
| 耳機 | Galaxy Buds3 Pro、Galaxy Buds4 Pro |
| macOS | 部署目標為 macOS 14 以上，主要實測環境為 macOS 27 |
| Mac | 主要建置及實測環境為 Apple Silicon |
| 語言 | 正體中文、英文 |

### 實機驗證

下表分別記錄程式實作與實機結果。封包解析或單元測試通過，代表對應的程式行為通過檢查，實際功能依各機型的操作結果判定。

| 項目 | Buds3 Pro | Buds4 Pro |
|---|---|---|
| 機型配置、五段 ANC、圖片及配色目錄 | 已實作 | 已實作 |
| 控制通道、左右耳電量及產品色碼 | 已取得實機回報 | 已取得實機回報 |
| 充電盒電量 | 待實機驗收 | 耳機放入充電盒且盒蓋開啟時取得回報，未提供時顯示未回報 |
| 四種模式、音質、長按、操作與進階設定 | 四種模式、ANC／環境音五段與 Google 助理回報已驗證，其餘項目分別驗收 | 已實作命令傳送與回報解析，待逐項驗收 |
| 耳機燈效樣式 | 三種樣式經使用者確認可切換 | 機型未提供燈效 |
| 頭部動作 | 機型未提供此能力 | 偵測設定與事件已實作，跨 App 通話及助理整合受平台 API 限制 |
| 尋找音效、密合度、版本與序號 | 待實機驗收 | 待逐項驗收 |
| 更新後設定保留 | 使用者確認長按、燈效及聆聽模式正常保留 | 待實機驗收 |
| Mac／手機切換與睡眠喚醒 | 使用者確認恢復連線、狀態、控制、音量及面板正常 | 待實機驗收 |
| 系統音量 | CoreAudio 實測，快速連續變更測試通過 | CoreAudio 實測，快速連續變更測試通過 |
| Mac 空間音訊 | 音訊擷取及追蹤已實測，音色變悶，音質驗收未通過 | 連續播放與追蹤方向已實測，音量修正經使用者確認改善，開關瞬間會短暫卡頓 |
| 韌體自我測試 | 已取得 25 項旗標，未通過旗標需要分別判讀 | 已取得韌體自我測試旗標，未公開項目可能未提供 |
| 韌體更新 | AYG3 → AZD2 實際安裝、重啟與版本確認均已通過，手機識別及正常操作已確認 | 目錄、真實映像解析與傳輸測試通過，目前裝置版本與已查詢封存目錄一致 |

<br>

## 建置

自行建置時，取得專案原始碼後，在專案根目錄執行下列指令，產物為 `dist/Galaxy Buds Mac Control.app`。建置需要完整 Xcode、Python 3 與可用的 macOS SDK，工具鏈選擇及詳細要求請參閱 [開發環境](CONTRIBUTING.md#開發環境)。

```bash
bash build.sh
```

<br>

## 安裝

依取得的產物選擇安裝方式。

| 管道 | 安裝方式 |
|---|---|
| DMG 下載 | 從 [GitHub Releases](https://github.com/linziyou0601/galaxy-buds-mac-control/releases) 選擇版本並下載 DMG，開啟後將 `Galaxy Buds Mac Control.app` 拖到「應用程式」 |
| 本機建置 | 在 Finder 開啟 `dist`，將 `Galaxy Buds Mac Control.app` 拖到「應用程式」 |
| Homebrew | 尚未提供 |

### 首次啟動

從「應用程式」開啟 App，依 macOS 提示允許藍牙。目前本機建置使用 ad-hoc 簽章，下載的未公證版本可能被 Gatekeeper 阻擋。確認檔案來源後，先嘗試開啟一次，再到「系統設定 → 隱私權與安全性」選擇「仍要打開」，依系統提示確認。操作說明請參閱 [Apple：安全地開啟 Mac 上的 App](https://support.apple.com/zh-tw/102445)。

### 更新 App

本機版本先取得新版原始碼並重新執行 `bash build.sh`。從選單列面板結束 App，再將新產物拖到「應用程式」，確認取代後重新開啟。

下載版本請先從 [GitHub Releases](https://github.com/linziyou0601/galaxy-buds-mac-control/releases) 取得新版 DMG，結束 App 後開啟 DMG，以新版取代已安裝 App。沿用相同 Bundle ID 的相容版本會讀取既有偏好設定，macOS 可能要求重新允許權限。目前 App 更新採用手動替換，耳機韌體更新由 App 的「韌體」頁另行操作。

<br>

## 使用方式

### 開始使用

1. 在 macOS「系統設定 → 藍牙」配對並連接耳機。
2. 開啟 Galaxy Buds Mac Control，允許 App 使用藍牙。
3. 從選單列耳機圖示開啟快捷面板。
4. 點「Galaxy Buds 設定」或按 ⌘, 進入詳細設定。
5. 在一般頁選擇產品配色與快捷控制，在各功能頁調整耳機設定。

### 連線與裝置選擇

一般啟動與連線操作使用快捷面板，設定入口才開啟完整視窗。App 讀取 Mac 已配對裝置，優先選擇目前的耳機音訊輸出。自訂耳機名稱無法辨識時，可在連線頁指定機型。其他耳機管理 App 可能同時使用控制通道，連線問題可先結束它們後重試。

### 電量與操作回饋

充電盒電量取決於耳機回報時機，耳機放回盒內、盒蓋開啟時可能提供數值。未知電量顯示未回報。Mac 音訊輸出與耳機控制通道分別管理，命令送出後的回覆顯示於操作回饋。

### 診斷與功能狀態

「關於與診斷」提供裝置資料與本機診斷，其中的「開發狀態」依目前連線機型顯示功能、限制原因與參考來源。

<br>

## 功能限制

功能受到耳機能力、macOS 公開 API 與 Samsung 服務限制，下表說明已提供的替代方式與尚未完成的部分。Samsung 手機端的支援條件另由 [Buds4 官方裝置功能表](https://image-us.samsung.com/us/wearables/galaxy-buds4/images/Buds4_Series_Available_Features_by_Device.pdf) 說明。

| 功能 | 狀態與原因 |
|---|---|
| Mac 空間音訊 | 使用 Apple Core Audio tap 與 AVAudioEnvironmentNode 自動最高品質渲染，將立體聲轉換為虛擬音場。頭部追蹤可獨立啟用或停用，喇叭角度可調整，音色及輸出延遲與 Samsung 360 不同。切換音訊路徑時可能短暫停頓 |
| Adapt sound 聽力設定 | 完整校準流程、係數格式與安全寫入協定尚未確認 |
| 語音模型下載 | 模型隨 Samsung 手機外掛封裝，兩個參考專案未提供獨立來源與完整安裝流程。Mac 尚缺少安裝版本確認及復原的實機證據，語音指令使用耳機既有模型 |
| 通知朗讀 | Apple 公開通知 API 提供本 App 通知，無法讀取所有其他 App 通知 |
| Auracast | macOS 公開藍牙 API 未提供完整廣播搜尋、來源選取與接入控制流程 |
| 三星帳號自動切換 | 依賴 Samsung 帳號服務，耳機的流暢連線旗標已獨立提供 |
| 頸部伸展提醒 | 手機的姿勢校準與服務未提供 Mac 公開整合，頭部追蹤資料本身不代表完整提醒功能 |
| UHQ 與超寬頻語音 | 依賴 Galaxy 音訊 codec 與系統整合，macOS 系統 Bluetooth codec 由平台管理 |
| 完整硬體診斷 | 已提供韌體自我測試，未公開旗標可能包含未提供的測試，無法取代 Samsung 完整診斷 |
| 韌體更新 | 已實作映像、機型與區段 CRC 驗證、裝置驅動傳輸及重啟版本確認，實際安裝需要使用者確認且版本較新 |
| 頭部動作通話與助理整合 | 頭部動作設定及事件已提供，Mac 公開 API 未提供所有通話 App 或 Google／Bixby 的通用控制入口 |

<br>

## 耳機韌體來源

手機設定或 Galaxy Wearable 的「耳機軟體更新」更新耳機韌體，Galaxy Store／Play Store 更新 Wearable 或 Buds 外掛則是更新手機 App。App 顯示的目前韌體版本來自耳機，更新資訊由機型配置選擇 Samsung 官方頁面。

封存下載來源為 [Galaxy Buds Firmware Archive](https://github.com/timschneeb/galaxy-buds-firmware-archive) 的第三方 API，維護者說明其從 Samsung OTA 伺服器收集韌體。該站的 FUMO 抓取程式使用 KOO 客戶通路及產生的查詢身分，查詢條件與使用者手機不同。封存版本名稱與年月編碼用於排序，Samsung 官方發布日期及對目前耳機的更新提供情況以官方資訊為準。檔案的機型、內嵌版本與 CRC 檢查確認格式及完整性，原始檔來源與官方更新資格各自判讀。官方自動查詢尚未提供，現有 FUMO 參考依賴客戶通路、裝置查詢身分及舊 TLS 相容條件；App 不以固定通路、虛構身分或手機版本取代實際資料。

<br>

## 隱私權與安全權限

連線畫面與「一般」設定顯示藍牙授權與系統音訊擷取狀態，並提供系統設定入口。回到 App 時重新讀取藍牙授權，授權開關由 macOS 管理。

系統音訊的顯示值代表實際擷取狀態，權限開關以系統設定為準。啟用空間音訊時由 macOS 顯示授權提示。一般耳機控制與系統音量操作不需要啟用空間音訊。App 不要求麥克風、相機、輔助使用或完整磁碟存取權限。韌體目錄查詢與下載使用網路，下載行為由使用者觸發。

| 權限 | 使用時機 | 用途與資料處理 |
| --- | --- | --- |
| 藍牙 | 搜尋、連線與控制耳機 | 讀取已配對裝置、耳機狀態並傳送設定命令 |
| 系統音訊錄製 | 使用者啟用選用空間音訊功能 | Core Audio tap 擷取播放音訊供本機即時 HRTF 處理，停止功能時釋放 tap，音訊不儲存或上傳 |
| 登入項目 | 使用者開啟登入時啟動 | macOS ServiceManagement 管理 App 自動啟動，系統可要求在登入項目設定允許 |

<br>

## 版本與發行

App 版本以 [Info.plist](Sources/Resources/Info.plist) 的 CFBundleShortVersionString 與 CFBundleVersion 為唯一來源。發佈依驗收範圍、素材使用條件、簽章方式與版本封裝確認。維護者先完成壓版並提交，再推送版本 tag，GitHub Actions 建置 DMG 與 SHA-256 檔並建立 Release，完整流程請參閱 [版本與發行](CONTRIBUTING.md#版本與發行)。

<br>

## 文件入口

| 文件 | 職責 | 閱讀者 |
|---|---|---|
| [README.md](README.md) | 安裝、使用與支援範圍 | 使用者與開發者 |
| [DESIGN.md](DESIGN.md) | 原生視覺、版面、元件與互動 | UI 開發者 |
| [CONTRIBUTING.md](CONTRIBUTING.md) | 分層、開發、測試與發佈 | 貢獻者 |
| [AGENTS.md](AGENTS.md) | 權威、規則與技能路由 | AI agent 與維護者 |
| [THIRD_PARTY.md](THIRD_PARTY.md) | 第三方來源與授權 | 維護者與發佈者 |

<br>

## 致謝

本專案的通訊實作、協定研究與圖示素材使用下列開源專案的成果，感謝作者與維護者提供程式、研究資料及素材。完整來源與授權條件請參閱 [THIRD_PARTY.md](THIRD_PARTY.md)。

- [galaxy-buds-mac](https://github.com/vedatkilic/galaxy-buds-mac)：原生通訊、部分模型、設定頁與韌體流程的實作基礎。
- [GalaxyBudsClient](https://github.com/timschneeb/GalaxyBudsClient)：耳機通訊協定與功能研究參考。
- [Galaxy Buds Firmware Archive](https://github.com/timschneeb/galaxy-buds-firmware-archive)：韌體封存目錄與下載來源。
- [Bootstrap Icons](https://github.com/twbs/icons)：App 圖示的耳機向量素材。
- [Poppins](https://github.com/google/fonts/tree/main/ofl/poppins)：App 圖示的 Buds 文字素材。

<br>

## 授權

程式授權請參閱 [LICENSE](LICENSE)，第三方程式與 Samsung 產品圖片的來源及使用條件請參閱 [THIRD_PARTY.md](THIRD_PARTY.md)。本專案為非官方耳機控制工具。
