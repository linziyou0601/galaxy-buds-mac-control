# 標題結構與分隔

Wiki 依標題產生側邊目錄，區段之間的間距由固定的分隔寫法決定。本檔的條目只套用在 Wiki 版面的檔案，哪些路徑採 Wiki 版面寫在專案定義表的 `layout-profiles.tsv`。

## 目錄標記

第一個標題之前放 `[[_TOC_]]`，Wiki 依它產生頁內目錄。只列子頁的索引頁放 `[[_TOSP_]]`。lint 以規則「TOC 缺少」檢查。

## 標題逐層

標題依 H1、H2、H3 逐層往下，不跳級。lint 以規則「標題跳級」檢查。

## H1 之間的分隔

H1 區段之間依序放空行、三行 `<br>`、兩個空行與 `---`，再接下一個 H1，Wiki 上的區段間距才會一致。lint 以規則「H1 分隔不符」檢查，寫法如下：

```markdown
# Section A
Content here

<br>
<br>
<br>


---
# Section B
```

## H2 之間的分隔

同一個 H1 下有多個 H2 時，H2 之間依序放空行、一個 `<br>` 與空行。lint 以規則「H2 分隔不符」檢查，寫法如下：

```markdown
## Subsection A
Content here

<br>

## Subsection B
```

## H4 的替代寫法

H3 以下的細項寫成單獨一行的 `**粗體標籤**`，下一行接表格、清單或段落。Wiki 的 H4 外觀接近清單項目，讀者容易看錯層級。lint 以規則「標題過深」檢查，最深層級寫在 `references/tables/layout-markdown.tsv`。

## H2 的語言

同一檔案的 H2 使用同一種語言，新增 H2 時沿用該檔既有的語言。模板 code fence 內的 H2 屬於範例字串，依模板需要撰寫，lint 不檢查 code fence 內的標題。一份檔案的 H2 同時出現中文標題與純英文標題時，lint 以規則「H2 語言混用」從數量少的一邊列出，讀過後確認是否為同一份檔案混用兩種語言。
