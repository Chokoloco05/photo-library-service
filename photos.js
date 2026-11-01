const sharp = require('sharp');
const { createHash, randomUUID } = require('node:crypto');
sharp.cache(false);
sharp.concurrency(1);
const MAX_BYTES = 10 * 1024 * 1024;
const formats = { jpeg: 'image/jpeg', png: 'image/png', webp: 'image/webp' };

async function analyze(buffer, name) {
  if (!Buffer.isBuffer(buffer) || !buffer.length) throw Object.assign(new Error('Choisis une image JPEG, PNG ou WebP.'), { status: 400 });
  if (buffer.length > MAX_BYTES) throw Object.assign(new Error('La limite est de 10 Mo par photo.'), { status: 413 });
  let meta, thumbnail, pixels;
  try {
    const options = { limitInputPixels: 24000000, failOn: 'error' };
    meta = await sharp(buffer, options).metadata();
    if (!formats[meta.format] || (meta.pages || 1) !== 1) throw new Error('Unsupported format');
    // Decode before storing: a plausible file header alone is not enough.
    thumbnail = await sharp(buffer, options).rotate().resize(480, 360, { fit: 'inside', withoutEnlargement: true }).webp({ quality: 78 }).toBuffer();
    pixels = await sharp(buffer, options).rotate().flatten({ background: '#ffffff' }).resize(9, 8, { fit: 'fill' }).greyscale().raw().toBuffer();
  } catch {
    throw Object.assign(new Error('Image invalide. Utilise un JPEG, PNG ou WebP non animé de 24 mégapixels maximum.'), { status: 415 });
  }
  let hash = 0n;
  for (let y = 0; y < 8; y++) for (let x = 0; x < 8; x++) hash = (hash << 1n) | BigInt(pixels[y * 9 + x] > pixels[y * 9 + x + 1]);
  const filename = String(name || 'photo').normalize('NFC').replace(/[\\/\x00-\x1f\x7f]/g, '_').slice(0, 200) || 'photo';
  const rotated = [5, 6, 7, 8].includes(meta.orientation);
  return {
    id: randomUUID(), filename, title: filename.replace(/\.[^.]+$/, '') || filename,
    mime_type: formats[meta.format], size_bytes: buffer.length,
    width: rotated ? meta.height : meta.width, height: rotated ? meta.width : meta.height,
    sha256: createHash('sha256').update(buffer).digest('hex'),
    visual_hash: hash.toString(16).padStart(16, '0'), original: buffer, thumbnail,
  };
}

function distance(left, right) {
  let value = BigInt(`0x${left}`) ^ BigInt(`0x${right}`), bits = 0;
  while (value) { bits++; value &= value - 1n; }
  return bits;
}

function duplicates(photos) {
  const byHash = new Map();
  for (const photo of photos) {
    const group = byHash.get(photo.sha256) || [];
    group.push(photo); byHash.set(photo.sha256, group);
  }
  return [...byHash.values()].filter(group => group.length > 1).map(group => ({
    photos: group, reclaimable_bytes: group.reduce((sum, photo) => sum + photo.size_bytes, 0) - Math.max(...group.map(photo => photo.size_bytes)),
  }));
}

// Candidates only: dHash can confuse unrelated images, especially flat colours.
function similar(photos, threshold = 6) {
  const pairs = [];
  for (let i = 0; i < photos.length; i++) for (let j = i + 1; j < photos.length; j++) {
    if (photos[i].sha256 === photos[j].sha256) continue;
    const d = distance(photos[i].visual_hash, photos[j].visual_hash);
    const ratioA = photos[i].width / photos[i].height, ratioB = photos[j].width / photos[j].height;
    if (d <= threshold && Math.abs(Math.log(ratioA / ratioB)) < 0.15) pairs.push({ left: photos[i], right: photos[j], distance: d });
  }
  return pairs.sort((a, b) => a.distance - b.distance).slice(0, 100);
}
module.exports = { analyze, distance, duplicates, similar, MAX_BYTES };
