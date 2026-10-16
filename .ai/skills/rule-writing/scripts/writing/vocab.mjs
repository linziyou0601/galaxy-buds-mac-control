/* ==================================================
 * vocab.mjs - 詞彙的檢查：正規式、詞表與成對連接詞
 * --------------------------------------------------
 * - 角色：依正規式表、不使用寫法、技術用語對照、英文詞、邊界詞與成對連接詞表，在遮罩後的正文找出要看的位置
 * - 指令：由進入點以 run(ctx, doc) 呼叫，RULES 傳給 Context 確認規則都登記在規則表
 * - 慣例：詞表在每個位置取最長的詞，英文詞不分大小寫並比對完整單字，中文詞的前一字與第一字或最後一字與後一字組成
 *   邊界詞時不算命中。詞在同一個區塊的命中數達規則的成群門檻才列出
 * - 慣例：英文詞以英文詞表的寫法為標準寫法，寫法不同時以 ENGLISH_CASE 列出，改用標準寫法
 * - 慣例：正規式每一列在一行只列出第一個不在例外的命中，具名群組 HIT_GROUP 標出命中文字
 * - 慣例：本模組不 import node:*
 * - 參見 references/scripts-contract.md 取得權威合約
 * ================================================== */
import { EMPTY_CELL, WORD_SEPARATOR } from "./base.mjs";
import { LIST, MASK, PARA, PROSE, QUOTE, TABLE, blocks, fill, pairScopes } from "./parse.mjs";
import { TARGET_MASKED, TARGET_NON_TABLE, TARGET_PARA_LIST } from "./rules.mjs";

/* ==================================================
 * 集中設定
 * ================================================== */

/**
 * 本模組判定的規則名稱：開頭詞之後沒有接續詞，以及英文詞的寫法與英文詞表不同。條目、層級與說明取自規則表。
 */
const UNPAIRED = "成對連接詞";
const ENGLISH_CASE = "專有名詞大小寫";

/**
 * 本模組判定的全部規則，由進入點傳給 Context 確認登記在規則表。正規式表與詞表的規則由各表的規則欄指定。
 */
export const RULES = [UNPAIRED, ENGLISH_CASE];

/**
 * 正規式表標出命中文字的具名群組。沒有這個群組時取整段命中。
 */
const HIT_GROUP = "命中";

/**
 * 比對對象為段落與清單時套用的行種類。
 */
const PARA_LIST_KINDS = new Set([PARA, QUOTE, LIST]);

/**
 * 網址。詞表比對前遮罩，網域與路徑不算正文的用詞。
 */
const URL_RE = /https?:\/\/[^\s)>\]]+/gu;

/**
 * 英文詞的組成字元。命中位置的前一字是這些字元或連字元、句點、斜線時不算完整單字，後一字是這些字元，
 * 或是連字元、句點、斜線再接這些字元時也不算。
 */
const WORD_CHAR_RE = /[A-Za-z0-9_@]/u;
const JOINER_RE = /[-./]/u;

/**
 * 依規則快取的掃描詞表：不使用寫法、技術用語與英文詞，依長度由長到短排列。
 * @type {WeakMap<import("./rules.mjs").Rules, Object[]>}
 */
const SCAN_WORDS = new WeakMap();

/* ==================================================
 * 正規式
 * ================================================== */

/**
 * 判定一列正規式是否套用在這一行。
 * @param {Object} p 正規式表的一列。
 * @param {import("./parse.mjs").Line} l 行。
 * @returns {boolean}
 */
function targets(p, l) {
  // 遮罩行套用在全部有文字的行
  if (p.target === TARGET_MASKED) return true;
  // 表格以外略過表格列
  if (p.target === TARGET_NON_TABLE) return l.kind !== TABLE;
  // 段落與清單只看段落、引言與清單
  return p.target === TARGET_PARA_LIST && PARA_LIST_KINDS.has(l.kind);
}

/**
 * 依正規式表檢查有文字的行，每一列在一行只列出第一個不在例外的命中。遮罩後的文字與原行等長，命中文字取自原行。
 * @param {import("./context.mjs").Context} ctx 執行環境。
 * @param {import("./context.mjs").Doc} doc 文件。
 */
function checkPatterns(ctx, doc) {
  // 逐行套用每一列正規式
  for (const l of doc.lines.filter((x) => PROSE.has(x.kind))) {
    // 依比對對象挑出套用在這一行的列
    for (const p of ctx.rules.patterns.filter((x) => targets(x, l))) {
      const spans = [...l.masked.matchAll(p.re)].map((m) => (m.groups?.[HIT_GROUP] === undefined ? m.indices[0] : m.indices.groups[HIT_GROUP]));
      const span = spans.find(([start, end]) => !p.exceptions.has(l.raw.slice(start, end)));
      // 沒有命中或命中的都是例外時看下一列
      if (!span) continue;
      const hit = l.raw.slice(span[0], span[1]);
      ctx.report(doc, p.rule, l, span[0], hit, { [HIT_GROUP]: hit });
    }
  }
}

/* ==================================================
 * 詞表
 * ================================================== */

/**
 * 判定中文詞的邊界：前一字與第一字，或最後一字與後一字，組成邊界詞時不算命中。
 * @param {string} text 遮罩後的文字。
 * @param {number} pos 詞的位置。
 * @param {number} len 詞的長度。
 * @param {Set<string>} boundary 邊界詞。
 * @returns {boolean} 邊界上沒有組成邊界詞時為 true。
 */
function clearBoundary(text, pos, len, boundary) {
  return !boundary.has(text.slice(pos - 1, pos + 1)) && !boundary.has(text.slice(pos + len - 1, pos + len + 1));
}

/**
 * 判定詞是否在指定位置出現，不在例外的整詞裡，邊界上也沒有組成邊界詞。
 * @param {string} text 遮罩後的文字。
 * @param {number} pos 位置。
 * @param {string} word 詞。
 * @param {string[]} exceptions 含這個詞的例外整詞。
 * @param {Set<string>} boundary 邊界詞。
 * @returns {boolean}
 */
function plainAt(text, pos, word, exceptions, boundary) {
  return text.startsWith(word, pos) && clearBoundary(text, pos, word.length, boundary) && !exceptions.some((e) => {
    const at = e.indexOf(word);
    return at >= 0 && text.startsWith(e, pos - at);
  });
}

/**
 * 判定詞是否在指定位置以完整的詞出現。英文詞不分大小寫，前後不能接英文字元，也不能是網域、路徑或連字名稱的一段。
 * @param {string} text 遮罩後的文字。
 * @param {number} pos 位置。
 * @param {Object} w 詞表的一列。
 * @param {Set<string>} boundary 邊界詞。
 * @returns {boolean}
 */
function wordAt(text, pos, w, boundary) {
  // 中文詞依例外與邊界判定
  if (!w.ascii) return plainAt(text, pos, w.word, w.exceptions, boundary);
  // 英文詞取前一字與後一字，判定是否為完整單字
  const end = pos + w.word.length;
  const before = text[pos - 1] ?? "";
  const after = text[end] ?? "";
  // 後一字是連字元、句點或斜線再接英文字時，命中的是連字名稱、網域或路徑的一段
  const joined = JOINER_RE.test(after) && WORD_CHAR_RE.test(text[end + 1] ?? "");
  return text.slice(pos, end).toLowerCase() === w.key && !WORD_CHAR_RE.test(before) && !JOINER_RE.test(before) && !WORD_CHAR_RE.test(after) && !joined;
}

/**
 * 掃描詞表：詞表加上英文詞。英文詞以英文詞表的寫法為標準寫法，只在寫法不同時列出，改用標準寫法。
 * @param {import("./rules.mjs").Rules} rules 規則。
 * @returns {Object[]} 依長度由長到短排列的詞。
 */
function scanWords(rules) {
  // 同一份規則只組一次
  if (!SCAN_WORDS.has(rules)) {
    const english = [...rules.english].map(([key, word]) => ({ word, key, ascii: true, rule: ENGLISH_CASE, use: word, exceptions: [], caseOnly: true }));
    // 同一位置取最長的詞，長的詞排在前面
    SCAN_WORDS.set(rules, [...rules.words, ...english].sort((a, b) => b.word.length - a.word.length));
  }
  return SCAN_WORDS.get(rules);
}

/**
 * 依詞表檢查每個區塊，一條規則在區塊內的命中數達成群門檻時逐一列出。只檢查寫法的詞只收寫法與詞不同的命中。
 * @param {import("./context.mjs").Context} ctx 執行環境。
 * @param {import("./context.mjs").Doc} doc 文件。
 */
function checkWords(ctx, doc) {
  const words = scanWords(ctx.rules);
  const boundary = ctx.rules.boundary;
  // 逐個區塊收集命中，再依規則的成群門檻列出
  for (const block of blocks(doc.lines)) {
    const hits = [];
    // 逐行由左到右掃描，每個位置取最長的詞
    for (const l of block) {
      const text = l.masked.replace(URL_RE, (m) => fill(m, MASK));
      // pos 是比對位置，命中時跳過整個詞
      for (let pos = 0; pos < text.length;) {
        const w = words.find((x) => wordAt(text, pos, x, boundary));
        // 沒有命中時往下一個字元
        if (!w) {
          pos++;
          continue;
        }
        const written = text.slice(pos, pos + w.word.length);
        // 英文詞只收寫法與標準寫法不同的命中
        if (!w.caseOnly || written !== w.word) hits.push({ l, pos, w, written });
        pos += w.word.length;
      }
    }
    // 規則的命中數達門檻時逐一列出
    for (const h of hits) {
      // 未達門檻的規則不列出
      if (hits.filter((x) => x.w.rule === h.w.rule).length < ctx.rules.rule(h.w.rule).threshold) continue;
      ctx.report(doc, h.w.rule, h.l, h.pos, h.written, { 詞: h.written, 改用: h.w.use }, h.w.use === EMPTY_CELL ? null : h.w.use);
    }
  }
}

/* ==================================================
 * 成對連接詞
 * ================================================== */

/**
 * 依成對連接詞表檢查每個範圍：開頭詞之後，同一個範圍內沒有任何接續詞時列出開頭詞。
 * @param {import("./context.mjs").Context} ctx 執行環境。
 * @param {import("./context.mjs").Doc} doc 文件。
 */
function checkPairs(ctx, doc) {
  // 逐個範圍套用每一列
  for (const scope of pairScopes(doc.lines)) {
    const text = scope.map((l) => l.masked).join("\n");
    const starts = scope.map((l, k) => scope.slice(0, k).reduce((n, x) => n + x.masked.length + 1, 0));
    // 每一列只列出範圍內第一個沒有接續的開頭詞
    for (const pair of ctx.rules.pairs) {
      let pos = -1;
      // 找第一個不在例外整詞裡、邊界上也沒有組成邊界詞的開頭詞
      for (let at = text.indexOf(pair.open); at >= 0; at = text.indexOf(pair.open, at + 1)) {
        // 找到後停止
        if (plainAt(text, at, pair.open, pair.exceptions, ctx.rules.boundary)) {
          pos = at;
          break;
        }
      }
      const rest = text.slice(pos + pair.open.length);
      // 沒有開頭詞，或開頭詞之後有接續詞時看下一列
      if (pos < 0 || pair.closers.some((c) => rest.includes(c))) continue;
      const k = starts.findLastIndex((x) => x <= pos);
      ctx.report(doc, UNPAIRED, scope[k], pos - starts[k], pair.open, { 開頭: pair.open, 接續: pair.closers.join(WORD_SEPARATOR) });
    }
  }
}

/* ==================================================
 * 入口
 * ================================================== */

/**
 * 檢查一份文件的詞彙。
 * @param {import("./context.mjs").Context} ctx 執行環境。
 * @param {import("./context.mjs").Doc} doc 已解析的文件。
 */
export function run(ctx, doc) {
  checkPatterns(ctx, doc);
  checkWords(ctx, doc);
  checkPairs(ctx, doc);
}
