# Deploying to the game

Auto-loaded into every session via `CLAUDE.md`. Rules, not background.

## Install is a copy

TwoManCrew installs into `~/Zomboid/mods/` by **copy**, via `node deploy.mjs` from
`two-man-crew/`.

The directory junction that used to live there was deleted 2026-08-22 — do not
recreate it or suggest it. The script refuses to run when the destination is a link.

It wipes the destination first, so files deleted in the repo also leave the install.

```
node deploy.mjs           deploy (destructive: wipes destination first)
node deploy.mjs --check   compare repo vs installed version, writes nothing
```

## Never deploy while the game is running

Ask first. Deploying replaces the mod folder under a live session.

## The install is deliberately pinned behind the repo

As of 2026-08-22 the install sits at `0.1.0` to match the other player in a co-op
save, while the repo is ahead. **Do not "sync" the install to the repo without
asking.**

To install a past version without disturbing the working tree, extract it from its
commit:

```
git archive <commit> two-man-crew/Contents/mods/TwoManCrew
```

Copy from there. Never `git checkout` an old version over the working tree.

Related: `.claude/memory/mods-folder-copy-install.md`,
`.claude/memory/pz-mod-state-survives-reinstall.md`.
