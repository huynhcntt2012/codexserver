import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import { createHash } from 'node:crypto';
const root = new URL('../public/art/boom/', import.meta.url);
test('web and PC use unchanged source PNGs with the expected five-character sheet layout', async () => {
  const manifest = JSON.parse(
    await readFile(new URL('PROVENANCE.json', root), 'utf8'),
  );
  for (const [name, hash] of Object.entries(manifest.files)) {
    const web = await readFile(new URL(name, root));
    const pc = await readFile(
      new URL('../../client/art/boom/' + name, import.meta.url),
    );
    assert.equal(createHash('sha256').update(web).digest('hex'), hash, name);
    assert.deepEqual(web, pc, name);
  }
  for (const name of ['bombo', 'mimi', 'zin', 'lala', 'kai']) {
    const png = await readFile(new URL('spritesheets/' + name + '.png', root));
    assert.equal(png.readUInt32BE(16), 128);
    assert.equal(png.readUInt32BE(20), 640);
  }
});
