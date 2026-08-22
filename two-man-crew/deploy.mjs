// Copy this mod into the local Zomboid mods folder.
//
// Deliberately a COPY, not a directory junction. The junction was removed on
// 2026-08-22 after a multiplayer version mismatch; Kami's call is that the
// install is a plain copy from here on.
//
// Copy semantics that matter:
//   - the destination is wiped first, so a file deleted in the repo is deleted
//     in the install too. A merge-copy leaves orphans behind, which is exactly
//     how the pre-junction install went stale at 0.1.0.
//   - refuses to write through a junction/symlink. If the destination is still
//     a link, deleting its contents would delete the repo's, so this stops.
//
// Usage:  node deploy.mjs          install
//         node deploy.mjs --check  report what is installed, change nothing
import { cpSync, rmSync, existsSync, lstatSync, readFileSync, mkdirSync } from 'node:fs';
import { join, dirname } from 'node:path';
import { execSync } from 'node:child_process';
import { fileURLToPath } from 'node:url';

const here = dirname(fileURLToPath(import.meta.url));
const MOD_ID = 'TwoManCrew';
const src = join(here, 'Contents', 'mods', MOD_ID);

const home = process.env.USERPROFILE || process.env.HOME;
if (!home) {
  console.error('cannot resolve home directory (USERPROFILE/HOME unset)');
  process.exit(2);
}
const dest = join(home, 'Zomboid', 'mods', MOD_ID);

const checkOnly = process.argv.includes('--check');

function modversion(dir) {
  try {
    const m = readFileSync(join(dir, 'mod.info'), 'utf8').match(/^modversion=(.+)$/m);
    return m ? m[1].trim() : '(none)';
  } catch {
    return '(not installed)';
  }
}

if (!existsSync(src)) {
  console.error(`source missing: ${src}`);
  process.exit(2);
}

// Both mod.info copies must agree, or the game and the server disagree about
// which version is loaded - the exact shape of a multiplayer version mismatch.
const rootV = modversion(src);
const buildV = modversion(join(src, '42'));
if (rootV !== buildV) {
  console.error(`mod.info mismatch: root=${rootV} 42/=${buildV} - fix before deploying`);
  process.exit(1);
}

console.log(`repo      ${rootV}`);
console.log(`installed ${modversion(dest)}`);
console.log(`dest      ${dest}`);

if (checkOnly) process.exit(0);

// The game holds the mod folder open and reads from it live. Wiping it under a
// running session is the destructive case docs/conventions/deploy.md forbids, and
// status.ps1 already refuses it for -Sync. This closes the same hole here.
function gameIsRunning() {
  try {
    const out = execSync('tasklist /FI "IMAGENAME eq ProjectZomboid*" /NH', {
      encoding: 'utf8',
      windowsHide: true,
    });
    return /ProjectZomboid/i.test(out);
  } catch {
    // tasklist missing or refused. Cannot prove the game is stopped, so do not
    // claim it is - a false "safe" here costs the live install.
    return true;
  }
}

if (gameIsRunning()) {
  console.error('Project Zomboid is running - close it first, or this wipes the live mod folder');
  console.error('(node deploy.mjs --check reports without writing)');
  process.exit(1);
}

if (existsSync(dest)) {
  // lstat, not stat: stat follows the link and would report the target.
  const st = lstatSync(dest);
  if (st.isSymbolicLink()) {
    console.error('destination is a symlink/junction - remove it first, or this deletes the repo');
    process.exit(1);
  }
  rmSync(dest, { recursive: true, force: true });
}

mkdirSync(dirname(dest), { recursive: true });
cpSync(src, dest, { recursive: true });

const after = modversion(dest);
if (after !== rootV) {
  console.error(`copy verify FAILED: expected ${rootV}, installed reads ${after}`);
  process.exit(1);
}
console.log(`deployed  ${after}  ok`);
