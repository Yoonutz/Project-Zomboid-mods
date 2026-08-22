# pz-b42-mods

A Project Zomboid Build 42 modding workspace: reference docs, a reusable mod
template, and worked examples. Each mod lives in its own top-level folder —
this is not a single-mod repo.

## Layout

```
docs/            reference material — read before writing any code
_template/       copy this folder to start a new mod (rename MOD_ID)
example-mod/     worked example: one item, one Lua hook, both verified
<your-mod>/      each new mod goes here, one top-level folder per mod
```

## Starting a new mod

1. Copy `_template/` to `<your-mod-name>/`.
2. Rename `Contents/mods/MOD_ID/` to `Contents/mods/<YourModID>/`.
3. Fill in `mod.info` (`name`, `id`, `author`, `description`) in `41/` and
   `42/` — see `docs/pz-modding-guide/mod-structure.md`.
4. Fill in `workshop.txt` at the mod root.
5. Add scripts under `Contents/mods/<YourModID>/42/media/scripts/`, Lua under
   `.../42/media/lua/{client,server,shared}/`. Use `common/` only for Lua
   shared between B41 and B42 — item/recipe script syntax is not compatible
   between builds.
6. Before using any Lua function or event not already noted in
   `docs/lua-events-reference.md` or `docs/lua-api-wiki.md`, verify it against
   those docs or <https://demiurgequantified.github.io/ProjectZomboidLuaDocs/> —
   do not rely on memory of older PZ versions, B42 changed a lot mid-cycle.

## Local testing

Copy `<your-mod>/Contents/mods/<YourModID>/` into `~/Zomboid/mods/<YourModID>/`,
then enable it from the in-game Mods menu.

**Copy, never symlink.** A directory junction here was removed on 2026-08-22 after
it caused a multiplayer version mismatch, and the tooling refuses to write through
one — deleting a link's contents deletes the repo's. See `docs/conventions/deploy.md`.

TwoManCrew has this automated: `node deploy.mjs` from `two-man-crew/`.

`/reloadlua` in the debug console reloads Lua without restarting; item and recipe
script changes need a full restart. See `docs/pz-modding-guide/testing.md`.

## Why the folder structure looks like this

B42 requires `mod.info` and `media/` inside a version-numbered folder (`41/`
or `42/`), not at the mod root like old B41 tutorials show. The outer
`workshop.txt` + `Contents/mods/<ModID>/` wrapper is the Steam Workshop
packaging convention. Full detail in `docs/pz-modding-guide/b42-changes.md`
and `mod-structure.md`.

## Status

`example-mod/`'s item script and Lua hook are written against verified B42 syntax
and event names (see the file-level comments citing the doc source) but have **not
been loaded in-game**. Verify in-game before treating them as more than a syntax
reference.

`two-man-crew/` is the active mod and carries the build tooling for the whole
workspace: `npm run check`, `npm run deploy`, `npm run diagnose`.
