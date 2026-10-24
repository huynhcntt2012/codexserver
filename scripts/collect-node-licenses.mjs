// Copy verbatim dependency license/copyright files into a distributable notice bundle.
import { readFile, readdir, mkdir, writeFile } from 'node:fs/promises';
import path from 'node:path';

const lock = JSON.parse(await readFile('package-lock.json', 'utf8'));
const output = process.argv[2] ?? 'build/licenses/node';
await mkdir(output, { recursive: true });
const inventory = [];
for (const [location, entry] of Object.entries(lock.packages)) {
  if (!location.includes('node_modules/') || entry.link) continue;
  let manifest;
  try {
    manifest = JSON.parse(
      await readFile(path.join(location, 'package.json'), 'utf8'),
    );
  } catch (error) {
    if (entry.optional && error.code === 'ENOENT') continue;
    throw error;
  }
  const name = `${manifest.name}@${manifest.version}`;
  const notices = (await readdir(location)).filter((f) =>
    /^(licen[sc]e|copying|notice|copyright)([._-]|$)/i.test(f),
  );
  // Some published packages carry their copyright/license in README only.
  if (notices.length === 0) {
    notices.push(
      ...(await readdir(location)).filter((f) => /^readme([._-]|$)/i.test(f)),
    );
  }
  const record = {
    name,
    license: manifest.license ?? entry.license ?? 'REVIEW REQUIRED',
    notices,
  };
  inventory.push(record);
  const directory = path.join(output, name.replaceAll('/', '__'));
  await mkdir(directory, { recursive: true });
  await writeFile(
    path.join(directory, 'metadata.json'),
    JSON.stringify(record, null, 2),
  );
  for (const file of notices) {
    try {
      await writeFile(
        path.join(directory, file),
        await readFile(path.join(location, file)),
      );
    } catch (error) {
      if (error.code !== 'EISDIR') throw error;
    }
  }
}
await writeFile(
  path.join(output, 'inventory.json'),
  JSON.stringify(inventory, null, 2),
);
console.info(
  `Collected notices for ${inventory.length} Node packages in ${output}`,
);
