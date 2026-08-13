# pz-b42-mods — project conventions

- Target Build 42 by default. Only add a `41/` folder for a mod if B41 support
  is explicitly needed — B41 and B42 item/recipe script syntax are not
  compatible (`Type=` vs `ItemType=`, old `recipe{}` vs `craftRecipe{}`).
- Before using any Lua function, event, or item/script property not already
  cited in `docs/`, verify it against `docs/pz-modding-guide/`,
  `docs/lua-api-wiki.md`, `docs/lua-events-reference.md`, or
  https://demiurgequantified.github.io/ProjectZomboidLuaDocs/ (the real
  current API reference — the PZwiki `LuaDocs` page itself is stale, see
  `docs/luadocs-wiki-note.md`). Add newly-verified facts to `docs/` as they're
  confirmed rather than re-deriving them each time.
- New mods: copy `_template/`, don't hand-build the folder tree — it already
  matches the Steam Workshop packaging layout (`workshop.txt` +
  `Contents/mods/<ModID>/{common,41,42}/`).
- No in-game testing happens automatically in this environment. Any change to
  a `.txt` script or `.lua` file is a syntax-level claim only until it's been
  loaded in PZ and checked against `~/Zomboid/Logs/` for parse errors.
