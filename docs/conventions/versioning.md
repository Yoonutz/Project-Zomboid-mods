# Versioning

Auto-loaded into every session via `CLAUDE.md`. Rules, not background.

## Bump `modversion` in the same commit

Any change to a mod's behaviour bumps `modversion` in that mod's `mod.info`, in the
SAME commit - patch for fixes, minor for new behaviour or assets.

TwoManCrew has two `mod.info` files:

```
two-man-crew/Contents/mods/TwoManCrew/mod.info
two-man-crew/Contents/mods/TwoManCrew/42/mod.info
```

They must stay identical, and have drifted once already. Check both.

## What never tracks the mod's iteration

Leave these alone - none of them is the mod's own version:

| Field                        | What it actually tracks |
| ---------------------------- | ----------------------- |
| `pzversion` / `versionMin`   | Game build              |
| `workshop.txt` → `version=1` | Workshop format         |

### workshop.txt keys (decided 2026-10-06)

The vendored guide writes `workshopid=0` and `visibility=public`; the PZwiki documents `id=`
(absent for a new item) and visibility as `0` to `3`. Nothing is published yet, and the game
regenerates `workshop.txt` from the in-game uploader, so the files stay as they are. The one
rule the schema enforces: `workshopid` may only ever be the placeholder `0`. A real Workshop ID
goes under `id=`, the key the game reads; under `workshopid` the uploader would ignore it and
create a duplicate item.

## Multiplayer

Both players need the same `modversion`. A mismatch there is a version problem, not
an install-method problem.

Related: `.claude/memory/bump-modversion-on-next-change.md`.
