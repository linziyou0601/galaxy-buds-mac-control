/* ==================================================
 * base.mjs - 共用常數、錯誤、字串工具、機讀定義表的解析與發現項目
 * --------------------------------------------------
 * - 角色：本模組不依賴套件內其他模組，其他模組都建立在它之上
 * - 指令：由其他模組與進入點匯入使用
 * - 慣例：機讀定義表以「檔名對應文字」的物件傳入，由 loadTableTexts(io) 讀取，解析函式只吃文字
 * - 慣例：專案定義表是與 references/tables/ 的機讀定義表同表頭的 TSV，以 Project 傳入，依 PROJECT_TABLES 的方式合併
 * - 慣例：檔案與目錄一律經由 io 介面存取（node 由 io-node.mjs 實作），本模組不 import node:*
 * - 慣例：字串位置以 JS 的 UTF-16 單位計，輸出的欄號以碼位計
 * - 參見 references/scripts-contract.md 取得權威合約
 * ================================================== */

/* ==================================================
 * 集中設定
 * ================================================== */

/**
 * 定義表與輸出中表示沒有值的格子。
 */
export const EMPTY_CELL = "-";

/**
 * 定義表是非欄的值。
 */
export const YES = "是";
export const NO = "否";

/**
 * 定義表格子內並列多個值的分隔符號：頓號。
 */
export const WORD_SEPARATOR = "、";

/**
 * 組合鍵各段的分隔字元，不會出現在檔名、條目編號與正文中。
 */
export const KEY_SEP = "\u0000";

/**
 * POSIX 路徑的分隔符號。
 */
export const PATH_SEP = "/";

/**
 * 機讀定義表目錄，相對於 skill 根目錄，用在錯誤訊息。io 介面有實際目錄時以 io 的為準。
 */
export const TABLES_DIR = "references/tables";

/**
 * 機讀定義表的副檔名與欄位分隔字元。
 */
export const TSV_EXT = ".tsv";
export const TSV_SEPARATOR = "\t";

/**
 * 結束代碼：成功、有須修正的發現項目或失敗、輸入資料錯誤。
 */
export const EXIT_OK = 0;
export const EXIT_FINDINGS = 1;
export const EXIT_INPUT = 2;

/**
 * 範本的欄位：「{名稱}」。說明欄與改法欄以此標出要代入的值。全域比對式，只搭配 replace 使用。
 */
const TEMPLATE_FIELD_RE = /\{([^}]+)\}/gu;

/**
 * 路徑樣式的萬用字元與要跳脫的字元：「**」跨目錄，「*」不跨目錄，其餘字元照字面比對。
 */
const GLOB_RE = /\*\*|\*|[.+^${}()|[\]\\?]/gu;

/**
 * 正規式的特殊字元，表內的寫法照字面比對時跳脫。
 */
const REGEX_SPECIAL_RE = /[.*+?^${}()|[\]\\]/gu;

/**
 * 換行：\r\n 與 \n。
 */
const NEWLINE_RE = /\r?\n/u;

/**
 * 規則表的檔名與表頭。一列一條規則，判定欄是是非問題，答案「是」表示違規。
 */
export const RULES_FILE = "check-rules.tsv";
export const RULES_HEADER = ["規則", "條目", "層級", "範圍", "成群門檻", "說明", "判定", "改法"];

/**
 * 層級表的檔名與表頭。順位決定同一位置只留哪一筆，輸出為否的層級不列出。
 */
export const LEVELS_FILE = "check-levels.tsv";
export const LEVELS_HEADER = ["層級", "順位", "輸出", "結束代碼", "判定", "嚴重度", "說明"];

/**
 * 判定表的檔名與表頭：判定值與依據的開頭。
 */
export const VERDICTS_FILE = "check-verdicts.tsv";
export const VERDICTS_HEADER = ["判定", "依據開頭", "說明"];

/**
 * 文風表與文風覆寫表的檔名與表頭。
 */
export const STYLES_FILE = "check-styles.tsv";
export const STYLES_HEADER = ["文風", "說明"];
export const STYLE_LEVELS_FILE = "check-style-levels.tsv";
export const STYLE_LEVELS_HEADER = ["文風", "規則", "層級"];

/**
 * 門檻表的檔名與表頭。
 */
export const THRESHOLDS_FILE = "check-thresholds.tsv";
export const THRESHOLDS_HEADER = ["門檻", "規則", "值", "說明"];

/**
 * 正規式表與成對連接詞表的檔名與表頭。
 */
export const PATTERNS_FILE = "check-patterns.tsv";
export const PATTERNS_HEADER = ["規則", "比對對象", "正規式", "例外"];
export const PAIRS_FILE = "check-pairs.tsv";
export const PAIRS_HEADER = ["開頭", "接續", "例外"];

/**
 * 路徑設定表、格式表與 markdown 寫法表的檔名與表頭。
 */
export const PROFILES_FILE = "layout-profiles.tsv";
export const PROFILES_HEADER = ["路徑", "Wiki 版面", "文風", "說明"];
export const FORMATS_FILE = "layout-formats.tsv";
export const FORMATS_HEADER = ["副檔名", "格式", "說明"];
export const MARKDOWN_FILE = "layout-markdown.tsv";
export const MARKDOWN_HEADER = ["名稱", "值", "說明"];

/**
 * 詞表的檔名與表頭：不使用寫法、技術用語對照、英文詞與中文詞的邊界。
 */
export const AVOID_FILE = "lex-avoid.tsv";
export const AVOID_HEADER = ["不使用", "規則", "改用", "例外"];
export const LOCALE_FILE = "lex-locale.tsv";
export const LOCALE_HEADER = ["English", "簡體中文", "大陸寫法", "正體中文", "分類", "規則", "例外"];
export const ENGLISH_FILE = "lex-english.tsv";
export const ENGLISH_HEADER = ["英文", "類別", "說明"];
export const BOUNDARY_FILE = "lex-boundary.tsv";
export const BOUNDARY_HEADER = ["詞", "說明"];

/**
 * 條目索引的檔名與表頭。參照寫成「檔案#標題」，檔案相對於 skill 根目錄。
 */
export const INDEX_FILE = "rule-index.tsv";
export const INDEX_HEADER = ["條目", "段落", "參照", "檢查主題"];

/**
 * 專案擴充方式：整張取代，或附加在 skill 的列之後。
 */
export const REPLACE = "整張取代";
export const APPEND = "附加";

/**
 * 可以由專案擴充的機讀定義表的表頭與擴充方式。表頭不屬於任何一張表的專案定義表以輸入資料錯誤停止。
 */
export const PROJECT_TABLES = new Map([
  [PROFILES_FILE, { header: PROFILES_HEADER, mode: REPLACE }],
  [AVOID_FILE, { header: AVOID_HEADER, mode: APPEND }],
  [ENGLISH_FILE, { header: ENGLISH_HEADER, mode: APPEND }],
  [BOUNDARY_FILE, { header: BOUNDARY_HEADER, mode: APPEND }],
  [STYLES_FILE, { header: STYLES_HEADER, mode: APPEND }],
  [STYLE_LEVELS_FILE, { header: STYLE_LEVELS_HEADER, mode: APPEND }],
]);

/* ==================================================
 * 錯誤與結束
 * ================================================== */

/**
 * 輸入資料錯誤：定義表、專案輸入、文風宣告或參數錯誤。進入點捕捉後以結束代碼 EXIT_INPUT 結束。
 */
export class InputError extends Error {
  /**
   * @param {string} message 錯誤摘要。
   */
  constructor(message) {
    super(message);
    this.name = "InputError";
  }
}

/**
 * 要求進入點結束執行，例如 --help 與輸入資料錯誤。核心模組不直接結束行程，由進入點寫出訊息後結束。
 */
export class ExitRequest extends Error {
  /**
   * @param {number} code 結束代碼。
   * @param {string} [stderr] 寫到標準錯誤的文字，含結尾換行。
   * @param {string} [stdout] 寫到標準輸出的文字，含結尾換行。
   */
  constructor(code, stderr = "", stdout = "") {
    super(stderr || stdout || `exit ${code}`);
    this.name = "ExitRequest";
    this.code = code;
    this.stderr = stderr;
    this.stdout = stdout;
  }
}

/**
 * 執行一段載入。輸入資料錯誤時所有檢查結果都無效，轉成以 EXIT_INPUT 結束的要求。
 * @template T
 * @param {function(): T} load 載入。
 * @returns {T} 載入的結果。
 * @throws {ExitRequest} 載入丟出 InputError 時。其他例外照常拋出。
 */
export function loading(load) {
  // 執行載入，丟出輸入資料錯誤時轉成結束要求
  try {
    return load();
  } catch (e) {
    // 不是輸入資料錯誤時照常拋出
    if (!(e instanceof InputError)) throw e;
    throw new ExitRequest(EXIT_INPUT, `錯誤：${e.message}\n`);
  }
}

/* ==================================================
 * 字串與路徑
 * ================================================== */

/**
 * 字串的碼位順序比較，排序結果與語系無關。
 * @param {string} a 字串。
 * @param {string} b 字串。
 * @returns {number}
 */
export const cmpStr = (a, b) => (a < b ? -1 : a > b ? 1 : 0);

/**
 * 依換行拆開文字。
 * @param {string} text 文字。
 * @returns {string[]}
 */
export const splitLines = (text) => text.split(NEWLINE_RE);

/**
 * 以頓號拆開多值格，「-」表示沒有值。
 * @param {string} cell 格子值。
 * @returns {string[]}
 */
export const splitCell = (cell) => (cell === EMPTY_CELL ? [] : cell.split(WORD_SEPARATOR));

/**
 * 以 KEY_SEP 串成組合鍵。
 * @param {...(string|number)} parts 各段。
 * @returns {string}
 */
export const joinKey = (...parts) => parts.join(KEY_SEP);

/**
 * 跳脫正規式的特殊字元，讓表內的寫法照字面比對。
 * @param {string} text 寫法。
 * @returns {string}
 */
export const escapeRegex = (text) => text.replace(REGEX_SPECIAL_RE, "\\$&");

/**
 * 以欄位值代入範本的 {名稱}，沒有對應值的欄位保留原樣。
 * @param {string} template 範本。
 * @param {Object<string, string|number>} fields 名稱對應值。
 * @returns {string}
 */
export const fillTemplate = (template, fields) => template.replace(TEMPLATE_FIELD_RE, (m, k) => (Object.hasOwn(fields, k) ? String(fields[k]) : m));

/**
 * 以碼位計的欄號：字串索引之前的字元數加 1。
 * @param {string} text 文字。
 * @param {number} index 字串索引。
 * @returns {number}
 */
export const columnOf = (text, index) => [...text.slice(0, index)].length + 1;

/**
 * 以 POSIX 分隔符號接起路徑片段。
 * @param {...string} parts 路徑片段。
 * @returns {string}
 */
export const joinPath = (...parts) => parts.join(PATH_SEP);

/**
 * 路徑的最後一段。
 * @param {string} p 路徑。
 * @returns {string}
 */
export const baseName = (p) => p.slice(p.lastIndexOf(PATH_SEP) + 1);

/**
 * 路徑的副檔名，含開頭的句點。沒有副檔名時為空字串。
 * @param {string} p 路徑。
 * @returns {string}
 */
export function extName(p) {
  const name = baseName(p);
  const at = name.lastIndexOf(".");
  return at > 0 ? name.slice(at) : "";
}

/**
 * 把路徑樣式轉成正規式：「**」跨目錄，「*」不跨目錄，其餘字元照字面比對。
 * @param {string} glob 路徑樣式，以「/」分隔。
 * @returns {RegExp}
 */
export function globToRegExp(glob) {
  const body = glob.replace(GLOB_RE, (m) => (m === "**" ? ".*" : m === "*" ? "[^/]*" : `\\${m}`));
  return new RegExp(`^${body}$`, "u");
}

/* ==================================================
 * 機讀定義表
 * ================================================== */

/**
 * 專案輸入：專案定義表的路徑，依傳入順序合併。
 */
export class Project {
  /**
   * @param {string[]} [tables] 專案定義表的路徑。
   */
  constructor(tables = []) {
    this.tables = tables;
  }
}

/**
 * 解析 TSV 文字，第一列要等於表頭，空行略過。
 * @param {string} text TSV 文字。
 * @param {string[]} header 表頭。
 * @param {string} name 來源檔名，用於錯誤訊息。
 * @returns {string[][]} 資料列。
 * @throws {InputError} 表頭或欄位數不符。
 */
export function parseTable(text, header, name) {
  const lines = splitLines(text);
  // 表頭不符時無法依欄位名稱讀值
  if (lines[0] !== header.join(TSV_SEPARATOR)) throw new InputError(`${name}: 表頭要是「${header.join(WORD_SEPARATOR)}」`);
  const rows = [];
  // 逐列切欄，行號從 2 起算，錯誤訊息的行號與編輯器一致
  for (let k = 1; k < lines.length; k++) {
    // 空行略過
    if (lines[k].trim() === "") continue;
    const cells = lines[k].split(TSV_SEPARATOR);
    // 欄位數不符時這一列的值會錯位
    if (cells.length !== header.length) throw new InputError(`${name}:${k + 1}: 欄位數要是 ${header.length}`);
    rows.push(cells);
  }
  return rows;
}

/**
 * 讀取一張機讀定義表，再依 PROJECT_TABLES 的方式併入屬於這張表的專案定義表。
 * @param {Object<string, string>} tables 機讀定義表的檔名對應文字。
 * @param {Project} project 專案輸入。
 * @param {Object} io io 介面，讀取專案定義表。
 * @param {string} name 檔名。
 * @param {string[]} header 表頭。
 * @returns {string[][]} 資料列。
 * @throws {InputError} 定義表缺漏或格式錯誤。
 */
export function readTable(tables, project, io, name, header) {
  // 定義表缺漏時依賴它的檢查都會失效
  if (!Object.hasOwn(tables, name)) throw new InputError(`找不到機讀定義表 ${joinPath(TABLES_DIR, name)}`);
  const files = project.tables.filter((p) => isProjectTable(io, p, header));
  const rows = parseTable(tables[name], header, name);
  // 專案沒有提供這張表時沿用 skill 的表
  if (!files.length) return rows;
  // 依傳入順序串接屬於這張表的專案定義表，再依擴充方式取代或附加
  const extra = files.flatMap((p) => parseTable(io.readText(p), header, p));
  return PROJECT_TABLES.get(name)?.mode === REPLACE ? extra : [...rows, ...extra];
}

/**
 * 專案定義表是否屬於某張機讀定義表：第一列與該表的表頭相同。各表的表頭不同，檔名不限。
 * @param {Object} io io 介面。
 * @param {string} path 專案定義表的路徑。
 * @param {string[]} header 機讀定義表的表頭。
 * @returns {boolean}
 */
export function isProjectTable(io, path, header) {
  return splitLines(io.readText(path))[0] === header.join(TSV_SEPARATOR);
}

/**
 * 確認每份專案定義表都是可以擴充的機讀定義表。
 * @param {Project} project 專案輸入。
 * @param {Object} io io 介面，讀取專案定義表的表頭。
 * @throws {InputError} 表頭不是可以擴充的機讀定義表的表頭。
 */
export function requireProjectTables(project, io) {
  // 逐份確認表頭
  for (const p of project.tables) {
    // 表頭不屬於任何一張可以擴充的定義表時停止
    if (![...PROJECT_TABLES.values()].some((t) => isProjectTable(io, p, t.header))) throw new InputError(`${p}: 表頭不是可以擴充的機讀定義表的表頭`);
  }
}

/**
 * 讀入機讀定義表目錄（io.tablesDir）下的全部 TSV 文字。
 * @param {Object} io io 介面，需提供 tablesDir。
 * @returns {Object<string, string>} 檔名對應文字。
 */
export function loadTableTexts(io) {
  const tables = {};
  // 只讀 .tsv，依檔名排序，每次讀入的順序相同
  for (const name of io.listFiles(io.tablesDir).filter((n) => n.endsWith(TSV_EXT)).sort(cmpStr)) {
    tables[name] = io.readText(joinPath(io.tablesDir, name));
  }
  return tables;
}

/**
 * 檢查格子值是允許的值。
 * @param {string} value 格子值。
 * @param {Set<string>|Map<string, *>} allowed 允許的值。
 * @param {string} where 錯誤訊息的位置。
 * @throws {InputError} 不是允許的值。
 */
export function requireValue(value, allowed, where) {
  // 值寫錯時檢查會悄悄失效
  if (!allowed.has(value)) throw new InputError(`${where}「${value}」不是${[...allowed.keys()].join(WORD_SEPARATOR)}之一`);
}

/**
 * 檢查格子值是正整數。
 * @param {string} value 格子值。
 * @param {string} where 錯誤訊息的位置。
 * @returns {number}
 * @throws {InputError} 不是正整數。
 */
export function requirePositive(value, where) {
  // 門檻與上限要是正整數
  if (!/^[1-9]\d*$/u.test(value)) throw new InputError(`${where}「${value}」不是正整數`);
  return Number(value);
}

/* ==================================================
 * 發現項目
 * ================================================== */

/**
 * 一筆發現項目。
 */
export class Finding {
  /**
   * @param {Object} f 欄位。
   * @param {string} f.rule 規則名稱。
   * @param {string} f.code 條目編號。
   * @param {string} f.level 層級。
   * @param {string} f.severity 嚴重度。
   * @param {string} f.file 顯示的路徑。
   * @param {number} f.line 行號，從 1 起。
   * @param {number} f.col 欄號，從 1 起，以碼位計。
   * @param {string} f.hit 命中的文字，整行的發現項目為空字串。
   * @param {string} f.message 說明。
   * @param {string} f.judge 判定問題，「是」表示違規。沒有判定問題時為 EMPTY_CELL。
   * @param {string} f.fix 改法。
   * @param {string} f.ref 參照：檔案#標題。
   * @param {string} f.excerpt 原行。
   * @param {?string} f.replacement --fix 取代命中文字的寫法，不能自動取代時為 null。
   */
  constructor(f) {
    this.rule = f.rule;
    this.code = f.code;
    this.level = f.level;
    this.severity = f.severity;
    this.file = f.file;
    this.line = f.line;
    this.col = f.col;
    this.hit = f.hit;
    this.message = f.message;
    this.judge = f.judge;
    this.fix = f.fix;
    this.ref = f.ref;
    this.excerpt = f.excerpt;
    this.replacement = f.replacement;
  }
}

/**
 * 發現項目的排序：檔案、行號、欄號、條目。
 * @param {Finding} a 發現項目。
 * @param {Finding} b 發現項目。
 * @returns {number}
 */
export const compareFindings = (a, b) => cmpStr(a.file, b.file) || a.line - b.line || a.col - b.col || cmpStr(a.code, b.code);
