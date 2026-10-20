# 專案寫作慣例的讀取

本 skill 的共同判準由規則型錄與機讀定義表提供，專案的版面、文件分工、語言資源與內容保留要求由各 repo 管理。

## 專案輸入

先讀 repo 根目錄 `AGENTS.md` 的寫作檢查章節，取得專案定義表目錄，再讀取該目錄的 `project-policy.md` 與 `docs-entry-policy.md`。版面與文風的路徑預設由同目錄的 `layout-profiles.tsv` 提供。

## 適用順序

專屬輸出指令與專案明定的版面、frontmatter、連結和來源引用方式優先，共同行文判準依本 skill 的規則型錄。文風宣告依專案允許的 frontmatter、HTML 註解或命令列參數使用。

## 獨立執行

本 repo 持有完整的 skill 本體、規則表與腳本，執行時使用本 repo 的 `scripts/lint.mjs` 與專案輸入。鏡像更新以共同來源的前後差異套用，各 repo 的專案輸入由各自維護。
