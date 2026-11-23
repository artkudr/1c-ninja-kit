#!/usr/bin/env node
// build-guide-pdf.mjs — Markdown-гайд -> PDF для роли Бард.
//
//   node tools/guide-pdf/build-guide-pdf.mjs <файл.md> [--out <файл.pdf>]
//        [--title "…"] [--subtitle "…"] [--date "ДД.ММ.ГГГГ"] [--keep-html]
//
// Печатает путём Chromium через Playwright (сначала свой node_modules рядом со
// скриптом, затем соседний скилл skill-web-test, затем глобальный npm), а если
// Playwright недоступен — крайним средством Edge/Chrome в headless-режиме
// (тогда без нумерации страниц).
//
// Разметка: заголовки #..####, абзацы, списки (в т.ч. вложенные), таблицы GFM,
// блоки кода, цитаты (> — предупреждения), картинки ![подпись](путь), ссылки,
// **жирный**, *курсив*, `код`. Первый # — заголовок обложки. Необязательный
// блок метаданных в начале файла:
//
//   ---
//   title: Название гайда
//   subtitle: Инструкция для пользователя
//   date: 01.11.2026
//   ---
//
// Раздел «## Входные данные» (служебная шапка) в PDF не попадает.

import fs from 'node:fs';
import path from 'node:path';
import os from 'node:os';
import { execFileSync } from 'node:child_process';
import { fileURLToPath, pathToFileURL } from 'node:url';

const EXIT_USAGE = 1;
const EXIT_INPUT = 2;
const EXIT_RENDER = 3;

function fail(code, message) {
  console.error(message);
  process.exit(code);
}

// --- аргументы ---------------------------------------------------------------

function parseArgs(argv) {
  const opts = { _: [], out: '', title: '', subtitle: '', date: '', keepHtml: false };
  for (let i = 0; i < argv.length; i++) {
    const a = argv[i];
    if (a === '--out') opts.out = argv[++i] ?? '';
    else if (a === '--title') opts.title = argv[++i] ?? '';
    else if (a === '--subtitle') opts.subtitle = argv[++i] ?? '';
    else if (a === '--date') opts.date = argv[++i] ?? '';
    else if (a === '--keep-html') opts.keepHtml = true;
    else if (a === '--help' || a === '-h') {
      console.log('node tools/guide-pdf/build-guide-pdf.mjs <файл.md> [--out <файл.pdf>] [--title …] [--subtitle …] [--date …]');
      process.exit(0);
    } else if (a.startsWith('--')) fail(EXIT_USAGE, 'аргумент: неизвестный ключ ' + a);
    else opts._.push(a);
  }
  return opts;
}

const opts = parseArgs(process.argv.slice(2));
if (opts._.length !== 1) {
  fail(EXIT_USAGE, 'аргумент: нужен ровно один путь к .md — файл гайда');
}

const srcPath = path.resolve(opts._[0]);
if (!fs.existsSync(srcPath)) fail(EXIT_INPUT, 'вход: нет файла ' + srcPath);
if (!/\.md$/i.test(srcPath)) fail(EXIT_INPUT, 'вход: ожидается файл .md, получено ' + srcPath);

const outPath = opts.out ? path.resolve(opts.out) : srcPath.replace(/\.md$/i, '.pdf');

// --- markdown -> html --------------------------------------------------------

const ESC = { '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;' };
const esc = (s) => String(s).replace(/[&<>"]/g, (c) => ESC[c]);

function inline(text) {
  const stash = [];
  const keep = (html) => {
    stash.push(html);
    return '\u0000' + (stash.length - 1) + '\u0000';
  };

  let s = esc(text);

  // код — до остальной разметки
  s = s.replace(/`([^`]+)`/g, (_, code) => keep('<code>' + code + '</code>'));

  // картинки: ![подпись](путь) — путь может быть в <…> и содержать пробелы
  s = s.replace(/!\[([^\]]*)\]\(\s*(<[^>]*>|[^()]*?)\s*\)/g, (_, alt, raw) => {
    const href = raw.replace(/^<|>$/g, '').replace(/\s+"[^"]*"$/, '').trim();
    const data = imageDataUri(href);
    if (!data) return keep('<span class="missing-image">[нет файла: ' + esc(href) + ']</span>');
    const caption = alt.trim() ? '<figcaption>' + alt.trim() + '</figcaption>' : '';
    return keep('<figure><img src="' + data + '" alt="' + alt + '">' + caption + '</figure>');
  });

  // ссылки
  s = s.replace(/\[([^\]]+)\]\(\s*(<[^>]*>|[^()]*?)\s*\)/g, (_, label, raw) => {
    const href = raw.replace(/^<|>$/g, '').replace(/\s+"[^"]*"$/, '').trim();
    return keep('<a href="' + esc(href) + '">' + label + '</a>');
  });

  s = s.replace(/\*\*([^*]+)\*\*/g, '<strong>$1</strong>');
  s = s.replace(/(^|[\s(«"„])__([^_]+)__(?=[\s.,;:!?)]|$)/g, '$1<strong>$2</strong>');
  s = s.replace(/(^|[\s(«"„])\*([^*\s][^*]*)\*(?=[\s.,;:!?)]|$)/g, '$1<em>$2</em>');
  s = s.replace(/(^|[\s(«"„])_([^_\s][^_]*)_(?=[\s.,;:!?)]|$)/g, '$1<em>$2</em>');

  return s.replace(/\u0000(\d+)\u0000/g, (_, n) => stash[Number(n)]);
}

const IMAGE_MIME = {
  '.png': 'image/png', '.jpg': 'image/jpeg', '.jpeg': 'image/jpeg',
  '.gif': 'image/gif', '.webp': 'image/webp', '.svg': 'image/svg+xml',
  '.bmp': 'image/bmp'
};

function imageDataUri(href) {
  const clean = decodeURIComponent(href.replace(/^file:\/\//i, '').replace(/^\/([a-zA-Z]:)/, '$1'));
  const candidates = path.isAbsolute(clean)
    ? [clean]
    : [path.resolve(path.dirname(srcPath), clean), path.resolve(process.cwd(), clean)];
  for (const file of candidates) {
    try {
      if (!fs.existsSync(file) || !fs.statSync(file).isFile()) continue;
      const mime = IMAGE_MIME[path.extname(file).toLowerCase()];
      if (!mime) continue;
      return 'data:' + mime + ';base64,' + fs.readFileSync(file).toString('base64');
    } catch {
      /* следующий кандидат */
    }
  }
  return '';
}

function splitFrontMatter(text) {
  const meta = {};
  const m = /^\uFEFF?---\r?\n([\s\S]*?)\r?\n---[ \t]*\r?\n?/.exec(text);
  if (!m) return { meta, body: text };
  for (const line of m[1].split(/\r?\n/)) {
    const kv = /^\s*([A-Za-zА-Яа-я_]+)\s*:\s*(.*)$/.exec(line);
    if (kv) meta[kv[1].toLowerCase()] = kv[2].trim().replace(/^["']|["']$/g, '');
  }
  return { meta, body: text.slice(m[0].length) };
}

function isTableSeparator(line) {
  return /^\s*\|?\s*:?-{2,}:?\s*(\|\s*:?-{2,}:?\s*)*\|?\s*$/.test(line);
}

function splitRow(line) {
  let s = line.trim();
  if (s.startsWith('|')) s = s.slice(1);
  if (s.endsWith('|') && !s.endsWith('\\|')) s = s.slice(0, -1);
  const cells = [];
  let cur = '';
  for (let i = 0; i < s.length; i++) {
    if (s[i] === '\\' && s[i + 1] === '|') { cur += '|'; i++; continue; }
    if (s[i] === '|') { cells.push(cur.trim()); cur = ''; continue; }
    cur += s[i];
  }
  cells.push(cur.trim());
  return cells;
}

const LIST_RE = /^(\s*)([-*+]|\d+[.)])\s+(.*)$/;
const HEAD_RE = /^(#{1,6})\s+(.*?)\s*#*\s*$/;

// Собирает список, начиная со строки i. Возвращает html и следующую строку.
function parseList(lines, i) {
  const first = LIST_RE.exec(lines[i]);
  const baseIndent = first[1].length;
  const ordered = /\d/.test(first[2]);
  const items = [];
  let current = null;

  const flush = () => {
    if (current) items.push(current);
    current = null;
  };

  while (i < lines.length) {
    const line = lines[i];
    if (!line.trim()) {
      // пустая строка внутри списка продолжает его, если дальше снова элемент
      let j = i + 1;
      while (j < lines.length && !lines[j].trim()) j++;
      if (j < lines.length && LIST_RE.test(lines[j]) && LIST_RE.exec(lines[j])[1].length >= baseIndent) {
        i = j;
        continue;
      }
      break;
    }
    const m = LIST_RE.exec(line);
    if (m && m[1].length >= baseIndent) {
      if (m[1].length <= baseIndent + 1) {
        flush();
        current = { text: m[3], extra: [] };
        i++;
        continue;
      }
      // вложенный список — отдаём рекурсии и кладём в текущий элемент
      const nested = parseList(lines, i);
      if (current) current.extra.push(nested.html);
      else items.push({ text: '', extra: [nested.html] });
      i = nested.next;
      continue;
    }
    if (/^\s{2,}\S/.test(line) && current) {
      current.extra.push('<p>' + inline(line.trim()) + '</p>');
      i++;
      continue;
    }
    break;
  }
  flush();

  const tag = ordered ? 'ol' : 'ul';
  const firstNumber = ordered ? parseInt(first[2], 10) : 1;
  const startAttr = ordered && firstNumber > 1 ? ' start="' + firstNumber + '"' : '';
  const html = '<' + tag + startAttr + '>' + items.map((item) => {
    const body = (item.text ? inline(item.text) : '') + item.extra.join('');
    return '<li>' + body + '</li>';
  }).join('') + '</' + tag + '>';
  return { html, next: i };
}

function parseTable(lines, i) {
  const header = splitRow(lines[i]);
  const align = splitRow(lines[i + 1]).map((cell) => {
    if (/^:-+:$/.test(cell)) return 'center';
    if (/^-+:$/.test(cell)) return 'right';
    return 'left';
  });
  const rows = [];
  i += 2;
  while (i < lines.length && /^\s*\|/.test(lines[i])) {
    rows.push(splitRow(lines[i]));
    i++;
  }
  const th = header.map((c, n) => '<th' + (align[n] && align[n] !== 'left' ? ' style="text-align:' + align[n] + '"' : '') + '>' + inline(c) + '</th>').join('');
  const trs = rows.map((row) => '<tr>' + row.map((c, n) => '<td' + (align[n] && align[n] !== 'left' ? ' style="text-align:' + align[n] + '"' : '') + '>' + inline(c) + '</td>').join('') + '</tr>').join('');
  return { html: '<table><thead><tr>' + th + '</tr></thead><tbody>' + trs + '</tbody></table>', next: i };
}

function parseBlocks(lines) {
  const out = [];
  let i = 0;

  while (i < lines.length) {
    const line = lines[i];

    if (!line.trim()) { i++; continue; }

    if (/^\s*<!--/.test(line)) {
      while (i < lines.length && !/-->\s*$/.test(lines[i])) i++;
      i++;
      continue;
    }

    if (/^\s*```/.test(line)) {
      const lang = line.trim().replace(/^```/, '').trim();
      const buf = [];
      i++;
      while (i < lines.length && !/^\s*```/.test(lines[i])) { buf.push(lines[i]); i++; }
      i++;
      out.push('<pre' + (lang ? ' class="language-' + esc(lang) + '"' : '') + '><code>' + esc(buf.join('\n')) + '</code></pre>');
      continue;
    }

    const head = HEAD_RE.exec(line);
    if (head) {
      const level = head[1].length;
      out.push('<h' + level + '>' + inline(head[2]) + '</h' + level + '>');
      i++;
      continue;
    }

    if (/^\s*(-{3,}|\*{3,}|_{3,})\s*$/.test(line)) {
      out.push('<hr>');
      i++;
      continue;
    }

    if (/^\s*\|/.test(line) && i + 1 < lines.length && isTableSeparator(lines[i + 1])) {
      const table = parseTable(lines, i);
      out.push(table.html);
      i = table.next;
      continue;
    }

    if (/^\s*>/.test(line)) {
      const buf = [];
      while (i < lines.length && /^\s*>/.test(lines[i])) {
        buf.push(lines[i].replace(/^\s*>\s?/, ''));
        i++;
      }
      const inner = buf.filter((l) => l.trim()).map((l) => '<p>' + inline(l.trim()) + '</p>').join('');
      out.push('<blockquote>' + (inner || '<p></p>') + '</blockquote>');
      continue;
    }

    if (LIST_RE.test(line)) {
      const list = parseList(lines, i);
      out.push(list.html);
      i = list.next;
      continue;
    }

    // абзац до пустой строки или начала блока
    const buf = [line];
    i++;
    while (i < lines.length) {
      const next = lines[i];
      if (!next.trim()) break;
      if (/^\s*(```|>|#{1,6}\s|\||<!--)/.test(next)) break;
      if (LIST_RE.test(next)) break;
      if (/^\s*(-{3,}|\*{3,}|_{3,})\s*$/.test(next)) break;
      buf.push(next);
      i++;
    }
    out.push('<p>' + inline(buf.map((l) => l.trim()).join(' ')) + '</p>');
  }

  return out.join('\n');
}

// Раздел «Входные данные» — служебный, в гайд для человека не идёт.
function dropServiceSections(lines) {
  const kept = [];
  let skipLevel = 0;
  for (const line of lines) {
    const m = HEAD_RE.exec(line);
    if (m) {
      const level = m[1].length;
      if (skipLevel && level <= skipLevel) skipLevel = 0;
      if (!skipLevel && /^входные данные$/i.test(m[2].trim())) { skipLevel = level; continue; }
    }
    if (!skipLevel) kept.push(line);
  }
  return kept;
}

// --- оформление --------------------------------------------------------------

const CSS = `
@page { size: A4; margin: 18mm 16mm; }

html { font-family: "Segoe UI", "PT Sans", Arial, sans-serif; }
body { margin: 0; color: #1c2530; font-size: 11pt; line-height: 1.55; }

.cover { height: 235mm; display: flex; flex-direction: column; justify-content: center; page-break-after: always; }
.cover .kicker { font-size: 10pt; letter-spacing: .18em; text-transform: uppercase; color: #5b6b7c; margin-bottom: 10mm; }
.cover h1 { font-size: 30pt; line-height: 1.15; margin: 0 0 6mm; color: #12293f; border: 0; padding: 0; }
.cover .subtitle { font-size: 14pt; color: #43566b; margin: 0 0 16mm; }
.cover .meta { font-size: 10pt; color: #6b7b8c; border-top: 1px solid #d7dee6; padding-top: 4mm; }

h1, h2, h3, h4 { color: #12293f; page-break-after: avoid; break-after: avoid; }
h1 { font-size: 19pt; margin: 0 0 5mm; padding-bottom: 2mm; border-bottom: 2px solid #2f6fa8; }
h2 { font-size: 15pt; margin: 9mm 0 3mm; padding-bottom: 1.5mm; border-bottom: 1px solid #dbe3ea; }
h3 { font-size: 12pt; margin: 6mm 0 2mm; }
h4 { font-size: 11pt; margin: 5mm 0 2mm; }

p { margin: 0 0 3mm; orphans: 3; widows: 3; }
ul, ol { margin: 0 0 3.5mm; padding-left: 7mm; }
li { margin: 0 0 1.8mm; }
li > ul, li > ol { margin-top: 1.8mm; }

li > ul { list-style-type: "–  "; }

a { color: #1f5f9c; text-decoration: none; }

code { font-family: "Cascadia Mono", Consolas, monospace; font-size: 9.5pt; background: #eef2f6; padding: 0 .5mm; border-radius: 2px; white-space: nowrap; }
pre { background: #f4f7fa; border: 1px solid #dde5ec; border-radius: 4px; padding: 3mm 4mm; overflow-wrap: anywhere; white-space: pre-wrap; page-break-inside: avoid; break-inside: avoid; }
pre code { background: none; padding: 0; font-size: 9pt; }

blockquote { margin: 4mm 0; padding: 3mm 4mm; background: #fff8e8; border-left: 3px solid #d9a441; page-break-inside: avoid; break-inside: avoid; }
blockquote p:last-child { margin-bottom: 0; }

table { width: 100%; border-collapse: collapse; margin: 3mm 0 5mm; font-size: 9.5pt; }
th, td { border: 1px solid #cfd8e2; padding: 2mm 2.5mm; vertical-align: top; text-align: left; }
th { background: #eaf0f6; font-weight: 600; }
thead { display: table-header-group; }
tr { page-break-inside: avoid; break-inside: avoid; }

figure { margin: 4mm 0 6mm; page-break-inside: avoid; break-inside: avoid; text-align: center; }
figure img { max-width: 100%; max-height: 115mm; border: 1px solid #cfd8e2; border-radius: 3px; }
figcaption { font-size: 9pt; color: #56677a; margin-top: 2mm; text-align: left; }

.missing-image { color: #a11; font-size: 9pt; }

hr { border: 0; border-top: 1px solid #dbe3ea; margin: 6mm 0; }
`;

function htmlDocument({ title, subtitle, metaLine, bodyHtml, lang = 'ru' }) {
  return `<!doctype html>
<html lang="${lang}">
<head>
<meta charset="utf-8">
<title>${esc(title)}</title>
<style>${CSS}</style>
</head>
<body>
<section class="cover">
  <div class="kicker">Инструкция</div>
  <h1>${esc(title)}</h1>
  ${subtitle ? '<p class="subtitle">' + esc(subtitle) + '</p>' : ''}
  ${metaLine ? '<p class="meta">' + esc(metaLine) + '</p>' : ''}
</section>
${bodyHtml}
</body>
</html>`;
}

// --- рендер в PDF -------------------------------------------------------------

// Playwright ищется рядом со скриптом, затем у соседнего скилла skill-web-test,
// затем в глобальном npm. Пути считаются от расположения самого скрипта: скиллы
// живут в репозитории кита, а не в ~/.config/opencode/skills.
const SCRIPT_DIR = path.dirname(fileURLToPath(import.meta.url));
const SKILLS_DIR = path.resolve(SCRIPT_DIR, '..', '..');

// Точка входа пакета playwright (<pkg>/index.mjs|index.js) или '' если пакета нет.
function playwrightEntry(pkgDir) {
  if (!pkgDir) return '';
  for (const rel of ['index.mjs', 'index.js']) {
    const file = path.join(pkgDir, rel);
    if (fs.existsSync(file)) return file;
  }
  return '';
}

function npmGlobalRoot() {
  try {
    const npm = process.platform === 'win32' ? 'npm.cmd' : 'npm';
    const out = execFileSync(npm, ['root', '-g'], {
      encoding: 'utf8',
      timeout: 15000,
      stdio: ['ignore', 'pipe', 'ignore']
    });
    return out.trim();
  } catch {
    return '';
  }
}

// Локальные кандидаты (без вызова npm): env, рядом со скриптом, соседний скилл.
function localPlaywrightCandidates() {
  const candidates = [];
  const addEntry = (entry) => { if (entry) candidates.push(entry); };

  const envPath = process.env.GUIDE_PDF_PLAYWRIGHT;
  if (envPath) {
    addEntry(/\.(?:c|m)?js$/i.test(envPath) ? envPath : playwrightEntry(envPath));
  }

  addEntry(playwrightEntry(path.join(SCRIPT_DIR, 'node_modules', 'playwright')));
  addEntry(playwrightEntry(path.resolve(SCRIPT_DIR, '..', 'node_modules', 'playwright')));
  addEntry(playwrightEntry(path.join(SKILLS_DIR, 'skill-web-test', 'scripts', 'node_modules', 'playwright')));

  return candidates;
}

// Глобальный npm: путь от `npm root -g`, затем типовые места установки Node.
function globalPlaywrightCandidates() {
  const candidates = [];
  const addEntry = (entry) => { if (entry) candidates.push(entry); };

  const globalRoot = npmGlobalRoot();
  if (globalRoot) addEntry(playwrightEntry(path.join(globalRoot, 'playwright')));
  addEntry(playwrightEntry(path.join(process.env.APPDATA || '', 'npm', 'node_modules', 'playwright')));
  addEntry(playwrightEntry(path.join(process.env.ProgramFiles || '', 'nodejs', 'node_modules', 'playwright')));

  return candidates;
}

async function importFirst(candidates) {
  for (const candidate of candidates) {
    try {
      if (!fs.existsSync(candidate)) continue;
      return await import(pathToFileURL(candidate).href);
    } catch { /* следующий кандидат */ }
  }
  return null;
}

async function loadPlaywright() {
  try {
    return await import('playwright');
  } catch { /* нет локального пакета — ищем по известным местам */ }

  const local = await importFirst(localPlaywrightCandidates());
  if (local) return local;

  return await importFirst(globalPlaywrightCandidates());
}

function findBrowserExe() {
  const local = process.env.LOCALAPPDATA || '';
  const candidates = [
    path.join(local, 'ms-playwright'),
    path.join(process.env['ProgramFiles(x86)'] || 'C:\\Program Files (x86)', 'Microsoft', 'Edge', 'Application'),
    path.join(process.env.ProgramFiles || 'C:\\Program Files', 'Microsoft', 'Edge', 'Application'),
    path.join(process.env.ProgramFiles || 'C:\\Program Files', 'Google', 'Chrome', 'Application')
  ];
  const exes = ['msedge.exe', 'chrome.exe'];
  for (const dir of candidates) {
    if (!dir || !fs.existsSync(dir)) continue;
    if (dir.toLowerCase().endsWith('ms-playwright')) {
      for (const entry of fs.readdirSync(dir)) {
        if (!/^chromium-\d+$/.test(entry)) continue;
        for (const rel of ['chrome-win\\chrome.exe', 'chrome-win64\\chrome.exe']) {
          const exe = path.join(dir, entry, rel);
          if (fs.existsSync(exe)) return exe;
        }
      }
      continue;
    }
    for (const exe of exes) {
      const full = path.join(dir, exe);
      if (fs.existsSync(full)) return full;
    }
  }
  return '';
}

async function renderWithPlaywright(pw, html, target) {
  const browser = await pw.chromium.launch();
  try {
    const page = await browser.newPage();
    await page.setContent(html, { waitUntil: 'load', baseURL: pathToFileURL(path.dirname(srcPath) + path.sep).href });
    await page.evaluate(() => Promise.all(Array.from(document.images).map((img) => img.complete ? null : new Promise((res) => { img.onload = img.onerror = res; }))));
    await page.pdf({
      path: target,
      format: 'A4',
      printBackground: true,
      displayHeaderFooter: true,
      headerTemplate: '<span></span>',
      footerTemplate: '<div style="width:100%;font-size:8pt;color:#7a8794;padding:0 16mm;text-align:right;">Стр. <span class="pageNumber"></span> из <span class="totalPages"></span></div>',
      margin: { top: '16mm', right: '16mm', bottom: '20mm', left: '16mm' }
    });
  } finally {
    await browser.close();
  }
}

function renderWithBrowserCli(html, target) {
  const exe = findBrowserExe();
  if (!exe) return false;
  const tmpDir = fs.mkdtempSync(path.join(os.tmpdir(), 'guide-pdf-'));
  const htmlFile = path.join(tmpDir, 'guide.html');
  const profile = path.join(tmpDir, 'profile');
  fs.writeFileSync(htmlFile, html, 'utf8');
  execFileSync(exe, [
    '--headless=new',
    '--disable-gpu',
    '--no-first-run',
    '--no-default-browser-check',
    '--user-data-dir=' + profile,
    '--no-pdf-header-footer',
    '--print-to-pdf=' + target,
    pathToFileURL(htmlFile).href
  ], { stdio: 'ignore', timeout: 120000 });
  return true;
}

// --- основной сценарий --------------------------------------------------------

const raw = fs.readFileSync(srcPath, 'utf8');
const { meta, body } = splitFrontMatter(raw);
const lines = body.split(/\r?\n/);

const firstH1 = lines.find((line) => /^#\s+/.test(line));
const titleFromDoc = firstH1 ? firstH1.replace(/^#\s+/, '').trim() : '';
const stripBody = lines.filter((line) => !(firstH1 && line === firstH1));

const title = opts.title || meta.title || titleFromDoc || path.basename(srcPath, '.md');
const subtitle = opts.subtitle || meta.subtitle || '';
const date = opts.date || meta.date || new Date().toLocaleDateString('ru-RU');
const taskMatch = /([0-9]{3})/.exec(path.basename(path.dirname(path.dirname(path.dirname(srcPath)))));
const metaLine = [meta.task || (taskMatch ? 'Задача ' + taskMatch[1] : ''), date, meta.author || ''].filter(Boolean).join(' · ');

const bodyHtml = parseBlocks(dropServiceSections(stripBody));
const html = htmlDocument({ title, subtitle, metaLine, bodyHtml });

if (!bodyHtml.trim()) fail(EXIT_INPUT, 'вход: в файле нет содержимого, кроме заголовка и служебных разделов');

const outDir = path.dirname(outPath);
if (!fs.existsSync(outDir)) fs.mkdirSync(outDir, { recursive: true });
if (fs.existsSync(outPath)) fs.unlinkSync(outPath);

const pw = await loadPlaywright();
let renderer = 'playwright';
if (pw) {
  await renderWithPlaywright(pw, html, outPath);
} else {
  if (!renderWithBrowserCli(html, outPath)) {
    fail(EXIT_RENDER, 'рендер: не найден ни Playwright, ни Chromium/Edge для печати PDF');
  }
  renderer = 'browser-cli';
}

if (opts.keepHtml) fs.writeFileSync(outPath.replace(/\.pdf$/i, '.html'), html, 'utf8');

if (!fs.existsSync(outPath) || fs.statSync(outPath).size === 0) {
  fail(EXIT_RENDER, 'рендер: PDF не записался ' + outPath);
}
const head = fs.readFileSync(outPath).subarray(0, 5).toString('latin1');
if (head !== '%PDF-') fail(EXIT_RENDER, 'рендер: файл ' + outPath + ' не похож на PDF');

const sizeKb = Math.round(fs.statSync(outPath).size / 1024);
console.log('PDF: ' + outPath + ' (' + sizeKb + ' КБ, ' + renderer + ')');
