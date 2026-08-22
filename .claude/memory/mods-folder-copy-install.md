---
name: mods-folder-copy-install
description: "Zomboid/mods/TwoManCrew is installed by COPY (no junction, deleted 2026-08-22); the install lags the repo on purpose - CHECK the real versions with deploy.mjs --check, never trust a remembered number"
metadata:
  node_type: memory
  type: project
  originSessionId: cbca21ca-727e-445d-8633-096927d6fbb4
  modified: 2026-08-21T21:57:26.714Z
---

`%USERPROFILE%\Zomboid\mods\TwoManCrew` is a **plain copy** of
`<repo>\two-man-crew\Contents\mods\TwoManCrew`, deployed by `two-man-crew/deploy.mjs`.

It used to be a directory junction. Kami deleted that on 2026-08-22 to join a friend's
multiplayer session after a version mismatch, and ruled that installs are copy-paste from
here on. Do not recreate the junction, and do not propose it as a fix.

**Why:** the standing instruction is copy-paste. Note for accuracy when advising: a junction
and a copy expose byte-identical files, so the junction itself could not have caused a
version mismatch - that comes from the two players running different `modversion` builds.
Say so if it comes up, but the install method is Kami's call and is settled.

**How to apply:**

- **The install deliberately lags the repo, but the exact versions drift - always read them
  rather than recalling them.** `node deploy.mjs --check` prints both and writes nothing.
  This memory previously asserted a 0.1.0 pin against a 0.1.2 repo; by 2026-08-22 the real
  state was 0.1.8 installed against a 0.2.0 repo, so the remembered numbers were wrong and
  would have produced bad advice. Treat any version in prose here as historical.
- Do not "update" the install to match the repo without asking - the gap is intentional,
  because Kami's co-op partner has to be on the same `modversion`.
- Install a specific version without disturbing the working tree:
  `git archive <commit> two-man-crew/Contents/mods/TwoManCrew | tar -x -C <tmp>`, then copy
  from there. Never `git checkout` an old version over the working tree.
- Install with `node deploy.mjs` from `two-man-crew/` to deploy the CURRENT repo version. It wipes the destination first, so a
  file deleted in the repo also disappears from the install - a merge-copy leaves orphans,
  which is how the pre-junction install silently went stale at 0.1.0.
- `node deploy.mjs --check` prints repo vs installed version and writes nothing. Safe to run
  while the game is open.
- The script refuses to write when the destination is a link. Verified 2026-08-22: Node's
  `lstatSync().isSymbolicLink()` returns true for a Windows junction, so the guard fires
  instead of deleting through it into the repo.
- **Never deploy while PZ is running.** Kami plays from this install. Deploying replaces the
  folder under the running game; ask before installing, and expect a restart after.
- Multiplayer: both players need the same `modversion`, in both `mod.info` copies. A mismatch
  is a version problem, never an install-method problem.

Related: [[pz-mod-state-survives-reinstall]], [[bump-modversion-on-next-change]].
