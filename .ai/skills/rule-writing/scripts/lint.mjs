#!/usr/bin/env node
/* ==================================================
 * lint.mjs - 寫作檢查入口：依序執行版面與格式、詞彙的檢查，每筆發現項目附層級、判定問題、改法與參照
 * --------------------------------------------------
 * - 角色：本入口只組合 writing/ 的模組：決定要執行的檢查、傳入程式判定的規則名稱，依參數執行檢查、判定檢查或標準答案集
 * - 指令：lint.mjs <路徑>... [--root DIR] [--project PATH]... [--style 文風]... [--off 規則=理由]... [--fix] [--json] [--out DIR]
 * - 指令：lint.mjs --text 文字 [--style 文風]... [--off 規則=理由]... [--json]
 * - 指令：lint.mjs --judged DIR
 * - 指令：lint.mjs --cases DIR
 * - 慣例：--fix 以改用的寫法取代沒有判定問題的詞表命中，寫回檔案後重新檢查
 * - 慣例：--out 寫入 lint.json，判定欄不是「不填」的層級附 verdict 與 basis，重跑時沿用上一次內容相同的判定。
 *   --out 與 --judged 的目錄另由 runMain 附加執行紀錄 runs.txt
 * - 慣例：--cases 以標準答案集目錄為 --root 檢查目錄下的檔案，檔案、行號與規則名稱要與預期檔完全相同
 * - 慣例：結束代碼：取列出的發現項目的層級結束代碼最大值，--judged 有待處理的發現項目或 --cases 有失敗為 1，
 *   參數、機讀定義表或輸出檔錯誤為 2
 * - 參見 references/scripts-contract.md 取得權威合約
 * ================================================== */
import {
  CASES_FILE, CASES_HEADER, COMMAND, Context, Doc, EXIT_FINDINGS, EXIT_INPUT, EXIT_OK, ExitRequest, FORMAT_TEXT, InputError, OUT_FILE, USAGE, applyFixes,
  caseReport, collectFiles, countByLevel, exitCode, joinPath, judgedReport, lintDocs, lintJson, loading, parseArgs, parseTable, projectFromArgs,
  publicFields, readDocs, render, structure, summaryLine, vocab,
} from "./writing/index.mjs";
import { nodeIo as io, runMain } from "./writing/io-node.mjs";

/* ==================================================
 * 集中設定
 * ================================================== */

/**
 * 依序執行的檢查。
 */
const CHECKS = [structure.run, vocab.run];

/**
 * 由程式判定的規則名稱，載入規則時確認都登記在規則表。
 */
const PROGRAM_RULES = [...structure.RULES, ...vocab.RULES];

/**
 * --text 的文件顯示的路徑，文字不屬於任何檔案。
 */
const TEXT_NAME = "<text>";

/* ==================================================
 * 工作
 * ================================================== */

/**
 * 讀取 JSON 檔。
 * @param {string} path 路徑。
 * @returns {Object}
 * @throws {InputError} 檔案不存在或不是 JSON。
 */
function readJson(path) {
  // 沒有檔案時無從讀取
  if (!io.exists(path)) throw new InputError(`輸出檔不存在：${path}`);
  // 檔案不是 JSON 時無從讀取
  try {
    return JSON.parse(io.readText(path));
  } catch (e) {
    // 解析失敗時指出檔案與原因
    throw new InputError(`${path}: 不是 JSON：${e.message}`);
  }
}

/**
 * 判定檢查：輸出目錄的 lint.json 是否全部處理。
 * @param {Context} ctx 執行環境。
 * @param {string} dir 輸出目錄。
 * @returns {number} 結束代碼。
 */
function judged(ctx, dir) {
  // 讀取輸出目錄的 lint.json，依層級表與判定表找出待處理的發現項目
  const report = judgedReport(loading(() => readJson(joinPath(io.resolve(dir), OUT_FILE))), ctx.rules);
  io.stdout(report.text);
  // 有待處理的發現項目時結束代碼為 EXIT_FINDINGS
  return report.pending ? EXIT_FINDINGS : EXIT_OK;
}

/**
 * 標準答案集：以目錄為 --root 檢查，比對預期檔。
 * @param {Context} ctx 執行環境。
 * @param {string} raw 標準答案集目錄。
 * @returns {number} 結束代碼。
 */
function cases(ctx, raw) {
  // 讀取標準答案集目錄下的預期檔
  const dir = io.resolve(raw);
  const expected = loading(() => {
    const file = joinPath(dir, CASES_FILE);
    // 沒有預期檔時無從比對
    if (!io.exists(file)) throw new InputError(`標準答案集缺少 ${CASES_FILE}：${raw}`);
    return parseTable(io.readText(file), CASES_HEADER, CASES_FILE);
  });
  // 以標準答案集目錄為基準讀取檔案、執行檢查並比對預期
  const docs = loading(() => readDocs(io, collectFiles(io, [dir], ctx.rules.formats), dir, ctx.rules.formats));
  const report = caseReport(expected, loading(() => lintDocs(ctx, docs, CHECKS)));
  io.stdout(report.text);
  // 有失敗時結束代碼為 EXIT_FINDINGS
  return report.failed ? EXIT_FINDINGS : EXIT_OK;
}

/**
 * 檢查路徑與文字，依參數取代、寫出 lint.json 並輸出。
 * @param {Context} ctx 執行環境。
 * @param {Object} args 命令列參數。
 * @returns {number} 結束代碼。
 * @throws {ExitRequest} 沒有要檢查的路徑或文字。
 */
function lint(ctx, args) {
  // 沒有路徑也沒有文字時沒有檢查範圍
  if (!args.paths.length && !args.texts.length) throw new ExitRequest(EXIT_INPUT, `錯誤：沒有要檢查的路徑或文字\n${USAGE}`);
  // 讀取路徑下的檔案與 --text 的文字，依序執行檢查
  const root = io.resolve(args.root);
  const files = loading(() => collectFiles(io, args.paths, ctx.rules.formats));
  const docs = [...readDocs(io, files, root, ctx.rules.formats), ...args.texts.map((t) => new Doc(null, TEXT_NAME, FORMAT_TEXT, t))];
  // 依序執行版面與格式、詞彙的檢查
  let findings = loading(() => lintDocs(ctx, docs, CHECKS));
  // --fix 取代後寫回檔案並重新檢查
  if (args.fix) {
    const changed = applyFixes(docs, findings);
    // 逐份寫回有變更的檔案
    for (const doc of changed) io.writeText(doc.abs, doc.text);
    // 有變更時重新檢查
    if (changed.length) findings = loading(() => lintDocs(ctx, docs, CHECKS));
  }
  // 指定 --out 時寫入 lint.json，沿用上一次的判定
  if (args.out) {
    const path = joinPath(io.resolve(args.out), OUT_FILE);
    // 上一次的 lint.json 存在時沿用其中的判定
    const previous = io.exists(path) ? loading(() => readJson(path)) : null;
    io.writeText(path, `${JSON.stringify(lintJson(findings, previous, ctx.rules, ctx.offs), null, 1)}\n`);
  }
  // 依層級計數，供摘要行與 JSON 輸出
  const counts = countByLevel(findings, ctx.rules);
  // 依 --json 輸出一個 JSON 物件，或逐筆輸出再接摘要行
  if (args.json) {
    io.stdout(`${JSON.stringify({ command: COMMAND, files: docs.length, counts: Object.fromEntries(counts), off: Object.fromEntries(ctx.offs), findings: findings.map(publicFields) }, null, 1)}\n`);
  } else {
    // 文字模式逐筆輸出，最後接摘要行
    io.stdout(`${findings.map(render).join("")}${summaryLine(docs.length, counts)}`);
  }
  // 結束代碼取列出的發現項目的層級結束代碼最大值
  return exitCode(findings, ctx.rules);
}

/* ==================================================
 * 入口
 * ================================================== */

/**
 * 進入點：依參數執行檢查、判定檢查或標準答案集，結束代碼見檔頭。
 * @returns {number} 結束代碼。
 */
function main() {
  // 解析命令列，參數錯誤以結束代碼 EXIT_INPUT 結束
  const args = loading(() => parseArgs(process.argv.slice(2)));
  // 說明模式只輸出用法
  if (args.help) {
    io.stdout(USAGE);
    return EXIT_OK;
  }
  // 載入規則，傳入程式判定的規則名稱、--style 與 --off
  const ctx = loading(() => new Context({ io, project: projectFromArgs(args.project, io), programRules: PROGRAM_RULES, styles: args.styles, offs: args.offs }));
  // 指定 --judged 時執行判定檢查
  if (args.judged) return judged(ctx, args.judged);
  // 指定 --cases 時執行標準答案集
  if (args.cases) return cases(ctx, args.cases);
  // 其餘執行一般檢查
  return lint(ctx, args);
}

runMain(main);
