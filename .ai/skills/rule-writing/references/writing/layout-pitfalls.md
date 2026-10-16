# 常見錯誤

交付文件前最常漏掉的事項。「.order 與收錄位置」只套用在 Wiki 版面的檔案，「規格型文章的內容」套用在規格型文章。

## .order 與收錄位置

新增文章時，同步把檔名加進同目錄的 `.order`，Azure DevOps Wiki 側邊欄才會顯示。`.order` 的維護、入口頁與檔案放置依 [docs-entry-policy](../docs-entry-policy.md)。lint 以規則「.order 沒有登記」檢查檔案所在目錄有 `.order` 時，檔名（不含副檔名）是否登記在其中。側欄排序檔的檔名寫在 `references/tables/layout-markdown.tsv`。

## 規格型文章的內容

規格型文章同時說明「why」與「what」，程式碼範例使用真實可執行的程式碼。
