/* ==================================================
 * index.mjs - 寫作檢查引擎的對外 API
 * --------------------------------------------------
 * - 角色：重新匯出各模組給進入點與其他工具引用的函式。模組的分層見 references/scripts-contract.md
 * - 慣例：本檔不 import node:*，node 的檔案存取由 io-node.mjs 另行提供
 * - 參見 references/scripts-contract.md 取得權威合約
 * ================================================== */

export * from "./base.mjs";
export * from "./rules.mjs";
export * from "./parse.mjs";
export * from "./context.mjs";
export * from "./pipeline.mjs";
export * from "./output.mjs";
export * from "./cli.mjs";
// 檢查模組各有 run 與 RULES 這類同名匯出，以模組名稱作為命名空間匯出
export * as structure from "./structure.mjs";
export * as vocab from "./vocab.mjs";
