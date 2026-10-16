/* ==================================================
 * cli.mjs - 進入點的命令列解析與專案輸入的建立
 * --------------------------------------------------
 * - 角色：依 OPTIONS 解析命令列，組出參數物件與專案輸入（Project），說明文字為 USAGE
 * - 指令：由進入點與 io-node 模組匯入使用
 * - 慣例：選項寫成「--名稱 值」或「--名稱=值」。可以重複的選項依序累加，其餘取最後一次。--style 的值可以以逗號或頓號分隔多個文風
 * - 慣例：參數錯誤丟出 InputError，由進入點以結束代碼 EXIT_INPUT 結束。本模組不 import node:*
 * - 參見 references/scripts-contract.md 取得權威合約
 * ================================================== */
import { InputError, Project, TSV_EXT, cmpStr, joinPath } from "./base.mjs";

/* ==================================================
 * 集中設定
 * ================================================== */

/**
 * 顯示說明的選項。
 */
export const HELP_OPTIONS = ["-h", "--help"];

/**
 * JSON 輸出、輸出目錄與判定檢查目錄的選項。io-node 模組依它們決定是否寫指令行與執行紀錄。
 */
export const JSON_OPTION = "--json";
export const OUT_OPTION = "--out";
export const JUDGED_OPTION = "--judged";

/**
 * 選項與值之間的等號寫法。
 */
export const OPTION_VALUE_SEPARATOR = "=";

/**
 * 執行紀錄檔名：指定輸出目錄或判定檢查目錄時，每次執行附加一段到該目錄的這個檔案。
 */
export const RUNS_FILE = "runs.txt";

/**
 * 選項的種類：旗標、單一值、可以重複的值、可以重複且以分隔符號拆開的值、「名稱=理由」。
 */
const FLAG = "旗標";
const VALUE = "值";
const REPEAT = "重複";
const SPLIT = "拆開";
const REASON = "理由";

/**
 * --style 的值裡分隔多個文風的符號，以及 --off 的規則與理由之間的符號。
 */
const STYLE_SEPARATOR_RE = /[,、]/u;
const OFF_SEPARATOR = "=";

/**
 * 選項的開頭與長選項的開頭。單獨一個 OPTION_PREFIX 是路徑。
 */
const OPTION_PREFIX = "-";
const LONG_PREFIX = "--";

/**
 * 選項對應參數物件的欄位與種類。
 */
const OPTIONS = new Map([
  [HELP_OPTIONS[0], { dest: "help", kind: FLAG }],
  [HELP_OPTIONS[1], { dest: "help", kind: FLAG }],
  [JSON_OPTION, { dest: "json", kind: FLAG }],
  ["--fix", { dest: "fix", kind: FLAG }],
  ["--root", { dest: "root", kind: VALUE }],
  [OUT_OPTION, { dest: "out", kind: VALUE }],
  [JUDGED_OPTION, { dest: "judged", kind: VALUE }],
  ["--cases", { dest: "cases", kind: VALUE }],
  ["--project", { dest: "project", kind: REPEAT }],
  ["--text", { dest: "texts", kind: REPEAT }],
  ["--style", { dest: "styles", kind: SPLIT }],
  ["--off", { dest: "offs", kind: REASON }],
]);

/**
 * 命令列說明。
 */
export const USAGE = `用法：
  lint.mjs <路徑>... [--root DIR] [--project PATH]... [--style 文風]... [--off 規則=理由]... [--fix] [--json] [--out DIR]
  lint.mjs --text 文字 [--style 文風]... [--off 規則=理由]... [--json]
  lint.mjs --judged DIR
  lint.mjs --cases DIR

  --root DIR        顯示路徑與比對 layout-profiles.tsv 路徑樣式的基準目錄，預設為工作目錄
  --project PATH    專案定義表：與機讀定義表同表頭的 TSV，或含 TSV 的目錄，可以重複指定
  --style 文風      取代路徑的文風，可以重複指定，依序套用
  --off 規則=理由   關閉一條規則並記下理由，可以重複指定
  --fix             以改用的寫法取代沒有判定問題的詞表命中，寫回檔案
  --text 文字       以純文字檢查這段文字，可以重複指定
  --json            以 JSON 輸出發現項目
  --out DIR         把發現項目寫進 DIR/lint.json，附判定欄
  --judged DIR      檢查 DIR/lint.json 的發現項目都已處理
  --cases DIR       執行標準答案集
`;

/* ==================================================
 * 解析
 * ================================================== */

/**
 * 解析命令列參數。
 * @param {string[]} argv 參數，不含 node 與腳本路徑。
 * @returns {{paths: string[], root: string, project: string[], styles: string[], offs: Map<string, string>, texts: string[],
 *   fix: boolean, json: boolean, out: ?string, judged: ?string, cases: ?string, help: boolean}}
 * @throws {InputError} 未知的選項、選項缺值，或 --off 沒有寫理由。
 */
export function parseArgs(argv) {
  const args = { paths: [], root: ".", project: [], styles: [], offs: new Map(), texts: [], fix: false, json: false, out: null, judged: null, cases: null, help: false };
  // 逐個參數分成選項與路徑
  for (let i = 0; i < argv.length; i++) {
    // 「--名稱=值」的寫法從等號拆出名稱與值
    const a = argv[i];
    const eq = a.startsWith(LONG_PREFIX) ? a.indexOf(OPTION_VALUE_SEPARATOR) : -1;
    const name = eq >= 0 ? a.slice(0, eq) : a;
    // 不是選項的參數是路徑
    if (!name.startsWith(OPTION_PREFIX) || name === OPTION_PREFIX) {
      args.paths.push(a);
      continue;
    }
    // 依選項表查出存放的欄位與種類
    const spec = OPTIONS.get(name);
    // 未知的選項無法判斷有沒有值
    if (!spec) throw new InputError(`未知的選項：${name}`);
    // 旗標沒有值
    if (spec.kind === FLAG) {
      args[spec.dest] = true;
      continue;
    }
    // 帶值的選項缺值時無法執行
    if (eq < 0 && i + 1 >= argv.length) throw new InputError(`${name} 缺少值`);
    // 值取等號後的文字，沒有等號時取下一個參數
    const v = eq >= 0 ? a.slice(eq + 1) : argv[++i];
    // 依種類存值
    if (spec.kind === VALUE) {
      // 單一值取最後一次
      args[spec.dest] = v;
    } else if (spec.kind === REPEAT) {
      // 可以重複的選項依序累加
      args[spec.dest].push(v);
    } else if (spec.kind === SPLIT) {
      // 以分隔符號拆開後依序累加
      args[spec.dest].push(...v.split(STYLE_SEPARATOR_RE).map((s) => s.trim()).filter(Boolean));
    } else {
      // 「規則=理由」拆成規則與理由
      const at = v.indexOf(OFF_SEPARATOR);
      // 關閉規則要寫理由，讀者才知道為什麼不檢查
      if (at <= 0 || !v.slice(at + 1).trim()) throw new InputError(`${name} 要寫成「規則${OFF_SEPARATOR}理由」：${v}`);
      args[spec.dest].set(v.slice(0, at), v.slice(at + 1).trim());
    }
  }
  return args;
}

/**
 * 展開 --project 的路徑，組出專案輸入：檔案原樣保留，目錄取其中的 TSV 檔，依檔名排序。
 * @param {string[]} paths 命令列的路徑。
 * @param {Object} io io 介面。
 * @returns {Project}
 * @throws {InputError} 路徑不存在。
 */
export function projectFromArgs(paths, io) {
  return new Project(paths.flatMap((raw) => {
    const p = io.resolve(raw);
    // 路徑不存在時無法讀取專案定義表
    if (!io.exists(p)) throw new InputError(`--project 的路徑不存在：${raw}`);
    // 目錄取其中的 TSV 檔並依檔名排序，檔案原樣保留
    return io.isDir(p) ? io.listFiles(p).filter((n) => n.endsWith(TSV_EXT)).sort(cmpStr).map((n) => joinPath(p, n)) : [p];
  }));
}
