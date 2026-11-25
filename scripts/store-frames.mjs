// Meridian's App Store pictures in the Cowdrey family's template (scripts/store-frame.mjs, the one Two Degrees,
// Cowdrey.MD and Cowdrey.PDF share): Cowdrey One's Fraunces headline, an Instrument Sans sub-line, the same sizes
// and places on every app's pictures, and Meridian's steel-navy ground.
//
//   node scripts/store-frames.mjs iphone <captures dir> <out dir>
//       the simulator captures 01-main.png ... 05-add.png (1320 x 2868) -> the same names, 1320 x 2868 RGB
//   python3 scripts/mac-store-shots.py <selftest dir> <stages dir>
//   node scripts/store-frames.mjs mac <stages dir> <out dir>
//       the Mac stages (the app's panel, widgets and window, drawn on a clear ground) -> the same names, 2880 x 1800 RGB
//
// <out dir> may be the input dir itself: every input is read before anything is written. A file whose name has no
// words below gets the generic words. Needs Playwright's Chromium (npm i playwright; npx playwright install chromium).
import fs from 'node:fs';
import path from 'node:path';
import { createRequire } from 'node:module';
import { fileURLToPath } from 'node:url';
import { THEMES, compose } from './store-frame.mjs';

const require = createRequire(import.meta.url);
let playwright;
try { playwright = require('playwright'); } catch {
  playwright = require(path.join(require('node:child_process').execSync('npm root -g').toString().trim(), 'playwright'));
}

const HERE = path.dirname(fileURLToPath(import.meta.url));
const [kind, SRC, OUT] = process.argv.slice(2);
if (!['iphone', 'mac'].includes(kind) || !SRC || !OUT) {
  console.error('Usage: node scripts/store-frames.mjs iphone|mac <in dir> <out dir>'); process.exit(2);
}

// One idea a picture, keyed by the file name's stem after the number. Every iPhone headline is two lines, so the
// phone sits at the same place on all five.
const IPHONE = {
  main: { head: 'Every time zone\nat a glance.', sub: 'Your cities, photos and hours side by side.' },
  travel: { head: 'Find a time\nthat works.', sub: 'Drag the hours and every city follows.' },
  widgets: { head: 'Your cities on\nyour Home Screen.', sub: 'Widgets for Home Screen and Lock Screen.' },
  date: { head: 'Go to\nany moment.', sub: 'Pick a date and time, and see it everywhere.' },
  add: { head: 'Search\n34,000 cities.', sub: 'Add any place on Earth in a tap.' },
};
const MAC = {
  'menu-bar': { head: 'The world, from your menu bar.', sub: 'One click shows every city you follow.' },
  widgets: { head: 'Time zones on your desktop.', sub: 'Widgets in every size.' },
  'working-hours': { head: 'See who’s at work.', sub: 'Working and off hours for every city.' },
  window: { head: 'Plan across time zones.', sub: 'Drag the hours to find a time for everyone.' },
  plan: { head: 'Plan across time zones.', sub: 'Drag the hours to find a time for everyone.' },
};
const COPY = kind === 'iphone' ? IPHONE : MAC;
const GENERIC = kind === 'iphone' ? IPHONE.main : MAC['menu-bar'];

const b64 = (f) => fs.readFileSync(path.join(HERE, 'store-fonts', f)).toString('base64');
const FONTS = { fraunces: b64('fraunces.woff2'), instrument: b64('instrument-sans.woff2') };
const pngSize = (buf) => [buf.readUInt32BE(16), buf.readUInt32BE(20)];

const names = fs.readdirSync(SRC).filter((n) => n.toLowerCase().endsWith('.png')).sort();
if (!names.length) { console.error(`[store-frames] no PNGs in ${SRC}`); process.exit(1); }
const inputs = Object.fromEntries(names.map((n) => [n, fs.readFileSync(path.join(SRC, n))]));   // read all first
fs.mkdirSync(OUT, { recursive: true });

const browser = await playwright.chromium.launch();
try {
  for (const name of names) {
    const png = inputs[name];
    const stem = name.replace(/\.png$/i, '').replace(/^\d+-/, '');
    const words = COPY[stem] || GENERIC;
    const story = { ...words, png, file: name, title: 'Meridian' };
    if (kind === 'iphone') story.lines = 2;
    else story.bare = pngSize(png);
    const out = await compose(browser, kind, story, THEMES.meridian, FONTS);
    fs.writeFileSync(path.join(OUT, name), out);
    console.log(`[store-frames] wrote ${path.join(OUT, name)}: ${words.head.replace('\n', ' / ')}`);
  }
} finally {
  await browser.close();
}
