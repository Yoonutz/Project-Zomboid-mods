# Versioning

Auto-loaded into every session via `CLAUDE.md`. Rules, not background.

## Bump `modversion` in the same commit

Any change to a mod's behaviour bumps `modversion` in that mod's `mod.info`, in the
SAME commit — patch for fixes, minor for new behaviour or assets.

TwoManCrew has two `mod.info` files:

```
two-man-crew/Contents/mods/TwoManCrew/mod.info
two-man-crew/Contents/mods/TwoManCrew/42/mod.info
```

They must stay identical, and have drifted once already. Check both.

## What never tracks the mod's iteration

Leave these alone — none of them is the mod's own version:

| Field                        | What it actually tracks |
| ---------------------------- | ----------------------- |
| `pzversion` / `versionMin`   | Game build              |
| `workshop.txt` → `version=1` | Workshop format         |

## Multiplayer

Both players need the same `modversion`. A mismatch there is a version problem, not
an install-method problem.

Related: `.claude/memory/bump-modversion-on-next-change.md`.
