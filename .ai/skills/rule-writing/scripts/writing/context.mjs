/* ==================================================
 * context.mjs - 一次執行的規則、文風、層級與發現項目
 * --------------------------------------------------
 * - 角色：進入點建立 Context，各檢查模組共用同一份規則，以 report() 依規則表記錄發現項目。
 *   文件由 prepare() 解析成行，並依路徑設定、--style、front matter 與 HTML 註解決定每一行的文風
 * - 指令：由進入點與檢查模組匯入使用
 * - 慣例：io、機讀定義表的文字、專案輸入、程式判定的規則名稱、--style 與 --off 都由建構子傳入，本模組不自行讀取命令列
 * - 慣例：規則的層級從規則表的預設層級起，依序套用每個文風的覆寫，--off 最後套用。輸出為否的層級不記錄，
 *   範圍是 markdown 的規則不套用在純文字，範圍是 Wiki 版面的規則只套用在 Wiki 版面
 * - 慣例：本模組不 import node:*
 * - 參見 references/scripts-contract.md 取得權威合約
 * ================================================== */
import { EMPTY_CELL, Finding, Project, columnOf, fillTemplate, joinKey, loadTableTexts, requireValue } from "./base.mjs";
import { FRONT_MATTER, HEADING, MARKUP, parseDoc } from "./parse.mjs";
import { ALL_RULES, FORMAT_TEXT, SCOPE_MARKDOWN, SCOPE_WIKI, loadRules } from "./rules.mjs";

/* ==================================================
 * 集中設定
 * ================================================== */

/**
 * 文風宣告的值可以用逗號或頓號分隔，可以包在方括號內，每個值可以加引號。
 */
const STYLE_LIST_SEPARATOR_RE = /[,、]/u;
const STYLE_BRACKETS_RE = /^\[|\]$/gu;
const STYLE_QUOTES_RE = /^["']|["']$/gu;

/* ==================================================
 * 文件
 * ================================================== */

/**
 * 一份要檢查的文件。
 */
export class Doc {
  /**
   * @param {?string} abs 絕對路徑，--text 為 null。
   * @param {string} rel 顯示的路徑，比對路徑設定表也用它。
   * @param {string} format 格式。
   * @param {string} text 內容。
   */
  constructor(abs, rel, format, text) {
    this.abs = abs;
    this.rel = rel;
    this.format = format;
    this.text = text;
    /** @type {import("./parse.mjs").Line[]} 解析後的行，由 Context.prepare() 填入。 */
    this.lines = [];
    /** @type {boolean} 是否採 Wiki 版面，由 Context.prepare() 填入。 */
    this.wiki = false;
  }
}

/* ==================================================
 * 文風
 * ================================================== */

/**
 * 拆開文風宣告的值，並確認每個文風都登記在文風表。
 * @param {string} value 宣告的值。
 * @param {Map<string, Map>} styles 文風表。
 * @param {string} where 錯誤訊息的位置。
 * @returns {string[]}
 * @throws {import("./base.mjs").InputError} 文風不在文風表。
 */
function parseStyles(value, styles, where) {
  const names = value.replace(STYLE_BRACKETS_RE, "").split(STYLE_LIST_SEPARATOR_RE).map((s) => s.trim().replace(STYLE_QUOTES_RE, "")).filter(Boolean);
  // 每個文風都要登記在文風表
  for (const s of names) requireValue(s, styles, `${where} 的文風`);
  return names;
}

/**
 * 依 front matter 與 HTML 註解的文風宣告，決定每一行套用的文風。
 * 註解宣告的文風套用到下一個同級以上的標題或結束宣告，同級指宣告所在章節的標題層級。
 * @param {import("./parse.mjs").Line[]} lines 全部行。
 * @param {string[]} base 路徑或 --style 決定的文風。
 * @param {import("./rules.mjs").Rules} rules 規則。
 * @param {string} file 顯示的路徑，用於錯誤訊息。
 * @throws {import("./base.mjs").InputError} 宣告的文風不在文風表。
 */
function assignStyles(lines, base, rules, file) {
  const { marks, styles } = rules;
  let fileStyles = base;
  // front matter 的文風宣告取代路徑的文風
  for (const l of lines) {
    // front matter 結束後停止
    if (l.kind !== MARKUP || (l.no > 1 && l.raw === FRONT_MATTER)) break;
    const m = marks.styleFront.exec(l.raw);
    // 找到宣告時取代
    if (m) fileStyles = parseStyles(m[1], styles, `${file}:${l.no}`);
  }
  let section = null;
  let sectionLevel = 0;
  let headingLevel = 0;
  // 逐行套用章節的文風，遇到同級以上的標題或結束宣告時回到檔案的文風
  for (const l of lines) {
    // 標題可能結束章節的文風
    if (l.kind === HEADING) {
      // 同級以上的標題結束章節的文風
      if (section && l.level <= sectionLevel) section = null;
      headingLevel = l.level;
    }
    const m = l.kind === MARKUP ? marks.styleComment.exec(l.raw) : null;
    // 註解宣告開始或結束章節的文風
    if (m) {
      section = m[1] === marks.styleEnd ? null : parseStyles(m[1], styles, `${file}:${l.no}`);
      sectionLevel = headingLevel;
    }
    l.styles = section ?? fileStyles;
  }
}

/* ==================================================
 * 執行環境
 * ================================================== */

/**
 * 一次執行的規則、文風、層級與發現項目。
 */
export class Context {
  /**
   * 建立執行環境，未傳入的定義表文字與規則當場載入。
   * @param {Object} options 選項。
   * @param {Object} options.io io 介面。
   * @param {Object<string, string>|null} [options.tables] 機讀定義表的檔名對應文字。未傳入時以 loadTableTexts(io) 讀取。
   * @param {Project} [options.project] 專案輸入。
   * @param {import("./rules.mjs").Rules|null} [options.rules] 已載入的規則。
   * @param {string[]} [options.programRules] 由程式判定的規則名稱，載入規則時確認登記在規則表。
   * @param {string[]} [options.styles] 取代路徑文風的文風，依序套用。空陣列時用路徑的文風。
   * @param {Map<string, string>} [options.offs] 關閉的規則對應理由。
   * @throws {import("./base.mjs").InputError} 定義表錯誤，或文風、關閉的規則沒有登記。
   */
  constructor({ io, tables = null, project = new Project(), rules = null, programRules = [], styles = [], offs = new Map() }) {
    this.io = io;
    // 未傳入的定義表文字與規則當場載入
    this.tables = tables ?? loadTableTexts(io);
    this.rules = rules ?? loadRules(project, io, this.tables, programRules);
    // --style 的文風要登記在文風表
    for (const s of styles) requireValue(s, this.rules.styles, "--style 的文風");
    // --off 的規則要登記在規則表
    for (const r of offs.keys()) requireValue(r, this.rules.rules, "--off 的規則");
    // 沒有 --style 時用路徑的文風
    this.styles = styles.length ? styles : null;
    this.offs = offs;
    /** @type {Finding[]} 累積的發現項目。 */
    this.findings = [];
    /** @type {Map<string, string>} 規則與文風組合對應層級的快取。 */
    this.levelCache = new Map();
  }

  /**
   * 依路徑取版面設定：符合的樣式中最長的一個，沒有符合時不採 Wiki 版面，也不套用文風。
   * @param {Doc} doc 文件。--text 不比對路徑。
   * @returns {{wiki: boolean, styles: string[]}}
   */
  profileOf(doc) {
    // --text 不比對路徑，其餘依樣式長度由長到短排列符合的樣式
    const hits = doc.abs === null ? [] : this.rules.profiles.filter((p) => p.re.test(doc.rel)).sort((a, b) => b.glob.length - a.glob.length);
    // 取最長的樣式，沒有符合時不採 Wiki 版面也不套用文風
    return hits.length ? { wiki: hits[0].wiki, styles: hits[0].styles } : { wiki: false, styles: [] };
  }

  /**
   * 解析文件，決定版面與每一行的文風。
   * @param {Doc} doc 文件。
   * @returns {Doc} 同一份文件，已填入 lines 與 wiki。
   * @throws {import("./base.mjs").InputError} 文風宣告不在文風表。
   */
  prepare(doc) {
    // 依路徑取版面設定，解析成行後決定每一行的文風
    const profile = this.profileOf(doc);
    doc.lines = parseDoc(doc.text, doc.format, this.rules.marks);
    doc.wiki = profile.wiki;
    // --style 取代路徑的文風，文件內的文風宣告再取代前兩者
    assignStyles(doc.lines, this.styles ?? profile.styles, this.rules, doc.rel);
    return doc;
  }

  /**
   * 依文風與 --off 決定規則的層級。
   * @param {string} name 規則名稱。
   * @param {string[]} styles 文風，依序套用。
   * @returns {string} 層級名稱。
   */
  level(name, styles) {
    const key = joinKey(name, ...styles);
    // 同一組規則與文風只計算一次
    if (!this.levelCache.has(key)) {
      let level = this.rules.rule(name).level;
      // 依序套用每個文風的覆寫，指名規則的列優先於全部規則的列
      for (const s of styles) level = this.rules.styles.get(s).get(name) ?? this.rules.styles.get(s).get(ALL_RULES) ?? level;
      // --off 最後套用
      this.levelCache.set(key, this.offs.has(name) ? this.rules.off : level);
    }
    return this.levelCache.get(key);
  }

  /**
   * 記錄一筆發現項目：依規則的範圍與這一行的層級決定是否記錄。
   * @param {Doc} doc 文件。
   * @param {string} name 規則名稱。
   * @param {import("./parse.mjs").Line} line 行。
   * @param {number} index 命中位置的字串索引，整行的發現項目為 0。
   * @param {string} hit 命中的文字。
   * @param {Object<string, string|number>} fields 說明與改法範本的值。
   * @param {?string} [replacement] 改用的寫法。規則沒有判定問題時供 --fix 取代。
   */
  report(doc, name, line, index, hit, fields, replacement = null) {
    // 取得規則與這一行文風下的層級
    const r = this.rules.rule(name);
    const level = this.rules.levels.get(this.level(name, line.styles));
    // 範圍不符或層級不輸出時不記錄
    if (!level.output || (r.scope === SCOPE_MARKDOWN && doc.format === FORMAT_TEXT) || (r.scope === SCOPE_WIKI && !doc.wiki)) return;
    // 沒有判定問題的規則才供 --fix 取代
    this.findings.push(new Finding({
      rule: name, code: r.code, level: level.name, severity: level.severity, file: doc.rel, line: line.no, col: columnOf(line.raw, index), hit,
      message: fillTemplate(r.template, fields), judge: r.judge, fix: fillTemplate(r.fix, fields), ref: r.ref, excerpt: line.raw,
      replacement: r.judge === EMPTY_CELL ? replacement : null,
    }));
  }
}
