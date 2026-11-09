// Create editable OpenRaster sources from the shipped achievement icons.
// The outer frame and central artwork remain separate lossless layers.
import fs from 'node:fs/promises';
import path from 'node:path';
import sharp from '/Users/frozen/.cache/codex-runtimes/codex-primary-runtime/dependencies/node/node_modules/sharp/dist/index.mjs';
import JSZip from '/Users/frozen/.cache/codex-runtimes/codex-primary-runtime/dependencies/node/node_modules/jszip/lib/index.js';

const root = path.resolve(import.meta.dirname, '..');
const catalog = JSON.parse(await fs.readFile(path.join(root, 'data/catalog/achievements.json'), 'utf8'));
const sourceDir = path.join(root, 'assets/source/achievements');
const iconDir = path.join(root, 'assets/ui/achievements');

for (const entry of catalog.items) {
  for (const state of ['locked', 'unlocked']) {
    const stem = `${entry.id.toLowerCase()}_${state}`;
    const merged = await fs.readFile(path.join(iconDir, `${stem}.png`));
    const { data, info } = await sharp(merged).ensureAlpha().raw().toBuffer({ resolveWithObject: true });
    const border = Buffer.from(data);
    const art = Buffer.from(data);
    // The center cut is aligned within the badge's wood/metal edge. Both
    // layers together reproduce the shipped PNG pixel for pixel.
    const inset = Math.round(info.width * 0.15);
    for (let y = 0; y < info.height; y++) {
      for (let x = 0; x < info.width; x++) {
        const i = (y * info.width + x) * 4;
        const inside = x >= inset && x < info.width - inset && y >= inset && y < info.height - inset;
        if (inside) border[i + 3] = 0;
        else art[i + 3] = 0;
      }
    }
    const png = async (pixels) => sharp(pixels, { raw: { width: info.width, height: info.height, channels: 4 } }).png().toBuffer();
    const zip = new JSZip();
    zip.file('mimetype', 'image/openraster', { compression: 'STORE' });
    zip.file('mergedimage.png', merged);
    zip.file('data/frame.png', await png(border));
    zip.file('data/art.png', await png(art));
    zip.file('stack.xml', `<?xml version="1.0" encoding="UTF-8"?>\n<image version="0.0.3" w="${info.width}" h="${info.height}" name="${stem}"><stack><layer name="中央图案" src="data/art.png" opacity="1.0" visibility="visible" composite-op="svg:src-over" x="0" y="0"/><layer name="徽章外框" src="data/frame.png" opacity="1.0" visibility="visible" composite-op="svg:src-over" x="0" y="0"/></stack></image>`);
    await fs.writeFile(path.join(sourceDir, `${stem}.ora`), await zip.generateAsync({ type: 'nodebuffer', compression: 'DEFLATE' }));
  }
}
console.log(`ACHIEVEMENT_SOURCES_OK ${catalog.items.length * 2}`);
