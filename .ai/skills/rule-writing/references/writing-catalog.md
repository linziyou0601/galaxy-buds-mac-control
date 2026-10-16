# 寫作判準型錄

`references/writing/` 是寫作的判準，依檔名前綴分成四組：版面、格式、交付內容與行文。條目檔一個條目一個標題，標題下寫判準、偵測訊號、成因與改寫前後對照，「改寫後」的文字同時符合所有其他條目，可以直接當成寫法參考。條目編號、檢查主題與參照只登記在條目索引 `references/tables/rule-index.tsv`，lint 的規則與層級只登記在規則表 `references/tables/check-rules.tsv`。偵測詞、正規式與成對連接詞寫在 `references/tables/` 的機讀定義表，由 `scripts/lint.mjs` 列出要看的位置，判定方法見 [judgment-policy](judgment-policy.md)。

## 判準索引

各組依檔名前綴排列。技術文字先查技術文體，再查語言與語法、填充與修辭腔、中文空話詞、交流殘留與風格。敘事段落從內容模式查起，全部條目都適用。套用範圍寫各條目檔的條目套用在哪些文字，路徑採用的版面寫在專案定義表的 `layout-profiles.tsv`：

| 組 | 段落 | 檔案 | 主題 | 套用範圍 |
|---|---|---|---|---|
| 版面 | 標題結構與分隔 | [layout-heading](writing/layout-heading.md) | Wiki 頁面的標題與區段間距 | Wiki 版面 |
| 版面 | 產物與段落邊界 | [layout-product](writing/layout-product.md) | 結構化產物與前後說明的排列 | markdown 與 mdx |
| 版面 | 常見錯誤 | [layout-pitfalls](writing/layout-pitfalls.md) | 交付文件前最常漏掉的事項 | Wiki 版面與規格型文章 |
| 版面 | 翻譯指引 | [layout-translation](writing/layout-translation.md) | 雙語版本的結構對齊 | 內部知識文件的兩個語言版本 |
| 格式 | 格式慣例 | [format-markdown](writing/format-markdown.md) | markdown 元素與中文句讀的寫法 | code block 與連結為 markdown 與 mdx，其餘為全部格式 |
| 格式 | 粗體使用 | [format-bold](writing/format-bold.md) | 粗體的位置 | markdown 與 mdx |
| 格式 | 中英排版 | [format-typography](writing/format-typography.md) | 中英文與數字混排的空白、標點與寫法 | 全部格式 |
| 交付內容 | 現況寫作 | [final-current](writing/final-current.md) | 正文只寫現況，編輯痕跡留在版本紀錄 | 全部格式 |
| 交付內容 | 完整性 | [final-complete](writing/final-complete.md) | 列出的內容就是全部內容 | 全部格式 |
| 行文 | 技術文體 | [prose-technical](writing/prose-technical.md) | 技術文字寫成精確、同向、可驗證的直述句 | 技術文字 |
| 行文 | 語言與語法 | [prose-grammar](writing/prose-grammar.md) | 詞彙與句法層級的 AI 痕跡 | 全部文字 |
| 行文 | 填充與修辭腔 | [prose-filler](writing/prose-filler.md) | 字數變多、資訊量不變的字詞與修辭 | 全部文字 |
| 行文 | 中文空話詞 | [prose-buzzword](writing/prose-buzzword.md) | 以抽象詞、比喻或截短的詞取代具體動作 | 全部文字 |
| 行文 | 交流殘留 | [prose-communication](writing/prose-communication.md) | 聊天對話留在正文的痕跡 | 全部文字 |
| 行文 | 風格 | [prose-style](writing/prose-style.md) | 版面裝飾與符號的使用 | 全部文字 |
| 行文 | 內容模式 | [prose-narrative](writing/prose-narrative.md) | 敘事段落的渲染、宣傳與公式化結構 | 敘事段落 |
| 行文 | 完整範例 | [prose-example](writing/prose-example.md) | 一篇敘事文章從草稿、覆核到定稿 | 敘事段落 |
| - | 文件收錄 | [docs-entry-policy](docs-entry-policy.md) | 文件分工、收錄位置與入口連結 | 專案文件 |

## 型錄紀律

- 條目檔一個條目一個標題，條目索引的參照指向這個標題。條目檔提到 lint 時寫規則名稱，條目編號與層級只寫在表。
- 句子層級的寫法（同向表述、現況陳述的用語、清單長度數字、中英夾雜）寫在行文組，版面、格式與交付內容組的條目指向那裡。
- 「改寫後」的範例符合所有條目，新增或修改範例時逐條自查，並以 `scripts/lint.mjs` 檢查條目檔。
- 範例使用通用情境，模組、服務與路徑以一般名稱描述。
- 條目檔提到被討論的寫法時寫在「」或 code span 內。
- 偵測詞、正規式與成對連接詞只寫在機讀定義表，條目檔的偵測訊號指向表內的規則名稱。
- 新增或修改條目依 [design/amendment](design/amendment.md)，條目編號登記在 `references/tables/rule-index.tsv`。
