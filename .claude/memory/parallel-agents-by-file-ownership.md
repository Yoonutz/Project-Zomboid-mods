---
name: parallel-agents-by-file-ownership
description: "When splitting mod work across parallel agents, partition by FILE not by task, forbid commits and mod.info edits, and check the cross-file seams yourself afterwards - no agent can see them"
metadata:
  node_type: memory
  type: project
  originSessionId: cbca21ca-727e-445d-8633-096927d6fbb4
  modified: 2026-08-21T23:38:36.895Z
---

Parallel agents on this repo are split by **file ownership**, never by task number. Tasks here
overlap heavily: one plan had `TwoManCrew_Tiers.lua` in 5 tasks and `TwoManCrew_JournalWindow.lua`
in 3. Handing each agent a task list would have had three of them editing the same file.

**Why:** on 2026-08-22, 12 plan tasks ran as 4 agents partitioned by file and finished in about 5
minutes with zero conflicts. The same work run one-task-at-a-time with a full review cycle took
about 45 minutes for a single task.

**How to apply:**

- Group tasks so each agent owns a disjoint set of files. Where one task spans two owners, split
  the task and give each half to the file's owner, telling both which steps to skip.
- **Forbid all writing git commands.** Agents editing one tree will clobber each other's staged
  state. The controller commits once, after merging.
- **Forbid `mod.info` edits.** Every task's spec says to bump `modversion`; four agents doing that
  in one tree corrupts it. The controller bumps once for the batch.
- **Forbid `lua-language-server`.** It checks the whole repo, so it reports other agents'
  in-progress edits as errors and the agent will chase phantoms. `node check-lua.mjs` is per-file
  and safe to run in parallel.
- Keep `types/pz.lua` off every agent's list - several will want to add the same stub.

**Check the seams yourself afterwards.** This is the part that actually catches bugs, because no
agent can see across its own boundary. Real example from that run: the server renamed campaign
tiers while the client kept a hardcoded copy of the old names, and both agents reported success.
The check that found it compared the two label tables programmatically. Seams worth checking:

- a command string sent by one file and handled in another
- a field written by one module and read by another (`x1/y1/x2/y2`, `census*`, `crewPresent`)
- duplicated constant tables - display labels on the client mirroring server-side names

Related: [[pz-vanilla-source-is-the-api-reference]], [[bump-modversion-on-next-change]].
