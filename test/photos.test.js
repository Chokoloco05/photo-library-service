const { test } = require('node:test');
const assert = require('node:assert/strict');
const sharp = require('sharp');
const { fixture } = require('./fixtures');
const { analyze, distance, duplicates, similar, MAX_BYTES } = require('../photos');

test('byte-identical copies have the same digest and reclaimable size keeps one original', async () => {
  const input = await fixture();
  const first = await analyze(input, 'voyage.png');
  const second = await analyze(input, 'copie.png');
  assert.notEqual(first.id, second.id);
  assert.equal(first.sha256, second.sha256);
  assert.equal(first.width, 160);
  assert.equal(first.mime_type, 'image/png');
  assert.equal((await sharp(first.thumbnail).metadata()).format, 'webp');
  assert.equal(duplicates([first, second])[0].reclaimable_bytes, input.length);
  assert.deepEqual(similar([first, second]), []);
});
test('recompressed images are candidates rather than byte-identical duplicates', async () => {
  const original = await analyze(await fixture(), 'original.png');
  const recompressed = await analyze(await fixture('jpeg'), 'version.jpg');
  assert.notEqual(original.sha256, recompressed.sha256);
  assert.deepEqual(duplicates([original, recompressed]), []);
  assert.equal(similar([original, recompressed]).length, 1);
  assert.ok(distance(original.visual_hash, recompressed.visual_hash) <= 6);
  assert.equal(distance('ffffffffffffffff', '0000000000000000'), 64);
});
test('rejects corrupt, unsupported and oversized uploads before persistence', async () => {
  await assert.rejects(analyze(Buffer.from('not an image'), 'x.png'), { status: 415 });
  await assert.rejects(analyze(Buffer.from('<svg xmlns="http://www.w3.org/2000/svg" width="1" height="1"/>'), 'x.svg'), { status: 415 });
  await assert.rejects(analyze(Buffer.alloc(MAX_BYTES + 1), 'large.png'), { status: 413 });
  await assert.rejects(analyze(Buffer.alloc(0), 'empty.png'), { status: 400 });
});
test('honours EXIF orientation and normalizes filenames', async () => {
  const input = await sharp(await fixture()).jpeg().withMetadata({ orientation: 6 }).toBuffer();
  const photo = await analyze(input, '../vacances\u0000.jpg');
  assert.equal(photo.width, 120);
  assert.equal(photo.height, 160);
  assert.ok(!photo.filename.includes('/'));
  assert.ok(!photo.filename.includes('\u0000'));
});
