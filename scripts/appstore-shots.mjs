#!/usr/bin/env node
// iPhone App Store screenshots for Meridian, on the Cowdrey family standard (bradleycowdrey/cowdrey-one,
// design/app-store/README.md): composed from the simulator captures with the family template,
// design/app-store/store-frame.mjs (a word-for-word copy of the master; never edit it here), in Meridian's steel blue.
//
//   node scripts/appstore-shots.mjs <captures dir> <out dir>
//
// Reads 01-main.png ... 05-add.png (6.9-inch simulator captures in dark mode, 1320 x 2868) and writes the same file
// names into <out dir>: each exactly 1320 x 2868 RGB (no alpha), the 6.9-inch App Store size, with a Fraunces
// headline and an Instrument Sans sub-line over the steel-blue ground and the capture in the template's iPhone.
// <out dir> may be the captures dir itself: every capture is read before anything is written.
// A capture of another size, or a screen with no copy below, stops the run (nothing is stretched or made up).
//
// Needs Node 20.15 or later and Playwright with Chromium: playwright is found on NODE_PATH, in ./node_modules or at
// /opt/node22/lib/node_modules; Chromium is Playwright's own, or /opt/pw-browsers/chromium when that exists.
import fs from 'node:fs';
import path from 'node:path';
import { createRequire } from 'node:module';
import { fileURLToPath } from 'node:url';
import { compose, THEMES } from '../design/app-store/store-frame.mjs';

const require = createRequire(import.meta.url);
const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const W = 1320, H = 2868;

// Headline / sub-line for each capture (the file name's stem after the number). Every headline is two lines, so
// the set lines up; "\n" is the line break.
const COPY = {
  main: ['Every time zone\nat a glance.', 'Your cities, photos and hours side by side.'],
  travel: ['Find a time\nthat works.', 'Drag the hours and every city follows.'],
  widgets: ['Your cities on\nyour Home Screen.', 'Widgets for Home Screen and Lock Screen.'],
  date: ['Go to\nany moment.', 'Pick a date and time, and see it everywhere.'],
  add: ['Search\n34,000 cities.', 'Add any place on Earth in a tap.'],
};
const LINES = 2;

const log = (m) => console.log(`[appstore-shots] ${m}`);
const fail = (m) => { console.error(`[appstore-shots] ${m}`); process.exit(1); };

function playwright() {
  for (const p of ['playwright', path.join(process.cwd(), 'node_modules/playwright'), '/opt/node22/lib/node_modules/playwright']) {
    try { return require(p); } catch { /* next */ }
  }
  fail('Playwright not found (npm install playwright, then npx playwright install chromium)');
}

const [capturesDir, outDir] = process.argv.slice(2);
if (!capturesDir || !outDir) fail('usage: node scripts/appstore-shots.mjs <captures dir> <out dir>');
const names = fs.readdirSync(capturesDir).filter((n) => n.toLowerCase().endsWith('.png')).sort();
if (!names.length) fail(`no PNG captures in ${capturesDir}`);

// Read every capture first, and check them all before anything is written.
const shots = names.map((name) => {
  const png = fs.readFileSync(path.join(capturesDir, name));
  const w = png.readUInt32BE(16), h = png.readUInt32BE(20);
  if (png.toString('latin1', 1, 4) !== 'PNG' || w !== W || h !== H) fail(`${name} is ${w}x${h}, not a ${W}x${H} capture`);
  const stem = path.basename(name, path.extname(name)).replace(/^\d+-/, '');
  if (!COPY[stem]) fail(`${name}: no headline for "${stem}" (add it to COPY)`);
  const [head, sub] = COPY[stem];
  return { name, png, head, sub };
});

const b64 = (f) => fs.readFileSync(path.join(root, 'design/app-store', f)).toString('base64');
const FONTS = { fraunces: b64('fraunces.woff2'), instrument: b64('instrument-sans.woff2') };
const chromium = '/opt/pw-browsers/chromium';
const browser = await playwright().chromium.launch(fs.existsSync(chromium) ? { executablePath: chromium } : {});
try {
  fs.mkdirSync(outDir, { recursive: true });
  for (const s of shots) {
    const out = await compose(browser, 'iphone', { head: s.head, sub: s.sub, png: s.png, title: 'Meridian', lines: LINES, file: s.name },
      THEMES.meridian, FONTS);
    fs.writeFileSync(path.join(outDir, s.name), out);
    log(`wrote ${s.name} ${out.readUInt32BE(16)}x${out.readUInt32BE(20)} RGB: ${s.head.replace('\n', ' / ')} | ${s.sub}`);
  }
} catch (e) {
  fail(e.message);
} finally {
  await browser.close();
}
