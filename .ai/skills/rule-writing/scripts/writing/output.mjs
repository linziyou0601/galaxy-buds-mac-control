/* ==================================================
 * output.mjs - 輸出：文字與 JSON、lint.json、判定檢查與標準答案集的比對
 * --------------------------------------------------
 * - 角色：把發現項目寫成多行的文字或 JSON 物件，組出 lint.json 的內容，依層級表與判定表找出待處理的發現項目，
 *   比對標準答案集的預期與實際
 * - 指令：由進入點匯入使用
 * - 慣例：本模組只產生文字與物件，讀寫檔案與標準輸出由進入點經由 io 介面執行。本模組不 import node:*
 * - 慣例：lint.json 重跑時沿用上一次輸出中檔案、條目、說明與摘錄都相同的判定，同一個鍵依出現順序沿用
 * - 參見 references/scripts-contract.md 取得權威合約
 * ================================================== */
import { EMPTY_CELL, EXIT_OK, WORD_SEPARATOR, joinKey } from "./base.mjs";
import { VERDICT_NONE, VERDICT_OPTIONAL } from "./rules.mjs";

/* ==================================================
 * 集中設定
 * ================================================== */

/**
 * 檢查入口的名稱，寫在摘要行與 JSON 輸出的 command 欄位。
 */
export const COMMAND = "lint";

/**
 * --out 寫出的檔名。
 */
export const OUT_FILE = "lint.json";

/**
 * 標準答案集預期檔的表頭：檔案、行號與規則名稱。
 */
export const CASES_HEADER = ["檔案", "行", "規則"];

/**
 * 文字輸出各行的開頭：位置、原行與判斷路徑。
 */
const LOCATION_PREFIX = "  --> ";
const EXCERPT_PREFIX = "   | ";
const PATH_PREFIX = "   = ";

/**
 * 判斷路徑三行的標籤。
 */
const JUDGE_LABEL = "判定：";
const FIX_LABEL = "改法：";
const REF_LABEL = "參照：";

/* ==================================================
 * 檢查結果
 * ================================================== */

/**
 * 把一筆發現項目寫成多行的文字：層級、條目與說明，位置，原行，判定、改法與參照。沒有判定問題時不寫判定一行。
 * @param {import("./base.mjs").Finding} f 發現項目。
 * @returns {string} 以換行結尾的文字。
 */
export function render(f) {
  const lines = [`${f.level}[${f.code}]: ${f.message}`, `${LOCATION_PREFIX}${f.file}:${f.line}:${f.col}`, `${EXCERPT_PREFIX}${f.excerpt.trim()}`];
  // 有判定問題時列出
  if (f.judge !== EMPTY_CELL) lines.push(`${PATH_PREFIX}${JUDGE_LABEL}${f.judge}`);
  lines.push(`${PATH_PREFIX}${FIX_LABEL}${f.fix}`, `${PATH_PREFIX}${REF_LABEL}${f.ref}`);
  return `${lines.join("\n")}\n`;
}

/**
 * 依層級計數，依層級順位由高到低排列。
 * @param {import("./base.mjs").Finding[]} findings 發現項目。
 * @param {import("./rules.mjs").Rules} rules 規則。
 * @returns {Array<[string, number]>} 層級與筆數。
 */
export function countByLevel(findings, rules) {
  const counts = new Map();
  // 逐筆計數
  for (const f of findings) counts.set(f.level, (counts.get(f.level) ?? 0) + 1);
  return [...counts].sort((a, b) => rules.levels.get(b[0]).rank - rules.levels.get(a[0]).rank);
}

/**
 * 摘要行：命令名稱、文件數與各層級的筆數。
 * @param {number} docs 文件數。
 * @param {Array<[string, number]>} counts 層級與筆數。
 * @returns {string} 以換行結尾的文字。
 */
export const summaryLine = (docs, counts) => `${[`command=${COMMAND}`, `files=${docs}`, ...counts.map(([k, n]) => `${k}=${n}`)].join(" ")}\n`;

/**
 * 結束代碼：列出的發現項目的層級結束代碼最大值。
 * @param {import("./base.mjs").Finding[]} findings 發現項目。
 * @param {import("./rules.mjs").Rules} rules 規則。
 * @returns {number}
 */
export const exitCode = (findings, rules) => Math.max(EXIT_OK, ...findings.map((f) => rules.levels.get(f.level).exit));

/**
 * 去掉發現項目中只供 --fix 使用的欄位。
 * @param {import("./base.mjs").Finding} f 發現項目。
 * @returns {Object}
 */
export function publicFields(f) {
  const { replacement, ...rest } = f;
  return rest;
}

/* ==================================================
 * lint.json
 * ================================================== */

/**
 * 發現項目的內容鍵，重跑時以此沿用上一次的判定。
 * @param {{file: string, code: string, message: string, excerpt: string}} f 發現項目。
 * @returns {string}
 */
const contentKey = (f) => joinKey(f.file, f.code, f.message, f.excerpt);

/**
 * 組出 lint.json 的內容：判定欄不是「不填」的層級附 verdict 與 basis，沿用上一次內容相同的判定。
 * @param {import("./base.mjs").Finding[]} findings 發現項目。
 * @param {?Object} previous 上一次的 lint.json 內容，沒有時為 null。
 * @param {import("./rules.mjs").Rules} rules 規則。
 * @param {Map<string, string>} offs 關閉的規則對應理由。
 * @returns {{off: Object<string, string>, findings: Object[]}}
 */
export function lintJson(findings, previous, rules, offs) {
  const judged = new Map();
  // 上一次輸出中已判定的發現項目依內容鍵分組，同一個鍵依出現順序沿用
  for (const x of previous?.findings ?? []) {
    // 沒有判定的發現項目略過
    if (!x.verdict) continue;
    const key = contentKey(x);
    // 內容鍵第一次出現時建立清單
    if (!judged.has(key)) judged.set(key, []);
    judged.get(key).push({ verdict: x.verdict, basis: x.basis });
  }
  const out = findings.map((f) => {
    // 不填判定的層級不附判定欄
    if (rules.levels.get(f.level).verdict === VERDICT_NONE) return publicFields(f);
    return { ...publicFields(f), ...(judged.get(contentKey(f))?.shift() ?? { verdict: null, basis: null }) };
  });
  return { off: Object.fromEntries(offs), findings: out };
}

/* ==================================================
 * 判定檢查
 * ================================================== */

/**
 * 一筆發現項目還要處理的事：結束代碼不為 0 的層級要修正，必填判定的層級要判定，選填判定的層級有填判定時依據要完整。
 * 依據要以判定值對應的開頭起頭，開頭之後要有理由。
 * @param {Object} f lint.json 的一筆發現項目。
 * @param {import("./rules.mjs").Rules} rules 規則，提供層級表與判定表。
 * @returns {?string} 待處理的原因，沒有時為 null。
 */
export function pendingOf(f, rules) {
  const level = rules.levels.get(f.level);
  // 層級要登記在層級表
  if (!level) return `層級「${f.level}」不在層級表`;
  // 結束代碼不為 0 的層級要修正
  if (level.exit !== EXIT_OK) return "要修正";
  // 不填判定的層級，以及選填判定而沒有填的發現項目，不用再處理
  if (level.verdict === VERDICT_NONE || (level.verdict === VERDICT_OPTIONAL && !f.verdict)) return null;
  // 判定要是判定表的值
  if (!rules.verdicts.has(f.verdict)) return `判定要是${[...rules.verdicts.keys()].join(WORD_SEPARATOR)}之一`;
  // 依據要以判定值對應的開頭起頭，開頭之後要有理由
  const lead = rules.verdicts.get(f.verdict);
  const basis = String(f.basis ?? "").trim();
  return basis.startsWith(lead) && basis.length > lead.length ? null : `依據要以「${lead}」起頭並寫出理由`;
}

/**
 * 判定檢查的報告：關閉的規則與理由、待處理的發現項目與摘要行。
 * @param {{off?: Object<string, string>, findings: Object[]}} data lint.json 的內容。
 * @param {import("./rules.mjs").Rules} rules 規則。
 * @returns {{text: string, pending: number}} 報告文字與待處理的筆數。
 */
export function judgedReport(data, rules) {
  // 逐筆找出待處理的原因
  const pending = data.findings.map((f) => [f, pendingOf(f, rules)]).filter(([, p]) => p !== null);
  // 報告依序列出關閉的規則、待處理的發現項目與摘要行
  const lines = [
    ...Object.entries(data.off ?? {}).map(([rule, reason]) => `關閉 ${rule}：${reason}`),
    ...pending.map(([f, p]) => `待處理 ${f.file}:${f.line}: ${f.level}[${f.code}] ${f.message}：${p}`),
    `command=lint-judged findings=${data.findings.length} pending=${pending.length}`,
  ];
  return { text: `${lines.join("\n")}\n`, pending: pending.length };
}

/* ==================================================
 * 標準答案集
 * ================================================== */

/**
 * 比對標準答案集的預期與實際：檔案、行號與規則名稱要完全相同。
 * @param {string[][]} expected 預期檔的資料列。
 * @param {import("./base.mjs").Finding[]} findings 實際的發現項目。
 * @returns {{text: string, failed: number}} 報告文字與失敗的筆數。
 */
export function caseReport(expected, findings) {
  // 預期與實際都以「檔案:行號 規則」為鍵
  const key = (file, line, rule) => `${file}:${line} ${rule}`;
  const want = new Set(expected.map(([file, line, rule]) => key(file, line, rule)));
  const got = new Set(findings.map((f) => key(f.file, f.line, f.rule)));
  // 預期有而實際沒有的是缺少，實際有而預期沒有的是多出
  const missing = [...want].filter((k) => !got.has(k));
  const extra = [...got].filter((k) => !want.has(k));
  // 報告逐筆列出缺少與多出，最後接摘要行
  const lines = [...missing.map((k) => `FAIL 缺少 ${k}`), ...extra.map((k) => `FAIL 多出 ${k}`)];
  lines.push(`command=lint-cases passed=${want.size - missing.length} failed=${missing.length + extra.length}`);
  return { text: `${lines.join("\n")}\n`, failed: missing.length + extra.length };
}
