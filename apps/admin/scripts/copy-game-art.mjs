// Copies the game's own item, bomb, character and mascot art into public/game so
// the static admin build can show catalog icons. Source: apps/practice/assets.
import { cpSync, mkdirSync, rmSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';

const root = dirname(dirname(fileURLToPath(import.meta.url)));
const source = join(root, '..', 'practice', 'assets');
const target = join(root, 'public', 'game');
const png = (path) => path.endsWith('.png') || !path.includes('.');

rmSync(target, { recursive: true, force: true });
for (const folder of ['items', 'bombs', 'characters/portraits']) {
  mkdirSync(join(target, folder), { recursive: true });
  cpSync(join(source, folder), join(target, folder), {
    recursive: true,
    filter: png,
  });
}
mkdirSync(join(target, 'ui', 'launch'), { recursive: true });
for (const file of ['mascot_pip.png', 'mascot_nop.png', 'logo_bupbup.png']) {
  cpSync(
    join(source, 'ui', 'launch', file),
    join(target, 'ui', 'launch', file),
  );
}
console.log('Copied game art to public/game');
