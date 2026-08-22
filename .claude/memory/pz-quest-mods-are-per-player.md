---
name: pz-quest-mods-are-per-player
description: "Both surveyed PZ quest engines (SSR, Soul Quest System) key progress to ONE player and have no shared-progress concept, so neither can back a two-player crew state; SSR additionally needs a Java-side mod for multiplayer, and both are all-rights-reserved"
metadata:
  node_type: memory
  type: project
---

Settled 2026-08-23 after installing and reading both engines rather than reading their
store pages. The question was whether TwoManCrew's campaign could sit on an existing quest
framework instead of growing its own.

**It cannot, and the reason is structural, not a matter of quality.**

- **SSR: Quest System** (workshop `2793385743`) is the better-built one: `Quest` holds
  `Task` holds `Action`, each with its own `unlocked` / `pending` / `completed` flags, a
  `SaveManager`, and custom Lua events so UI redraws on state change instead of polling.
  Its server stores progress per Steam ID and does nothing else. Its multiplayer path also
  requires a separate **Java-side mod** (`JM.require`, "SSROveride v1.05+"), so it is not
  reachable from pure Lua at all.
- **Soul Quest System** (workshop `2941736178`) declares quests as flat Lua tables in
  public pools, with a stringly-typed command mini-language (`;` and `:` separated). Its
  entire server side is 118 lines that write one backup text file per username.
- Searching both trees for any party, group, shared or co-op concept returns nothing.

**Why this matters:** TwoManCrew's whole premise is one campaign state that two people
share. A per-player engine cannot express that, so adopting one would mean writing the
shared layer anyway plus carrying a dependency both players must install and version-match.

**Licensing:** SSR's own file headers read `Copyright (c) 2022-2025 Oneline/D.Borovsky,
All rights reserved`, and its store page bans redistribution. Soul Quest states nothing,
which means all rights reserved by default. **Patterns only, never copied lines.**

**What was worth taking, and is recorded in
`docs/superpowers/specs/2026-08-23-declarative-tier-model-design.md`:**

- the three-layer tier/task/condition split, with per-node state
- firing a custom Lua event on state change instead of rebuilding the window every frame
- a checksum handshake so two machines detect a version mismatch instead of desyncing
  quietly (deliberately deferred, not dropped)

**What was rejected:** the string command language. Lua tables and registered functions do
the same job with no parser, and Kahlua gives no reason to prefer strings.

**How to apply:** do not re-survey this. If a new quest mod is proposed as a dependency,
the first question is whether it has shared progress; both leaders in this space do not.

Related: [[pz-journal-campaign-is-task-cards]], [[pz-sendservercommand-is-mp-only]],
[[pz-chunk-free-evidence-sources]].
