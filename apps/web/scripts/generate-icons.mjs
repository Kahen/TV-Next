// Rasterize the app's simple blue/play brand for browser PWA and Apple touch icons.
// No native/image package is needed in clean Node-only Docker builds.
import { deflateSync } from "node:zlib";
import { writeFileSync } from "node:fs";

function crc32(data) {
  let crc = 0xffffffff;
  for (const value of data) {
    crc ^= value;
    for (let bit = 0; bit < 8; bit++) crc = (crc >>> 1) ^ ((crc & 1) ? 0xedb88320 : 0);
  }
  return (crc ^ 0xffffffff) >>> 0;
}
function chunk(name, data) {
  const type = Buffer.from(name);
  const length = Buffer.alloc(4); length.writeUInt32BE(data.length);
  const crc = Buffer.alloc(4); crc.writeUInt32BE(crc32(Buffer.concat([type, data])));
  return Buffer.concat([length, type, data, crc]);
}
for (const size of [180, 192, 512]) {
  const rows = Buffer.alloc(size * (1 + size * 3));
  for (let y = 0; y < size; y++) {
    for (let x = 0; x < size; x++) {
      const u = (x + 0.5) / size, v = (y + 0.5) / size;
      // Play glyph fits inside the maskable icon's central safe circle.
      const white = u >= 0.39 && u <= 0.72 && Math.abs(v - 0.5) <= (0.72 - u) * 0.7;
      const offset = y * (1 + size * 3) + 1 + x * 3;
      rows.set(white ? [255, 255, 255] : [79, 119, 238], offset);
    }
  }
  const header = Buffer.alloc(13);
  header.writeUInt32BE(size, 0); header.writeUInt32BE(size, 4); header[8] = 8; header[9] = 2;
  writeFileSync(new URL(`../public/icon-${size}.png`, import.meta.url), Buffer.concat([
    Buffer.from([137, 80, 78, 71, 13, 10, 26, 10]), chunk("IHDR", header),
    chunk("IDAT", deflateSync(rows)), chunk("IEND", Buffer.alloc(0))
  ]));
}
