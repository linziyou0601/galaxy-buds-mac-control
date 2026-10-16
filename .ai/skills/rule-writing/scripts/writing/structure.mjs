/* ==================================================
 * structure.mjs - 版面與格式的檢查：Wiki 版面、code block 語言、句中粗體與產物之後的補述
 * --------------------------------------------------
 * - 角色：依 markdown 寫法表與解析後的行，檢查標題、分隔、側欄排序檔、code fence、粗體位置與產物之後的段落
 * - 指令：由進入點以 run(ctx, doc) 呼叫，RULES 傳給 Context 確認規則都登記在規則表
 * - 慣例：Wiki 版面的檢查只在 Context.prepare() 判定為 Wiki 版面的 markdown 檔執行。規則的層級與範圍由 Context.report() 決定
 * - 慣例：側欄排序檔經由 io 介面讀取，本模組不 import node:*
 * - 參見 references/scripts-contract.md 取得權威合約
 * ================================================== */
import { PATH_SEP, baseName, extName, joinPath, splitLines } from "./base.mjs";
import { BLANK, BLOCK_OPEN, FENCE_RE, HEADING, HEADING_RE, LIST, MARKUP, PARA, PRODUCTS, QUOTE, RUNNING, TABLE } from "./parse.mjs";
import { FORMAT_TEXT } from "./rules.mjs";

/* ==================================================
 * 集中設定
 * ================================================== */

/**
 * 本模組判定的規則名稱，條目、層級與說明取自規則表。
 */
const TOC_MISSING = "TOC 缺少";
const HEADING_SKIP = "標題跳級";
const H1_SEPARATOR_MISMATCH = "H1 分隔不符";
const H2_SEPARATOR_MISMATCH = "H2 分隔不符";
const HEADING_TOO_DEEP = "標題過深";
const H2_LANGUAGE_MIX = "H2 語言混用";
const ORDER_MISSING = ".order 沒有登記";
const FENCE_NO_LANGUAGE = "code block 沒有語言";
const AFTER_PRODUCT = "產物之後的補述";
const INLINE_BOLD = "句中粗體";

/**
 * 本模組判定的全部規則，由進入點傳給 Context 確認登記在規則表。
 */
export const RULES = [TOC_MISSING, HEADING_SKIP, H1_SEPARATOR_MISMATCH, H2_SEPARATOR_MISMATCH, HEADING_TOO_DEEP, H2_LANGUAGE_MIX, ORDER_MISSING,
  FENCE_NO_LANGUAGE, AFTER_PRODUCT, INLINE_BOLD];

/**
 * 標題跳級的說明中，上一個標題不存在（檔案開頭）時代入的值。
 */
const NO_HEADING = "無";

/**
 * markdown 的粗體、區塊開頭的粗體（行首、清單記號或表格第一格之後）與單獨一行的粗體（前面可以有一個表情符號）。
 */
const BOLD_RE = /\*\*[^*]+\*\*/gu;
const BLOCK_START_BOLD_RE = /^\s*(?:(?:[-*+]|\d+\.)\s+|\|\s*)?\*\*[^*]+\*\*/u;
const SUBTITLE_RE = /^\s*(?:\p{Extended_Pictographic}️?\s*)?\*\*[^*]+\*\*\s*$/u;

/**
 * 判定 H2 語言的中文字與英文字。
 */
const CJK_RE = /\p{Script=Han}/u;
const LATIN_RE = /[A-Za-z]/u;

/* ==================================================
 * Wiki 版面
 * ================================================== */

/**
 * 比對一行之前的幾行是否依序等於分隔寫法。
 * @param {import("./parse.mjs").Line[]} lines 全部行。
 * @param {number} at 目標行的索引。
 * @param {string[]} expected 分隔寫法，由上到下。
 * @returns {boolean}
 */
function precededBy(lines, at, expected) {
  const start = at - expected.length;
  return start >= 0 && expected.every((e, k) => lines[start + k].raw.trim() === e);
}

/**
 * 檢查側欄排序檔：檔案所在目錄有排序檔時，檔名（不含副檔名）要登記在其中。
 * @param {import("./context.mjs").Context} ctx 執行環境。
 * @param {import("./context.mjs").Doc} doc 文件。
 */
function checkOrder(ctx, doc) {
  // --text 沒有所在目錄
  if (doc.abs === null) return;
  const order = joinPath(doc.abs.slice(0, doc.abs.lastIndexOf(PATH_SEP)), ctx.rules.marks.orderFile);
  const stem = baseName(doc.abs).slice(0, baseName(doc.abs).length - extName(doc.abs).length);
  // 沒有排序檔，或檔名已登記時不列出
  if (!ctx.io.exists(order) || splitLines(ctx.io.readText(order)).map((x) => x.trim()).includes(stem)) return;
  ctx.report(doc, ORDER_MISSING, doc.lines.find((l) => l.kind !== BLANK) ?? doc.lines[0], 0, "", { 檔名: stem });
}

/**
 * 檢查 Wiki 版面：TOC、標題層級、H1 與 H2 的分隔、標題深度與 H2 的語言。
 * @param {import("./context.mjs").Context} ctx 執行環境。
 * @param {import("./context.mjs").Doc} doc 文件。
 */
function checkWiki(ctx, doc) {
  const { lines } = doc;
  const marks = ctx.rules.marks;
  // 找出第一個標題
  const firstHeading = lines.findIndex((l) => l.kind === HEADING);
  // 第一個標題之前要有 TOC 標記
  if (firstHeading >= 0 && !lines.slice(0, firstHeading).some((l) => marks.toc.has(l.raw.trim()))) ctx.report(doc, TOC_MISSING, lines[firstHeading], 0, "", {});
  // 逐個標題累積的狀態：上一個標題的層級、是否出現過 H1、所在 H1 下的 H2 數與全部 H2
  let prevLevel = 0;
  let h1Seen = false;
  let h2InSection = 0;
  const h2 = [];
  // 依序檢查每個標題的層級與分隔
  lines.forEach((l, i) => {
    // 只看標題
    if (l.kind !== HEADING) return;
    // 層級一次只能往下一層
    if (l.level > prevLevel + 1) ctx.report(doc, HEADING_SKIP, l, 0, "", { 上層: prevLevel === 0 ? NO_HEADING : `H${prevLevel}`, 本層: l.level });
    // 超過標題最深層級的細項改用粗體標籤
    if (l.level > marks.maxLevel) ctx.report(doc, HEADING_TOO_DEEP, l, 0, "", { 最深: marks.maxLevel });
    // 第二個以後的 H1 要有 H1 分隔，同一個 H1 下第二個以後的 H2 要有 H2 分隔
    if (l.level === 1) {
      // 第一個 H1 之前不需要分隔
      if (h1Seen && !precededBy(lines, i, marks.h1)) ctx.report(doc, H1_SEPARATOR_MISMATCH, l, 0, "", {});
      // 記下出現過 H1，新的 H1 下重新計算 H2
      h1Seen = true;
      h2InSection = 0;
    } else if (l.level === 2) {
      // 同一個 H1 下的第一個 H2 之前不需要分隔
      if (h2InSection > 0 && !precededBy(lines, i, marks.h2)) ctx.report(doc, H2_SEPARATOR_MISMATCH, l, 0, "", {});
      h2InSection++;
      h2.push(l);
    }
    // 記下這個標題的層級，供下一個標題比對
    prevLevel = l.level;
  });
  // H2 分成含中文的標題與只有英文的標題
  const cjk = h2.filter((l) => CJK_RE.test(l.masked));
  const latin = h2.filter((l) => !CJK_RE.test(l.masked) && LATIN_RE.test(l.masked));
  // 中文標題與英文標題並存時，從數量少的一邊列出
  if (cjk.length && latin.length) {
    // 逐個列出數量少的一邊
    for (const l of cjk.length < latin.length ? cjk : latin) ctx.report(doc, H2_LANGUAGE_MIX, l, 0, "", { 標題: l.raw.replace(HEADING_RE, "$2") });
  }
  checkOrder(ctx, doc);
}

/* ==================================================
 * 格式與產物
 * ================================================== */

/**
 * 檢查 code fence 的語言、句中粗體與產物之後的補述。
 * @param {import("./context.mjs").Context} ctx 執行環境。
 * @param {import("./context.mjs").Doc} doc 文件。
 */
function checkFormat(ctx, doc) {
  let afterProduct = false;
  // 逐行檢查，afterProduct 表示上一個區塊是產物
  for (const l of doc.lines) {
    const fence = l.kind === BLOCK_OPEN ? FENCE_RE.exec(l.raw) : null;
    // code fence 的開頭要標明語言
    if (fence && fence[2].trim() === "") ctx.report(doc, FENCE_NO_LANGUAGE, l, 0, "", {});
    const subtitle = SUBTITLE_RE.test(l.masked);
    // 區塊開頭以外的粗體列為句中粗體，加重語氣區塊內與單獨一行的粗體除外
    if ([PARA, QUOTE, LIST, TABLE].includes(l.kind) && !l.inDiv && !subtitle) {
      const startBold = BLOCK_START_BOLD_RE.exec(l.masked);
      // 區塊開頭的第一個粗體略過，其餘逐一列出
      for (const m of l.masked.matchAll(BOLD_RE)) {
        // 區塊開頭的粗體是標籤位置
        if (!(startBold && m.index + m[0].length === startBold[0].length)) ctx.report(doc, INLINE_BOLD, l, m.index, m[0], { 粗體: m[0] });
      }
    }
    // 依區塊的種類更新產物狀態，產物之後開始的段落沒有引出下一個產物時列出
    if (PRODUCTS.has(l.kind)) {
      // 產物之後開始找補述
      afterProduct = true;
    } else if (l.kind === HEADING || l.kind === MARKUP || subtitle) {
      // 標題、標記與單獨一行的粗體開始新的主題
      afterProduct = false;
    } else if (RUNNING.has(l.kind) && l.starts) {
      // 以引出標點結尾的段落是下一個產物的說明
      if (afterProduct && !ctx.rules.marks.leadEnd.test(l.raw)) ctx.report(doc, AFTER_PRODUCT, l, 0, "", {});
      afterProduct = false;
    }
  }
}

/* ==================================================
 * 入口
 * ================================================== */

/**
 * 檢查一份文件的版面與格式。純文字沒有 markdown 版面，不檢查。
 * @param {import("./context.mjs").Context} ctx 執行環境。
 * @param {import("./context.mjs").Doc} doc 已解析的文件。
 */
export function run(ctx, doc) {
  // 純文字沒有標題、粗體與產物
  if (doc.format === FORMAT_TEXT) return;
  // Wiki 版面的檢查只在 Wiki 版面的檔案執行
  if (doc.wiki) checkWiki(ctx, doc);
  checkFormat(ctx, doc);
}
