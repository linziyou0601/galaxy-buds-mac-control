# 機讀定義表型錄

`references/tables/` 是 `scripts/lint.mjs` 讀取的機讀定義表，人與 lint 讀同一份資料。lint 實作通用機制，規則的層級、判定問題、改法、詞、正規式、成對連接詞、門檻、文風、路徑設定與 markdown 寫法都寫在這裡，改規則就是改表。各規則對應的條目與判法寫在 [writing-catalog](writing-catalog.md) 的條目檔。

## 分組

每張表回答一個問題，檔名依「類別-對象.tsv」命名，前綴是表的類別。規則表是中心：正規式表、詞表與門檻表的「規則」欄指向規則表的規則名稱，規則表的條目指向條目索引，條目索引的參照指向條目檔的標題。lint 載入時檢查每個指向都存在，每條規則都有檢查使用：

| 問題 | 前綴 | 表 |
|---|---|---|
| 這個寫法用不用 | `lex-` | `lex-avoid` 是不使用的寫法，`lex-locale` 是技術用語對照，`lex-english` 是英文詞的寫法，`lex-boundary` 是中文詞的邊界 |
| 怎麼判、怎麼回報 | `check-` | `check-rules` 是規則，`check-levels` 是層級，`check-verdicts` 是判定值，`check-styles` 與 `check-style-levels` 是文風與它覆寫的層級，`check-thresholds` 是門檻，`check-patterns` 以正規式比對，`check-pairs` 找成對連接詞 |
| 版面怎麼寫、套用在哪些檔案 | `layout-` | `layout-profiles` 是路徑的 Wiki 版面與文風，`layout-formats` 是副檔名的格式，`layout-markdown` 是 markdown 寫法 |
| 條目寫在哪裡 | `rule-` | `rule-index` 是條目編號、段落與參照 |

## 共用寫法

全部檔案是 UTF-8 的 TSV，第一列是表頭，表頭與欄位數不符時 lint 以結束代碼 2 停止。各表共用下列寫法：

- 識別欄識別一列，同一個識別只寫一列。識別欄是第一欄，`check-style-levels` 是文風與規則兩欄，`lex-locale` 是英文與簡體中文兩欄。列依各欄的 Unicode 碼位排序，列序不承載規則。
- 一個儲存格有多個值時以頓號分隔，沒有值時寫 `-`，是非欄寫「是」或「否」。
- 層級、範圍、比對對象、格式與文風寫各自表內登記的值，值寫錯時 lint 以結束代碼 2 停止。
- 說明欄與改法欄是範本，以 `{名稱}` 標出 lint 代入的值。
- 例外欄列出含命中文字、但不算命中的整詞或命中文字本身，例如「落地頁」不算空話詞「落地」。

## 規則與層級

規則表的每一列是一條規則，欄位是規則名稱、條目、預設層級、範圍、成群門檻、說明、判定與改法。判定欄是一個是非問題，答案「是」表示違規，沒有判定問題的規則寫 `-`，由 lint 直接判定。範圍欄決定規則套用在哪些檔案：「文字」套用在全部格式，「markdown」套用在 markdown 與 mdx，「Wiki 版面」只套用在 `layout-profiles.tsv` 判定為 Wiki 版面的檔案。

判定表定義判定值與依據的開頭：「違規」的依據以「是」起頭，「誤報」的依據以「否」起頭，依據的開頭就是判定問題的答案。層級表定義四個層級，每筆發現項目的層級決定要不要輸出、結束代碼、要不要填判定與對應的嚴重度：

| 層級 | 輸出 | 結束代碼 | 判定 | 用途 |
|---|---|---|---|---|
| 錯誤 | 是 | 1 | 不填 | 程式能精確判定的規則，依改法修正 |
| 警告 | 是 | 0 | 必填 | 逐筆回答判定問題，判為違規時依改法修正 |
| 提示 | 是 | 0 | 選填 | 讀過後自行決定要不要改 |
| 關閉 | 否 | 0 | 不填 | 不檢查 |

## 文風

文風是一組層級覆寫，依文件的寫作目的調整規則的鬆緊。`check-styles.tsv` 登記文風與說明，`check-style-levels.tsv` 寫每個文風把哪條規則改成哪個層級，規則寫「全部」時套用在全部規則，同一個文風內指名規則的列優先。一份文件套用哪些文風、層級怎麼計算，見 [design/engine](design/engine.md) 的「路徑設定與文風」與「層級的決定」。

## 檔案

各表的內容、讀取的程式與專案擴充方式。專案擴充方式寫「不可擴充」的表只由本 skill 整批修改。其餘的表由專案放同表頭的 TSV，以 `--project` 傳入：

| 檔案 | 內容 | 讀取的程式 | 專案擴充方式 |
|---|---|---|---|
| `check-rules.tsv` | 規則：規則名稱、條目、預設層級、範圍、成群門檻、說明、判定與改法。成群門檻只用在詞表的規則，是同一個區塊內同規則命中數的下限，未達門檻不列出 | `rules.loadRules`，供 `Context.report` 使用 | 不可擴充 |
| `check-levels.tsv` | 層級：順位、輸出、結束代碼、判定（必填、選填、不填）、嚴重度與說明。輸出為否的層級剛好一個，`--off` 與文風的關閉使用它 | `rules.loadLevels`，供 `Context.report` 與 `output.pendingOf` 使用 | 不可擴充 |
| `check-verdicts.tsv` | 判定值與依據的開頭 | `rules.loadRules`，供 `output.pendingOf` 使用 | 不可擴充 |
| `check-styles.tsv` | 文風與說明 | `rules.loadStyles` | 附加 |
| `check-style-levels.tsv` | 文風、規則與層級 | `rules.loadStyles`，供 `Context.level` 使用 | 附加，同文風、同規則時以專案的列為準 |
| `check-thresholds.tsv` | 門檻：名稱、規則與值。「術語檔案數」是中英夾雜的片語在同一次檢查中出現的檔案數下限，達到時視為術語 | `rules.loadRules`，供 `pipeline.lintDocs` 使用 | 不可擴充 |
| `check-patterns.tsv` | 正規式：規則、比對對象（遮罩行、表格以外、段落與清單）、正規式與例外。具名群組「命中」標出說明顯示的文字 | `rules.loadRules`，供 `vocab.checkPatterns` 使用 | 不可擴充 |
| `check-pairs.tsv` | 成對連接詞：開頭詞、接續詞與例外 | `rules.loadRules`，供 `vocab.checkPairs` 使用 | 不可擴充 |
| `lex-avoid.tsv` | 不使用的寫法：寫法、規則、一對一的改用寫法與例外。英文寫法不分大小寫並比對完整單字 | `rules.loadWords`，供 `vocab.checkWords` 使用 | 附加，不分大小寫不得與其他詞表重複 |
| `lex-locale.tsv` | 技術用語對照：英文、簡體中文、大陸寫法、正體中文、分類、規則與例外。大陸寫法是大陸用語以正體字寫成的樣子，有大陸寫法與規則的列才比對 | `rules.loadWords`，供 `vocab.checkWords` 使用 | 不可擴充 |
| `lex-english.tsv` | 英文詞的標準寫法、類別與說明。寫法與表內不同時列為專有名詞大小寫，全部列都視為術語，不列為中英夾雜 | `rules.loadWords`，供 `vocab.checkWords` 與 `pipeline.lintDocs` 使用 | 附加 |
| `lex-boundary.tsv` | 中文詞的邊界：命中位置的前一字與第一字，或最後一字與後一字組成這些詞時不算命中，例如「修改檔案」不算截短的「改檔」 | `rules.loadRules`，供 `vocab.checkWords` 與 `vocab.checkPairs` 使用 | 附加 |
| `layout-profiles.tsv` | 路徑樣式、是否採 Wiki 版面與文風。路徑相對於 `--root`，「**」跨目錄、「*」不跨目錄，一個檔案符合多個樣式時取最長的樣式，「**」是預設。skill 只提供預設列，各路徑的版面與文風是專案事實，寫在專案定義表 | `rules.loadRules`，供 `Context.profileOf` 使用 | 整張取代 |
| `layout-formats.tsv` | 副檔名與格式：markdown、mdx、純文字 | `rules.loadRules`，供 `pipeline.collectFiles` 與 `pipeline.readDocs` 使用 | 不可擴充 |
| `layout-markdown.tsv` | markdown 寫法：H1 與 H2 之前的分隔行、TOC 標記、圖表區塊、引言前綴、標題最深層級、側欄排序檔、加重語氣區塊的標籤、引出產物的標點、引用括號與文風宣告。分隔行的值由上到下以頓號分隔，空行寫「空行」 | `rules.loadMarks`，供 `parse`、`Context.prepare` 與 `structure` 使用 | 不可擴充 |
| `rule-index.tsv` | 條目編號、段落、參照與檢查主題。參照寫成「檔案#標題」，檔案相對於 skill 目錄 | `rules.loadIndex` | 不可擴充 |
