# Project memory index — Project Zomboid mods

Project-local facts for this repo, stored in `.claude/memory/` and committed alongside the
code, so a clone carries them. `CLAUDE.md` imports this index, which is what loads it.

Cross-project facts live in `~/.claude/memories/` and are indexed by the global `MEMORY.md`;
both stores are consulted, never merged. An index line is a pointer — read the file before
acting on its topic.

- [work-on-master-no-branches](work-on-master-no-branches.md) — commit straight to `master` and push; no feature branches, no worktrees, no PRs, and never suggest one
- [pz-vanilla-source-is-the-api-reference](pz-vanilla-source-is-the-api-reference.md) — the installed game ships its full Lua source; grep it to verify any API or copy a UI style
- [pz-language-server-catches-stranded-refs](pz-language-server-catches-stranded-refs.md) — it is NOT on PATH but ships in the VS Code Lua extension; the only scope-aware check here, and skipping it shipped a per-frame crash
- [pz-lua-diagnostics-setup](pz-lua-diagnostics-setup.md) — `.luarc.json` + `types/pz.lua` stubs; run `--check` from the repo root, and never "fix" the atan2 or duplicate-set-field warnings
- [pz-mod-state-survives-reinstall](pz-mod-state-survives-reinstall.md) — re-adding or updating a build keeps campaign progress; state is in the save's ModData, not the mod folder
- [bump-modversion-on-next-change](bump-modversion-on-next-change.md) — standing rule: every mod change bumps `modversion` in the same commit, in BOTH `mod.info` copies
- [mods-folder-copy-install](mods-folder-copy-install.md) — install is a COPY (junction deleted 2026-08-22) and is PINNED to 0.1.0 for multiplayer while the repo sits at 0.1.2; don't "update" it to match the repo without asking
- [pz-api-doc-sources-ranked](pz-api-doc-sources-ranked.md) — which external doc source to trust for what; pzwiki.net and projectzomboid.com need a browser User-Agent (403 otherwise)
- [parallel-agents-by-file-ownership](parallel-agents-by-file-ownership.md) — split parallel agents by FILE not task; ban commits/mod.info/language-server in agents; check cross-file seams yourself afterwards
- [server-files-need-isclient-guard](server-files-need-isclient-guard.md) — every `server/` file needs `if isClient() then return end`; PZ loads that folder on MP clients too, and the failure is invisible in singleplayer
- [pz-mod-icons-are-generated](pz-mod-icons-are-generated.md) — TwoManCrew UI icons come from `make-icons.py` character grids; edit the grid and re-run, and ASCII-render to check the shape reads
- [pz-ui-size-must-go-through-setters](pz-ui-size-must-go-through-setters.md) — PZ hit-tests against the Java object; raw `self.width` resizes the drawing but not the hitbox
- [pz-hot-reload-lua-without-restarting](pz-hot-reload-lua-without-restarting.md) — `reloadLuaFile()` re-runs a mod file live; safe only for files registering no events, and close the window first or a ghost renders the old code
- [pz-verification-is-ingame-only](pz-verification-is-ingame-only.md) — the fengari UI harness was deleted by decision; `npm run check` never executes a line, so a UI claim is proved in-game or reported Unverified
- [pz-journal-campaign-is-task-cards](pz-journal-campaign-is-task-cards.md) — the Campaign view is tabbed task cards built from data the client already had; the done/failed/unreadable three-mark rule must never become a boolean
- [no-verification-scaffolding](no-verification-scaffolding.md) — never write a test or probe ad-hoc; `superpowers:test-driven-development` must be invoked first, otherwise verify by diffing origin/master
- [pz-runs-lua-5-1-kahlua](pz-runs-lua-5-1-kahlua.md) — PZ is Lua 5.1 (Kahlua): use the 5.1 manual, `require` takes slash paths, `unpack` not `table.unpack`, no `goto`; `pcall` is confirmed WORKING in-game despite zero vanilla usage, and `io`/`coroutine` are likewise unused-not-absent
- [pz-instrument-before-fixing-runtime-faults](pz-instrument-before-fixing-runtime-faults.md) — in-game faults get logging + a real game run BEFORE a fix; three builds reasoned from source were all wrong
- [pz-sendservercommand-is-mp-only](pz-sendservercommand-is-mp-only.md) — `sendServerCommand` reaches nobody in singleplayer; request/reply must use the mod's local-dispatch helpers
- [superpowers-artifacts-committed-vs-local](superpowers-artifacts-committed-vs-local.md) — plans in `docs/superpowers/plans/` are committed and carry an execution-status banner; `.superpowers/` brainstorm scratch is gitignored on purpose
- [pz-list-rows-draw-on-the-list](pz-list-rows-draw-on-the-list.md) — a custom `doDrawItem` must draw on the LIST; drawing on the parent window kills scrolling, shifts every row, and the stencil hides the evidence
- [checker-must-strip-comments](checker-must-strip-comments.md) — a text-search check passes on a file whose code was deleted but whose explaining comment survives; strip comments, and prove every check red before trusting it green
