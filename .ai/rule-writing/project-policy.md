# 專案寫作慣例

依本檔判定文件版面、收錄位置與翻譯資源，通用行文與格式依本 skill 的規則型錄。專案既有格式與專屬輸出指令優先，讓讀者與工具持續使用既有結構。

## 標題與版面

標題拓撲由既有文件決定。README、AGENTS、CONTRIBUTING 各有一個 H1，H1 下方接一句用途說明，再以一個 `<br>` 進入第一個 H2。DESIGN 使用 YAML metadata 與單一 H1，章節維持設計系統結構。新增內容沿用檔內層級，既有標題維持原順序。

標題依 H1 → H2 → H3 逐層往下。

多個 H1 的文件，H1 區段之間依序放入空行、三行 `<br>`、兩個空行與 `---`，再接下一個 H1，GitHub 上的區段間距才會一致：

```markdown
# Section A
Content here

<br>
<br>
<br>


---
# Section B
```

同一個 H1 下有多個 H2 時，H2 之間加一個 `<br>`：

```markdown

## 翻譯資源

可見文字由 `Sources/Resources/en.lproj/Localizable.strings`、`Sources/Resources/zh-Hant.lproj/Localizable.strings` 維護。README、CONTRIBUTING、AGENTS、DESIGN 以臺灣正體中文撰寫，沒有逐段英文鏡像。

- 功能的翻譯資源以正體中文與英文維護，新增可見文字同步檢查兩個語系。
- code block 保持原樣，只翻譯其中的註解與使用者可見字串範例。
- 連結、檔案路徑、i18n 鍵、程式識別子與插值參數名稱保持原樣。
- 譯文依目標語言的語序重寫，句子讀起來像以該語言直接寫成。
- 翻譯完成後執行 `bash test.sh`，驗證配置與協定，另以 `plutil -lint` 檢查翻譯資源語法。

## 圖表與版本行

架構、部署、時序與判定流程使用 Mermaid，圖前說明權威邊界與讀圖目的。Mermaid 與文字樹使用四個空格縮排，版本型文件的 title-block 可記載修訂註記，正文描述現況。

## lint 版面範圍

本專案的路徑設定使用一般 Markdown 版面，標題與分隔另依本檔人工檢查。引擎保留 Wiki 檢查與標準答案集，專案文件採用上列版面規則。
