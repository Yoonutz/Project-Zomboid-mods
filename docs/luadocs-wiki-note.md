# LuaDocs (PZwiki page) — read this before trusting the wiki page itself

Fetched 2026-08-13 from `https://pzwiki.net/wiki/LuaDocs`.

**The wiki page is stale.** Its own banner says: *"This page was last updated
for an older version of the current build (42.8.1). The current stable version
is 42.20.2, so information on this page may be inaccurate."* The page is a
pointer/description page, not the API reference itself.

## The actual current reference

LuaDocs is a Doxygen-generated API reference maintained separately from the
wiki. Use these, not the wiki page:

- Site: https://demiurgequantified.github.io/ProjectZomboidLuaDocs/
- Source: https://github.com/demiurgeQuantified/ProjectZomboidLuaDocs
- Underlying generator: https://github.com/demiurgeQuantified/rosetta_doxygen

It documents: callbacks, Lua events, hooks, a link to the current JavaDocs,
classes with their functions/hierarchy/inheritance, and the source file
location for each class — useful for finding where a class actually lives in
`media/lua/`.

## What was verified there this session

- Event `OnGameStart` — "Triggered upon finishing loading and entering the
  game." No parameters. Used for the example Lua hook in `example-mod/`.

Anything else pulled from this site for future mods should get the same
treatment: quote the exact wording found, note the date checked, and don't
assume training-data knowledge of the Lua API is current — B42 changed a lot
mid-cycle (see `pz-modding-guide/b42-changes.md` and `version-changelog.md`).
