/* ==================================================
 * rules.mjs - 規則、層級、文風、詞表、正規式、版面與 markdown 寫法的載入與驗證
 * --------------------------------------------------
 * - 角色：讀取全部機讀定義表，檢查格子值與表與表之間的指向，組成一次執行共用的 Rules
 * - 指令：由 context 模組與進入點匯入使用
 * - 慣例：程式判定的規則名稱由呼叫者以 programRules 傳入（各檢查模組匯出的 RULES），本模組確認它們都登記在規則表，
 *   規則表的每條規則都有程式、正規式或詞表使用
 * - 慣例：條目索引的參照以 io 讀取 skill 目錄下的 md，確認檔案與標題存在
 * - 慣例：本模組不 import node:*
 * - 參見 references/scripts-contract.md 取得權威合約
 * ================================================== */
import {
  AVOID_FILE, AVOID_HEADER, BOUNDARY_FILE, BOUNDARY_HEADER, EMPTY_CELL, ENGLISH_FILE, ENGLISH_HEADER, FORMATS_FILE, FORMATS_HEADER, INDEX_FILE,
  INDEX_HEADER, InputError, LEVELS_FILE, LEVELS_HEADER, LOCALE_FILE, LOCALE_HEADER, MARKDOWN_FILE, MARKDOWN_HEADER, NO, PAIRS_FILE, PAIRS_HEADER,
  PATTERNS_FILE, PATTERNS_HEADER, PROFILES_FILE, PROFILES_HEADER, RULES_FILE, RULES_HEADER, STYLES_FILE, STYLES_HEADER, STYLE_LEVELS_FILE,
  STYLE_LEVELS_HEADER, THRESHOLDS_FILE, THRESHOLDS_HEADER, VERDICTS_FILE, VERDICTS_HEADER, WORD_SEPARATOR, YES, escapeRegex, globToRegExp, joinPath,
  readTable, requirePositive, requireProjectTables, requireValue, splitCell, splitLines,
} from "./base.mjs";

/* ==================================================
 * 集中設定
 * ================================================== */

/**
 * 層級表判定欄的值：必須填寫、可以填寫、不填寫。
 */
export const VERDICT_REQUIRED = "必填";
export const VERDICT_OPTIONAL = "選填";
export const VERDICT_NONE = "不填";
const VERDICT_MODES = new Set([VERDICT_REQUIRED, VERDICT_OPTIONAL, VERDICT_NONE]);

/**
 * 層級表嚴重度欄的值，不輸出的層級寫 EMPTY_CELL。
 */
const SEVERITIES = new Set(["Critical", "Major", "Minor", "Nit", EMPTY_CELL]);

/**
 * 規則表範圍欄的值：任何格式、markdown 與 mdx、Wiki 版面的檔案。
 */
export const SCOPE_TEXT = "文字";
export const SCOPE_MARKDOWN = "markdown";
export const SCOPE_WIKI = "Wiki 版面";
const SCOPES = new Set([SCOPE_TEXT, SCOPE_MARKDOWN, SCOPE_WIKI]);

/**
 * 格式表格式欄的值。--text 的文字是純文字。
 */
export const FORMAT_MARKDOWN = "markdown";
export const FORMAT_MDX = "mdx";
export const FORMAT_TEXT = "純文字";
const FORMATS = new Set([FORMAT_MARKDOWN, FORMAT_MDX, FORMAT_TEXT]);

/**
 * 正規式表比對對象欄的值：全部有文字的行、表格列以外的行、段落與清單的行。
 */
export const TARGET_MASKED = "遮罩行";
export const TARGET_NON_TABLE = "表格以外";
export const TARGET_PARA_LIST = "段落與清單";
const TARGETS = new Set([TARGET_MASKED, TARGET_NON_TABLE, TARGET_PARA_LIST]);

/**
 * 文風覆寫表規則欄代表全部規則的值。同一個文風內指名規則的列優先。
 */
export const ALL_RULES = "全部";

/**
 * 正規式表的正規式旗標：d 取得具名群組的位置，g 逐一比對，u 支援 Unicode 屬性。
 */
const PATTERN_FLAGS = "dgu";

/**
 * markdown 寫法表的名稱：H1 與 H2 之前的分隔行、TOC 標記、圖表區塊、引言前綴、標題最深層級、側欄排序檔、
 * 加重語氣區塊的標籤、引出產物的標點、引用括號、文風宣告的名稱與結束值。
 */
const MARK_H1_SEPARATOR = "H1 分隔";
const MARK_H2_SEPARATOR = "H2 分隔";
const MARK_TOC = "TOC 標記";
const MARK_DIAGRAM = "圖表區塊";
const MARK_QUOTE_PREFIX = "引言前綴";
const MARK_MAX_LEVEL = "標題最深層級";
const MARK_ORDER_FILE = "側欄排序檔";
const MARK_CALLOUT = "加重語氣區塊";
const MARK_LEAD = "引出標點";
const MARK_QUOTE = "引用括號";
const MARK_STYLE = "文風宣告";
const MARK_STYLE_END = "文風宣告結束";

/**
 * markdown 寫法表必須登記的名稱，缺少或多出時停止載入。
 */
const MARK_NAMES = [MARK_H1_SEPARATOR, MARK_H2_SEPARATOR, MARK_TOC, MARK_DIAGRAM, MARK_QUOTE_PREFIX, MARK_MAX_LEVEL, MARK_ORDER_FILE, MARK_CALLOUT,
  MARK_LEAD, MARK_QUOTE, MARK_STYLE, MARK_STYLE_END];

/**
 * 分隔行的值裡表示空行的寫法。
 */
const BLANK_TOKEN = "空行";

/**
 * markdown 的標題層數上限，標題最深層級不能超過。
 */
export const MARKDOWN_LEVELS = 6;

/**
 * 參照欄的檔案與標題分隔字元，以及 md 的標題行。
 */
const REF_SEPARATOR = "#";
const MD_HEADING_RE = /^#{1,6}\s+(.*?)\s*$/u;

/**
 * 全為可列印 ASCII 的寫法，以英文詞的方式比對：不分大小寫並比對完整單字。
 */
const ASCII_RE = /^[\x20-\x7e]+$/u;

/* ==================================================
 * 各表的載入
 * ================================================== */

/**
 * 由 markdown 寫法表組出各檢查使用的寫法與比對式。
 * @param {string[][]} rows 寫法表的資料列。
 * @returns {Object} 寫法與比對式。
 * @throws {InputError} 名稱不是登記的名稱、名稱重複或缺少，標題最深層級不是 1 到 MARKDOWN_LEVELS，或引用括號不是一個開括號與一個閉括號。
 */
function loadMarks(rows) {
  const values = new Map();
  // 逐列登記名稱與值
  for (const [name, value] of rows) {
    // 名稱寫錯或重複時無法判斷要用哪一列
    if (!MARK_NAMES.includes(name) || values.has(name)) throw new InputError(`${MARKDOWN_FILE}: 「${name}」不是登記的名稱，或重複出現`);
    values.set(name, value);
  }
  // 每個名稱都要有值，缺少時對應的檢查無法進行
  for (const name of MARK_NAMES) {
    // 缺少時報出這個名稱
    if (!values.has(name)) throw new InputError(`${MARKDOWN_FILE}: 缺少「${name}」`);
  }
  /**
   * 以頓號拆開一個名稱的值，BLANK_TOKEN 換成空行。
   * @param {string} name 名稱。
   * @returns {string[]}
   */
  const list = (name) => values.get(name).split(WORD_SEPARATOR).map((v) => (v === BLANK_TOKEN ? "" : v));
  const leads = list(MARK_LEAD).map(escapeRegex).join("|");
  const quote = list(MARK_QUOTE);
  // 引用括號要是開括號與閉括號兩個值
  if (quote.length !== 2) throw new InputError(`${MARKDOWN_FILE}: 「${MARK_QUOTE}」要寫開括號與閉括號兩個值`);
  const [open, close] = quote.map(escapeRegex);
  const maxLevel = Number(values.get(MARK_MAX_LEVEL));
  // markdown 的標題最多 MARKDOWN_LEVELS 層
  if (!Number.isInteger(maxLevel) || maxLevel < 1 || maxLevel > MARKDOWN_LEVELS) throw new InputError(`${MARKDOWN_FILE}: 「${MARK_MAX_LEVEL}」要是 1 到 ${MARKDOWN_LEVELS}`);
  // 加重語氣區塊的標籤與文風宣告的名稱照字面比對
  const tag = escapeRegex(values.get(MARK_CALLOUT));
  const styleKey = escapeRegex(values.get(MARK_STYLE));
  // 分隔行、TOC 標記、引出標點與引用括號組成各檢查使用的寫法與比對式
  return {
    toc: new Set(list(MARK_TOC)),
    diagram: values.get(MARK_DIAGRAM),
    quotePrefix: values.get(MARK_QUOTE_PREFIX),
    maxLevel,
    h1: list(MARK_H1_SEPARATOR),
    h2: list(MARK_H2_SEPARATOR),
    orderFile: values.get(MARK_ORDER_FILE),
    leadEnd: new RegExp(`(?:${leads})\\s*$`, "u"),
    calloutOpen: new RegExp(`<${tag}\\b`, "giu"),
    calloutClose: new RegExp(`</${tag}>`, "giu"),
    quoted: new RegExp(`(${open})([^${close}]*)(${close})`, "gu"),
    styleFront: new RegExp(`^${styleKey}\\s*:\\s*(.+?)\\s*$`, "u"),
    styleComment: new RegExp(`^\\s*<!--\\s*${styleKey}\\s*:\\s*(.+?)\\s*-->\\s*$`, "u"),
    styleEnd: values.get(MARK_STYLE_END),
  };
}

/**
 * 讀取條目索引，並確認每個參照的檔案與標題存在。
 * @param {string[][]} rows 條目索引的資料列。
 * @param {Object} io io 介面，需提供 skillDir。
 * @returns {Map<string, string>} 條目編號對應參照。
 * @throws {InputError} 條目重複、參照沒有寫成「檔案#標題」，或檔案、標題不存在。
 */
function loadIndex(rows, io) {
  const headings = new Map();
  const out = new Map();
  // 逐列確認參照
  for (const [code, , ref] of rows) {
    // 同一個條目登記兩次時無法判斷參照
    if (out.has(code)) throw new InputError(`${INDEX_FILE}: 條目「${code}」重複`);
    const at = ref.indexOf(REF_SEPARATOR);
    // 參照要有檔案與標題
    if (at <= 0) throw new InputError(`${INDEX_FILE}: ${code} 的參照「${ref}」要寫成「檔案${REF_SEPARATOR}標題」`);
    const file = ref.slice(0, at);
    // 每個檔案只讀一次標題
    if (!headings.has(file)) {
      const abs = joinPath(io.skillDir, file);
      // 參照的檔案不存在時讀者找不到說明
      if (!io.exists(abs)) throw new InputError(`${INDEX_FILE}: ${code} 參照的檔案不存在：${file}`);
      headings.set(file, new Set(splitLines(io.readText(abs)).map((l) => MD_HEADING_RE.exec(l)?.[1]).filter(Boolean)));
    }
    // 參照的標題不存在時讀者找不到說明
    if (!headings.get(file).has(ref.slice(at + 1))) throw new InputError(`${INDEX_FILE}: ${code} 參照的標題不存在：${ref}`);
    out.set(code, ref);
  }
  return out;
}

/**
 * 讀取層級表，並找出唯一不輸出的層級。
 * @param {string[][]} rows 層級表的資料列。
 * @returns {{levels: Map<string, Object>, off: string}} 層級名稱對應設定，以及不輸出的層級名稱。
 * @throws {InputError} 值不是允許的值，或輸出為否的層級不是剛好一個。
 */
function loadLevels(rows) {
  const levels = new Map(rows.map(([name, rank, output, exit, verdict, severity]) => {
    // 輸出、判定與嚴重度要是登記的值
    requireValue(output, new Set([YES, NO]), `${LEVELS_FILE}: ${name} 的輸出`);
    requireValue(verdict, VERDICT_MODES, `${LEVELS_FILE}: ${name} 的判定`);
    requireValue(severity, SEVERITIES, `${LEVELS_FILE}: ${name} 的嚴重度`);
    // 順位與結束代碼要是非負整數
    if (!/^\d+$/u.test(rank) || !/^\d+$/u.test(exit)) throw new InputError(`${LEVELS_FILE}: ${name} 的順位與結束代碼要是非負整數`);
    return [name, { name, rank: Number(rank), output: output === YES, exit: Number(exit), verdict, severity }];
  }));
  // 找出不輸出的層級
  const offs = [...levels.values()].filter((l) => !l.output);
  // --off 與文風的關閉需要剛好一個不輸出的層級
  if (offs.length !== 1) throw new InputError(`${LEVELS_FILE}: 輸出為否的層級要剛好一個`);
  return { levels, off: offs[0].name };
}

/**
 * 讀取文風表與文風覆寫表。後出現的覆寫列取代同文風、同規則的列。
 * @param {string[][]} styleRows 文風表的資料列。
 * @param {string[][]} overrideRows 文風覆寫表的資料列。
 * @param {Map<string, Object>} rules 規則表。
 * @param {Map<string, Object>} levels 層級表。
 * @returns {Map<string, Map<string, string>>} 文風對應「規則名稱對應層級」。
 * @throws {InputError} 文風、規則或層級不是登記的值。
 */
function loadStyles(styleRows, overrideRows, rules, levels) {
  const styles = new Map(styleRows.map(([name]) => [name, new Map()]));
  // 文風覆寫依序登記
  for (const [style, rule, level] of overrideRows) {
    requireValue(style, styles, `${STYLE_LEVELS_FILE}: 文風`);
    // 「全部」以外的規則要在規則表
    if (rule !== ALL_RULES) requireValue(rule, rules, `${STYLE_LEVELS_FILE}: ${style} 的規則`);
    requireValue(level, levels, `${STYLE_LEVELS_FILE}: ${style} 的層級`);
    styles.get(style).set(rule, level);
  }
  return styles;
}

/**
 * 讀取詞表：不使用寫法與技術用語合成一份依長度由長到短排列的詞表，英文詞表另外組成標準寫法的對照。
 * @param {Object<string, string>} tables 機讀定義表的檔名對應文字。
 * @param {import("./base.mjs").Project} project 專案輸入。
 * @param {Object} io io 介面。
 * @param {Map<string, Object>} rules 規則表。
 * @returns {{words: Object[], english: Map<string, string>}} 詞表，以及英文詞的小寫寫法對應標準寫法。
 * @throws {InputError} 規則不存在或沒有成群門檻，或同一個寫法登記兩次。
 */
function loadWords(tables, project, io, rules) {
  const words = [];
  const seen = new Map();
  /**
   * 登記一個詞。
   * @param {string} word 詞。
   * @param {string} rule 規則名稱。
   * @param {string} use 改用的寫法，沒有時為 EMPTY_CELL。
   * @param {string[]} exceptions 含這個詞的例外整詞。
   * @param {string} source 來源檔名。
   */
  const add = (word, rule, use, exceptions, source) => {
    requireValue(rule, rules, `${source}: ${word} 的規則`);
    // 詞表的規則要有成群門檻
    if (rules.get(rule).threshold === 0) throw new InputError(`${source}: ${word} 的規則「${rule}」沒有成群門檻`);
    const key = word.toLowerCase();
    // 同一個寫法登記兩次時無法判斷以哪一列為準
    if (seen.has(key)) throw new InputError(`${source}: 寫法「${word}」與 ${seen.get(key)} 重複`);
    seen.set(key, source);
    words.push({ word, key, ascii: ASCII_RE.test(word), rule, use, exceptions });
  };
  // 不使用寫法逐列登記
  for (const [word, rule, use, exceptions] of readTable(tables, project, io, AVOID_FILE, AVOID_HEADER)) add(word, rule, use, splitCell(exceptions), AVOID_FILE);
  // 技術用語只登記有大陸寫法與規則的列
  for (const [, , mainland, taiwan, , rule, exceptions] of readTable(tables, project, io, LOCALE_FILE, LOCALE_HEADER)) {
    // 沒有大陸寫法或規則的列只作參考
    if (mainland !== EMPTY_CELL && rule !== EMPTY_CELL) add(mainland, rule, taiwan, splitCell(exceptions), LOCALE_FILE);
  }
  const english = new Map();
  // 英文詞以表內寫法為標準寫法，全部列都視為術語
  for (const [word] of readTable(tables, project, io, ENGLISH_FILE, ENGLISH_HEADER)) {
    const key = word.toLowerCase();
    // 不分大小寫登記兩次時無法判斷以哪一列為準
    if (seen.has(key) || english.has(key)) throw new InputError(`${ENGLISH_FILE}: 寫法「${word}」重複`);
    english.set(key, word);
  }
  // 同一位置取最長的詞，長的詞排在前面
  words.sort((a, b) => b.word.length - a.word.length);
  return { words, english };
}

/* ==================================================
 * 規則
 * ================================================== */

/**
 * 一次執行的規則：規則、層級、判定、文風、門檻、正規式、成對連接詞、版面、格式、詞表與 markdown 寫法。
 */
export class Rules {
  /**
   * @param {Object} parts 各表載入的結果，欄位見 loadRules。
   */
  constructor(parts) {
    Object.assign(this, parts);
  }

  /**
   * 取得一條規則。
   * @param {string} name 規則名稱。
   * @returns {Object} 條目、預設層級、範圍、成群門檻、說明範本、判定問題、改法範本與參照。
   * @throws {InputError} 規則沒有登記。
   */
  rule(name) {
    requireValue(name, this.rules, `${RULES_FILE}: 規則`);
    return this.rules.get(name);
  }

  /**
   * 取得一個門檻。
   * @param {string} name 門檻名稱。
   * @returns {{rule: string, value: number}} 套用的規則與值。
   * @throws {InputError} 門檻沒有登記。
   */
  threshold(name) {
    requireValue(name, this.thresholds, `${THRESHOLDS_FILE}: 門檻`);
    return this.thresholds.get(name);
  }
}

/**
 * 讀取全部機讀定義表並驗證值與指向。
 * @param {import("./base.mjs").Project} project 專案輸入。
 * @param {Object} io io 介面，讀取專案定義表與條目索引參照的 md。
 * @param {Object<string, string>} tables 機讀定義表的檔名對應文字。
 * @param {string[]} programRules 由程式判定的規則名稱，各檢查模組匯出的 RULES。
 * @returns {Rules}
 * @throws {InputError} 專案定義表不是可以擴充的表、格式錯誤、值不是允許的值、正規式無法編譯、指向不存在，
 *   或規則沒有被任何檢查使用。
 */
export function loadRules(project, io, tables, programRules) {
  requireProjectTables(project, io);
  /**
   * 讀取一張表並併入專案定義表。
   * @param {string} name 檔名。
   * @param {string[]} header 表頭。
   * @returns {string[][]}
   */
  const read = (name, header) => readTable(tables, project, io, name, header);
  // 先讀層級、判定與條目索引，規則表的值依它們驗證
  const { levels, off } = loadLevels(read(LEVELS_FILE, LEVELS_HEADER));
  const verdicts = new Map(read(VERDICTS_FILE, VERDICTS_HEADER).map(([name, lead]) => [name, lead]));
  const index = loadIndex(read(INDEX_FILE, INDEX_HEADER), io);
  // 規則表的每一列組成一條規則，參照取自條目索引
  const rules = new Map(read(RULES_FILE, RULES_HEADER).map(([name, code, level, scope, threshold, template, judge, fix]) => {
    // 層級、範圍與條目要是登記的值，成群門檻是「-」或正整數
    requireValue(level, levels, `${RULES_FILE}: ${name} 的層級`);
    requireValue(scope, SCOPES, `${RULES_FILE}: ${name} 的範圍`);
    requireValue(code, index, `${RULES_FILE}: ${name} 的條目`);
    // 成群門檻寫「-」時為 0，表示不是詞表的規則
    const group = threshold === EMPTY_CELL ? 0 : requirePositive(threshold, `${RULES_FILE}: ${name} 的成群門檻`);
    return [name, { name, code, level, scope, threshold: group, template, judge, fix, ref: index.get(code) }];
  }));
  // 文風覆寫依規則表與層級表驗證
  const styles = loadStyles(read(STYLES_FILE, STYLES_HEADER), read(STYLE_LEVELS_FILE, STYLE_LEVELS_HEADER), rules, levels);
  // 層級要求判定時，規則要有判定問題
  for (const r of rules.values()) {
    const used = [r.level, ...[...styles.values()].map((s) => s.get(r.name)).filter(Boolean)];
    // 沒有判定問題的規則不能落在必填判定的層級
    if (r.judge === EMPTY_CELL && used.some((l) => levels.get(l).verdict === VERDICT_REQUIRED)) throw new InputError(`${RULES_FILE}: ${r.name} 沒有判定問題，層級不能要求判定`);
  }
  const patterns = read(PATTERNS_FILE, PATTERNS_HEADER).map(([rule, target, source, exceptions]) => {
    // 規則與比對對象要是登記的值
    requireValue(rule, rules, `${PATTERNS_FILE}: 規則`);
    requireValue(target, TARGETS, `${PATTERNS_FILE}: ${rule} 的比對對象`);
    // 正規式寫錯時整張表無效
    try {
      return { rule, target, re: new RegExp(source, PATTERN_FLAGS), exceptions: new Set(splitCell(exceptions)) };
    } catch (e) {
      // 編譯失敗時指出規則與原因
      throw new InputError(`${PATTERNS_FILE}: ${rule} 的正規式錯誤：${e.message}`);
    }
  });
  // 成對連接詞的接續詞與例外拆成多個值
  const pairs = read(PAIRS_FILE, PAIRS_HEADER).map(([open, closers, exceptions]) => ({ open, closers: splitCell(closers), exceptions: splitCell(exceptions) }));
  const thresholds = new Map(read(THRESHOLDS_FILE, THRESHOLDS_HEADER).map(([name, rule, value]) => {
    // 門檻套用的規則要在規則表，值要是正整數
    requireValue(rule, rules, `${THRESHOLDS_FILE}: ${name} 的規則`);
    return [name, { rule, value: requirePositive(value, `${THRESHOLDS_FILE}: ${name} 的值`) }];
  }));
  const profiles = read(PROFILES_FILE, PROFILES_HEADER).map(([glob, wiki, style]) => {
    // Wiki 版面是是非欄
    requireValue(wiki, new Set([YES, NO]), `${PROFILES_FILE}: ${glob} 的 Wiki 版面`);
    // 路徑的文風可以寫多個，依序套用
    for (const s of splitCell(style)) requireValue(s, styles, `${PROFILES_FILE}: ${glob} 的文風`);
    return { glob, re: globToRegExp(glob), wiki: wiki === YES, styles: splitCell(style) };
  });
  const formats = new Map(read(FORMATS_FILE, FORMATS_HEADER).map(([ext, format]) => {
    // 格式要是登記的格式
    requireValue(format, FORMATS, `${FORMATS_FILE}: ${ext} 的格式`);
    return [ext, format];
  }));
  // 合成詞表，統計每條規則有沒有檢查使用
  const { words, english } = loadWords(tables, project, io, rules);
  const used = new Set([...programRules, ...patterns.map((p) => p.rule), ...words.map((w) => w.rule)]);
  // 程式判定的規則都要登記在規則表，規則表的每條規則都要有檢查使用
  for (const name of new Set([...rules.keys(), ...programRules])) {
    // 程式判定的規則要登記在規則表
    requireValue(name, rules, `${RULES_FILE}: 程式判定的規則`);
    // 沒有檢查使用的規則讀者會以為有檢查
    if (!used.has(name)) throw new InputError(`${RULES_FILE}: ${name} 沒有被任何檢查使用`);
  }
  // 邊界詞與 markdown 寫法一併載入
  return new Rules({
    rules, levels, off, verdicts, styles, patterns, pairs, thresholds, profiles, formats, words, english,
    boundary: new Set(read(BOUNDARY_FILE, BOUNDARY_HEADER).map(([w]) => w)),
    marks: loadMarks(read(MARKDOWN_FILE, MARKDOWN_HEADER)),
  });
}
