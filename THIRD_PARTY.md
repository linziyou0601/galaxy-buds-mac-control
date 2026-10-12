# 第三方程式與素材

本文件記錄 Galaxy Buds Mac Control 使用的上游程式、協定研究與產品圖片來源。

<br>

## 程式

原生通訊、部分模型、設定頁及韌體目錄、映像與傳輸流程沿用 [galaxy-buds-mac](https://github.com/vedatkilic/galaxy-buds-mac)，來源 commit 為 `3ffedf8217695075188ac4a6b1d0664022f58d92`，MIT 授權全文保存在 `LICENSE`。App 圖示的來源與授權位於下方「App 圖示」。

協定研究參照 [GalaxyBudsClient](https://github.com/timschneeb/GalaxyBudsClient)。該專案以 GPLv3 發佈，本專案使用獨立 Swift 實作與 MIT 上游程式，產品圖片直接取自 Samsung 官網。通訊格式亦以本機已安裝的 Samsung 耳機外掛及設定事件記錄對照，獨立實作 Swift 編解碼。外掛 APK、反編譯內容及手機記錄保存於本機研究目錄，該目錄排除於版本控制。

<br>

## 產品圖片

下列圖片用於本機識別產品，權利屬 Samsung，並未因程式的 MIT 授權而取得相同授權。公開發佈前須確認產品圖片的重製條件。完整下載 URL 與 SHA-256 位於 [素材清單](Sources/Resources/Products/sources.json)。

| 檔案 | 內容 | 官方來源 |
|---|---|---|
| `Sources/Resources/Products/buds3Pro-silver-earbuds.png` | buds3Pro 銀河灰耳機 | [Samsung 產品頁](https://www.samsung.com/uk/business/audio-sound/galaxy-buds/galaxy-buds3-pro-silver-sm-r630nzaaeua/) |
| `Sources/Resources/Products/buds3Pro-silver-case.png` | buds3Pro 銀河灰充電盒 | [Samsung 產品頁](https://www.samsung.com/uk/business/audio-sound/galaxy-buds/galaxy-buds3-pro-silver-sm-r630nzaaeua/) |
| `Sources/Resources/Products/buds3Pro-white-earbuds.png` | buds3Pro 雲朵白耳機 | [Samsung 產品頁](https://www.samsung.com/uk/business/audio-sound/galaxy-buds/galaxy-buds3-pro-white-sm-r630nzwaeua/) |
| `Sources/Resources/Products/buds3Pro-white-case.png` | buds3Pro 雲朵白充電盒 | [Samsung 產品頁](https://www.samsung.com/uk/business/audio-sound/galaxy-buds/galaxy-buds3-pro-white-sm-r630nzwaeua/) |
| `Sources/Resources/Products/buds4Pro-black-earbuds.png` | buds4Pro 曜石黑耳機 | [Samsung 產品頁](https://www.samsung.com/sg/business/audio-sound/galaxy-buds/galaxy-buds4-pro-black-sm-r640nzkaasa/) |
| `Sources/Resources/Products/buds4Pro-black-case.png` | buds4Pro 曜石黑充電盒 | [Samsung 產品頁](https://www.samsung.com/sg/business/audio-sound/galaxy-buds/galaxy-buds4-pro-black-sm-r640nzkaasa/) |
| `Sources/Resources/Products/buds4Pro-white-earbuds.png` | buds4Pro 極光白耳機 | [Samsung 產品頁](https://www.samsung.com/sg/business/audio-sound/galaxy-buds/galaxy-buds4-pro-white-sm-r640nzwaasa/) |
| `Sources/Resources/Products/buds4Pro-white-case.png` | buds4Pro 極光白充電盒 | [Samsung 產品頁](https://www.samsung.com/sg/business/audio-sound/galaxy-buds/galaxy-buds4-pro-white-sm-r640nzwaasa/) |
| `Sources/Resources/Products/buds4Pro-pinkGold-earbuds.png` | buds4Pro 粉霧金耳機 | [Samsung 產品頁](https://www.samsung.com/sg/business/audio-sound/galaxy-buds/galaxy-buds4-pro-pink-gold-sm-r640nzdaasa/) |
| `Sources/Resources/Products/buds4Pro-pinkGold-case.png` | buds4Pro 粉霧金充電盒 | [Samsung 產品頁](https://www.samsung.com/sg/business/audio-sound/galaxy-buds/galaxy-buds4-pro-pink-gold-sm-r640nzdaasa/) |

<br>

## App 圖示

[原生圖示資產](Sources/Resources/AppIcon.icon/icon.json) 與 [SVG 原檔](Sources/Resources/AppIcon.svg) 使用 Bootstrap Icons 的 earbuds 路徑，搭配 Poppins SemiBold 的文字輪廓。原生圖示的背景、外框、材質及系統相容產物由 Icon Composer 與 actool 管理，SVG 保留可攜的向量版本。SVG 全部轉成路徑，成品不需要安裝字型。背景藍紫色依使用者提供的官方圖示取樣，耳機與文字採用本專案的組合排版。

App bundle 的 Resources/Licenses 隨建置包含上述授權檔。選單列保留系統 SF Symbol，App 圖示使用獨立 SVG 組合。

| 元素 | 來源 | 授權 |
|---|---|---|
| 耳機路徑 | [Bootstrap Icons earbuds](https://github.com/twbs/icons/blob/e568465481c0c541f63a78f6452d09387711d489/icons/earbuds.svg) | [MIT 全文](Sources/Resources/Licenses/BootstrapIcons-MIT.txt) |
| Buds 文字輪廓 | [Poppins SemiBold](https://github.com/google/fonts/blob/8b0a1d0f5983c89bc2b93f1b5fb55f9e252744b5/ofl/poppins/Poppins-SemiBold.ttf) | [SIL OFL 1.1 全文](Sources/Resources/Licenses/Poppins-OFL.txt) |
