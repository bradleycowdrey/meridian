#!/usr/bin/env node
// Mac App Store screenshots for Meridian, on the Cowdrey family standard (bradleycowdrey/cowdrey-one,
// design/app-store/README.md): the app's real renders from the self-test, on a MacBook's desktop drawn by the family
// template, design/app-store/store-frame.mjs (a word-for-word copy of the master; never edit it here), in Meridian's
// steel blue.
//
//   node scripts/mac-store-shots.mjs <selftest dir> <out dir>
//
// <selftest dir> is what `Meridian --selftest <dir>` wrote. It reads:
//   store-panel.png        the menu bar panel at 2x (falls back to menubar-panel.png, 1x)
//   store-widget-large.png the widgets at 3x (fall back to widget-*.png, 2x)
//   store-widget-medium.png
//   store-widget-small.png
//   store-window.png       the desktop window at Large, 2x (optional)
//
// and writes 01-*.png ... into <out dir>: 3 to 5 pictures, each exactly 2880 x 1800 RGB (no alpha), the size the Mac
// App Store takes. Each is the template's Mac picture: the Fraunces headline and the Instrument Sans sub-line over
// the steel-blue ground, and a MacBook whose screen is a desktop (desktop()) with Meridian's globe in the menu bar
// and the app's renders on it at their own point size: the panel hung from the menu bar (where macOS puts it, against
// the screen's right edge), the widgets on the desktop, the window. The renders are only placed, never painted over.
// The menu bar's clock is the family's one clock (the template's MAC_CLOCK, desktop()'s default): never passed here.
//
// Each picture shows something different: 01 the panel hung from the menu bar; 02 the three widgets as one centred
// group; 03 the whole window beside the large and medium widgets (every city's Working / Off hours tag); 04 the window alone.
//
// A missing optional input skips that picture. It always makes at least 3, and stops with an error if it can't
// (no panel at all). Earlier PNGs in <out dir> are removed first, so a skipped picture can't linger and be uploaded.
//
// Needs Node 20.15 or later and Playwright with Chromium: playwright is found on NODE_PATH, in ./node_modules or at
// /opt/node22/lib/node_modules; Chromium is Playwright's own, or /opt/pw-browsers/chromium when that exists.
import fs from 'node:fs';
import path from 'node:path';
import { createRequire } from 'node:module';
import { fileURLToPath } from 'node:url';
import { compose, desktop, THEMES, MACBOOK } from '../design/app-store/store-frame.mjs';

const require = createRequire(import.meta.url);
const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const [DW, DH] = MACBOOK.desktop, BAR = MACBOOK.menuBar;   // the desktop, in points
const APP = 'Meridian';
const PANEL_GAP = 4;    // the menu bar panel's top, below the menu bar
const WIDGET_GAP = 24;  // between widgets on the desktop

// The four stories: headline and sub-line (one headline line, so the copy stays above the MacBook).
const COPY = {
  menuBar: ['The world, from your menu bar.', 'One click shows every city you follow.'],
  widgets: ['Time zones on your desktop.', 'Widgets in every size.'],
  workingHours: ['See who’s at work.', 'Working and off hours for every city.'],
  window: ['Plan across time zones.', 'Drag the hours to find a time for everyone.'],
};

// Meridian's menu bar item: SF Symbols' globe, drawn in white.
const GLOBE = `<svg viewBox="0 0 20 20" fill="none" stroke="currentColor" stroke-width="1.4"><circle cx="10" cy="10" r="8.2"/>
  <ellipse cx="10" cy="10" rx="3.6" ry="8.2"/><path d="M1.8 10h16.4M3 5.8h14M3 14.2h14"/></svg>`;

const log = (m) => console.log(`[mac-store-shots] ${m}`);
const fail = (m) => { console.error(`[mac-store-shots] ${m}`); process.exit(1); };

function playwright() {
  for (const p of ['playwright', path.join(process.cwd(), 'node_modules/playwright'), '/opt/node22/lib/node_modules/playwright']) {
    try { return require(p); } catch { /* next */ }
  }
  fail('Playwright not found (npm install playwright, then npx playwright install chromium)');
}

const [src, outDir] = process.argv.slice(2);
if (!src || !outDir) fail('usage: node scripts/mac-store-shots.mjs <selftest dir> <out dir>');

// ---------------------------------------------------------------------------------------------
// Inputs: each render with its size in points.

const read = (name) => {
  try {
    const png = fs.readFileSync(path.join(src, name));
    return png.toString('latin1', 1, 4) === 'PNG' ? png : null;
  } catch { return null; }
};
const size = (png) => [png.readUInt32BE(16), png.readUInt32BE(20)];

// Image checks, done in the browser: an all-one-colour render drew nothing; a high-resolution render must show the
// same thing as the 1x capture.
async function checker(browser) {
  const ctx = await browser.newContext();
  const page = await ctx.newPage();
  const stats = (big, small) => page.evaluate(async ([a, b]) => {
    const load = (u) => new Promise((ok, no) => { const i = new Image(); i.onload = () => ok(i); i.onerror = no; i.src = u; });
    const pixels = (img, w, h) => { const c = document.createElement('canvas'); c.width = w; c.height = h;
      const g = c.getContext('2d'); g.imageSmoothingQuality = 'high'; g.drawImage(img, 0, 0, w, h); return g.getImageData(0, 0, w, h).data; };
    const A = await load(a), w = A.naturalWidth, h = A.naturalHeight, pa = pixels(A, w, h);
    let n = 0, sum = 0, sq = 0;
    for (let i = 0; i < pa.length; i += 4) { const l = 0.299 * pa[i] + 0.587 * pa[i + 1] + 0.114 * pa[i + 2]; sum += l; sq += l * l; n++; }
    const out = { stddev: Math.sqrt(Math.max(0, sq / n - (sum / n) ** 2)) };
    if (b) {
      const B = await load(b), bw = B.naturalWidth, bh = B.naturalHeight, ra = pixels(A, bw, bh), rb = pixels(B, bw, bh);
      let d = 0;
      for (let i = 0; i < ra.length; i += 4) d += Math.abs(ra[i] - rb[i]) + Math.abs(ra[i + 1] - rb[i + 1]) + Math.abs(ra[i + 2] - rb[i + 2]);
      out.diff = d / (bw * bh * 3);
    }
    return out;
  }, [`data:image/png;base64,${big.toString('base64')}`, small ? `data:image/png;base64,${small.toString('base64')}` : null]);
  return { stats, close: () => ctx.close() };
}

async function pickPanel(check) {
  const small = read('menubar-panel.png'), big = read('store-panel.png');
  if (big) {
    const s = await check.stats(big, small);
    if (s.stddev >= 3 && (s.diff === undefined || s.diff < 24)) return { png: big, scale: 2, from: 'store-panel.png' };
    log('store-panel.png looks wrong (blank or not the panel); using menubar-panel.png');
  }
  if (small && (await check.stats(small)).stddev >= 3) return { png: small, scale: 1, from: 'menubar-panel.png (1x)' };
  return null;
}

async function pickWidget(check, name) {
  for (const [file, scale] of [[`store-widget-${name}.png`, 3], [`widget-${name}.png`, 2]]) {
    const png = read(file);
    if (png && (await check.stats(png)).stddev >= 3) return { png, scale, from: file };
  }
  return null;
}

async function pickWindow(check) {
  const png = read('store-window.png');
  return png && (await check.stats(png)).stddev >= 3 ? { png, scale: 2, from: 'store-window.png' } : null;
}

const pt = (r) => { const [w, h] = size(r.png); return { png: r.png, w: w / r.scale, h: h / r.scale }; };

// ---------------------------------------------------------------------------------------------
// The desktops, in points (1512 x 982, the menu bar 32 high, its middle 190 left to the notch).

// The panel hangs from the menu bar under Meridian's item: macOS keeps it on screen, so it sits against the right edge.
const hung = (panel) => ({ png: panel.png, x: DW - panel.w, y: BAR + PANEL_GAP, w: panel.w, h: panel.h, chrome: 'none' });
const widget = (w, x, y) => ({ png: w.png, x, y, w: w.w, h: w.h });

const scenes = {
  menuBar: ({ panel }) => ({ windows: [hung(panel)] }),
  // Two columns of the same width, centred on the desktop: the large widget on the left; on the right the medium
  // over the small, the small centred under it and the column centred against the large.
  widgets: ({ large, medium, small }) => {
    const first = large || medium, column = [large ? medium : null, small].filter(Boolean);
    const colW = Math.max(0, ...column.map((w) => w.w));
    const colH = column.reduce((a, w) => a + w.h, 0) + WIDGET_GAP * Math.max(0, column.length - 1);
    const groupW = first.w + (column.length ? WIDGET_GAP + colW : 0), groupH = Math.max(first.h, colH);
    const x0 = Math.round((DW - groupW) / 2), y0 = Math.round(BAR + (DH - BAR - groupH) / 2);
    const extras = [widget(first, x0, Math.round(y0 + (groupH - first.h) / 2))];
    const cx = x0 + first.w + WIDGET_GAP;
    let y = y0 + (groupH - colH) / 2;
    for (const w of column) { extras.push(widget(w, Math.round(cx + (colW - w.w) / 2), Math.round(y))); y += w.h + WIDGET_GAP; }
    return { extras };
  },
  // The whole window, every city with its Working / Off hours tag, and beside it a column of the large widget over
  // the medium (the tags again, with their icons): one group, centred on the desktop.
  workingHours: ({ window, large, medium }) => {
    const column = [large, medium].filter(Boolean), gap = 48;
    const colW = Math.max(...column.map((w) => w.w));
    const colH = column.reduce((a, w) => a + w.h, 0) + WIDGET_GAP * (column.length - 1);
    const groupW = window.w + gap + colW, groupH = Math.max(window.h, colH);
    const x0 = Math.round((DW - groupW) / 2), y0 = Math.round(BAR + (DH - BAR - groupH) / 2);
    const extras = [];
    let y = y0 + (groupH - colH) / 2;
    for (const w of column) { extras.push(widget(w, x0 + window.w + gap, Math.round(y))); y += w.h + WIDGET_GAP; }
    return {
      windows: [{ png: window.png, x: x0, y: Math.round(y0 + (groupH - window.h) / 2), w: window.w, h: window.h, chrome: 'none', lights: true }],
      extras,
    };
  },
  // The desktop window on its own (its own toolbar, so only the traffic lights over its header), centred.
  window: ({ window }) => ({ windows: [{ png: window.png, w: window.w, h: window.h, chrome: 'none', lights: true }] }),
};

// ---------------------------------------------------------------------------------------------

const b64 = (f) => fs.readFileSync(path.join(root, 'design/app-store', f)).toString('base64');
const FONTS = { fraunces: b64('fraunces.woff2'), instrument: b64('instrument-sans.woff2') };
const theme = THEMES.meridian;
const chromium = '/opt/pw-browsers/chromium';
const browser = await playwright().chromium.launch(fs.existsSync(chromium) ? { executablePath: chromium } : {});
try {
  const check = await checker(browser);
  const panelPick = await pickPanel(check);
  if (!panelPick) fail(`no panel render (store-panel.png or menubar-panel.png) in ${src}`);
  const [largeP, mediumP, smallP] = [await pickWidget(check, 'large'), await pickWidget(check, 'medium'), await pickWidget(check, 'small')];
  const windowP = await pickWindow(check);
  await check.close();
  log(`panel from ${panelPick.from}`);
  log(`widgets: ${[['large', largeP], ['medium', mediumP], ['small', smallP]].map(([n, w]) => `${n} ${w ? w.from : 'missing'}`).join(', ')}`);
  log(`window: ${windowP ? windowP.from : 'missing'}`);
  const r = { panel: pt(panelPick), large: largeP && pt(largeP), medium: mediumP && pt(mediumP), small: smallP && pt(smallP), window: windowP && pt(windowP) };


  const shots = [['01-menu-bar.png', 'menuBar']];
  if (r.large || r.medium) shots.push(['02-widgets.png', 'widgets']);
  if (r.large && r.window) shots.push(['03-working-hours.png', 'workingHours']);
  if (r.window) shots.push(['04-window.png', 'window']);
  // Never fewer than three: the panel again, for the stories left out.
  const extra = [['05-working-hours.png', 'workingHours'], ['06-plan.png', 'window']];
  while (shots.length < 3 && extra.length) {
    const [name, story] = extra.shift();
    if (!shots.some(([, s]) => s === story)) shots.push([name, story]);
  }
  const panelOnly = (story) => (story === 'workingHours' && !(r.large && r.window)) || (story === 'window' && !r.window);

  fs.mkdirSync(outDir, { recursive: true });
  for (const n of fs.readdirSync(outDir)) if (n.toLowerCase().endsWith('.png')) fs.rmSync(path.join(outDir, n));
  for (const [name, story] of shots.slice(0, 5)) {
    const scene = panelOnly(story) ? scenes.menuBar(r) : scenes[story](r);
    const screen = await desktop(browser, { theme, app: APP, fonts: FONTS, menuExtra: { text: '', icon: GLOBE }, ...scene });
    const [head, sub] = COPY[story];
    const out = await compose(browser, 'mac', { head, sub, device: 'macbook', png: screen, title: APP, file: name }, theme, FONTS);
    fs.writeFileSync(path.join(outDir, name), out);
    log(`wrote ${name} ${out.readUInt32BE(16)}x${out.readUInt32BE(20)} RGB: ${head} | ${sub}`);
  }
  log(`${Math.min(shots.length, 5)} screenshots in ${outDir}`);
} catch (e) {
  fail(e.message);
} finally {
  await browser.close();
}
