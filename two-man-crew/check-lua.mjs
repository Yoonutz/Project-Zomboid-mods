// Parse every .lua file under the mod with luaparse in Lua 5.1 mode (Kahlua's dialect).
// Usage: node check-lua.mjs [rootDir]
// Exits 1 if any file fails to parse, so it can gate a build.
import { readdirSync, statSync, readFileSync, existsSync } from 'node:fs';
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

// PZ loads media/lua/server/ on multiplayer CLIENTS too - the folder name is a
// convention, not an engine boundary. A server file without this guard runs on a
// client, where the files that DID guard have bailed, so its calls into them hit
// nil. That shipped once as a dead Claim button and was fixed in 0.1.8; it came
// back in five files by 0.10.5, because nothing checked.
// See .claude/memory/server-files-need-isclient-guard.md
// Comments are stripped before looking. The guard ships with a comment above it
// explaining itself, and that comment says "isClient()" - so a plain text search
// passes on a file whose guard has been deleted but whose comment survives.
// Caught by deleting a real guard and watching this still report ok.
const unguarded = files
  .filter((f) => /[\\/]server[\\/]/.test(f))
  .filter((f) => {
    const code = readFileSync(f, 'utf8').replace(/--\[\[[\s\S]*?\]\]|--[^\n]*/g, '');
    return !/\bisClient\s*\(\s*\)\s*then\s+return\s+end/.test(code);
  });

if (unguarded.length) {
  console.log('\nMISSING isClient() GUARD - these load on multiplayer clients:');
  for (const f of unguarded) console.log('  ' + relative(root, f));
} else {
  console.log('\nserver guards  ok');
}

// A stranded call - Class.method() whose definition was deleted with the block
// around it - is the failure mode that has cost the most rounds here. luaparse
// only checks syntax, and the language server reports undefined GLOBALS but not
// undefined FIELDS on a table, which is what every one of these is.
//
// Scope: the mod's own namespaces. A call on a vanilla class is the engine's
// business. Both shapes count as ours - ISPanel:derive() classes AND the
// `X = X or {}` namespaces, which are most of the codebase: 2 of 29 files use
// derive, while TwoManCrew.Server alone carries 25 functions.
const sources = files.map((f) => ({ f, text: readFileSync(f, 'utf8') }));

const defined = new Set();
for (const { text } of sources) {
  for (const m of text.matchAll(/^\s*function\s+([\w.]+)[.:](\w+)/gm)) {
    defined.add(m[1] + '.' + m[2]);
  }
  // Field assigned an anonymous function, e.g. TwoManCrewJournalWindow.toggle =
  // function() ... end - a second definition style this codebase actually uses,
  // and the call site is often in a different file than the assignment.
  for (const m of text.matchAll(/^\s*([\w.]+)\.(\w+)\s*=\s*function\s*\(/gm)) {
    defined.add(m[1] + '.' + m[2]);
  }
}

// The `X = X or {}` shape is also the ordinary "default to an empty table" idiom
// (`found = found or {}`, `state.tiers = state.tiers or {}`), so matching it bare
// pulled in ten locals and put the namespace count at 16. Requiring an initial
// capital keeps the module namespaces this codebase actually declares and drops
// the locals. Overbreadth here is not harmless: every extra owner is a chance to
// report a dangling call that is not real, and a checker that cries wolf is one
// nobody reads.
const isModuleName = (n) => /^[A-Z]/.test(n);

const ours = new Set();
for (const { text } of sources) {
  for (const m of text.matchAll(/(\w+)\s*=\s*[\w.]+:derive\(/g)) ours.add(m[1]);
  for (const m of text.matchAll(/([\w.]+)\s*=\s*\1\s*or\s*\{\}/g)) {
    if (isModuleName(m[1])) ours.add(m[1]);
  }
}

const dangling = [];
for (const { f, text } of sources) {
  for (const m of text.matchAll(/([\w.]+)[.:](\w+)\s*\(/g)) {
    const [, owner, fn] = m;
    if (!ours.has(owner)) continue;
    if (defined.has(owner + '.' + fn)) continue;
    // Assigned rather than called, e.g. Class.instance = ...
    if (new RegExp(`${owner.replace(/\./g, '\\.')}\\.${fn}\\s*=`).test(text)) continue;
    const line = text.slice(0, m.index).split('\n').length;
    dangling.push(`  ${relative(root, f)}:${line}  calls ${owner}.${fn}, never defined`);
  }
}

if (dangling.length) {
  console.log('\nDANGLING CALLS - these throw the moment they run:');
  for (const d of [...new Set(dangling)].sort()) console.log(d);
} else {
  console.log(`dangling calls ok  (${ours.size} namespaces, ${defined.size} definitions)`);
}

// Both mod.info copies must agree or the two players disagree about which
// version is loaded - the exact shape of a multiplayer version mismatch.
// deploy.mjs checks this too, but only at deploy time, so a drift can sit in a
// commit for days. See docs/conventions/versioning.md
let versionsDiffer = false;
const infoPair = [
  join(root, 'mods', 'TwoManCrew', 'mod.info'),
  join(root, 'mods', 'TwoManCrew', '42', 'mod.info'),
];

if (infoPair.every((p) => existsSync(p))) {
  const [a, b] = infoPair.map((p) => {
    const m = readFileSync(p, 'utf8').match(/^modversion=(.+)$/m);
    return m ? m[1].trim() : '(none)';
  });
  if (a !== b) {
    versionsDiffer = true;
    console.log(`\nMOD.INFO MISMATCH: root=${a}  42/=${b} - they must be identical`);
  } else {
    console.log(`mod.info       ok  (both ${a})`);
  }
}

process.exit(bad || unguarded.length || dangling.length || versionsDiffer ? 1 : 0);
