/* ==================================================
 * io-node.mjs - io 介面的 node 實作與進入點的執行包裝
 * --------------------------------------------------
 * - 角色：核心模組只透過 io 物件存取檔案與標準輸出入，本檔以 node:fs 與 node:path 實作。瀏覽器或測試可以傳入記憶體版本
 * - 介面：readText、writeText、exists、isDir、listFiles、listEntries、resolve、relative、stdout、stderr，
 *   以及 skill 根目錄 skillDir 與機讀定義表目錄 tablesDir
 * - 慣例：路徑一律是 POSIX 絕對路徑，relative 回傳相對路徑。listEntries 不跟隨符號連結的目錄
 * - 慣例：進入點以 runMain 執行主函式，ExitRequest 在此寫出訊息並設定結束代碼
 * - 慣例：文字模式的第一行寫出本次執行的指令，最後一行寫出結束代碼。--json 與說明模式不寫
 * - 慣例：指定 --out 或 --judged 目錄時，本次執行的指令、標準輸出、標準錯誤與結束代碼附加到該目錄的 runs.txt，
 *   作為腳本結果的原文紀錄
 * - 參見 references/scripts-contract.md 取得權威合約
 * ================================================== */
import { appendFileSync, existsSync, mkdirSync, readFileSync, readdirSync, statSync, writeFileSync } from "node:fs";
import { dirname, join, relative, resolve } from "node:path";
import { fileURLToPath } from "node:url";
import { EXIT_OK, ExitRequest, TABLES_DIR } from "./base.mjs";
import { HELP_OPTIONS, JSON_OPTION, JUDGED_OPTION, OPTION_VALUE_SEPARATOR, OUT_OPTION, RUNS_FILE } from "./cli.mjs";

/* ==================================================
 * 集中設定
 * ================================================== */

/**
 * skill 根目錄。機讀定義表與條目索引參照的 md 都以它定位。
 */
export const SKILL_DIR = resolve(dirname(fileURLToPath(import.meta.url)), "../..");

/**
 * 決定執行紀錄所在目錄的參數。參數後一個值是目錄。
 */
const RUN_DIR_OPTIONS = [OUT_OPTION, JUDGED_OPTION];

/**
 * 不寫指令行與結束代碼的參數：JSON 輸出與說明。
 */
const QUIET_OPTIONS = [JSON_OPTION, ...HELP_OPTIONS];

/* ==================================================
 * io 物件
 * ================================================== */

/**
 * 是否為目錄，跟隨符號連結。
 * @param {string} path 路徑。
 * @returns {boolean}
 */
function isDir(path) {
  // 路徑不存在或無法讀取時視為不是目錄
  try {
    return statSync(path).isDirectory();
  } catch {
    // 讀取失敗時不是目錄
    return false;
  }
}

/**
 * 本次執行寫到標準輸出與標準錯誤的文字，依寫出順序保存，結束時附加到執行紀錄。
 * @type {string[]}
 */
const transcript = [];

/**
 * 寫到標準輸出或標準錯誤，同時保存到本次執行的紀錄。
 * @param {NodeJS.WriteStream} stream process.stdout 或 process.stderr。
 * @param {string} text 文字。
 */
function write(stream, text) {
  transcript.push(text);
  stream.write(text);
}

/**
 * node 的 io 介面。
 */
export const nodeIo = {
  skillDir: SKILL_DIR,
  tablesDir: join(SKILL_DIR, TABLES_DIR),
  readText: (path) => readFileSync(path, "utf8"),
  writeText: (path, text) => {
    mkdirSync(dirname(path), { recursive: true });
    writeFileSync(path, text, "utf8");
  },
  exists: (path) => existsSync(path),
  isDir,
  listFiles: (dir) => readdirSync(dir),
  listEntries: (dir) => readdirSync(dir, { withFileTypes: true }).map((e) => ({ name: e.name, dir: e.isDirectory() })),
  resolve: (...parts) => resolve(...parts),
  relative: (from, to) => relative(from, to),
  stdout: (text) => write(process.stdout, text),
  stderr: (text) => write(process.stderr, text),
};

/* ==================================================
 * 執行包裝
 * ================================================== */

/**
 * 本次執行的指令行：「$ node 腳本 參數...」，腳本路徑相對於工作目錄，含空白或殼層特殊字元的參數加單引號。
 * @returns {string} 不含換行的指令行。
 */
export function commandLine() {
  const quote = (a) => (/^[\w./:=,@%+-]+$/u.test(a) ? a : `'${a.replaceAll("'", "'\\''")}'`);
  return `$ node ${[relative(process.cwd(), process.argv[1]), ...process.argv.slice(2)].map(quote).join(" ")}`;
}

/**
 * 執行紀錄所在的目錄：命令列最後一個 RUN_DIR_OPTIONS 的值。
 * @param {string[]} args 命令列參數。
 * @returns {string|null} 沒有指定時為 null。
 */
function runDir(args) {
  let dir = null;
  // 逐個參數找目錄參數，後一個值是目錄，「--out=DIR」的寫法取等號後的值
  args.forEach((a, k) => {
    const eq = a.indexOf(OPTION_VALUE_SEPARATOR);
    const [name, value] = eq >= 0 ? [a.slice(0, eq), a.slice(eq + 1)] : [a, args[k + 1]];
    // 目錄參數有值時記下
    if (RUN_DIR_OPTIONS.includes(name) && value !== undefined) dir = value;
  });
  return dir;
}

/**
 * 執行進入點的主函式：回傳值為結束代碼，丟出 ExitRequest 時寫出其訊息並以其代碼結束。
 * 以 process.exitCode 設定結束代碼，不呼叫 process.exit，導向管線的大量輸出才不會被截斷。
 * @param {function(): (number|Promise<number>)} main 主函式。
 * @returns {Promise<void>}
 */
export async function runMain(main) {
  const args = process.argv.slice(2);
  const text = !args.some((a) => QUIET_OPTIONS.includes(a));
  // 文字模式先寫出本次執行的指令
  if (text) process.stdout.write(`${commandLine()}\n`);
  // 一般結束取主函式的回傳值，ExitRequest 依其內容輸出後結束，其餘錯誤照常拋出
  try {
    process.exitCode = (await main()) ?? EXIT_OK;
  } catch (e) {
    // 只處理結束要求，其他例外照常拋出
    if (!(e instanceof ExitRequest)) throw e;
    // 結束要求附帶的標準輸出先寫出
    if (e.stdout) write(process.stdout, e.stdout);
    // 結束要求附帶的錯誤訊息寫到標準錯誤
    if (e.stderr) write(process.stderr, e.stderr);
    process.exitCode = e.code;
  }
  // 結束代碼寫成一行，文字模式與執行紀錄共用
  const exit = `結束代碼：${process.exitCode}\n`;
  // 文字模式最後寫出結束代碼
  if (text) process.stdout.write(exit);
  // 執行紀錄的目錄取 --out 或 --judged 的值
  const dir = runDir(args);
  // 指定目錄時把本次執行附加到執行紀錄，目錄不存在時建立
  if (dir) {
    const path = join(resolve(dir), RUNS_FILE);
    mkdirSync(dirname(path), { recursive: true });
    // 指令行、本次的輸出與結束代碼附加成一段
    appendFileSync(path, `${commandLine()}\n${transcript.join("")}${exit}\n`, "utf8");
  }
}
