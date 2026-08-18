// EReader icon generator — black background, white polygonal knight helmet,
// black "E" letter inside. Pure Node.js (zlib) PNG encoder, no dependencies.
// Usage: node tool/generate_icon.js
'use strict';

const fs = require('fs');
const path = require('path');
const zlib = require('zlib');

const ROOT = path.resolve(__dirname, '..');

// ── PNG encoding ────────────────────────────────────────────────────────────
const CRC_TABLE = (() => {
  const t = new Int32Array(256);
  for (let n = 0; n < 256; n++) {
    let c = n;
    for (let k = 0; k < 8; k++) c = c & 1 ? 0xedb88320 ^ (c >>> 1) : c >>> 1;
    t[n] = c;
  }
  return t;
})();

function crc32(buf) {
  let c = 0xffffffff;
  for (let i = 0; i < buf.length; i++) c = CRC_TABLE[(c ^ buf[i]) & 0xff] ^ (c >>> 8);
  return (c ^ 0xffffffff) >>> 0;
}

function chunk(type, data) {
  const len = Buffer.alloc(4);
  len.writeUInt32BE(data.length);
  const typeBuf = Buffer.from(type, 'ascii');
  const crc = Buffer.alloc(4);
  crc.writeUInt32BE(crc32(Buffer.concat([typeBuf, data])));
  return Buffer.concat([len, typeBuf, data, crc]);
}

function encodePng(width, height, rgba) {
  const stride = width * 4;
  const raw = Buffer.alloc((stride + 1) * height);
  for (let y = 0; y < height; y++) {
    raw[y * (stride + 1)] = 0; // filter: none
    rgba.copy(raw, y * (stride + 1) + 1, y * stride, (y + 1) * stride);
  }
  const ihdr = Buffer.alloc(13);
  ihdr.writeUInt32BE(width, 0);
  ihdr.writeUInt32BE(height, 4);
  ihdr[8] = 8; // bit depth
  ihdr[9] = 6; // color type RGBA
  ihdr[10] = 0; ihdr[11] = 0; ihdr[12] = 0;
  return Buffer.concat([
    Buffer.from([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a]),
    chunk('IHDR', ihdr),
    chunk('IDAT', zlib.deflateSync(raw, { level: 9 })),
    chunk('IEND', Buffer.alloc(0)),
  ]);
}

// ── Shape definition (normalized 0..1, y grows downwards) ───────────────────
// White polygonal knight helmet (shield-shaped dome + cheeks).
const HELMET = [
  [0.16, 0.14], [0.84, 0.14], [0.84, 0.36], [0.72, 0.52],
  [0.72, 0.80], [0.28, 0.80], [0.28, 0.52], [0.16, 0.36],
];

// Black "E" letter inside the helmet crown.
const E_RECTS = [
  [0.40, 0.18, 0.46, 0.32], // vertical bar
  [0.40, 0.18, 0.62, 0.22], // top bar
  [0.40, 0.24, 0.62, 0.26], // middle bar
  [0.40, 0.28, 0.62, 0.32], // bottom bar
];

// Black visor slits.
const SLITS = [
  [0.34, 0.40, 0.66, 0.44], // eye slit
  [0.48, 0.44, 0.52, 0.60], // nose slit
];

function pointInPoly(px, py, pts) {
  let inside = false;
  for (let i = 0, j = pts.length - 1; i < pts.length; j = i++) {
    const xi = pts[i][0], yi = pts[i][1];
    const xj = pts[j][0], yj = pts[j][1];
    if ((yi > py) !== (yj > py) &&
      px < ((xj - xi) * (py - yi)) / (yj - yi) + xi) {
      inside = !inside;
    }
  }
  return inside;
}

function inRect(px, py, r) {
  return px >= r[0] && px <= r[2] && py >= r[1] && py <= r[3];
}

/**
 * Render the icon.
 * @param size pixel size (square)
 * @param bg 'black' | 'transparent'
 */
function render(size, bg) {
  const buf = Buffer.alloc(size * size * 4);
  const BLACK = [0, 0, 0, 255];
  const WHITE = [255, 255, 255, 255];
  const TRANS = [0, 0, 0, 0];
  for (let y = 0; y < size; y++) {
    for (let x = 0; x < size; x++) {
      const nx = (x + 0.5) / size;
      const ny = (y + 0.5) / size;
      let color = bg === 'black' ? BLACK : TRANS;
      if (pointInPoly(nx, ny, HELMET)) {
        color = WHITE;
        for (const r of E_RECTS) if (inRect(nx, ny, r)) color = BLACK;
        for (const r of SLITS) if (inRect(nx, ny, r)) color = BLACK;
      }
      const o = (y * size + x) * 4;
      buf[o] = color[0]; buf[o + 1] = color[1];
      buf[o + 2] = color[2]; buf[o + 3] = color[3];
    }
  }
  return encodePng(size, size, buf);
}

function writePng(rel, size, bg) {
  const p = path.join(ROOT, rel);
  fs.mkdirSync(path.dirname(p), { recursive: true });
  fs.writeFileSync(p, render(size, bg));
  console.log('  ' + rel + ' (' + size + 'x' + size + ')');
}

console.log('Generating EReader icons...');

// Android legacy launcher icons (black background)
writePng('android/app/src/main/res/mipmap-mdpi/launcher_icon.png', 48, 'black');
writePng('android/app/src/main/res/mipmap-hdpi/launcher_icon.png', 72, 'black');
writePng('android/app/src/main/res/mipmap-xhdpi/launcher_icon.png', 96, 'black');
writePng('android/app/src/main/res/mipmap-xxhdpi/launcher_icon.png', 144, 'black');
writePng('android/app/src/main/res/mipmap-xxxhdpi/launcher_icon.png', 192, 'black');

// Android adaptive icon foregrounds (transparent background)
writePng('android/app/src/main/res/drawable-mdpi/ic_launcher_foreground.png', 108, 'transparent');
writePng('android/app/src/main/res/drawable-hdpi/ic_launcher_foreground.png', 162, 'transparent');
writePng('android/app/src/main/res/drawable-xhdpi/ic_launcher_foreground.png', 216, 'transparent');
writePng('android/app/src/main/res/drawable-xxhdpi/ic_launcher_foreground.png', 324, 'transparent');
writePng('android/app/src/main/res/drawable-xxxhdpi/ic_launcher_foreground.png', 432, 'transparent');

// iOS AppIcon set (black background, opaque)
const iosSizes = [
  ['Icon-App-20x20@2x.png', 40], ['Icon-App-20x20@3x.png', 60],
  ['Icon-App-29x29@2x.png', 58], ['Icon-App-29x29@3x.png', 87],
  ['Icon-App-38x38@2x.png', 76], ['Icon-App-38x38@3x.png', 114],
  ['Icon-App-40x40@2x.png', 80], ['Icon-App-40x40@3x.png', 120],
  ['Icon-App-60x60@2x.png', 120], ['Icon-App-60x60@3x.png', 180],
  ['Icon-App-64x64@2x.png', 128], ['Icon-App-64x64@3x.png', 192],
  ['Icon-App-68x68@2x.png', 136], ['Icon-App-76x76@2x.png', 152],
  ['Icon-App-83.5x83.5@2x.png', 167], ['Icon-App-1024x1024@1x.png', 1024],
];
const iosDir = 'ios/Runner/Assets.xcassets/AppIcon.appiconset';
for (const [name, size] of iosSizes) {
  writePng(iosDir + '/' + name, size, 'black');
  writePng(iosDir + '/Icon-App-Dark-' + name.replace('Icon-App-', ''), size, 'black');
  writePng(iosDir + '/Icon-App-Tinted-' + name.replace('Icon-App-', ''), size, 'black');
}

// Source images for flutter_launcher_icons
writePng('assets/icons/icon_opaque.png', 1024, 'black');
writePng('assets/icons/icon_foreground.png', 1024, 'transparent');

console.log('Done.');
