/* ==================================================
 * parse.mjs - 文件解析：行的種類、等長遮罩、區塊與成對連接詞的範圍
 * --------------------------------------------------
 * - 角色：把 markdown、mdx 與純文字解析成行，供各檢查模組使用。markdown 的版面記號取自 markdown 寫法表（Rules.marks）
 * - 指令：由 context 模組與檢查模組匯入使用
 * - 慣例：遮罩與原行等長，命中的欄號與文字都對應原行。行內 code 遮罩成 CODE_MASK，其餘遮罩成 MASK
 * - 慣例：front matter、code fence、圖表區塊與 HTML 註解區塊內的行不是正文。純文字的非空行都是段落
 * - 慣例：本模組不 import node:*
 * - 參見 references/scripts-contract.md 取得權威合約
 * ================================================== */
import { FORMAT_MDX, FORMAT_TEXT } from "./rules.mjs";

/* ==================================================
 * 集中設定
 * ================================================== */

/**
 * 遮罩字元：行內 code 以外的遮罩與行內 code 的遮罩。正規式要把行內 code 當成英文字時寫 \x01。
 */
export const MASK = "\u0000";
export const CODE_MASK = "\u0001";

/**
 * 行的種類：空行、標題、表格、清單、圖、引言、段落、區塊的開頭、內容與結尾，以及不是正文的標記。
 */
export const BLANK = "空行";
export const HEADING = "標題";
export const TABLE = "表格";
export const LIST = "清單";
export const IMAGE = "圖";
export const QUOTE = "引言";
export const PARA = "段落";
export const BLOCK_OPEN = "區塊開頭";
export const BLOCK_BODY = "區塊內容";
export const BLOCK_CLOSE = "區塊結尾";
export const MARKUP = "標記";

/**
 * 產物：表格、清單、圖與區塊的結尾。產物之後的段落是產物之後的補述的候選。
 */
export const PRODUCTS = new Set([TABLE, LIST, IMAGE, BLOCK_CLOSE]);

/**
 * 正文：遮罩後供檢查的行。
 */
export const PROSE = new Set([HEADING, TABLE, LIST, QUOTE, PARA]);

/**
 * 連續的行併成同一個區塊的種類：段落與引言的接續行。
 */
export const RUNNING = new Set([PARA, QUOTE]);

/**
 * front matter 的界線。
 */
export const FRONT_MATTER = "---";

/**
 * markdown 的 code fence：開頭的反引號或波浪號，第 1 組是記號，第 2 組是語言。
 */
export const FENCE_RE = /^\s*(`{3,}|~{3,})(.*)$/u;

/**
 * markdown 的標題，第 1 組是 # 記號，第 2 組是標題文字。
 */
export const HEADING_RE = /^(#{1,6})\s+(.*)$/u;

/**
 * markdown 的表格列、清單項與圖的開頭。
 */
const TABLE_RE = /^\s*\|/u;
const LIST_RE = /^\s*(?:[-*+]|\d+\.)\s+/u;
const IMAGE_RE = /^\s*!\[/u;

/**
 * 只有 HTML 標籤的行與分隔線，不是正文。
 */
const MARKUP_RE = /^\s*(?:<\/?[A-Za-z][^>]*>\s*)+$|^\s*-{3,}\s*$/u;

/**
 * mdx 的 import 與 export 行，不是正文。
 */
const MDX_ESM_RE = /^(?:import|export)\s/u;

/**
 * HTML 註解的開頭與結尾，以及行內的 HTML 註解。
 */
const COMMENT_OPEN = "<!--";
const COMMENT_CLOSE = "-->";
const INLINE_COMMENT_RE = /<!--.*?-->/gu;

/**
 * 行內 code：開頭與結尾的反引號數相同。
 */
const INLINE_CODE_RE = /(?<!`)(`+)(?!`).*?(?<!`)\1(?!`)/gu;

/**
 * 連結網址、HTML 標籤與 mdx 的大括號運算式。
 */
const LINK_TARGET_RE = /\]\([^)]*\)/gu;
const HTML_TAG_RE = /<\/?[A-Za-z][^>]*>/gu;
const MDX_EXPR_RE = /\{[^{}]*\}/gu;

/* ==================================================
 * 遮罩
 * ================================================== */

/**
 * 以等長的遮罩字元取代一段文字。
 * @param {string} text 被遮罩的文字。
 * @param {string} ch 遮罩字元。
 * @returns {string}
 */
export const fill = (text, ch) => ch.repeat(text.length);

/**
 * 以等長的遮罩字元遮罩一行的 HTML 註解、行內 code、連結網址、HTML 標籤、mdx 運算式與引用括號內的文字。
 * 引用括號內是被討論的寫法，不是正文的用詞。
 * @param {string} line 原行。
 * @param {Object} marks markdown 寫法表組出的寫法，提供引用括號。
 * @param {boolean} mdx 是否遮罩 mdx 運算式。
 * @returns {string}
 */
export function maskInline(line, marks, mdx) {
  let out = line.replace(INLINE_COMMENT_RE, (m) => fill(m, MASK)).replace(INLINE_CODE_RE, (m) => fill(m, CODE_MASK));
  out = out.replace(LINK_TARGET_RE, (m) => `]${fill(m.slice(1), MASK)}`).replace(HTML_TAG_RE, (m) => fill(m, MASK));
  // mdx 的大括號是運算式
  if (mdx) out = out.replace(MDX_EXPR_RE, (m) => fill(m, MASK));
  return out.replace(marks.quoted, (m, open, inner, close) => `${open}${fill(inner, MASK)}${close}`);
}

/* ==================================================
 * 行
 * ================================================== */

/**
 * 解析後的一行。
 */
export class Line {
  /**
   * @param {number} no 行號，從 1 起。
   * @param {string} raw 原行。
   * @param {string} kind 行的種類。
   * @param {number} level 標題層級，不是標題時為 0。
   * @param {boolean} inDiv 是否在加重語氣區塊內。
   * @param {boolean} starts 是否開始一個新區塊：前一行是空行、標題、標記或檔案開頭。
   * @param {string} masked 與原行等長的遮罩後文字。不是正文的行為空字串。
   */
  constructor(no, raw, kind, level, inDiv, starts, masked) {
    this.no = no;
    this.raw = raw;
    this.kind = kind;
    this.level = level;
    this.inDiv = inDiv;
    this.starts = starts;
    this.masked = masked;
    /** @type {string[]} 這一行套用的文風，由 context 模組指定。 */
    this.styles = [];
  }
}

/**
 * 判定 markdown 中區塊與 front matter 以外的一行屬於哪一種。
 * @param {string} raw 原行。
 * @param {Object} marks markdown 寫法表組出的寫法，提供 TOC 標記與引言前綴。
 * @param {boolean} mdx 是否把 import 與 export 行當成標記。
 * @returns {[string, number]} 種類與標題層級。
 */
function lineKind(raw, marks, mdx) {
  const heading = HEADING_RE.exec(raw);
  // # 開頭的行是標題，層級是 # 的個數
  if (heading) return [HEADING, heading[1].length];
  // 只有空白的行是空行
  if (raw.trim() === "") return [BLANK, 0];
  // 只有 HTML 標籤的行、分隔線、TOC 標記與 mdx 的 import、export 不是正文
  if (MARKUP_RE.test(raw) || marks.toc.has(raw.trim()) || (mdx && MDX_ESM_RE.test(raw))) return [MARKUP, 0];
  // | 開頭的行是表格列
  if (TABLE_RE.test(raw)) return [TABLE, 0];
  // 清單記號或編號開頭的行是清單項
  if (LIST_RE.test(raw)) return [LIST, 0];
  // ![ 開頭的行是圖
  if (IMAGE_RE.test(raw)) return [IMAGE, 0];
  // 引言前綴開頭的行是引言
  if (raw.trimStart().startsWith(marks.quotePrefix)) return [QUOTE, 0];
  // 其餘是段落
  return [PARA, 0];
}

/**
 * 把文字解析成行。markdown 的 front matter、code fence、圖表區塊與 HTML 註解區塊內的行不是正文，純文字的非空行都是段落。
 * @param {string} text 文件內容。
 * @param {string} format 格式。
 * @param {Object} marks markdown 寫法表組出的寫法。
 * @returns {Line[]}
 */
export function parseDoc(text, format, marks) {
  // markdown 與 mdx 依 markdown 解析，mdx 另遮罩 import、export 與大括號運算式
  const raws = text.split(/\r?\n/u);
  const mdx = format === FORMAT_MDX;
  const markdown = format !== FORMAT_TEXT;
  // 解析結果，一行一個 Line
  const out = [];
  // 逐行累積的狀態：所在的 code fence 記號、圖表區塊、註解區塊、front matter、加重語氣區塊的深度與前一行的種類
  let fence = null;
  let diagram = false;
  let comment = false;
  let front = markdown && raws[0] === FRONT_MATTER;
  let depth = 0;
  let prev = BLANK;
  // 逐行判定種類，記下 front matter、code fence、圖表區塊、註解區塊與加重語氣區塊的狀態
  raws.forEach((raw, i) => {
    let kind;
    let level = 0;
    // 先比對 code fence 的寫法，開頭與結尾都用它判定
    const m = FENCE_RE.exec(raw);
    // 依格式、front matter、code fence、圖表區塊、註解區塊、一般行的順序判定
    if (!markdown) {
      // 純文字的非空行都是段落
      kind = raw.trim() === "" ? BLANK : PARA;
    } else if (front) {
      // front matter 內的行不是正文
      kind = MARKUP;
      // front matter 的結尾界線之後是正文
      if (i > 0 && raw === FRONT_MATTER) front = false;
    } else if (fence) {
      // code fence 內的行不是正文，遇到結尾的 fence 時結束
      const closing = m && m[1][0] === fence[0] && m[1].length >= fence.length && m[2].trim() === "";
      kind = closing ? BLOCK_CLOSE : BLOCK_BODY;
      // 結尾的 fence 與開頭同字元、不短於開頭，且後面沒有文字
      if (closing) fence = null;
    } else if (diagram) {
      // 圖表區塊內的行不是正文，遇到單獨的結尾記號時結束
      kind = raw.trim() === marks.diagram ? BLOCK_CLOSE : BLOCK_BODY;
      diagram = kind !== BLOCK_CLOSE;
    } else if (m) {
      // code fence 的開頭，記下記號以比對結尾
      kind = BLOCK_OPEN;
      fence = m[1];
    } else if (raw.trimStart().startsWith(marks.diagram)) {
      // 圖表區塊的開頭
      kind = MARKUP;
      diagram = true;
    } else if (comment || raw.trim().startsWith(COMMENT_OPEN)) {
      // HTML 註解區塊內的行不是正文，同一行有結尾記號時區塊結束
      kind = MARKUP;
      comment = !raw.includes(COMMENT_CLOSE);
    } else {
      // 其餘依行的寫法判定種類
      [kind, level] = lineKind(raw, marks, mdx);
    }
    // 這一行是否在加重語氣區塊內，依這一行之前的深度判定
    const inDiv = depth > 0;
    // 加重語氣區塊的開頭與結尾決定之後的行是否在區塊內
    if (kind === MARKUP || kind === PARA) depth += (raw.match(marks.calloutOpen) ?? []).length - (raw.match(marks.calloutClose) ?? []).length;
    let masked = "";
    // 正文才遮罩，引言去掉前綴
    if (PROSE.has(kind)) {
      masked = maskInline(raw, marks, mdx);
      // 引言前綴換成等長的空白
      if (kind === QUOTE) masked = masked.replace(marks.quotePrefix, " ".repeat(marks.quotePrefix.length));
    }
    // 前一行是空行、標題或標記時，這一行開始新的區塊
    out.push(new Line(i + 1, raw, kind, level, inDiv, [BLANK, HEADING, MARKUP].includes(prev), masked));
    prev = kind;
  });
  return out;
}

/* ==================================================
 * 區塊與範圍
 * ================================================== */

/**
 * 把行分成區塊：段落或引言的連續行、清單項、一個表格列、一個標題。詞表的成群門檻以區塊計數。
 * @param {Line[]} lines 全部行。
 * @returns {Line[][]}
 */
export function blocks(lines) {
  const out = [];
  let current = null;
  // 新的段落、清單項、表格列與標題開始新的區塊，段落的接續行併入正在累積的區塊
  for (const l of lines) {
    // 不是正文的行結束正在累積的區塊
    if (!PROSE.has(l.kind)) {
      current = null;
      continue;
    }
    // 接續行併入正在累積的區塊，其餘開始新的區塊
    if (RUNNING.has(l.kind) && !l.starts && current) {
      current.push(l);
    } else {
      // 其餘開始新的區塊
      current = [l];
      out.push(current);
    }
  }
  return out;
}

/**
 * 把行分成找成對連接詞的範圍：一個段落，或項與項之間沒有空行的一份清單。
 * @param {Line[]} lines 全部行。
 * @returns {Line[][]}
 */
export function pairScopes(lines) {
  const out = [];
  let current = null;
  // 連續的段落、引言與清單行組成一個範圍，其他行結束正在累積的範圍
  for (const l of lines) {
    // 段落、引言與清單以外的行結束正在累積的範圍
    if (!RUNNING.has(l.kind) && l.kind !== LIST) {
      current = null;
      continue;
    }
    // 範圍開始於空行、標題或標記之後的第一行
    if (!current || l.starts) {
      current = [];
      out.push(current);
    }
    current.push(l);
  }
  return out;
}
