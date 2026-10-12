---
version: 1
name: Galaxy Buds Mac Control
description: 原生 macOS 耳機控制介面的視覺、版面、互動與可存取性規範
colors:
  primary: Color.accentColor
  primary-text: Color.primary
  secondary-text: Color.secondary
  error: Color.red
  selected-label: Color.accentColor
  selected-icon: NSColor.controlAccentColor
  unselected-icon: Color.primary
surfaces:
  popover: NSPopover
  window: NSWindow
  form: Form.grouped
  footer: ShapeStyle.bar
typography:
  family: system
  title: Font.title3
  section: Font.headline
  control: Font.subheadline
  metadata: Font.caption
  battery: Font.caption2
  menu-bar-size-pt: 12
rounded:
  popover: system
  window: system
  form: system
  listening-mode: circle
spacing:
  panel-padding-pt: 16
  panel-section-gap-pt: 12
  mode-label-gap-pt: 6
layout:
  popover-width-pt: 310
  settings-initial-width-pt: 780
  settings-initial-height-pt: 580
  settings-min-width-pt: 700
  settings-min-height-pt: 520
  product-width-pt: 120
  product-height-pt: 80
components:
  listening-mode:
    diameter-pt: 40
    connector-width-pt: 1
    connector-gap-pt: 4
  appearance-picker:
    style: menu
  setting-toggle:
    style: switch
  settings:
    navigation: NavigationSplitView
    content: Form.grouped
---

# DESIGN.md

本檔參考 [Google DESIGN.md 規格](https://github.com/google-labs-code/design.md/blob/main/docs/spec.md)，使用 YAML metadata 與 Markdown body，依 Overview、Colors、Typography、Layout、Elevation & Depth、Shapes、Components、Do's and Don'ts 的順序描述設計。小章節定義 Galaxy Buds Mac Control 的原生 macOS 視覺、互動與元件樣式，YAML 記錄原生 API 的語意對應與尺寸。系統元件的外觀由 SwiftUI 與 AppKit 呈現，共用尺寸由 [InterfaceMetrics.swift](Sources/Views/InterfaceMetrics.swift) 宣告。

<br>

## Overview

Galaxy Buds Mac Control 使用 macOS 選單列聲音面板的資訊密度，結合 Samsung 耳機的四圓聆聽模式與功能分類。快捷控制提供即時操作，設定視窗提供機型、音質、操作與連線設定。

| 原則 | 實作方向 |
|---|---|
| 原生系統外觀 | 視窗、popover、表單、滑桿、開關及選單使用公開系統元件 |
| 穩定資訊位置 | 產品圖片、名稱與電量維持固定框架，回報變動由內容區吸收 |
| 相同語意共用元件 | 快捷面板與設定頁共用 ListenModePicker 與 DiscreteLevelSlider |
| 功能依使用情境分類 | 分頁沿用 Samsung 的聆聽、音質、操作、語音、連線及協助工具語意 |
| 狀態可辨識 | 選取、等待、錯誤與未回報均有文字或圖示語意 |

<br>

## Colors

### 品牌色

主要選取色採用 `Color.accentColor`，跟隨 macOS 的使用者偏好。產品配色由官方圖片呈現，手動選色以原生下拉選單提供。

### 表面色（語意角色）

| 角色 | 來源 | 用途 |
|---|---|---|
| 快捷面板 | NSPopover | 系統背景、半透明、邊界與陰影 |
| 設定視窗 | NSWindow | 標題列、視窗底色與系統明暗 |
| 設定群組 | Form.grouped | 設定列、群組底色與分隔線 |
| 對話框 | sheet | 自訂環境音設定 |
| 狀態區 | `.bar` | 命令回饋與預覽標示 |

### 狀態語意色

| 狀態 | 文字 | 圖示及操作元件 |
|---|---|---|
| 已選取模式 | accentColor | accentColor 底標與白色圖示 |
| 未選取模式 | secondary | 系統中性色與 primary 圖示 |
| 一般資料 | primary | 系統標準外觀 |
| 次要資料 | secondary | 名稱補充、序號、電量及說明 |
| 錯誤 | red | 錯誤文案與操作回饋 |

### Accessibility

同時以文字、圖示及 selected trait 表達模式。系統高對比、減少透明度與明暗外觀由原生元件處理，驗收需要涵蓋啟用與未啟用視窗。

<br>

## Typography

### Font Family

採用系統字型。SwiftUI 使用語意字級，選單列以 NSFont 的等寬數字樣式維持電量變動時的寬度。

### 階層

| 內容 | 字級 |
|---|---|
| 裝置名稱 | title3 或 subheadline.semibold，依所在畫面 |
| 區段標題 | headline |
| 操作列 | 系統表單預設 |
| 快捷控制 | subheadline |
| 說明、型號與狀態 | caption |
| 行內電量 | caption2 |
| 選單列電量 | 12 pt、medium、monospacedDigit |

### Weight 慣例

裝置名稱與區段標題使用 semibold，操作與內容保留系統字重，顯示數值採用等寬數字。選單列數字基準線下移 1 pt，與耳機圖示對齊。

### 排版原則

產品圖片放在裝置名稱與電量上方。名稱支援換行，序號支援選取複製。文字由翻譯資源提供，較長的英文與正體中文文字都需要清楚顯示。

<br>

## Layout

### 視窗尺寸

| 畫面 | 尺寸與行為 |
|---|---|
| 快捷面板 | 寬 310 pt，開啟時依錨點下方的可見高度量測，內容過長可捲動 |
| 設定視窗 | 初始 780 × 580 pt，最小 700 × 520 pt，可調整大小 |
| 側欄 | 最小 200 pt、理想 230 pt、最大 280 pt，側欄列高 38 pt |
| 產品圖片 | 耳機與盒子各 120 × 80 pt，等比例顯示 |

### 可用空間

一般啟動、重新開啟與耳機連線使用小彈窗，完整設定視窗由設定入口或 ⌘, 開啟。連線狀態切換時重新量測內容，電量回報維持原 viewport。面板依所在螢幕的 visibleFrame 與選單列按鈕位置決定高度。資料更新維持 viewport，捲動內容可以增加高度。設定頁採用 Form 的內部捲動。

### Sidebar-Detail 佈局

NavigationSplitView 顯示功能側欄與詳情，設定視窗使用原生 unified toolbar、sidebarTrackingSeparator 與 fullSizeContentView，左欄延伸到視窗頂部，標題與捲動材質位於右側內容欄。側欄搜尋限於設定分類，採用 SwiftUI searchable 的 sidebar placement，由系統配置外觀及焦點。分頁與順序由機型配置的 settingsCategories 注入，文字與 SF Symbols 由共用分類 metadata 提供。頭部動作分類與 headGestures 能力在配置載入時驗證一致性。

### Spacing 慣例

快捷面板內距 16 pt，區段使用 12 pt 間距。模式圓與文字相隔 6 pt。詳細設定採用系統 Form 間距，跨機型產品區固定為 90 pt 高，避免名稱及設定列上下位移。

### Background

NSPopover、NSWindow 與系統 Form 提供背景。Liquid Glass 使用公開元件樣式，維持系統材質、焦點與明暗行為。

### 導航與內容邊界

一般頁保存 App 偏好與產品外觀。音質、操作、語音、連線與協助工具各自提供對應設定，功能研究與相容性說明位於關於頁，快捷面板只呈現使用者勾選的操作元件。

<br>

## Elevation & Depth

### 原生材質

| 層級 | 元件 |
|---|---|
| 主視窗 | NSWindow |
| 功能內容 | NavigationSplitView、Form.grouped |
| 快捷控制 | NSPopover |
| 設定對話框 | sheet |

### Elevation 層級

系統管理視窗、popover 與 sheet 的陰影及層級。一般設定列以表單群組分隔，錯誤以訊息呈現。

### 前後景

popover 錨定選單列圖示，點擊外部關閉；設定視窗保有原生標題列與大小調整。sheet 依附設定視窗，完成按鈕位於右下方。

### 視覺重點

選取模式與可操作項目取得主要視覺權重。官方產品圖片提供辨識，裝飾與半透明效果維持在系統元件的責任範圍。

<br>

## Shapes

### Radius Scale

| 元件 | 形狀來源 |
|---|---|
| 視窗、popover、表單群組 | 系統預設 |
| 聆聽模式 | `.circle`，相同按鈕樣式與相同尺寸 |
| 一般按鈕與輸入 | 系統預設 |
| 滑桿與開關 | 系統預設 |

### 形狀慣例

同一模式群組的所有圓使用相同材質與幾何，選取只改變語意色及可存取性狀態。連接線繪於圓形之間，距圓邊至少 4 pt。

<br>

## Components

主要元件使用下列既有實作，新增畫面先確認相同職責是否已有共用元件。

| 元件 | 來源 | 責任 |
|---|---|---|
| 快捷面板 | MenuPopoverView、MenuPopoverContent | 固定 viewport、自然高度內容與捲動 |
| 設定入口 | NativeSettingsView | 側欄、功能分類與原生表單 |
| 聆聽模式 | ListenModePicker | 四圓橫排、選取色、文字與圖示 |
| ANC | DiscreteLevelSlider | 配置段數的原生 Slider 與加減操作，ANC 與環境音共用軌道 |
| 產品圖片 | BudsIllustration | 可見矩形、等比例縮放與共用快取 |
| 配色 | Picker.menu | 自動辨識與裝置手動覆寫 |
| EQ | EqualizerView | 原生垂直 NSSlider 與九段曲線 |
| 自訂環境音 | AmbientSoundView | 原生 sheet 內容 |
| 頭部動作 | HeadGesturesView | 偵測方向、偏好及事件 |

### Sheet

自訂環境音使用寬 500 pt、高 360 pt 的 sheet，內容採用 Form.grouped，完成按鈕提供預設鍵盤操作。

### Card

設定資料使用 Section 與 Form.grouped 呈現，資料列使用 LabeledContent，產品區使用固定圖片框。聆聽模式按鈕與降噪、環境音滑桿共用同一個 Section，卡片背景與圓角由分組表單提供。

### Panel

快捷面板資訊順序為聲音與音量、產品圖片、名稱與電量、聆聽模式、模式強度、使用者勾選的快捷控制、設定入口及結束操作。只有音訊輸出與正在控制的耳機不同時，才在音量下方顯示輸出名稱。

### Button

模式群組共用原生 Button，採用 glass 與 glassProminent 樣式，未選取項目保留系統預設材質，較舊系統採用 bordered。一般操作使用 Button，破壞性操作依具體後果提供獨立確認流程。

### Input

離散數值使用 Slider 與 step，布林值使用 Toggle，有限選項使用 Picker。需要解釋效果的列以標題與 caption 說明組成原生 Toggle 標籤，側欄維持單行標題。未知值顯示未回報，取得有效資料後提供對應操作。

### Chart

EQ 的預設曲線來自耳機回報，自訂曲線以九個垂直滑桿編輯，增益範圍為 -10...10，預設曲線尚未回報時顯示等待文字。

### 選單列

耳機圖示與左右耳較低的有效電量共用 NSStatusBarButton。未取得有效電量時保留圖示，裝置狀態與名稱由系統與耳機回報提供。

### Sidebar

側欄使用 AppKit NSTableView 的 sourceList 樣式，資料列由 NSTableCellView、NSImageView 與 NSTextField 組成，選取背景由原生 NSTableRowView 的非強調狀態繪製。SF Symbols 採用共用 16 pt 字級及自然尺寸，24×28 pt 圖示區域保留完整符號比例，文字使用系統字型，列高 38 pt，圖示區域與標題間距 6 pt，捲動內容左右內距 10 pt。深淺外觀遵循系統語意色，鍵盤選取與導覽保留原生行為。每項設定由單一詳細頁負責，快捷控制經相同服務操作該設定。

### Scrollbar

面板與設定頁使用原生捲動，遵循系統捲軸偏好，側欄捲軸保留右側 10 pt 內距。開啟面板時量測內容，後續回報不重新定位 popover。

### App 圖示資產

AppIcon.icon 使用 Apple 原生分層圖示格式，前景是耳機與 Buds 字樣的 SVG 路徑，背景使用藍紫主色。畫布遮罩與外框由系統套用，建置透過 actool 產生 Assets.car 及供舊系統使用的 ICNS，並合併圖示 metadata。選單列圖示沿用原生 SF Symbol。

<br>

## Do's and Don'ts

### Do

- 使用公開原生 API 與語意色，保留系統焦點及明暗行為。
- 相同模式、圖片與 ANC 控制共用既有元件。
- 依 Samsung 的功能語意放置設定。
- 模式圓保持相同尺寸，文字、圖示及 selected trait 一致。
- 產品素材依機型配置選擇，驗證每個顏色的耳機與盒子。
- 驗收短螢幕、長文字、兩款機型、明暗及快速操作。

### Don't

- 禁止自製 NSWindow 仿造 NSPopover。
- 禁止以黑色遮罩、固定透明度或手工陰影冒充系統材質。
- 禁止以特定手機、版本或使用者識別改寫 UI 能力。
- 禁止把未知設定當成關閉、把傳輸成功當成硬體驗收成功。
- 禁止為同一設定在不同詳細頁建立各自狀態。
- 禁止將所有耳機功能放入其他或進階頁。
