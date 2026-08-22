# Workspace Enforcement and Doc Drift Implementation Plan

> **STATUS: written, NOT TESTED. 2026-08-22, version `0.10.5`.**
>
> **This code has never been executed.** No Project Zomboid session has loaded
> it. Nothing below is known to work.
>
> What actually ran while writing this plan: `npm run check` (29/29 parsed), the
> `pz-status` skill, and read-only greps over the repo and the installed game
> source. None of that executes a line of the mod. It is proofreading, not
> testing — it cannot catch a wrong method name, a nil at runtime, a wrong
> event, or a UI that draws garbage.
>
> Every in-game check is OPEN. In particular Task 1 records a question that
> **only a game run can settle**, and deliberately does not answer it.

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Close the gap between the rules this repo writes down and the rules anything actually enforces, and correct the committed statements that are false today.

**Architecture:** Three groups. Group A (Tasks 1-3) corrects auto-loaded text that misstates fact — zero code risk, highest value per minute. Group B (Tasks 4-7) turns four prose rules into mechanical checks inside `check-lua.mjs`, the one command the conventions already tell every session to run. Group C (Tasks 8-10) fixes the remaining verified drift and commits what is stranded in the working tree.

**Tech Stack:** Node 20+ ESM build scripts, PowerShell 7 for the status skill, Lua 5.1 (Kahlua) for the mod itself, Project Zomboid Build 42.

---

## Context for the implementer

You have zero repo knowledge. Read this section fully. The constraints below cannot be guessed from reading the code, and several look like defects that want "simplifying" away.

### What the mod is

`two-man-crew/` holds TwoManCrew, a two-player co-op mod: a Lumberjack and a Carpenter with shared progression, a crew journal UI, and a campaign layer where the pair restore one ruined town block. **Co-op is the default assumption, not an edge case.** Code paths differ between the host and a remote client, and a bug invisible in singleplayer can be real. The repo also holds five other mods (`campfire-tales/`, `last-words/`, `named-blades/`, `scavengers-eye/`, `example-mod/`) plus `_template/`; only TwoManCrew has Lua today.

### How verification works here, and what it cannot do

**The game cannot run in this environment.** There is no unit-test harness for engine code, because the mod calls globals (`getCell`, `getWorld`, `IsoPlayer`, `instanceof`) that exist only inside the running game. A fengari-based mock-engine harness used to exist and was **deleted by decision on 2026-08-22**. Do not rebuild it, not as a test file, not as a "quick harness", not as a probe.

The real gates, and their honest limits:

| Gate              | Command                                   | What it proves                                                    | What it cannot catch                                               |
| ----------------- | ----------------------------------------- | ----------------------------------------------------------------- | ------------------------------------------------------------------ |
| Parser            | `npm run check` in `two-man-crew/`        | every `.lua` file parses as Lua 5.1                               | wrong method name, nil at runtime, wrong event, UI drawing garbage |
| Language server   | see below                                 | scope analysis, stranded globals                                  | undefined _fields_ on a table                                      |
| `pz-status` skill | `& ".claude/skills/pz-status/status.ps1"` | install matches repo file-by-file, log is live, mod threw nothing | anything about how it looks on screen                              |

The language server is **not on PATH**. It ships inside the VS Code Lua extension and must be run from the repo root, or `.luarc.json` is not picked up:

```
"$HOME/.vscode/extensions/sumneko.lua-3.19.1-win32-x64/server/bin/lua-language-server.exe" --check=. --checklevel=Warning
```

Never "fix" the `atan2` or `duplicate-set-field` warnings it reports.

**Do not author tests in this repo.** The red-green steps in this plan use the repo's _own_ checks against real repo state — you make a checker report a defect that genuinely exists, then remove the defect. That is running an existing gate, not writing a test. If you believe a real test is warranted somewhere, stop and invoke `superpowers:test-driven-development` rather than improvising one.

### The language is Lua 5.1 (Kahlua)

Not current Lua. `goto`, `table.unpack`, integer division and bitwise operators do not exist. `require` takes **slash** paths. `unpack` is the global.

### Rules that bind you

- **Work directly on `master`.** No branches, no worktrees, no PRs, and never suggest one.
- **Bump `modversion` in the same commit as any change to a mod's behaviour**, patch for fixes, minor for new behaviour. TwoManCrew has **two** `mod.info` files that must stay identical:
  `two-man-crew/Contents/mods/TwoManCrew/mod.info` and `.../TwoManCrew/42/mod.info`.
  Only **Task 5** in this plan changes mod behaviour, and it bumps `0.10.5` to `0.10.6`. Build tooling under `two-man-crew/*.mjs` is never packaged into the mod, so every other task here touches only tooling or docs and does **not** bump.
- **Never deploy while the game is running.** Closing that hole is Task 4.
- The install at `~/Zomboid/mods/TwoManCrew` is a **copy**, never a junction. The junction was deleted 2026-08-22. Do not recreate one or suggest it.
- Before committing any `.md` this repo authored, run `npx prettier --check` on it. Skip the vendored `docs/pz-modding-guide/` snapshot.
- Never add Claude attribution to a commit — no `Co-authored-by`, no "Generated with", no mention.

### Where the current state came from

Every defect this plan fixes was verified by reading, not inferred. The evidence sits in `~/.claude/my-business/01_INBOX/consensus/consensus_report.md`, which is ephemeral and will be overwritten by the next poll — so the relevant evidence is restated inline in each task below. You do not need that file.

---

## File structure

| File                                                       | Change         | Responsible for                                                                       |
| ---------------------------------------------------------- | -------------- | ------------------------------------------------------------------------------------- |
| `.claude/memory/MEMORY.md`                                 | modify line 26 | index line that currently misstates its own memory body                               |
| `docs/conventions/deploy.md`                               | modify         | pin claim that is false today                                                         |
| `CLAUDE.md`                                                | modify         | same pin claim, auto-loaded                                                           |
| `README.md`                                                | modify         | symlink instruction and stale status                                                  |
| `two-man-crew/deploy.mjs`                                  | modify         | refuse to wipe a live install                                                         |
| `two-man-crew/check-lua.mjs`                               | modify         | becomes the single mechanical gate: parse + guards + dangling calls + mod.info parity |
| 5 files under `.../lua/server/TwoManCrew/`                 | modify         | restore the `isClient()` guard                                                        |
| `.claude/skills/pz-status/status.ps1`                      | modify         | drop the duplicated checker, keep reporting                                           |
| `_template/Contents/mods/MOD_ID/42/mod.info`               | modify         | new mods start compliant                                                              |
| `two-man-crew/SPEC.md`                                     | modify         | name the gates that exist                                                             |
| 4 files under `.claude/memory/`                            | modify         | remove links to a deleted memory                                                      |
| `docs/superpowers/plans/2026-08-22-campaign-task-cards.md` | modify         | banner naming a branch that never existed                                             |
| `.claude/settings.json`                                    | modify         | project hook enforcing the gate                                                       |
| `.gitignore`                                               | modify         | stop ignoring the lockfile                                                            |

`check-lua.mjs` takes on three new responsibilities. It stays one file on purpose: it is the command the conventions already name, a session runs it by reflex, and splitting it into four scripts means three of them never get run. It is ~40 lines today and lands near 150.

---

## Task 1: Correct the memory index line that misstates its own memory

The highest-value change in the plan, and the least risky. Docs only.

**Background you need.** `.claude/memory/MEMORY.md` is imported into every session by `CLAUDE.md`, so its one-line entries load every time. The individual memory files do **not** auto-load — an index line is a pointer.

Line 26 currently ends `no goto/pcall/io`. That asserts `pcall` does not exist in this engine. The memory file it points at says something materially different and more careful, at `.claude/memory/pz-runs-lua-5-1-kahlua.md:34`:

> Zero-usage counts show what is idiomatic, not a hard proof a function is absent.

Meanwhile the mod calls `pcall` at **7 committed sites**, all load-bearing error handling in paths that were bug-fixed in commits `19ae243` and `53a2c44`:

```
client/TwoManCrew/TwoManCrew_MastersMark.lua:42
server/TwoManCrew/TwoManCrew_Campaign.lua:366
server/TwoManCrew/TwoManCrew_CrewReport.lua:39
server/TwoManCrew/TwoManCrew_TierReport.lua:45
server/TwoManCrew/TwoManCrew_Tiers.lua:231
server/TwoManCrew/TwoManCrew_Tiers.lua:334
```

So every session begins believing `pcall` is unavailable while seven shipped call sites depend on it. The risk runs both ways: a future session could rip out working error handling, or could wrongly distrust three shipped fixes.

**Whether Kahlua actually provides `pcall` is NOT settled by this task and you must not pretend otherwise.** Verified facts: `pcall` appears in 0 of 1,395 vanilla `.lua` files by word-boundary grep, and nothing in the shipped tree defines or redefines it. Zero usage is not absence. Only a game run settles it.

**Files:**

- Modify: `.claude/memory/MEMORY.md:26`
- Modify: `.claude/memory/pz-runs-lua-5-1-kahlua.md` (append a note)

- [ ] **Step 1: Confirm the contradiction still exists**

```bash
cd "d:/Dropbox/Apps/Project Zomboid"
grep -n "kahlua" .claude/memory/MEMORY.md
grep -rn "pcall" --include=*.lua two-man-crew/ | grep -v "^.*--" | wc -l
```

Expected: the index line contains `no goto/pcall/io`, and the count of `pcall` references is non-zero. If the index line no longer says that, this task is already done — skip to Task 2.

- [ ] **Step 2: Rewrite the index line**

Replace line 26 of `.claude/memory/MEMORY.md` entirely with:

```markdown
- [pz-runs-lua-5-1-kahlua](pz-runs-lua-5-1-kahlua.md) — PZ is Lua 5.1 (Kahlua): use the 5.1 manual, `require` takes slash paths, `unpack` not `table.unpack`, no `goto`; `pcall`/`io`/`coroutine` are unused by vanilla but NOT proven absent — the mod itself calls `pcall` in 7 places
```

- [ ] **Step 3: Record the open question in the memory body**

Append to the end of `.claude/memory/pz-runs-lua-5-1-kahlua.md`, before the `Related:` line:

```markdown
**Open, needs one game run.** TwoManCrew calls `pcall` at 7 sites, all of them the
error handling that makes Claim and Refresh always send a reply
(`Campaign.lua:366`, `CrewReport.lua:39`, `TierReport.lua:45`, `Tiers.lua:231`
and `:334`, `MastersMark.lua:42`). Vanilla uses `pcall` in 0 of 1,395 files and
never defines it, which says it is unidiomatic here, not that Kahlua lacks it.
Until someone loads a session and exercises Claim and Refresh, treat those seven
sites as UNVERIFIED rather than broken. Do not remove them on the strength of the
zero-usage count alone - that count is not evidence of absence.
```

- [ ] **Step 4: Check formatting**

```bash
npx prettier --check ".claude/memory/MEMORY.md" ".claude/memory/pz-runs-lua-5-1-kahlua.md"
```

Expected: both listed as passing. If it reports a style issue, run the same command with `--write` and re-check.

- [ ] **Step 5: Commit**

```bash
git add .claude/memory/MEMORY.md .claude/memory/pz-runs-lua-5-1-kahlua.md
node --no-warnings --experimental-strip-types ~/.claude/scripts/git-commit.ts "docs: stop the index line claiming pcall does not exist" "The index line asserted 'no goto/pcall/io'. The memory it points at says the opposite in its own body: zero-usage counts show what is idiomatic, not that a function is absent.

Only the index line auto-loads, so every session started believing pcall was unavailable while seven committed call sites depend on it - the error handling that makes Claim and Refresh always reply.

Whether Kahlua provides pcall is still open and needs a game run. Recorded as open rather than answered."
```

---

## Task 2: Correct the install-pin claim in the two auto-loaded rule files

**Background.** Both files below load into every session. Both state the install is pinned at `0.1.0` behind the repo. That was true once and is false now: `pz-status` reports repo `0.10.5`, installed `0.10.5`, 41 files identical.

`.claude/memory/mods-folder-copy-install.md` already learned this lesson and was corrected to treat versions in prose as historical. The convention docs were not given the same treatment. The fix is not to write in today's numbers — they go stale the same way — but to point at the command that reports live state.

**Files:**

- Modify: `docs/conventions/deploy.md:24-31`
- Modify: `CLAUDE.md:22-26`

- [ ] **Step 1: Confirm the claim is still false**

```bash
cd "d:/Dropbox/Apps/Project Zomboid"
node two-man-crew/deploy.mjs --check
grep -n "0\.1\.0" docs/conventions/deploy.md CLAUDE.md
```

Expected: `--check` prints matching repo and installed versions; the grep finds the stale `0.1.0` text. If repo and installed genuinely differ, the pin may be real again — stop and ask rather than editing.

- [ ] **Step 2: Rewrite the deploy.md section**

Replace the whole `## The install is deliberately pinned behind the repo` section in `docs/conventions/deploy.md` with:

````markdown
## The install may be pinned behind the repo

The install is sometimes held at an older version deliberately, to match the other
player in a co-op save. **Never "sync" the install to the repo without asking.**

Do not trust any version number written in prose here — this section has been
wrong before. Ask the tooling instead:

```
node deploy.mjs --check
```

To install a past version without disturbing the working tree, extract it from its
commit:

```
git archive <commit> two-man-crew/Contents/mods/TwoManCrew
```

Copy from there. Never `git checkout` an old version over the working tree.
````

- [ ] **Step 3: Rewrite the CLAUDE.md paragraph**

Replace the paragraph beginning `**The installed copy is deliberately behind the repo.**` in `CLAUDE.md` with:

```markdown
**The installed copy may deliberately sit behind the repo.** It is sometimes pinned
so it matches the other player in a co-op save. An install/repo version gap is
intended, not drift to be tidied away. Whether a gap exists right now is a question
for `node deploy.mjs --check`, never for a number written here.
```

- [ ] **Step 4: Check formatting**

```bash
npx prettier --check "CLAUDE.md" "docs/conventions/deploy.md"
```

Expected: both pass.

- [ ] **Step 5: Commit**

```bash
git add CLAUDE.md docs/conventions/deploy.md
node --no-warnings --experimental-strip-types ~/.claude/scripts/git-commit.ts "docs: stop asserting a pin that is no longer true" "Both files said the install sits at 0.1.0 behind the repo. Both sides read 0.10.5 today, 41 files identical.

Both files auto-load, so every session started holding a false constraint. The memory file for this same fact was already corrected to treat prose versions as historical; the convention docs were not.

Points at deploy.mjs --check instead of naming a number that goes stale again."
```

---

## Task 3: Fix the README instructions that contradict the deploy rule

**Background.** `README.md:34` tells the reader to "Copy (or symlink)" a mod into `~/Zomboid/mods/`. The symlink half is forbidden: the junction was deleted 2026-08-22, and `deploy.mjs:66` refuses to write through a link because deleting the link's contents would delete the repo's. The README's Status section also claims no PZ install was available in this workspace, which is false — the game was running while this plan was written.

**Files:**

- Modify: `README.md:32-36` and the `## Status` section

- [ ] **Step 1: Rewrite the local testing section**

Replace the `## Local testing` section body in `README.md` with:

```markdown
Copy `<your-mod>/Contents/mods/<YourModID>/` into `~/Zomboid/mods/<YourModID>/`,
then enable it from the in-game Mods menu.

**Copy, never symlink.** A directory junction here was removed on 2026-08-22 after
it caused a multiplayer version mismatch, and the tooling refuses to write through
one — deleting a link's contents deletes the repo's. See `docs/conventions/deploy.md`.

TwoManCrew has this automated: `node deploy.mjs` from `two-man-crew/`.

`/reloadlua` in the debug console reloads Lua without restarting; item and recipe
script changes need a full restart. See `docs/pz-modding-guide/testing.md`.
```

- [ ] **Step 2: Rewrite the Status section**

Replace the `## Status` section body in `README.md` with:

```markdown
`example-mod/`'s item script and Lua hook are written against verified B42 syntax
and event names (see the file-level comments citing the doc source) but have **not
been loaded in-game**. Verify in-game before treating them as more than a syntax
reference.

`two-man-crew/` is the active mod and carries the build tooling for the whole
workspace: `npm run check`, `npm run deploy`, `npm run diagnose`.
```

- [ ] **Step 3: Confirm no other file still suggests a symlink**

```bash
cd "d:/Dropbox/Apps/Project Zomboid"
grep -rn "symlink\|junction" README.md docs/conventions/ | grep -iv "refus\|removed\|deleted\|never\|not a"
```

Expected: no output. Any hit is another place telling someone to make a link.

- [ ] **Step 4: Check formatting and commit**

```bash
npx prettier --check "README.md"
git add README.md
node --no-warnings --experimental-strip-types ~/.claude/scripts/git-commit.ts "docs: stop offering a symlink the tooling refuses" "The README told readers to copy or symlink into the mods folder. The junction was deleted 2026-08-22 and deploy.mjs refuses to write through a link, because deleting the link's contents deletes the repo's.

Its status note also said no PZ install was available here. There is one, and the game runs against it."
```

---

## Task 4: Stop `deploy.mjs` wiping a live install

**Background, and why this one matters most in Group B.** `docs/conventions/deploy.md` says "Never deploy while the game is running." The `pz-status` skill enforces that for its own `-Sync` path at `status.ps1:30` with a process check. `deploy.mjs` — the canonical installer that `package.json`, the convention docs and the memory file all point at — has **no such check**. Its only `process` references are Node's own global. It goes straight to:

```js
rmSync(dest, { recursive: true, force: true });
```

at line 69. Running `npm run deploy` mid-session wipes the mod folder under the running game with no warning. The game was running while this plan was written, so the exposure is live, not theoretical.

`--check` must stay exempt: it writes nothing and exits before this point.

**Files:**

- Modify: `two-man-crew/deploy.mjs`

- [ ] **Step 1: Confirm the guard is absent**

```bash
cd "d:/Dropbox/Apps/Project Zomboid"
grep -n "tasklist\|ProjectZomboid\|execSync" two-man-crew/deploy.mjs
```

Expected: no output. If a check already exists, skip this task.

- [ ] **Step 2: Add the import**

In `two-man-crew/deploy.mjs`, directly below the existing `import { join, dirname } from 'node:path';` line, add:

```js
import { execSync } from "node:child_process";
```

- [ ] **Step 3: Add the check function and the guard**

Insert this immediately after the `if (checkOnly) process.exit(0);` line (currently line 59), so `--check` is exempt by construction:

```js
// The game holds the mod folder open and reads from it live. Wiping it under a
// running session is the destructive case docs/conventions/deploy.md forbids, and
// status.ps1 already refuses it for -Sync. This closes the same hole here.
function gameIsRunning() {
  try {
    const out = execSync('tasklist /FI "IMAGENAME eq ProjectZomboid*" /NH', {
      encoding: "utf8",
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
  console.error(
    "Project Zomboid is running - close it first, or this wipes the live mod folder",
  );
  console.error("(node deploy.mjs --check reports without writing)");
  process.exit(1);
}
```

Note the `catch` returns `true`. If the process list cannot be read, the safe answer is to refuse.

- [ ] **Step 4: Verify the guard fires — the game is running now**

```bash
cd "d:/Dropbox/Apps/Project Zomboid/two-man-crew"
node deploy.mjs; echo "exit=$?"
```

Expected while a session is open: `Project Zomboid is running - close it first, or this wipes the live mod folder` and `exit=1`. Nothing is copied.

If no session is running, this instead performs a real deploy. **Check first** with `& "../.claude/skills/pz-status/status.ps1"` and read the `== GAME ==` line. If it says `not running`, skip this step and note it unverified rather than deploying to manufacture a result.

- [ ] **Step 5: Verify `--check` still works**

```bash
node deploy.mjs --check; echo "exit=$?"
```

Expected: prints repo, installed and dest, then `exit=0`. The guard must not block a read-only report.

- [ ] **Step 6: Commit**

`deploy.mjs` is build tooling and is never packaged into the mod, so no `modversion` bump.

```bash
cd "d:/Dropbox/Apps/Project Zomboid"
git add two-man-crew/deploy.mjs
node --no-warnings --experimental-strip-types ~/.claude/scripts/git-commit.ts "fix: refuse to deploy over a running game" "The convention says never deploy while the game runs, and status.ps1 enforces it for -Sync. deploy.mjs - the installer every doc points at - had no check and went straight to rmSync on the live mod folder.

Refuses when tasklist finds the process, and also when tasklist cannot be read: an unprovable 'safe' costs the install. --check stays exempt, it writes nothing."
```

---

## Task 5: Make `check-lua.mjs` enforce the server guard rule

**Background.** `.claude/memory/server-files-need-isclient-guard.md` records that every file under `media/lua/server/` needs `if isClient() then return end` after its `require` lines, because PZ loads that folder on multiplayer clients too. It documents the rule being broken once in `TwoManCrew_Campaign.lua` and fixed at 0.1.8.

It is broken again at 0.10.5, in five files:

```
TwoManCrew_DistressCall.lua
TwoManCrew_Restoration.lua
TwoManCrew_SharedApprenticeship.lua
TwoManCrew_TwoManCarry.lua
TwoManCrew_WatchMyBack.lua
```

All five contain zero occurrences of `isClient()` and all five register `Events.OnClientCommand.Add(...)` at module scope.

**Be precise about severity, and do not oversell it in the commit message.** `OnClientCommand` does not fire on a multiplayer client, so a file whose only module-scope act is registering that handler is inert there. The real exposure is `Restoration.lua`, which defines `TwoManCrew.Server.*` from line 48 with no guard while `CrewState.lua` bails at line 23 — the same shape as the 0.1.8 bug. The other four are policy violations and latent hazards. Fix all five anyway: a guard present in 9 of 14 files reads as deliberate, which is exactly why nothing flagged the gap.

This task adds the check first so you watch it catch a real defect, then removes the defect.

**Files:**

- Modify: `two-man-crew/check-lua.mjs`
- Modify: the five files above, under `two-man-crew/Contents/mods/TwoManCrew/42/media/lua/server/TwoManCrew/`

- [ ] **Step 1: Add the guard check to `check-lua.mjs`**

Replace the final two lines of `two-man-crew/check-lua.mjs`:

```js
console.log(`\n${files.length - bad}/${files.length} parsed`);
process.exit(bad ? 1 : 0);
```

with:

```js
console.log(`\n${files.length - bad}/${files.length} parsed`);

// PZ loads media/lua/server/ on multiplayer CLIENTS too - the folder name is a
// convention, not an engine boundary. A server file without this guard runs on a
// client, where the files that DID guard have bailed, so its calls into them hit
// nil. That shipped once as a dead Claim button and was fixed in 0.1.8; it came
// back in five files by 0.10.5, because nothing checked.
// See .claude/memory/server-files-need-isclient-guard.md
const unguarded = files
  .filter((f) => /[\\/]server[\\/]/.test(f))
  .filter((f) => !/\bisClient\s*\(\s*\)/.test(readFileSync(f, "utf8")));

if (unguarded.length) {
  console.log(
    "\nMISSING isClient() GUARD - these load on multiplayer clients:",
  );
  for (const f of unguarded) console.log("  " + relative(root, f));
} else {
  console.log("\nserver guards  ok");
}

process.exit(bad || unguarded.length ? 1 : 0);
```

- [ ] **Step 2: Run it and watch it fail on the real defect**

```bash
cd "d:/Dropbox/Apps/Project Zomboid/two-man-crew"
npm run check; echo "exit=$?"
```

Expected: `29/29 parsed`, then `MISSING isClient() GUARD` listing exactly these five, and `exit=1`:

```
mods\TwoManCrew\42\media\lua\server\TwoManCrew\TwoManCrew_DistressCall.lua
mods\TwoManCrew\42\media\lua\server\TwoManCrew\TwoManCrew_Restoration.lua
mods\TwoManCrew\42\media\lua\server\TwoManCrew\TwoManCrew_SharedApprenticeship.lua
mods\TwoManCrew\42\media\lua\server\TwoManCrew\TwoManCrew_TwoManCarry.lua
mods\TwoManCrew\42\media\lua\server\TwoManCrew\TwoManCrew_WatchMyBack.lua
```

If a different set appears, the repo moved since this plan was written — fix what it names, not what this list names.

- [ ] **Step 3: Add the guard to each of the five files**

In each file, insert the guard on its own line immediately after the last `require "..."` line, followed by a blank line. The pattern to match is `TwoManCrew_CrewReport.lua:15`.

For `TwoManCrew_DistressCall.lua`, after `require "TwoManCrew/TwoManCrew_Config"`:

```lua
require "TwoManCrew/TwoManCrew_Config"

-- PZ loads server/ on multiplayer clients too. Without this the file runs there,
-- where the guarded server files have bailed out. isClient() is false in
-- singleplayer, so this does not disable anything offline.
if isClient() then return end

```

Apply the identical three-comment-lines-plus-guard block after the last `require` in the other four files: `TwoManCrew_Restoration.lua`, `TwoManCrew_SharedApprenticeship.lua`, `TwoManCrew_TwoManCarry.lua`, `TwoManCrew_WatchMyBack.lua`.

If a file has no `require` line, put the block at the top, below the file-level comment header.

- [ ] **Step 4: Run the check again**

```bash
npm run check; echo "exit=$?"
```

Expected: `29/29 parsed`, `server guards  ok`, `exit=0`.

- [ ] **Step 5: Run the language server**

Deletions and insertions both strand references. This is the only scope-aware check here.

```bash
cd "d:/Dropbox/Apps/Project Zomboid"
"$HOME/.vscode/extensions/sumneko.lua-3.19.1-win32-x64/server/bin/lua-language-server.exe" --check=. --checklevel=Warning
```

Expected: no new diagnostics beyond the pre-existing `atan2` and `duplicate-set-field` warnings, which you must not "fix".

- [ ] **Step 6: Bump `modversion` in both `mod.info` files**

This task changes mod behaviour, so it bumps — patch level, `0.10.5` to `0.10.6`. Both files, identical, same commit:

```bash
sed -i 's/^modversion=0\.10\.5$/modversion=0.10.6/' \
  two-man-crew/Contents/mods/TwoManCrew/mod.info \
  two-man-crew/Contents/mods/TwoManCrew/42/mod.info
grep -n modversion two-man-crew/Contents/mods/TwoManCrew/mod.info two-man-crew/Contents/mods/TwoManCrew/42/mod.info
```

Expected: both read `modversion=0.10.6`.

- [ ] **Step 7: Commit**

```bash
git add two-man-crew/check-lua.mjs two-man-crew/Contents/mods/TwoManCrew/
node --no-warnings --experimental-strip-types ~/.claude/scripts/git-commit.ts "fix: restore the server guard in five files, and check for it from now on" "Every file under media/lua/server/ needs 'if isClient() then return end' - PZ loads that folder on multiplayer clients too. Nine of fourteen files had it, which read as deliberate, so nothing flagged the five that did not.

Restoration.lua is the one that matters: it defines TwoManCrew.Server.* at module scope while CrewState.lua bails, so on a client those definitions land against a state table nobody made. That is the shape of the dead Claim button fixed in 0.1.8. The other four register a handler that never fires on a client - policy violations and latent, not live faults.

npm run check now fails on an unguarded server file, so this cannot come back a third time quietly.

Unverified in-game."
```

---

## Task 6: Fix the dangling-call checker's blind spot and move it into the gate

**Background.** There is an **uncommitted** change in the working tree adding a `== DANGLING CALLS ==` section to `.claude/skills/pz-status/status.ps1` (about 62 added lines). Its purpose is real and fills a gap nothing else covers: luaparse checks syntax only, and the language server reports undefined globals but not undefined _fields_ on a table — and every one of this mod's namespaced functions is a field on a table.

Two problems, both verified:

1. **It is nearly blind.** It treats a class as "ours" only when matched by `X = Base:derive(`. Exactly **2 of 29** files use `:derive(`. Every other file hits `if ($ours.Count -eq 0) { continue }` and is skipped whole. The `TwoManCrew.Server` / `.Client` / `.Prefs` namespaces are built with `X = X or {}` and are invisible: **25 functions, 25 call sites**, including `TwoManCrew.Server.getState` — the exact function whose absence caused the 0.1.8 bug. It currently prints `none - every call resolves to a definition` while inspecting 7% of the codebase. That is worse than no check, because it manufactures confidence.

2. **It is in the wrong place.** It runs only when someone invokes the `pz-status` skill. A commit made without invoking it skips the check entirely.

Since it is uncommitted, fix both before it ever lands. It moves to `check-lua.mjs` and comes out of `status.ps1`.

**Files:**

- Modify: `two-man-crew/check-lua.mjs`
- Modify: `.claude/skills/pz-status/status.ps1` (remove the added block)

- [ ] **Step 1: Confirm the blind spot before changing anything**

```bash
cd "d:/Dropbox/Apps/Project Zomboid/two-man-crew/Contents/mods/TwoManCrew/42/media/lua"
echo "files using :derive( = $(grep -rl ':derive(' --include=*.lua . | wc -l) of $(find . -name '*.lua' | wc -l)"
grep -rho "TwoManCrew\.[A-Za-z]* = TwoManCrew\.[A-Za-z]* or {}" --include=*.lua . | sort -u
```

Expected: `files using :derive( = 2 of 29`, and four namespace declarations (`Client`, `LocalHandlers`, `Prefs`, `Server`). Those four are what the current checker cannot see.

- [ ] **Step 2: Add the dangling-call scan to `check-lua.mjs`**

Insert this immediately before the final `process.exit(...)` line you wrote in Task 5:

```js
// A stranded call - Class.method() whose definition was deleted with the block
// around it - is the failure mode that has cost the most rounds here. luaparse
// only checks syntax, and the language server reports undefined GLOBALS but not
// undefined FIELDS on a table, which is what every one of these is.
//
// Scope: the mod's own namespaces. A call on a vanilla class is the engine's
// business. Both shapes count as ours - ISPanel:derive() classes AND the
// `X = X or {}` namespaces, which are most of the codebase: 2 of 29 files use
// derive, while TwoManCrew.Server alone carries 25 functions.
const sources = files.map((f) => ({ f, text: readFileSync(f, "utf8") }));

const defined = new Set();
for (const { text } of sources) {
  for (const m of text.matchAll(/^\s*function\s+([\w.]+)[.:](\w+)/gm)) {
    defined.add(m[1] + "." + m[2]);
  }
}

const ours = new Set();
for (const { text } of sources) {
  for (const m of text.matchAll(/(\w+)\s*=\s*[\w.]+:derive\(/g)) ours.add(m[1]);
  for (const m of text.matchAll(/([\w.]+)\s*=\s*\1\s*or\s*\{\}/g))
    ours.add(m[1]);
}

const dangling = [];
for (const { f, text } of sources) {
  for (const m of text.matchAll(/([\w.]+)[.:](\w+)\s*\(/g)) {
    const [, owner, fn] = m;
    if (!ours.has(owner)) continue;
    if (defined.has(owner + "." + fn)) continue;
    // Assigned rather than called, e.g. Class.instance = ...
    if (new RegExp(`${owner.replace(/\./g, "\\.")}\\.${fn}\\s*=`).test(text))
      continue;
    const line = text.slice(0, m.index).split("\n").length;
    dangling.push(
      `  ${relative(root, f)}:${line}  calls ${owner}.${fn}, never defined`,
    );
  }
}

if (dangling.length) {
  console.log("\nDANGLING CALLS - these throw the moment they run:");
  for (const d of [...new Set(dangling)].sort()) console.log(d);
} else {
  console.log(
    `dangling calls ok  (${ours.size} namespaces, ${defined.size} definitions)`,
  );
}
```

- [ ] **Step 3: Update the exit line to include the new failure**

Replace the exit line from Task 5:

```js
process.exit(bad || unguarded.length ? 1 : 0);
```

with:

```js
process.exit(bad || unguarded.length || dangling.length ? 1 : 0);
```

- [ ] **Step 4: Run it and read the namespace count**

```bash
cd "d:/Dropbox/Apps/Project Zomboid/two-man-crew"
npm run check; echo "exit=$?"
```

Expected: a `dangling calls ok` line reporting **6 namespaces** (`TwoManCrewPanel`, `TwoManCrewJournalWindow`, `TwoManCrew.Client`, `TwoManCrew.LocalHandlers`, `TwoManCrew.Prefs`, `TwoManCrew.Server`) and roughly 25+ definitions.

The namespace count is the point of this step. If it reports 2, the `X = X or {}` pattern did not match and the checker is still blind — fix the regex before continuing. Do not accept a passing run that inspected 7% of the code.

If it reports genuine dangling calls, they are real defects: fix them, or if a name is engine-provided rather than ours, narrow `ours` rather than deleting the check.

- [ ] **Step 5: Remove the duplicated block from `status.ps1`**

Delete the entire `# ---- dangling calls` section added in the working tree — from the comment banner through the closing `}` of its `if ($dangling.Count -eq 0) { ... } else { ... }`, ending just before the `# ---- the log` banner. `status.ps1` goes back to reporting only.

- [ ] **Step 6: Verify the skill still runs**

```bash
cd "d:/Dropbox/Apps/Project Zomboid"
& ".claude/skills/pz-status/status.ps1"
```

Expected: `== GAME ==`, `== INSTALL ==`, `== LOG ==`, `== MOD ERRORS ==`, `== TIMINGS ==` sections print, and no `== DANGLING CALLS ==` section. No PowerShell errors.

- [ ] **Step 7: Commit**

Tooling only — no `modversion` bump.

```bash
git add two-man-crew/check-lua.mjs .claude/skills/pz-status/status.ps1
node --no-warnings --experimental-strip-types ~/.claude/scripts/git-commit.ts "fix: make the dangling-call check see the whole codebase, and run it by default" "The working-tree version matched classes only via ':derive(' - 2 of 29 files. Everything built as 'X = X or {}' was skipped whole, which is TwoManCrew.Server, .Client and .Prefs: 25 functions and 25 call sites, including the getState whose absence caused the dead Claim button.

It printed 'every call resolves to a definition' while reading 7% of the code. A check that manufactures confidence is worse than none.

Now matches both shapes, and lives in npm run check rather than a skill nobody has to invoke."
```

---

## Task 7: Fold the `mod.info` parity check into the same gate

**Background.** TwoManCrew's two `mod.info` files must stay identical; `docs/conventions/versioning.md` records that they have drifted once. Today only `deploy.mjs` checks parity, and only at deploy time — so a drift committed on Monday surfaces on Thursday when someone installs. Both currently read `0.10.5` (or `0.10.6` after Task 5), so this check will pass; it is a tripwire, not a repair.

**Files:**

- Modify: `two-man-crew/check-lua.mjs`

- [ ] **Step 1: Add the parity check**

Insert immediately before the final `process.exit(...)` line:

```js
// Both mod.info copies must agree or the two players disagree about which
// version is loaded - the exact shape of a multiplayer version mismatch.
// deploy.mjs checks this too, but only at deploy time, so a drift can sit in a
// commit for days. See docs/conventions/versioning.md
let versionsDiffer = false;
const infoPair = [
  join(root, "mods", "TwoManCrew", "mod.info"),
  join(root, "mods", "TwoManCrew", "42", "mod.info"),
];

if (infoPair.every((p) => existsSync(p))) {
  const [a, b] = infoPair.map((p) => {
    const m = readFileSync(p, "utf8").match(/^modversion=(.+)$/m);
    return m ? m[1].trim() : "(none)";
  });
  if (a !== b) {
    versionsDiffer = true;
    console.log(
      `\nMOD.INFO MISMATCH: root=${a}  42/=${b} - they must be identical`,
    );
  } else {
    console.log(`mod.info       ok  (both ${a})`);
  }
}
```

- [ ] **Step 2: Add the two imports this needs**

`check-lua.mjs` currently imports `readdirSync, statSync, readFileSync` from `node:fs` and `join, relative` from `node:path`. Add `existsSync`:

```js
import { readdirSync, statSync, readFileSync, existsSync } from "node:fs";
```

`join` is already imported. Leave the `node:path` import alone.

- [ ] **Step 3: Update the exit line**

```js
process.exit(
  bad || unguarded.length || dangling.length || versionsDiffer ? 1 : 0,
);
```

- [ ] **Step 4: Verify it passes, then verify it can fail**

```bash
cd "d:/Dropbox/Apps/Project Zomboid/two-man-crew"
npm run check; echo "exit=$?"
```

Expected: `mod.info       ok  (both 0.10.6)` and `exit=0`.

Now prove the tripwire actually trips, then put it straight back:

```bash
sed -i 's/^modversion=0\.10\.6$/modversion=0.10.7/' Contents/mods/TwoManCrew/42/mod.info
npm run check; echo "exit=$?"
git checkout Contents/mods/TwoManCrew/42/mod.info
npm run check; echo "exit=$?"
```

Expected: the middle run prints `MOD.INFO MISMATCH: root=0.10.6  42/=0.10.7` and `exit=1`; the final run is back to `ok` and `exit=0`. Confirm `git status` is clean for that file before moving on.

- [ ] **Step 5: Commit**

```bash
cd "d:/Dropbox/Apps/Project Zomboid"
git add two-man-crew/check-lua.mjs
node --no-warnings --experimental-strip-types ~/.claude/scripts/git-commit.ts "feat: catch mod.info drift at check time, not deploy time" "The two mod.info copies must agree, and have drifted once. Only deploy.mjs checked, so a drift could sit in a commit until someone installed days later."
```

---

## Task 8: Make new mods start compliant, and fix the remaining stale text

Four small verified corrections. One commit.

**Files:**

- Modify: `_template/Contents/mods/MOD_ID/42/mod.info`
- Modify: `two-man-crew/SPEC.md:113`
- Modify: `.claude/memory/no-verification-scaffolding.md`, `pz-instrument-before-fixing-runtime-faults.md`, `pz-sendservercommand-is-mp-only.md`, `pz-ui-size-must-go-through-setters.md`
- Modify: `docs/superpowers/plans/2026-08-22-campaign-task-cards.md`

- [ ] **Step 1: Give the template its version fields**

`docs/conventions/versioning.md` requires every mod to carry `modversion`, and `README.md` tells people to start a mod by copying `_template/`. The template has `name`, `id`, `author`, `description`, `poster` and none of the three version fields, so every new mod starts out of compliance. The four scaffolded stubs all carry them.

Replace `_template/Contents/mods/MOD_ID/42/mod.info` entirely with:

```
name=My Mod Display Name
id=MOD_ID
author=YourName
description=What your mod does, shown in the mod list.
poster=poster.png
pzversion=42
modversion=0.1.0
versionMin=42.0.0
```

- [ ] **Step 2: Point SPEC.md at gates that exist**

`two-man-crew/SPEC.md:113` names `luacheck` and `luac -p`. Neither appears anywhere else in the repo and neither is installed. Replace that line with:

```markdown
- [ ] Passes `npm run check` — parses under luaparse, server guards present, no dangling calls, mod.info copies agree
```

- [ ] **Step 3: Remove the four links to a memory that does not exist**

`[[pz-run-the-ui-not-just-the-parser]]` described the fengari harness deleted on 2026-08-22. Four memory files still link it, so four auto-loadable files gesture at running a suite that no longer exists.

```bash
cd "d:/Dropbox/Apps/Project Zomboid"
grep -rn "pz-run-the-ui-not-just-the-parser" .claude/memory/
```

In each of the four hits, remove the `[[pz-run-the-ui-not-just-the-parser]]` reference. Where it sits in a `Related:` list, delete just that entry and tidy the commas. Where a sentence depends on it, repoint to `[[pz-verification-is-ingame-only]]`, which is the memory that now carries that fact.

Confirm none survive:

```bash
grep -rn "pz-run-the-ui-not-just-the-parser" .claude/ docs/ CLAUDE.md; echo "exit=$?"
```

Expected: no output, `exit=1`.

- [ ] **Step 4: Fix the plan banner naming a branch**

`docs/conventions/skills.md` says a plan's status banner "names a version and a date, not a branch". The banner in `docs/superpowers/plans/2026-08-22-campaign-task-cards.md` names `feature/campaign-task-cards`. `git branch -a` shows only `master`; that branch has never existed.

Edit that banner to drop the branch name, keeping the version and date. Leave everything else in that plan alone — it is a record of past work.

- [ ] **Step 5: Check formatting and commit**

```bash
npx prettier --check "*.md" "docs/*.md" "docs/conventions/*.md" "docs/superpowers/plans/*.md" ".claude/memory/*.md" "two-man-crew/*.md"
git add _template two-man-crew/SPEC.md .claude/memory/ docs/superpowers/plans/
node --no-warnings --experimental-strip-types ~/.claude/scripts/git-commit.ts "docs: fix four stale claims across the template, spec, memories and a plan" "The template had no modversion, so every mod started by copying it began out of compliance with the versioning rule.

SPEC.md's definition of done named luacheck and luac -p. Neither is installed anywhere in this repo; the real gate is npm run check.

Four memory files linked pz-run-the-ui-not-just-the-parser, which described the deleted fengari harness and no longer exists.

A plan banner named a branch, in a repo whose own convention says banners name a version and a date."
```

---

## Task 9: Commit the lockfile so the one dependency stops floating

**Background.** `.gitignore:16` ignores `package-lock.json`. `two-man-crew/package-lock.json` exists on disk but is untracked, so `luaparse: ^0.3.1` resolves to whatever is newest on a fresh clone. One dev dependency, low stakes — but the fix is two lines and the parser is now the repo's only real gate.

**Files:**

- Modify: `.gitignore`
- Add: `two-man-crew/package-lock.json`

- [ ] **Step 1: Stop ignoring lockfiles**

In `.gitignore`, replace:

```
# local lua syntax checker deps
node_modules/
package-lock.json
```

with:

```
# local lua syntax checker deps
node_modules/
```

- [ ] **Step 2: Track the lockfile and confirm**

```bash
cd "d:/Dropbox/Apps/Project Zomboid"
git add .gitignore two-man-crew/package-lock.json
git status --short
```

Expected: both listed as staged. If the lockfile is still ignored, `git check-ignore -v two-man-crew/package-lock.json` shows which rule is still catching it.

- [ ] **Step 3: Verify the gate still runs from the lockfile**

```bash
cd "d:/Dropbox/Apps/Project Zomboid/two-man-crew"
npm run check; echo "exit=$?"
```

Expected: `exit=0`, all sections ok. Do **not** run `npm --prefix ... install` from the repo root — `--prefix` adds the parent as a `file:..` dependency and symlinks the whole repo. `cd` into `two-man-crew/` first, as above.

- [ ] **Step 4: Commit**

```bash
cd "d:/Dropbox/Apps/Project Zomboid"
node --no-warnings --experimental-strip-types ~/.claude/scripts/git-commit.ts "build: track the lockfile so the parser version stops floating" "package-lock.json was gitignored, so luaparse resolved to whatever was newest on a fresh clone. It is now the repo's only real gate, so it should not move underfoot."
```

---

## Task 10: Make the gate fire without anyone remembering it

**Background, and the reason this task is last.** Every rule this repo cares about was prose only. The project `.claude/settings.json` is `{}` and `.git/hooks/` holds nothing but samples. The user's own `~/.claude` enforces its top rules with hooks "so they hold regardless of what the model decides"; this repo did not. That is the root cause behind Tasks 5, 6, 7 and 8 — each was a written rule that nothing checked.

Tasks 5-7 already moved four rules into `check-lua.mjs`. This task makes that command run on its own.

**Files:**

- Modify: `.claude/settings.json`

- [ ] **Step 1: Read the current file**

```bash
cd "d:/Dropbox/Apps/Project Zomboid"
cat .claude/settings.json
```

Expected: `{}`. If it has content, merge rather than overwrite.

- [ ] **Step 2: Add a PostToolUse hook that runs the gate after any Lua edit**

Replace the contents of `.claude/settings.json` with:

```json
{
  "hooks": {
    "PostToolUse": [
      {
        "matcher": "Edit|Write",
        "hooks": [
          {
            "type": "command",
            "command": "node \"$CLAUDE_PROJECT_DIR/two-man-crew/check-lua.mjs\" \"$CLAUDE_PROJECT_DIR/two-man-crew/Contents\""
          }
        ]
      }
    ]
  }
}
```

This runs the full gate — parse, server guards, dangling calls, `mod.info` parity — after every file edit, and surfaces the output. It is deliberately not a blocking `PreToolUse` gate on commits: a blocking hook that misfires on this repo's own tooling edits would be worse than the problem, and the gate is fast enough to run on every edit.

- [ ] **Step 3: Verify the JSON parses**

```bash
node -e "console.log(JSON.stringify(JSON.parse(require('fs').readFileSync('.claude/settings.json','utf8')),null,2))"
```

Expected: the settings object prints back. A `SyntaxError` means a stray comma.

- [ ] **Step 4: Verify the hook fires**

Make a trivial whitespace edit to any file under `two-man-crew/Contents/` using the Edit tool, then revert it. The check output should appear after the edit.

If it does not fire, the settings file may need the session reloaded — note that rather than rewriting the hook shape. Do not spend more than one attempt here; report it unverified instead.

- [ ] **Step 5: Commit**

```bash
git add .claude/settings.json
node --no-warnings --experimental-strip-types ~/.claude/scripts/git-commit.ts "feat: run the gate after every edit instead of hoping someone remembers" "The project settings were empty and there were no git hooks, so every rule in the conventions was enforced only by a session remembering it. The isClient guard rule shipped broken twice that way.

Runs check-lua.mjs after any Edit or Write. Not a blocking commit gate - a hook that misfires on the repo's own tooling edits would cost more than it saves."
```

---

## Final verification

- [ ] **Run the full gate**

```bash
cd "d:/Dropbox/Apps/Project Zomboid/two-man-crew"
npm run check; echo "exit=$?"
```

Expected: `29/29 parsed`, `server guards  ok`, `dangling calls ok  (6 namespaces, ...)`, `mod.info       ok  (both 0.10.6)`, `exit=0`.

- [ ] **Run the language server from the repo root**

```bash
cd "d:/Dropbox/Apps/Project Zomboid"
"$HOME/.vscode/extensions/sumneko.lua-3.19.1-win32-x64/server/bin/lua-language-server.exe" --check=. --checklevel=Warning
```

Expected: no new diagnostics beyond the pre-existing `atan2` and `duplicate-set-field` warnings.

- [ ] **Run the status skill**

```bash
& ".claude/skills/pz-status/status.ps1"
```

Expected: all sections print, no `== DANGLING CALLS ==` section, no PowerShell errors. The install will now read `0.10.5` against a repo at `0.10.6` — that gap is expected and is **not** to be closed by deploying. Ask first.

- [ ] **Confirm the working tree is clean**

```bash
git status --short
```

Expected: empty. Anything left means a task committed partially.

- [ ] **Push**

```bash
git push origin master
```

- [ ] **Report honestly**

The status line for this work is `Unverified: no Project Zomboid session has loaded the guard changes`. Everything above proves files parse, guards are present and text is accurate. None of it proves the mod behaves correctly on screen.

Two items stay OPEN and neither is closed by this plan:

1. **Does Kahlua provide `pcall`?** Seven call sites depend on it and vanilla never uses it. Settled only by loading a session and exercising Claim and Refresh. Task 1 records the question; it does not answer it.
2. **Does the five-file guard fix change anything in co-op?** The reasoning says `Restoration.lua` was the one that mattered. That is a hypothesis until two players load `0.10.6`.

---

## Deliberately not in this plan

- **Deleting the root-level `two-man-crew/Contents/mods/TwoManCrew/mod.info`.** The vendored `docs/pz-modding-guide/mod-structure.md` shows `mod.info` only inside `42/`, and no other mod here has a root copy, so it looks redundant. But that diagram is labelled "Minimal Structure", which is not evidence the root copy goes unread, and the downside of being wrong is a broken install. It needs a game run, not a guess.
- **Splitting `TwoManCrew_JournalWindow.lua`** (1,258 lines against a 488-line runner-up, and named in the file-ownership memory as a source of agent collisions). Real, but a large refactor of the most UI-heavy file in a repo where UI cannot be tested locally. It wants its own plan and a session that can look at the screen.
- **Generalising `deploy.mjs`, `diagnose.mjs` and `status.ps1` across all six mods.** They hardcode `TwoManCrew`; `check-lua.mjs` is already mod-agnostic. Worth doing when a second mod grows Lua — today five of six have none, so it would be tooling with nothing to tool.
- **The global `"model": "opus[1m]"` default versus the stated 60/30/10 routing policy.** Cross-project and a cost/quality tradeoff that belongs to the user, not to this repo.
