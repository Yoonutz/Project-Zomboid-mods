# Lua language reference — which manual applies, and where PZ deviates

Added 2026-08-22. This file covers the **base Lua language** — syntax, standard
library, semantics. For the game's own API (engine globals, events, exposed Java
classes) see `api-documentation-sources.md`, `lua-api-wiki.md`, and
`lua-events-reference.md`.

The distinction matters: a question like "does `table.unpack` exist" is a base
Lua question answered here, while "does `getPlayer()` exist" is a PZ question
answered by those files.

## The version — 5.1, not current Lua

Project Zomboid embeds **Kahlua**, a Java implementation of **Lua 5.1**
(`se.krka.kahlua.vm` in the JavaDocs package tree). Lua's current release is 5.5.

**Always consult the 5.1 manual. Never the current one.**

- Lua 5.1 Reference Manual (the one that applies):
  <https://www.lua.org/manual/5.1/manual.html>
- Documentation index (all versions, books):
  <https://www.lua.org/docs.html>
- Programming in Lua, 1st edition — free online, written for 5.0 but the
  language chapters are close enough to 5.1 to be useful:
  <https://www.lua.org/pil/contents.html>

The later _Programming in Lua_ editions target 5.2 and 5.3. They are good books
and the wrong reference for this repo.

### What using the wrong manual costs

These are all real 5.2+ features that do **not** exist here:

| Feature                      | 5.1 / PZ reality                     |
| ---------------------------- | ------------------------------------ |
| `goto` / `::label::`         | Not available. No `continue` either. |
| `table.unpack`               | It is the global `unpack`.           |
| Integer division `//`        | Not available. `math.floor(a/b)`.    |
| Bitwise operators            | `& \| ~ << >>` not available.        |
| Integer subtype (5.3+)       | All numbers are floats.              |
| `load` on a string           | Use `loadstring`.                    |
| `\z` and `\x` string escapes | Not available.                       |

Each row above was checked by parsing a snippet with `luaparse` in `luaVersion:
'5.1'` mode (the repo's own parser, `two-man-crew/check-lua.mjs`). All five
constructs are rejected; `unpack` parses. Note this proves only what the 5.1
_grammar_ rejects — for library-level questions, grep the shipped game source.

A comment in the shipped source settles the `goto` point directly:

```lua
-- server/metazones/metazoneHandler.lua:92
-- Lua seriously needs a "continue", and yes, i refuse to use goto :D
```

## Where PZ deviates from stock 5.1

Kahlua is not a complete 5.1 runtime, and the game sandboxes parts of it. Verified
by grepping all ~1,400 shipped Lua files (word-boundary matched, so
`Scenarios.Trailer` does not count as `os.Trailer`).

### `require` uses slash paths, not dots

The single most common deviation, and the one most likely to bite. Stock Lua
maps `require "a.b"` through `package.path`. PZ resolves a **slash-separated
path relative to a `media/lua/{client,server,shared}` root**, with no extension.

```lua
require "TimedActions/ISBaseTimedAction"   -- correct, PZ style
require "TimedActions.ISBaseTimedAction"   -- wrong, dot notation
```

Counts across the shipped source: 1,112 slash-form paths, **zero** dot-form.
Quote style is free (`require "x"`, `require 'x'`, `require("x")` all appear).

### Standard library — what the game actually touches

| Library      | Shipped-source usage                                  |
| ------------ | ----------------------------------------------------- |
| `string`     | Heavy. `string.format` in 65 files.                   |
| `table`      | Heavy.                                                |
| `math`       | Heavy, including `math.fmod`.                         |
| `os`         | **One** call in the entire game: `os.date`.           |
| `io`         | **Zero** uses. Do not reach for it.                   |
| `coroutine`  | **Zero** uses.                                        |
| `debug`      | **Zero** uses.                                        |
| `loadstring` | 8 uses. `load()` on a string is not the 5.1 spelling. |

**File I/O does not go through `io`.** PZ provides its own engine functions —
`getFileWriter` / `getModFileWriter` — and as of a recent build `getFileWriter`
is restricted to `ini`, `cfg`, `txt`, `log`, `json` extensions
(`getModFileWriter` is not restricted). See `api-documentation-sources.md`.

A zero count means "the vanilla game never does this", which is strong evidence
about what is idiomatic and supported. It is not the same as a hard proof the
function is absent — but reaching for something the entire game avoids needs a
reason, and needs in-game testing.

### Error handling

`pcall` and `xpcall` appear **zero** times in the shipped Lua. `error()` appears
in 12 files. The engine catches Lua errors and writes them to
`~/Zomboid/Logs/`; the vanilla pattern is to let errors surface there rather
than swallow them locally.

### Instance fields are not readable

Not a Lua-language point but it trips Lua-shaped code: since Build 42.15.0,
reading Java **instance** fields by reflection is debug-mode only. Use getters.
Static fields still read directly. Detail in `lua-api-wiki.md`.

## Which to reach for

| Question                                        | Source                                |
| ----------------------------------------------- | ------------------------------------- |
| Syntax, semantics, metatables, scoping          | 5.1 manual, sections 2 and 8          |
| A standard library function's exact signature   | 5.1 manual, section 5                 |
| "Is this 5.2+ only?"                            | 5.1 manual — absent means unavailable |
| Learning the language properly                  | Programming in Lua 1st ed             |
| Whether PZ actually supports/uses a stdlib call | grep the shipped source               |
| Engine globals, events, Java classes            | `api-documentation-sources.md`        |

Sections 3 (C API) and 4 (Auxiliary Library) of the manual describe embedding
Lua in a C host. They are irrelevant here — the host is Java, and mods never
touch that layer.
