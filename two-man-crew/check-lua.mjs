// Parse every .lua file under the mod with luaparse in Lua 5.1 mode (Kahlua's dialect).
// Usage: node check-lua.mjs [rootDir]
// Exits 1 if any file fails to parse, so it can gate a build.
import { readdirSync, statSync, readFileSync } from 'node:fs';
import { join, relative } from 'node:path';
import { createRequire } from 'node:module';

const root = process.argv[2] || 'Contents';
const require = createRequire(import.meta.url);

let luaparse;
try {
  luaparse = require('luaparse');
} catch {
  console.error('luaparse not resolvable - run: npx --yes -p luaparse node check-lua.mjs');
  process.exit(2);
}

function walk(dir, out = []) {
  for (const name of readdirSync(dir)) {
    const p = join(dir, name);
    if (statSync(p).isDirectory()) walk(p, out);
    else if (name.endsWith('.lua')) out.push(p);
  }
  return out;
}

const files = walk(root);
if (files.length === 0) {
  console.log('no .lua files found under ' + root);
  process.exit(0);
}

let bad = 0;
for (const f of files) {
  try {
    luaparse.parse(readFileSync(f, 'utf8'), { luaVersion: '5.1' });
    console.log('ok   ' + relative(root, f));
  } catch (e) {
    bad++;
    console.log('FAIL ' + relative(root, f) + '  ' + e.message);
  }
}

console.log(`\n${files.length - bad}/${files.length} parsed`);
process.exit(bad ? 1 : 0);
