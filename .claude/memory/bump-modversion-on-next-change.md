---
name: bump-modversion-on-next-change
description: "Standing instruction from 2026-08-22 - the next change to a mod bumps its modversion in mod.info as part of that change, not as a separate step"
metadata:
  node_type: memory
  type: feedback
  originSessionId: a3a676dc-560c-46e9-9fb8-fc132dd1dc04
  modified: 2026-08-21T21:30:30.727Z
---

Kami's instruction, given 2026-08-22: **raise the iteration on the next change.** From now on,
any change to a mod's behaviour bumps `modversion` in that mod's `mod.info` within the same
commit as the change itself.

TwoManCrew sat at `modversion=0.1.0` while a session shipped five bug fixes and a new icon,
because the mod is unpublished (`workshopid=0`) and bumping looked like empty bookkeeping.
Kami's call is that the version tracks the code, not the release.

**Why:** an unchanged version across materially different builds means two folders can claim
to be the same thing. That costs nothing until a build is copied, handed over, or uploaded -
and by then the history that would tell them apart is gone.

**How to apply:**

- Bump `modversion` in the SAME commit as the change, never a follow-up "bump version" commit.
- TwoManCrew currently has **two** `mod.info` files - `Contents/mods/TwoManCrew/mod.info` and
  `Contents/mods/TwoManCrew/42/mod.info`. They must stay identical; they have already drifted
  once. Update both or the drift returns.
- Semver on behaviour: bug fixes only → patch; new visible behaviour or assets → minor.
  Next bump from `0.1.0` is `0.1.1` for pure fixes, `0.2.0` if anything new is added.
- Do NOT touch `pzversion` / `versionMin` (game build targeted) or `version=1` in
  `workshop.txt` (Workshop format version) - neither tracks the mod's own iteration.
- Applies to every mod in the repo, not only TwoManCrew.

Related: [[pz-mod-state-survives-reinstall]].
