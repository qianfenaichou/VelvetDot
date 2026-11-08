#!/usr/bin/env node
/**
 * docs/ 中文 Markdown 文风与格式检查。
 *
 * 用法：
 *   node tools/check_docs.mjs          人类可读输出
 *   node tools/check_docs.mjs --json   单行 JSON
 *
 * 规则来源：
 *   - 禁用词与禁用句式：out/submission/style-spec.md 第 6 节 E（第 364-451 行）。
 *     该节表格的「禁用」列抄成 E_RULES；6.5 的句法条目抄成正则。
 *   - 追加禁用词：作业号、slurm、sacct、门禁、判据、落点、台账、工单、本轮、
 *     本次、待回填、TODO、全绿、自证、借鉴、参考仓库、对标。
 *   - 结构：每章首行 `# NN 标题`；二级标题 `## 章号.序号 小标题`；表题 `表 章号-序号`。
 *   - 链接：Markdown 相对链接的目标必须存在；跳过 http、https、# 与其它协议。
 *   - 密度：每千字破折号 > 2、加粗 > 10、分号 > 8，或单段 > 300 字，只告警。
 *
 * 边界：
 *   - 只读，不写文件，不联网，无第三方依赖。
 *   - docs/ 不存在时视为通过，输出 `docs 尚未创建`。
 *   - 禁用词扫描包含代码行；标题、表题、链接和密度扫描跳过围栏代码块。
 *   - H2 与表题的章号接受 1-2 位数字，按数值与首行章号比较。
 *   - 输出顺序固定：文件按路径排序，问题按行号、kind、text 排序。
 */

import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const ROOT = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const DOCS_DIR = path.join(ROOT, 'docs');
const JSON_MODE = process.argv.slice(2).includes('--json');

const BLOCKING_KINDS = new Set(['forbidden', 'heading', 'table', 'link']);
const KIND_RANK = { forbidden: 0, heading: 1, table: 2, link: 3, density: 4 };
const KIND_LABEL = {
  forbidden: '禁用词',
  heading: '标题',
  table: '表题',
  link: '链接',
  density: '密度',
};

/* ------------------------------------------------------------------ */
/* 禁用词与禁用句式                                                     */
/* ------------------------------------------------------------------ */

const escapeRegExp = (s) => s.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');

function lit(term, flags = 'g') {
  return { label: term, re: new RegExp(escapeRegExp(term), flags) };
}

function pat(label, source, flags = 'g') {
  return { label, re: new RegExp(source, flags) };
}

// out/submission/style-spec.md:366-389（6.1 AI 腔）
const E_RULES = [
  lit('值得注意的是'),
  lit('综上所述'),
  lit('由此可见'),
  pat('不仅……而且……', '不仅[^。！？；\\n]{0,60}?而且'),
  pat('既……又……', '既(?!然)[^。！？；\\n]{0,60}?又'),
  pat('在当今……背景下', '在当今[^。！？\\n]{0,40}?背景下'),
  pat('随着……的不断发展', '随着[^。！？\\n]{0,40}?的不断发展'),
  lit('本文旨在'),
  lit('本文将深入探讨'),
  lit('显著'),
  lit('大幅'),
  lit('明显'),
  lit('充分'),
  lit('有效'),
  lit('全面'),
  lit('系统性'),
  lit('首次'),
  lit('首创'),
  lit('唯一'),
  lit('领先'),
  lit('奠定了基础'),
  lit('提供了有力支撑'),
  lit('具有重要的理论意义和工程价值'),
  lit('众所周知'),
  lit('不难看出'),
  lit('显然'),
  lit('笔者认为'),
  lit('我们'),
  lit('从某种意义上说'),
  lit('某种程度上'),
  lit('相关'),
  lit('相应'),
  lit('一定的'),
  lit('等等'),
  lit('等问题'),
  lit('基本上'),
  lit('大约'),
  lit('左右'),
  pat('起到了……作用', '起到了[^。！？\\n]{0,40}?作用'),
  pat('对……进行了测试', '对[^。！？\\n]{0,60}?进行了测试'),
  pat('存在着……问题', '存在着[^。！？\\n]{0,40}?问题'),
  lit('优于'),
  lit('快于'),

  // out/submission/style-spec.md:391-408（6.2 商业黑话）
  lit('赋能'),
  lit('助力'),
  lit('闭环'),
  lit('抓手'),
  lit('生态'),
  lit('落地'),
  lit('对齐'),
  lit('维度'),
  lit('层面'),
  lit('颗粒度'),
  lit('端到端'),
  lit('迭代'),
  lit('复盘'),
  lit('打法'),
  lit('组合拳'),
  lit('护城河'),
  lit('降本增效'),
  lit('业界领先'),

  // out/submission/style-spec.md:410-429（6.3 内部流程词）
  lit('本轮'),
  lit('本格'),
  lit('开工'),
  lit('收工'),
  lit('门禁'),
  lit('任务票'),
  pat('blocker', '\\bblocker\\b', 'gi'),
  lit('冻结'),
  lit('交接书'),
  lit('红队'),
  lit('回归全绿'),
  lit('已产出待验'),
  lit('口径'),
  lit('落点'),
  lit('改动面'),
  lit('证据链'),
  pat('P-2', '\\bP-2\\b', 'gi'),
  pat('H3', '\\bH3\\b'),
  pat('H4', '\\bH4\\b'),
  pat('12/12 有产物', '12\\/12\\s*有产物'),

  // out/submission/style-spec.md:431-442（6.4 空话动词与模糊限定）
  lit('进行了分析'),
  lit('开展了工作'),
  lit('作出处理'),
  lit('进行处理'),
  lit('有所提升'),
  lit('有所改善'),
  lit('表现良好'),
  lit('效果不错'),
  lit('基本一致'),
  lit('大致相同'),
  lit('覆盖了多种情况'),
  lit('满足要求'),
  lit('未发现异常'),

  // out/submission/style-spec.md:444-451（6.5 句法层面的禁用）
  pat('通过……实现了……提升了', '通过[^。！？\\n]{0,60}?实现了[^。！？\\n]{0,60}?提升了'),
  pat('不是……而是……', '不是[^。！？\\n]{0,60}?而是'),
  pat('一方面……另一方面……', '一方面[^。！？\\n]{0,60}?另一方面'),
  pat('首先……其次/最后', '(?:首先[^。！？\\n]{0,80}?其次|首先[^。！？\\n]{0,80}?最后|其次[^。！？\\n]{0,80}?最后)'),
  pat('连续三个「的」', '[^\\s\\p{P}]{1,12}的[^\\s\\p{P}]{1,12}的[^\\s\\p{P}]{1,12}的', 'gu'),
];

// 任务额外要求的禁用词。门禁、落点、本轮已在 E 节；此处补齐其余项。
const EXTRA_RULES = [
  lit('作业号'),
  pat('slurm', '\\bslurm\\b', 'gi'),
  pat('sacct', '\\bsacct\\b', 'gi'),
  lit('判据'),
  lit('台账'),
  lit('工单'),
  lit('本次'),
  lit('待回填'),
  pat('TODO', '\\bTODO\\b', 'gi'),
  lit('全绿'),
  lit('自证'),
  lit('借鉴'),
  lit('参考仓库'),
  lit('对标'),
];

const FORBIDDEN_RULES = [...E_RULES, ...EXTRA_RULES];

// 6.5「每段开头都是『随着』『在……的背景下』」。只在段落首行检查。
const PARAGRAPH_START_RULES = [
  pat('段首「随着」', '^随着'),
  pat('段首「在……背景下」', '^在[^。！？\\n]{0,30}?背景下'),
];

/* ------------------------------------------------------------------ */
/* 文件遍历与通用工具                                                   */
/* ------------------------------------------------------------------ */

function stripBom(text) {
  return text.charCodeAt(0) === 0xfeff ? text.slice(1) : text;
}

function listMarkdownFiles(dir) {
  const files = [];
  const stack = [dir];
  while (stack.length > 0) {
    const current = stack.pop();
    let entries;
    try {
      entries = fs.readdirSync(current, { withFileTypes: true });
    } catch {
      continue;
    }
    for (const entry of entries) {
      const full = path.join(current, entry.name);
      if (entry.isSymbolicLink()) continue;
      if (entry.isDirectory()) {
        stack.push(full);
      } else if (entry.isFile() && entry.name.toLowerCase().endsWith('.md')) {
        files.push(full);
      }
    }
  }
  files.sort((a, b) => (a < b ? -1 : a > b ? 1 : 0));
  return files;
}

function toRel(absPath) {
  return path.relative(ROOT, absPath).split(path.sep).join('/');
}

function countChars(text) {
  return text.replace(/\s/g, '').length;
}

function excerpt(text, max = 80) {
  const oneLine = String(text).replace(/\s+/g, ' ').trim();
  if (oneLine.length <= max) return oneLine;
  return `${oneLine.slice(0, max - 1)}…`;
}

function quoted(text) {
  const value = excerpt(text);
  return value ? `「${value}」` : '空行';
}

function stripBlockPrefix(line) {
  return line.replace(/^\s{0,3}(?:#{1,6}|>|[-*+]|\d{1,3}[.)])\s+/, '');
}

/* ------------------------------------------------------------------ */
/* 禁用词                                                               */
/* ------------------------------------------------------------------ */

function findForbidden(line) {
  const hits = [];
  for (const rule of FORBIDDEN_RULES) {
    rule.re.lastIndex = 0;
    const match = rule.re.exec(line);
    if (!match || match[0].length === 0) continue;
    hits.push({
      start: match.index,
      end: match.index + match[0].length,
      text: match[0],
    });
  }
  // 同一行重叠的命中只保留起点最早、长度最长的一条，避免「回归全绿」+「全绿」重复。
  hits.sort((a, b) => a.start - b.start || (b.end - b.start) - (a.end - a.start));
  const kept = [];
  for (const hit of hits) {
    if (kept.some((k) => hit.start < k.end && hit.end > k.start)) continue;
    kept.push(hit);
  }
  return kept;
}

/* ------------------------------------------------------------------ */
/* 代码围栏与文本清洗                                                   */
/* ------------------------------------------------------------------ */

function fenceMarker(line) {
  const match = line.match(/^\s{0,3}(`{3,}|~{3,})/);
  if (!match) return null;
  return { ch: match[1][0], len: match[1].length };
}

function cleanProse(line) {
  return line
    .replace(/`+[^`\n]*`+/g, '')
    .replace(/!?\[[^\]\n]*\]\((?:[^()\n]|\([^()\n]*\))*\)/g, (whole) => {
      const label = whole.match(/^!?\[([^\]\n]*)\]/);
      return label ? label[1] : '';
    })
    .replace(/^\s{0,3}(?:#{1,6}|>|[-*+]|\d{1,3}[.)])\s+/, '')
    .replace(/<\/?[A-Za-z][^>]*>/g, '')
    .replace(/[|*_~]/g, '')
    .replace(/\s+/g, ' ');
}

/* ------------------------------------------------------------------ */
/* 链接                                                                 */
/* ------------------------------------------------------------------ */

// 手工扫描 `[text](dest)`，允许目标里有一层以上括号；图片链接同样处理。
function extractInlineDestinations(line) {
  const destinations = [];
  for (let i = 0; i < line.length; i += 1) {
    if (line[i] !== '[') continue;
    let closeBracket = i + 1;
    while (closeBracket < line.length && line[closeBracket] !== ']') closeBracket += 1;
    if (closeBracket >= line.length || line[closeBracket + 1] !== '(') continue;
    let depth = 1;
    let closeParen = closeBracket + 2;
    for (; closeParen < line.length; closeParen += 1) {
      if (line[closeParen] === '(') depth += 1;
      else if (line[closeParen] === ')') {
        depth -= 1;
        if (depth === 0) break;
      }
    }
    if (depth !== 0) continue;
    destinations.push(line.slice(closeBracket + 2, closeParen));
    i = closeParen;
  }
  return destinations;
}

function normalizeDestination(raw) {
  let dest = raw.trim();
  if (dest.startsWith('<')) {
    const end = dest.indexOf('>');
    if (end === -1) return null;
    dest = dest.slice(1, end);
  } else {
    dest = dest.split(/\s+/)[0];
  }
  return dest.trim();
}

function isExternalOrNonRelative(dest) {
  if (!dest) return true;
  if (dest.startsWith('#')) return true;
  if (dest.startsWith('//')) return true;
  if (dest.startsWith('/') || dest.startsWith('~')) return true;
  // http、https、mailto、data、ftp 等任何带协议的地址。
  return /^[A-Za-z][A-Za-z0-9+.-]*:/.test(dest);
}

function linkTargetExists(fileDir, dest) {
  let target = dest.split('#')[0].split('?')[0];
  if (!target) return true;
  target = target.replace(/\\/g, '/');
  const candidates = [target];
  try {
    const decoded = decodeURIComponent(target);
    if (decoded !== target) candidates.push(decoded);
  } catch {
    // 非法百分号编码按原样检查。
  }
  return candidates.some((candidate) => {
    try {
      return fs.existsSync(path.resolve(fileDir, candidate));
    } catch {
      return false;
    }
  });
}

/* ------------------------------------------------------------------ */
/* 单文件检查                                                           */
/* ------------------------------------------------------------------ */

function checkFile(absPath, relPath) {
  let text;
  try {
    text = fs.readFileSync(absPath, 'utf8');
  } catch (error) {
    const code = error && error.code ? error.code : 'READ_ERROR';
    return [{ path: relPath, line: 1, kind: 'heading', text: `无法读取文件（${code}）` }];
  }

  const lines = stripBom(text).split(/\r?\n/);
  const issues = [];
  const fileDir = path.dirname(absPath);

  const add = (kind, line, issueText) => {
    issues.push({ path: relPath, line, kind, text: issueText });
  };

  /* 首行：每章第一行必须是 `# NN 标题`。 */
  const firstLine = lines[0] ?? '';
  const h1 = firstLine.match(/^# (\d{2}) (\S.*)$/);
  const chapterNo = h1 ? h1[1] : null;
  if (!h1) {
    add('heading', 1, `首行应为 "# 两位数字 标题"，实际为${quoted(firstLine)}`);
  }

  let fence = null;
  let paragraph = null;
  let totalChars = 0;
  let dashCount = 0;
  let dashFirstLine = 0;
  let boldCount = 0;
  let boldFirstLine = 0;
  let semicolonCount = 0;
  let semicolonFirstLine = 0;

  const flushParagraph = () => {
    if (!paragraph) return;
    const length = countChars(paragraph.text);
    if (length > 300) {
      add('density', paragraph.start, `段落 ${length} 字（上限 300）`);
    }
    paragraph = null;
  };

  const startParagraph = (lineNo, clean, forbiddenHits) => {
    paragraph = { start: lineNo, text: '' };
    if (forbiddenHits.length > 0) return;
    const head = clean.trimStart();
    for (const rule of PARAGRAPH_START_RULES) {
      rule.re.lastIndex = 0;
      const match = rule.re.exec(head);
      if (match) {
        add('forbidden', lineNo, excerpt(match[0]));
        break;
      }
    }
  };

  for (let index = 0; index < lines.length; index += 1) {
    const raw = lines[index];
    const lineNo = index + 1;

    /* 1. 禁用词：代码行也扫，避免 TODO、命令名藏在代码块里。 */
    const forbiddenHits = findForbidden(stripBlockPrefix(raw));
    for (const hit of forbiddenHits) {
      add('forbidden', lineNo, excerpt(hit.text));
    }

    /* 2. 围栏代码块：结构、链接、密度都跳过。 */
    const marker = fenceMarker(raw);
    if (fence) {
      if (marker && marker.ch === fence.ch && marker.len >= fence.len) fence = null;
      continue;
    }
    if (marker) {
      fence = marker;
      flushParagraph();
      continue;
    }

    /* 3. 二级标题。 */
    if (/^\s{0,3}##(?!#)/.test(raw)) {
      const heading = raw.match(/^## (\d{1,2})\.(\d{1,3}) (\S.*)$/);
      if (!heading) {
        add('heading', lineNo, `二级标题应为 "## 章号.序号 小标题"，实际为${quoted(raw)}`);
      } else if (chapterNo && Number(heading[1]) !== Number(chapterNo)) {
        add(
          'heading',
          lineNo,
          `二级标题章号 ${heading[1]} 与文件章号 ${chapterNo} 不一致`,
        );
      }
    }

    /* 4. 表题：只检查以「表」加数字开头的行。 */
    const tableLine = raw.replace(/^\s+/, '');
    if (/^表[\s\u3000]*\d/.test(tableLine)) {
      const caption = tableLine.match(/^表 (\d{1,2})-(\d{1,3})(?!\d)/);
      if (!caption) {
        add('table', lineNo, `表题应以 "表 章号-序号" 开头，实际为${quoted(tableLine)}`);
      } else if (chapterNo && Number(caption[1]) !== Number(chapterNo)) {
        add('table', lineNo, `表题章号 ${caption[1]} 与文件章号 ${chapterNo} 不一致`);
      }
    }

    /* 5. 链接：行内链接、图片链接、引用式定义。 */
    const linkSource = raw.replace(/`+[^`\n]*`+/g, '');
    for (const rawDest of extractInlineDestinations(linkSource)) {
      const dest = normalizeDestination(rawDest);
      if (!dest || isExternalOrNonRelative(dest)) continue;
      if (!linkTargetExists(fileDir, dest)) {
        add('link', lineNo, `链接目标不存在: ${dest}`);
      }
    }
    const definition = linkSource.match(/^ {0,3}\[([^\]\n]+)\]:[ \t]*(.*)$/);
    if (definition && !definition[1].startsWith('^')) {
      const dest = normalizeDestination(definition[2]);
      if (dest && !isExternalOrNonRelative(dest) && !linkTargetExists(fileDir, dest)) {
        add('link', lineNo, `链接目标不存在: ${dest}`);
      }
    }

    /* 6. 密度与段落。 */
    const clean = cleanProse(raw);
    totalChars += countChars(clean);

    const dashes = clean.match(/—+/g);
    if (dashes) {
      if (dashFirstLine === 0) dashFirstLine = lineNo;
      dashCount += dashes.length;
    }

    const semicolons = clean.match(/[；;]/g);
    if (semicolons) {
      if (semicolonFirstLine === 0) semicolonFirstLine = lineNo;
      semicolonCount += semicolons.length;
    }

    const boldSource = raw
      .replace(/`+[^`\n]*`+/g, '')
      .replace(/!?\[([^\]\n]*)\]\((?:[^()\n]|\([^()\n]*\))*\)/g, '$1');
    const bolds = boldSource.match(/(?:\*\*[^*\n]+\*\*|__[^_\n]+__)/g);
    if (bolds) {
      if (boldFirstLine === 0) boldFirstLine = lineNo;
      boldCount += bolds.length;
    }

    const isBlank = raw.trim() === '';
    const isHeading = /^\s{0,3}#{1,6}\s/.test(raw);
    const isTableRow = /^\s*\|/.test(raw);
    const isThematicBreak = /^\s{0,3}([-*_])(?:\s*\1){2,}\s*$/.test(raw);
    const isLinkDefinition = /^ {0,3}\[[^\]\n]+\]:/.test(raw);
    const isListItem = /^\s*(?:[-*+]|\d{1,3}[.)])\s+/.test(raw);

    if (isBlank || isHeading || isTableRow || isThematicBreak || isLinkDefinition) {
      flushParagraph();
    } else if (isListItem) {
      flushParagraph();
      startParagraph(lineNo, clean, forbiddenHits);
      paragraph.text += `${clean}\n`;
    } else {
      if (!paragraph) startParagraph(lineNo, clean, forbiddenHits);
      paragraph.text += `${clean}\n`;
    }
  }
  flushParagraph();

  /* 7. 每千字密度。 */
  if (totalChars > 0) {
    const rateIssues = [
      { label: '破折号', count: dashCount, firstLine: dashFirstLine, limit: 2, unit: '处' },
      { label: '加粗', count: boldCount, firstLine: boldFirstLine, limit: 10, unit: '处' },
      { label: '分号', count: semicolonCount, firstLine: semicolonFirstLine, limit: 8, unit: '个' },
    ];
    for (const metric of rateIssues) {
      if (metric.count === 0) continue;
      const rate = (metric.count * 1000) / totalChars;
      if (rate > metric.limit) {
        add(
          'density',
          metric.firstLine,
          `${metric.label} ${metric.count} ${metric.unit} / ${totalChars} 字，每千字 ${rate.toFixed(1)} ${metric.unit}（上限 ${metric.limit}）`,
        );
      }
    }
  }

  issues.sort((a, b) => {
    if (a.line !== b.line) return a.line - b.line;
    const rank = KIND_RANK[a.kind] - KIND_RANK[b.kind];
    if (rank !== 0) return rank;
    return a.text < b.text ? -1 : a.text > b.text ? 1 : 0;
  });

  return issues;
}

/* ------------------------------------------------------------------ */
/* 汇总与输出                                                           */
/* ------------------------------------------------------------------ */

function buildResult() {
  if (!fs.existsSync(DOCS_DIR)) {
    return { ok: true, summary: 'docs 尚未创建', files: [] };
  }

  let stats;
  try {
    stats = fs.statSync(DOCS_DIR);
  } catch {
    return { ok: false, summary: 'docs 无法读取', files: [] };
  }
  if (!stats.isDirectory()) {
    return { ok: false, summary: 'docs 不是目录', files: [] };
  }

  const files = listMarkdownFiles(DOCS_DIR).map((absPath) => {
    const relPath = toRel(absPath);
    return { path: relPath, issues: checkFile(absPath, relPath) };
  });

  const allIssues = files.flatMap((file) => file.issues);
  const blocking = allIssues.filter((issue) => BLOCKING_KINDS.has(issue.kind)).length;
  const warnings = allIssues.length - blocking;
  const ok = blocking === 0;

  let summary;
  if (files.length === 0) {
    summary = 'docs 下没有 .md 文件';
  } else if (allIssues.length === 0) {
    summary = `检查 ${files.length} 个文件，未发现问题`;
  } else {
    summary = `检查 ${files.length} 个文件，${blocking} 个必须修复，${warnings} 个告警`;
  }

  return { ok, summary, files };
}

function printHuman(result) {
  if (result.files.length === 0) {
    process.stdout.write(`${result.summary}\n`);
    return;
  }

  let printedFile = false;
  for (const file of result.files) {
    if (file.issues.length === 0) continue;
    printedFile = true;
    process.stdout.write(`\n${file.path}\n`);
    for (const issue of file.issues) {
      const label = KIND_LABEL[issue.kind] ?? issue.kind;
      process.stdout.write(`  ${String(issue.line).padStart(4)}  [${label}] ${issue.text}\n`);
    }
  }
  if (printedFile) process.stdout.write('\n');
  process.stdout.write(`${result.summary}\n`);
}

const result = buildResult();

if (JSON_MODE) {
  process.stdout.write(`${JSON.stringify(result)}\n`);
} else {
  printHuman(result);
}

if (!result.ok) {
  process.exitCode = 2;
} else {
  process.exitCode = 0;
}