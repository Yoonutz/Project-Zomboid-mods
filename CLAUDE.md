# pz-b42-mods

A Project Zomboid Build 42 modding workspace. Several mods, one per top-level
folder, sharing a docs tree and a mod template. `two-man-crew/` is the active one
and carries all the build tooling; the rest are smaller and mostly stable.

This file holds context — the things that change how an answer should be framed.
The enforceable rules are imported at the bottom and load with it.

## What makes this repo unusual

**The game cannot run here.** Nothing in this environment loads Project Zomboid, so
no change can be confirmed to work by running it. Syntax checks and the UI test
suite are proofreading: they catch a typo, never a wrong method name, a nil at
runtime, or a UI that draws garbage.

The practical effect on answers: any statement about runtime behaviour is a
hypothesis, and should be labelled as one. Three consecutive TwoManCrew builds were
shipped on code-reading alone and all three were wrong, each costing a round trip.
When a fault only appears in-game, the move is instrumentation first and a fix
second — ship `print()` calls, ask for one run, then fix what the log names. Asking
for a two-minute run is cheaper than a wrong build.

**The installed copy is deliberately behind the repo.** It is pinned so it matches
the other player in a co-op save. An install/repo version gap is intended, not drift
to be tidied away.

**The language is Lua 5.1**, not current Lua. The game embeds Kahlua, so `goto`,
`table.unpack`, integer division and bitwise operators do not exist here.

**Multiplayer is the default assumption.** Code paths differ between the host and a
remote client, and a bug that is invisible in singleplayer can still be real —
`sendServerCommand` reaches nobody in singleplayer, and `server/` files load on
clients too.

## Where things live

```
docs/               PZ and Lua reference material
docs/conventions/   this repo's own rules (imported below)
.claude/memory/     project facts, indexed and imported below
_template/          copy this to start a new mod
two-man-crew/       active mod, plus all build tooling
```

## Project memory

This repo's memories live in `.claude/memory/`, indexed by
`.claude/memory/MEMORY.md`, and are versioned with the code so they travel with a
clone. They used to sit outside the repo in the user profile, where they were
invisible to anyone else and to a fresh checkout.

An index line is a pointer — read the memory file before acting on its topic. Global
cross-project memories in `~/.claude/memories/` still apply on top of these; the two
stores are consulted, never merged.

## Rules

Imported, so they load every session. These are binding, not reference.

@docs/conventions/versioning.md
@docs/conventions/deploy.md
@docs/conventions/lua-and-checks.md
@docs/conventions/skills.md
@.claude/memory/MEMORY.md
