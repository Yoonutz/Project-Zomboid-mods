# Lua, scripts and checks

Auto-loaded into every session via `CLAUDE.md`. Rules, not background.

## Build target

Target Build 42 by default. Only add a `41/` folder for a mod if B41 support is
explicitly needed — B41 and B42 item/recipe script syntax are not compatible
(`Type=` vs `ItemType=`, old `recipe{}` vs `craftRecipe{}`).

## New mods

Copy `_template/`, don't hand-build the folder tree — it already matches the Steam
Workshop packaging layout (`workshop.txt` + `Contents/mods/<ModID>/{common,41,42}/`).

## Verify APIs before using them

Before using any Lua function, event, or item/script property not already cited in
`docs/`, verify it against:

- `docs/pz-modding-guide/`
- `docs/lua-api-wiki.md`, `docs/lua-events-reference.md`
- <https://demiurgequantified.github.io/ProjectZomboidLuaDocs/> — the real current
  API reference. The PZwiki `LuaDocs` page itself is stale, see
  `docs/luadocs-wiki-note.md`.

Add newly-verified facts to `docs/` as they're confirmed rather than re-deriving
them each time.

`docs/api-documentation-sources.md` ranks every external doc source — which is
current, which is archived, and the browser User-Agent needed to fetch `pzwiki.net`
and `projectzomboid.com` (both 403 the default fetch agent).

The installed game ships its full Lua source; grep it to verify any API or copy a UI
style. See `.claude/memory/pz-vanilla-source-is-the-api-reference.md`.

## The language is Lua 5.1

The game runs Lua 5.1 (Kahlua), so base-language questions go to the 5.1 manual,
never the current one. `docs/lua-language-reference.md` has the link and lists the
5.2+ features (`goto`, `table.unpack`, `//`, bitwise ops) that do not exist here.

## Editor diagnostics

Diagnostics come from `.luarc.json` + `types/pz.lua` (a `---@meta` stub for the PZ
globals). `types/` sits outside every mod's `Contents/`, so it is never packaged.

When a mod starts using a new engine global, add it to the stub with a signature
verified against the installed game source rather than silencing the warning.

It is **not on PATH**. It ships inside the VS Code Lua extension, and that copy
works fine from the shell:

```
"$HOME/.vscode/extensions/sumneko.lua-3.19.1-win32-x64/server/bin/lua-language-server.exe"   --check=. --checklevel=Warning
```

Run it from the repo root, not a mod subfolder, or `.luarc.json` is not picked up.

**Run it on every Lua change.** It is the only check here that does scope
analysis, so it is the only one that catches a variable that no longer exists.
Skipping it once shipped a crash that fired every render frame and lagged the
whole machine: a deletion left `vw` behind in an arithmetic expression, luaparse
parsed it happily, and `__sub not defined for operands` came back from the game.
Assume any deletion has stranded a reference until this says otherwise.

Never "fix" the atan2 or duplicate-set-field warnings — see
`.claude/memory/pz-lua-diagnostics-setup.md`.

## Repo checks

From `two-man-crew/`:

```
npm run check      parses every Lua file (luaparse)
npm run diagnose   reads the newest game log, prints the command chain
```

**There is no local test suite, by decision (2026-08-22).** A fengari-based UI
harness used to live at `two-man-crew/test-ui.mjs`. It was deleted because it
tested the mod against a hand-written fake of the engine, so a green run only
proved the fake agreed with itself.

**The only real test is running the game.** `npm run check` is proofreading: it
cannot catch a wrong method name, a nil at runtime, a wrong event, or a UI that
draws garbage. Never report a UI change as tested on the strength of it - say
`Unverified` until a Project Zomboid session has loaded it.

## Reading game logs

The CURRENT session's log sits at the `~/Zomboid/Logs/` root, not in the dated
`logs_<date>/` subfolder (those hold only earlier sessions):

```
ls -t ~/Zomboid/Logs/*.txt | head
```

Tail that file directly. Check its timestamp against the install's — an old log has
twice nearly produced a false conclusion.

## Markdown

Before committing a change to any `.md` file this repo authored (root files,
`docs/*.md` — not the vendored `docs/pz-modding-guide/` snapshot):

```
npx prettier --check "*.md" "docs/*.md" "docs/conventions/*.md"
```

Fix anything it flags.
