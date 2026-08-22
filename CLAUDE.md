# pz-b42-mods — project conventions

- Target Build 42 by default. Only add a `41/` folder for a mod if B41 support
  is explicitly needed — B41 and B42 item/recipe script syntax are not
  compatible (`Type=` vs `ItemType=`, old `recipe{}` vs `craftRecipe{}`).
- Before using any Lua function, event, or item/script property not already
  cited in `docs/`, verify it against `docs/pz-modding-guide/`,
  `docs/lua-api-wiki.md`, `docs/lua-events-reference.md`, or
  <https://demiurgequantified.github.io/ProjectZomboidLuaDocs/> (the real
  current API reference — the PZwiki `LuaDocs` page itself is stale, see
  `docs/luadocs-wiki-note.md`). Add newly-verified facts to `docs/` as they're
  confirmed rather than re-deriving them each time.
  The game runs **Lua 5.1** (Kahlua), so base-language questions go to the 5.1
  manual, never the current one — `docs/lua-language-reference.md` has the link
  and lists the 5.2+ features (`goto`, `table.unpack`, `//`, bitwise ops) that
  do not exist here.
  `docs/api-documentation-sources.md` ranks every external doc source — which
  is current, which is archived, and the browser User-Agent needed to fetch
  `pzwiki.net` and `projectzomboid.com` (both 403 the default fetch agent).
- New mods: copy `_template/`, don't hand-build the folder tree — it already
  matches the Steam Workshop packaging layout (`workshop.txt` +
  `Contents/mods/<ModID>/{common,41,42}/`).
- No in-game testing happens automatically in this environment. Any change to
  a `.txt` script or `.lua` file is a syntax-level claim only until it's been
  loaded in PZ and checked against `~/Zomboid/Logs/` for parse errors.
  The CURRENT session's log sits at the `~/Zomboid/Logs/` root, not in the
  dated `logs_<date>/` subfolder (those hold only earlier sessions), so read
  it with `ls -t ~/Zomboid/Logs/*.txt | head` and tail that file directly.
- Any change to a mod's behaviour bumps `modversion` in that mod's `mod.info`
  in the SAME commit - patch for fixes, minor for new behaviour or assets.
  TwoManCrew has two `mod.info` files (`Contents/mods/TwoManCrew/mod.info` and
  `.../42/mod.info`); they must stay identical, and have drifted once already.
  Leave `pzversion`/`versionMin` (game build) and `workshop.txt`'s `version=1`
  (Workshop format) alone - neither tracks the mod's own iteration.

- Editor diagnostics come from `.luarc.json` + `types/pz.lua` (a `---@meta`
  stub for the PZ globals). `types/` sits outside every mod's `Contents/`, so
  it is never packaged. When a mod starts using a new engine global, add it to
  the stub with a signature verified against the installed game source rather
  than silencing the warning. Check the whole repo with:
  `lua-language-server --check=. --checklevel=Warning` from the repo root -
  run it from the root, not a mod subfolder, or `.luarc.json` is not picked up.

- Before committing a change to any `.md` file this repo authored (root files,
  `docs/*.md` — not the vendored `docs/pz-modding-guide/` snapshot), run
  `npx prettier --check "*.md" "docs/*.md"` and fix anything it flags.

- TwoManCrew installs into `~/Zomboid/mods/` by **copy**, via
  `node deploy.mjs` from `two-man-crew/`. The directory junction that used to
  live there was deleted 2026-08-22 — do not recreate it or suggest it. The
  script wipes the destination first, so files deleted in the repo also leave
  the install, and it refuses to run when the destination is a link.
  `node deploy.mjs --check` compares repo and installed versions and writes
  nothing. Never deploy while the game is running — ask first, since it
  replaces the folder under a live session. For multiplayer, both players need
  the same `modversion`; a mismatch there is a version problem, not an
  install-method problem.

- The installed copy is deliberately allowed to lag the repo. As of
  2026-08-22 it is pinned to 0.1.0 so it matches the other player in a
  co-op save, while the repo is ahead. Do not "sync" the install to the
  repo without asking. To install a past version without disturbing the
  working tree, extract it from its commit
  (`git archive <commit> two-man-crew/Contents/mods/TwoManCrew`) and copy
  from there — never `git checkout` an old version over the working tree.

## Project memory

This repo's memories live in `.claude/memory/`, indexed by `.claude/memory/MEMORY.md`,
and are versioned with the code so they travel with a clone. They used to sit outside
the repo in the user profile, where they were invisible to anyone else and to a fresh
checkout.

An index line is a pointer — read the memory file before acting on its topic. Global
cross-project memories in `~/.claude/memories/` still apply on top of these; the two
stores are consulted, never merged.

@.claude/memory/MEMORY.md
