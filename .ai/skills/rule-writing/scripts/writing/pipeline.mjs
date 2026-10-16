/* ==================================================
 * pipeline.mjs - 檢查流程：展開路徑、讀取文件、執行檢查、排除術語、去除重複的發現項目與自動取代
 * --------------------------------------------------
 * - 角色：進入點以 lintDocs(ctx, docs, checks) 執行傳入的檢查函式，彙整一次執行的發現項目
 * - 指令：由進入點匯入使用
 * - 慣例：目錄遞迴列出格式表登記副檔名的檔案，略過 SKIP_DIRS、名稱以「.」開頭的子目錄與含 CASES_FILE 的子目錄
 * - 慣例：中英夾雜這類術語門檻以同一次檢查的全部文件計算，規則與值取自門檻表的 TERM_FILES
 * - 慣例：同一行、同一條目與同一命中文字的發現項目只留層級順位最高的一筆
 * - 慣例：applyFixes 只改文件物件的內容，寫回檔案由進入點經由 io 介面執行。本模組不 import node:*
 * - 參見 references/scripts-contract.md 取得權威合約
 * ================================================== */
import { InputError, cmpStr, compareFindings, extName, joinKey, joinPath } from "./base.mjs";
import { Doc } from "./context.mjs";

/* ==================================================
 * 集中設定
 * ================================================== */

/**
 * 遞迴列出檔案時略過的目錄名稱，以及略過的目錄名稱開頭。
 */
const SKIP_DIRS = new Set(["node_modules"]);
const HIDDEN_PREFIX = ".";

/**
 * 標準答案集的預期檔名。含這個檔的子目錄是標準答案集，遞迴列出檔案時略過。
 */
export const CASES_FILE = "expected.tsv";

/**
 * 門檻表的名稱：英文片語視為術語的檔案數。套用的規則取自門檻表的規則欄。
 */
const TERM_FILES = "術語檔案數";

/* ==================================================
 * 路徑與文件
 * ================================================== */

/**
 * 展開命令列的路徑：檔案原樣保留，目錄遞迴列出登記副檔名的檔案。
 * @param {Object} io io 介面。
 * @param {string[]} paths 路徑。
 * @param {Map<string, string>} formats 副檔名對應格式。
 * @returns {string[]} 依路徑排序的檔案絕對路徑。
 * @throws {InputError} 路徑不存在，或檔案的副檔名沒有登記。
 */
export function collectFiles(io, paths, formats) {
  const out = [];
  /**
   * 遞迴列出目錄下登記副檔名的檔案。
   * @param {string} dir 目錄。
   */
  const walk = (dir) => {
    // 逐個項目分成子目錄與檔案
    for (const e of io.listEntries(dir)) {
      const p = joinPath(dir, e.name);
      // 子目錄略過登記的名稱、隱藏目錄與標準答案集，其餘遞迴，登記副檔名的檔案收錄
      if (e.dir) {
        // 略過的子目錄不走訪
        if (SKIP_DIRS.has(e.name) || e.name.startsWith(HIDDEN_PREFIX) || io.exists(joinPath(p, CASES_FILE))) continue;
        // 其餘子目錄遞迴
        walk(p);
      } else if (formats.has(extName(e.name))) {
        // 登記副檔名的檔案收錄
        out.push(p);
      }
    }
  };
  // 逐個命令列路徑展開
  for (const raw of paths) {
    const p = io.resolve(raw);
    // 路徑不存在時無法判定檢查範圍
    if (!io.exists(p)) throw new InputError(`路徑不存在：${raw}`);
    // 目錄遞迴，檔案要有登記的副檔名
    if (io.isDir(p)) {
      walk(p);
    } else {
      // 檔案的副檔名沒有登記時無法判定格式
      if (!formats.has(extName(p))) throw new InputError(`${raw}: 副檔名沒有登記在格式表`);
      out.push(p);
    }
  }
  return [...new Set(out)].sort(cmpStr);
}

/**
 * 讀取檔案成為文件，顯示的路徑相對於基準目錄。
 * @param {Object} io io 介面。
 * @param {string[]} files 絕對路徑。
 * @param {string} root 基準目錄的絕對路徑。
 * @param {Map<string, string>} formats 副檔名對應格式。
 * @returns {Doc[]}
 */
export function readDocs(io, files, root, formats) {
  return files.map((abs) => new Doc(abs, io.relative(root, abs), formats.get(extName(abs)), io.readText(abs)));
}

/* ==================================================
 * 檢查
 * ================================================== */

/**
 * 排除術語：命中文字登記在英文詞表，或出現在達門檻數的文件時，不列出套用門檻的規則。
 * @param {import("./context.mjs").Context} ctx 執行環境。
 * @param {import("./base.mjs").Finding[]} findings 發現項目。
 * @returns {import("./base.mjs").Finding[]}
 */
function dropTerms(ctx, findings) {
  const term = ctx.rules.threshold(TERM_FILES);
  const filesOf = new Map();
  // 依命中文字統計套用門檻的規則出現的文件
  for (const f of findings.filter((x) => x.rule === term.rule)) {
    const key = f.hit.toLowerCase();
    // 第一次出現時建立集合
    if (!filesOf.has(key)) filesOf.set(key, new Set());
    filesOf.get(key).add(f.file);
  }
  return findings.filter((f) => f.rule !== term.rule || !(ctx.rules.english.has(f.hit.toLowerCase()) || filesOf.get(f.hit.toLowerCase()).size >= term.value));
}

/**
 * 去除重複：同一行、同一條目與同一命中文字只留層級順位最高的一筆。
 * @param {import("./context.mjs").Context} ctx 執行環境。
 * @param {import("./base.mjs").Finding[]} findings 發現項目。
 * @returns {import("./base.mjs").Finding[]}
 */
function dedupe(ctx, findings) {
  const rank = (f) => ctx.rules.levels.get(f.level).rank;
  const kept = new Map();
  // 同一個鍵只留順位最高的一筆
  for (const f of findings) {
    const k = joinKey(f.file, f.line, f.code, f.hit);
    // 第一次出現，或順位較高時取代
    if (!kept.has(k) || rank(kept.get(k)) < rank(f)) kept.set(k, f);
  }
  return [...kept.values()];
}

/**
 * 解析每份文件，依序執行傳入的檢查，彙整發現項目。
 * @param {import("./context.mjs").Context} ctx 執行環境，發現項目記錄在 ctx.findings。
 * @param {Doc[]} docs 文件。
 * @param {Array<function(import("./context.mjs").Context, Doc): void>} checks 檢查函式，例如各檢查模組的 run。
 * @returns {import("./base.mjs").Finding[]} 排除術語、去除重複後依檔案、行號、欄號與條目排序的發現項目。
 * @throws {InputError} 文風宣告不在文風表，或門檻沒有登記。
 */
export function lintDocs(ctx, docs, checks) {
  ctx.findings = [];
  // 逐份文件解析後依序執行檢查
  for (const doc of docs) {
    ctx.prepare(doc);
    // 每個檢查都看同一份解析結果
    for (const check of checks) check(ctx, doc);
  }
  return dedupe(ctx, dropTerms(ctx, ctx.findings)).sort(compareFindings);
}

/* ==================================================
 * 自動取代
 * ================================================== */

/**
 * 以改用的寫法取代可以自動取代的命中，同一行由右到左取代。命中文字已經不在原位時略過。
 * @param {Doc[]} docs 文件。有絕對路徑的文件才取代。
 * @param {import("./base.mjs").Finding[]} findings 發現項目。
 * @returns {Doc[]} 內容有變更的文件。
 */
export function applyFixes(docs, findings) {
  const changed = [];
  // 逐份文件取代
  for (const doc of docs.filter((d) => d.abs !== null)) {
    // 保留換行拆成行，同一份文件的取代由後往前，前面的位置才不會位移
    const lines = doc.text.split(/(?<=\n)/u);
    const fixes = findings.filter((f) => f.file === doc.rel && f.replacement !== null).sort((a, b) => b.line - a.line || b.col - a.col);
    let count = 0;
    // 逐筆取代命中文字
    for (const f of fixes) {
      // 欄號以碼位計，拆成字元後比對與取代
      const chars = [...lines[f.line - 1]];
      const at = f.col - 1;
      const len = [...f.hit].length;
      // 命中文字已經不在原位時略過
      if (chars.slice(at, at + len).join("") !== f.hit) continue;
      // 以改用的寫法取代命中文字，計入取代的處數
      lines[f.line - 1] = [...chars.slice(0, at), f.replacement, ...chars.slice(at + len)].join("");
      count++;
    }
    // 有取代時更新內容
    if (count) {
      doc.text = lines.join("");
      changed.push(doc);
    }
  }
  return changed;
}
