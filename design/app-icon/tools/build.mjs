// Builds the BubblePaw Desktop app-icon candidates from the library's bubblepaw.svg.
// Usage (from design/app-icon): PLAYWRIGHT=<path to playwright module> node tools/build.mjs
// Only recomposes the existing mark and kit primitives; kit colours only.
import fs from 'node:fs';
import { createRequire } from 'node:module';
const require = createRequire(import.meta.url);
const { chromium } = require(process.env.PLAYWRIGHT || 'C:/Users/Admin/Documents/Projects/Pawth/node_modules/playwright');

const K = { milk: '#FFFAF1', ivory: '#F2EBDD', charcoal: '#282A2F', apricot: '#DE945F', facet: '#E4DCCD' };
const SAFE_R = 387; // px of 1280, inside the 391.1 safe radius (same target as the library's FIT table)
const src = fs.readFileSync('source/bubblepaw.svg', 'utf8');
const fitM = src.match(/<g id="safe-fit"[^>]*>\n([\s\S]*)<\/g>\n<\/svg>/);
const S0 = 0.8676;
// Unfitted art: stroke widths back to the rendered tiers (41.48 / 37.93).
let art = fitM[1].replace(/stroke-width="([\d.]+)"/g, (m, w) => `stroke-width="TIER:${(Math.round(w * S0 * 100) / 100).toFixed(2)}"`);
art = art.replace(/<g id="burst"[\s\S]*?<\/g>\n/, ''); // sparkles dropped: they cost size and vanish at 24 px

const finish = (a, s) => a.replace(/stroke-width="TIER:([\d.]+)"/g, (m, t) => `stroke-width="${Math.round((parseFloat(t) / s) * 100) / 100}"`);

// ---- candidate additions (art coordinates of bubblepaw.svg) ----
const B_WINDOW = `<g id="window" data-name="Window badge" data-part="object/window">
<rect id="window-body" data-name="Milk window" x="900" y="285" width="150" height="112" rx="14" fill="${K.milk}" stroke="${K.charcoal}" stroke-width="TIER:37.93" stroke-linejoin="round"/>
<path id="window-bar" data-name="Apricot title bar" d="M914 299H1036V327H914Z" fill="${K.apricot}"/>
<path id="window-rule" data-name="Title bar rule" d="M900 330H1050" fill="none" stroke="${K.charcoal}" stroke-width="TIER:37.93" stroke-linecap="round" stroke-linejoin="round"/>
</g>
`;
const C_DOT = `<g id="host-dot" data-name="Host running dot" data-part="status/dot">
<circle id="dot" data-name="Apricot running dot" cx="985" cy="350" r="62" fill="${K.apricot}" stroke="${K.charcoal}" stroke-width="TIER:41.48"/>
</g>
`;

const CANDS = [
  { id: 'a-folder-cat', name: 'A: Folder cat, desktop-tuned', desc: 'The folder cat without the sparkles, refit to fill the safe circle so the face is larger at 16-48 px.', extra: '' },
  { id: 'b-window-cat', name: 'B: Folder cat with window', desc: 'The folder cat with a small milk window (apricot title bar) beside the ear: a desktop app.', extra: B_WINDOW },
  { id: 'c-host-dot-cat', name: 'C: Folder cat with host dot', desc: 'The folder cat with an apricot dot beside the ear: the host is running.', extra: C_DOT },
];

// ---- tray glyphs: one colour; shapes cut out of the head with gap rings ----
const HEAD = 'M426.66 434.06L520.53 331.66H546.13L640 425.53L733.87 331.66H759.47L853.34 434.06V621.8L768 758.34H494.93L426.66 690.07Z';
const FOLDER = 'M320 760H960L922 940H358Z';
const EYE_L = 'M538 456Q554.56 531.44 630 548Q554.56 564.56 538 640Q521.44 564.56 446 548Q521.44 531.44 538 456Z';
const EYE_R = 'M742 456Q758.56 531.44 834 548Q758.56 564.56 742 640Q725.44 564.56 650 548Q725.44 531.44 742 456Z';
const GAP = 44;
const trayExtra = {
  'a-folder-cat': { box: [300, 310, 680, 650], body: '' },
  'b-window-cat': { box: [300, 260, 780, 700],
    body: `<rect x="900" y="285" width="150" height="112" rx="14" fill="#000" stroke="#000" stroke-width="${GAP * 2}" stroke-linejoin="round"/><rect x="900" y="285" width="150" height="112" rx="14" fill="#fff" stroke="#fff" stroke-width="12" stroke-linejoin="round"/><path d="M880 335H1070" stroke="#000" stroke-width="22"/>` },
  'c-host-dot-cat': { box: [300, 270, 740, 690],
    body: `<circle cx="985" cy="350" r="62" fill="#000" stroke="#000" stroke-width="${GAP * 2}"/><circle cx="985" cy="350" r="68" fill="#fff"/>` },
};
function tray(id, color) {
  const t = trayExtra[id]; const [x, y, w, h] = t.box; const side = Math.max(w, h);
  const vx = x - (side - w) / 2, vy = y - (side - h) / 2;
  return `<svg xmlns="http://www.w3.org/2000/svg" viewBox="${vx} ${vy} ${side} ${side}">
<title>BubblePaw tray glyph (${id})</title>
<defs><mask id="m" maskUnits="userSpaceOnUse" x="${vx}" y="${vy}" width="${side}" height="${side}">
<rect x="${vx}" y="${vy}" width="${side}" height="${side}" fill="#000"/>
<path d="${HEAD}" fill="#fff" stroke="#fff" stroke-width="30" stroke-linejoin="round"/>
<path d="${FOLDER}" fill="#000" stroke="#000" stroke-width="${GAP * 2}" stroke-linejoin="round"/>
<path d="${FOLDER}" fill="#fff" stroke="#fff" stroke-width="30" stroke-linejoin="round"/>
<path d="${EYE_L}" fill="#000"/><path d="${EYE_R}" fill="#000"/>
${t.body}
</mask></defs>
<rect x="${vx}" y="${vy}" width="${side}" height="${side}" fill="${color}" mask="url(#m)"/>
</svg>
`;
}

const doc = (c, s, cx, cy) => `<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 1280 1280">
<title>BubblePaw Desktop icon ${c.name}</title>
<desc>${c.desc}</desc>
<metadata id="pawth-style" type="application/json">{"version":1,"kit":"kits/bubblebuffer.kit.svg"}</metadata>
<metadata id="pawth-icon" type="application/json">{"version":1,"template":"android-adaptive"}</metadata>
<g id="background" data-name="Background" data-icon-layer="background">
<rect id="tile" data-name="Ivory tile" x="0" y="0" width="1280" height="1280" fill="${K.ivory}"/>
</g>
<g id="safe-fit" data-name="Safe-circle fit" transform="translate(640 640) scale(${s}) translate(${-cx} ${-cy})">
${finish(art + c.extra, s)}</g>
</svg>
`;

// ---- ICO writer (PNG-compressed frames) ----
function ico(frames) {
  const n = frames.length, head = Buffer.alloc(6 + 16 * n);
  head.writeUInt16LE(0, 0); head.writeUInt16LE(1, 2); head.writeUInt16LE(n, 4);
  let off = head.length;
  frames.forEach((f, i) => {
    const o = 6 + 16 * i, b = f.size >= 256 ? 0 : f.size;
    head[o] = b; head[o + 1] = b;
    head.writeUInt16LE(1, o + 4); head.writeUInt16LE(32, o + 6);
    head.writeUInt32LE(f.png.length, o + 8); head.writeUInt32LE(off, o + 12); off += f.png.length;
  });
  return Buffer.concat([head, ...frames.map(f => f.png)]);
}

const browser = await chromium.launch();
const page = await browser.newPage();
async function raster(svg, size) {
  await page.setViewportSize({ width: size, height: size });
  await page.setContent(`<html><body style="margin:0;background:transparent"><img id=i style="display:block;width:${size}px;height:${size}px" src="data:image/svg+xml;base64,${Buffer.from(svg).toString('base64')}"></body></html>`);
  await page.evaluate(() => document.getElementById('i').decode());
  return page.screenshot({ omitBackground: true, clip: { x: 0, y: 0, width: size, height: size } });
}
// Enclosing circle of the painted pixels (Badoiu-Clarkson), in 1280 px.
async function measure(svg) {
  return page.evaluate(async (src) => {
    const N = 640, img = new Image(); img.src = 'data:image/svg+xml;charset=utf-8,' + encodeURIComponent(src); await img.decode();
    const c = document.createElement('canvas'); c.width = c.height = N; const g = c.getContext('2d'); g.drawImage(img, 0, 0, N, N);
    const a = g.getImageData(0, 0, N, N).data, pts = [];
    for (let y = 0; y < N; y++) { let l = -1, r = -1; for (let x = 0; x < N; x++) if (a[(y * N + x) * 4 + 3] > 8) { if (l < 0) l = x; r = x; } if (l >= 0) pts.push([l * 2, y * 2], [r * 2 + 2, y * 2 + 2]); }
    let cx = pts[0][0], cy = pts[0][1];
    for (let i = 1; i <= 3000; i++) { let b = pts[0], d = -1; for (const p of pts) { const q = Math.hypot(p[0] - cx, p[1] - cy); if (q > d) { d = q; b = p; } } cx += (b[0] - cx) / (i + 1); cy += (b[1] - cy) / (i + 1); }
    let R = 0; for (const p of pts) R = Math.max(R, Math.hypot(p[0] - 640, p[1] - 640));
    let Rc = 0; for (const p of pts) Rc = Math.max(Rc, Math.hypot(p[0] - cx, p[1] - cy));
    return { cx, cy, R, Rc };
  }, svg);
}
const noTile = (s) => s.replace(/<rect id="tile"[^>]*\/>/, '');

const SIZES = [16, 20, 24, 32, 48, 64, 128, 256, 512, 1024], ICO = [16, 20, 24, 32, 48, 64, 256];
const report = {};
for (const c of CANDS) {
  let s = S0, cx = 636, cy = 627;
  for (let i = 0; i < 4; i++) {
    const m = await measure(noTile(doc(c, s, cx, cy)));
    cx = cx + (m.cx - 640) / s; cy = cy + (m.cy - 640) / s; s = Math.round(s * SAFE_R / m.Rc * 10000) / 10000;
  }
  cx = Math.round(cx * 10) / 10; cy = Math.round(cy * 10) / 10;
  const svg = doc(c, s, cx, cy), m = await measure(noTile(svg));
  report[c.id] = { s, cx, cy, maxR: +m.R.toFixed(1) };
  const dir = c.id; fs.mkdirSync(`${dir}/png`, { recursive: true }); fs.mkdirSync(`${dir}/tray`, { recursive: true });
  fs.writeFileSync(`${dir}/icon.svg`, svg);
  const pngs = {};
  for (const n of SIZES) { pngs[n] = await raster(svg, n); fs.writeFileSync(`${dir}/png/icon-${n}.png`, pngs[n]); }
  fs.writeFileSync(`${dir}/icon.ico`, ico(ICO.map(n => ({ size: n, png: pngs[n] }))));
  for (const [theme, color] of [['light', K.charcoal], ['dark', K.milk]]) {
    const t = tray(c.id, color); fs.writeFileSync(`${dir}/tray/tray-${theme}.svg`, t);
    const tp = {};
    for (const n of [16, 20, 24, 32]) { tp[n] = await raster(t, n); fs.writeFileSync(`${dir}/tray/tray-${theme}-${n}.png`, tp[n]); }
    fs.writeFileSync(`${dir}/tray/tray-${theme}.ico`, ico([16, 20, 24, 32].map(n => ({ size: n, png: tp[n] }))));
  }
}
await browser.close();
console.log(JSON.stringify(report, null, 1));
