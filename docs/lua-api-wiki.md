# Lua (API) — notes from PZwiki

Fetched 2026-08-13 from `https://pzwiki.net/wiki/Lua_(API)`, revision current
for build **42.20.2** (page's own version category, confirmed current — unlike
the LuaDocs page, see `luadocs-wiki-note.md`).

## What it is

PZ's Lua is Kahlua (Java implementation of Lua 5.1) with exposed Java classes
and methods. Only **public** Java members are exposed. Two call syntaxes:

- Static method: `ClassName.methodName(args)` — e.g. `IsoPlayer.getPlayers()`
- Instance method: `instance:methodName(args)` — e.g. `player:getMoveSpeed()`
- `LuaManager.GlobalObject` static methods are called like bare global
  functions: `getPlayer()`, `getCell()`.

Class objects from Java are **not** Lua tables — they're direct links to Java
classes and don't behave like ordinary Lua objects.

## Instance fields — important B42 change

As of **Build 42.15.0**, direct instance-field access via reflection is
restricted to debug mode only (security). Static fields are still accessible
directly: `local x = IsoPlayer.SOME_STATIC_FIELD`. For instance data, use the
class's getter methods instead of reflecting into fields.

## Folder structure (confirms pz-modding-guide)

```
media/lua/client/   ← client-side
media/lua/server/   ← server-side, only loaded when a save is actually running
media/lua/shared/   ← loaded by both
```

Load order: shared (vanilla) -> shared (mods) -> client (vanilla) -> client
(mods); server subfolder loads separately, only while a save is active, in the
same vanilla-then-mods order. Put mod files in a subfolder named after the mod
to avoid filename collisions with vanilla or other mods' files — a same-path
file silently overwrites another.

## Where to start

Programming with the Lua API in practice means hooking a `Events.<Name>.Add(fn)`
event, per `docs/lua-events-reference.md`. When an event doesn't cover what's
needed, the wiki's own steer is to check vanilla code or a similar mod, not to
assume something exists.
