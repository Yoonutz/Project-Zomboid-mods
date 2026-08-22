# API documentation sources — what to consult, and in what order

Checked 2026-08-22. Three sources were requested for this repo; this file records
what each one actually is, how current it is, and when to reach for it.

Companion files: `luadocs-wiki-note.md` (why the PZwiki LuaDocs page itself is
stale), `lua-api-wiki.md`, `lua-events-reference.md`.

## Access note — two of these block the fetch tool

`pzwiki.net` and `projectzomboid.com` both return **HTTP 403** to the default
WebFetch agent. They serve fine with a browser User-Agent:

```
curl -sL -A "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/131.0.0.0 Safari/537.36" <url>
```

Do not conclude a page is gone because WebFetch 403s it. Retry with curl first.

## 1. Official JavaDocs — <https://projectzomboid.com/modding/index.html>

**The most current of the three, and the ground truth for engine signatures.**
Standard Javadoc of the game's Java classes, hosted by The Indie Stone.

- Generation stamp in the page source: `javadoc (25) on Wed Aug 19 20:42:15 BST 2026`
  — three days before this file was written, so it tracks the live build.
- Navigation: Overview / Tree / Deprecated / Index / Search across the top.
  The **Index** and **Search** links are the fastest way in; browsing packages
  by hand is slow.
- Packages are the `zombie.*` tree: `zombie.characters`, `zombie.characters.skills`,
  `zombie.characters.traits`, `zombie.characters.Moodles`, `zombie.inventory`,
  `zombie.iso`, `zombie.entity.components.crafting`, `zombie.ui`, `zombie.core.*`,
  plus vendored libraries (`org.joml`, `org.lwjglx.*`, `fmod.fmod`,
  `se.krka.kahlua.vm` — Kahlua being the Lua VM the game embeds).

Use it when you need an exact method signature, parameter order, or return type
for anything exposed to Lua. It has no Lua-side usage examples.

## 2. PZ API Documentation (PZwiki page) — <https://pzwiki.net/wiki/PZ_API_Documentation>

**A pointer page, not the reference.** It describes and links to a separate
generated documentation project. Page state: revised for stable **42.20.0**,
with a banner noting parts were auto-updated to **42.20.3**.

The thing it points at:

- Docs: <https://pz-wiki-modding.github.io/PZ-API-Docs/>
- Repo: <https://github.com/PZ-Wiki-Modding/PZ-API-Docs>

That project generates documentation from the game's own data files, covering
**ScriptsDocs, distributions, Java-parsed data, tile properties, translations,
and XML such as AnimNodes** — the data-side counterpart to the JavaDocs.
Useful for item/recipe script fields, procedural distributions, and tile
properties, which the JavaDocs do not describe.

The wiki page also carries a per-build "Modding News" changelog. Recent entries
worth knowing:

- `language.txt` moved to a JSON format (`language.json`).
- `getFileWriter` is now restricted to `ini`, `cfg`, `txt`, `log`, and `json`
  extensions. `getModFileWriter` was **not** restricted.
- `%` must now be escaped in translations (`%%` for a literal `%`).
- New Lua events `RequestMedicalCheck` and `AcceptedMedicalCheck`.
- New faction and foraging sync methods on `LuaManager.GlobalObject`.
- `drawTextWithBackground` added for UI work.
- Newly exposed classes: `CraftRecipe.XpAward`, `StreetPoints`, `Transform`,
  `VirtualVehicle`, `WorldMapStreet`.

Its Java method links point at a community JavaDoc mirror,
`albion.codeberg.page/PZ-JavaDocs/`, which is convenient for deep-linking a
single method but is not the official host — prefer source 1 for signatures.

## 3. FWolfe Zomboid-Modding-Guide — <https://github.com/FWolfe/Zomboid-Modding-Guide>

**Archived read-only on 2026-07-25, and it targets Build 40/41.** Sections:
Mod Structure, Scripts, Code (API), Translations, Maps, Models. Its own README
calls it a work in progress.

Treat it as historical background only. Its script syntax is the B41 dialect
this repo's `CLAUDE.md` explicitly warns against (`Type=` vs `ItemType=`, old
`recipe{}` vs `craftRecipe{}`), and its model guidance stops at `.X`/`.fbx` for
B41. **Never copy script snippets from it into a B42 mod.** The conceptual
chapters on mod folder layout and general Lua structure are still readable, but
this repo already vendors a newer B42-targeted guide at
`docs/pz-modding-guide/` (see its `SOURCE.md`), which supersedes it.

## Which to reach for

| Question                                            | Source                                     |
| --------------------------------------------------- | ------------------------------------------ |
| Exact Java method signature exposed to Lua          | 1, official JavaDocs                       |
| Lua events, callbacks, class-to-source-file mapping | LuaDocs, see `luadocs-wiki-note.md`        |
| Item/recipe script fields, distributions, tiles     | 2, PZ-API-Docs generated site              |
| What changed in a specific 42.x build               | 2, the wiki page's Modding News            |
| Installed game's real behaviour                     | grep the game's own Lua source, see memory |
| B41-era concepts, background reading                | 3, archived and not authoritative          |

The installed game ships its full Lua source and remains the highest-confidence
check for anything ambiguous — a doc says what should happen, the source says
what does. It lives here:

```
D:\Games\Steam\steamapps\common\ProjectZomboid\media\lua\{client,server,shared}
D:\Games\Steam\steamapps\common\ProjectZomboid\media\ui        # UI textures
D:\Games\Steam\steamapps\common\ProjectZomboid\media\scripts   # item/recipe scripts
```

Roughly 1,400 Lua files (728 client, 294 server, 373 shared), 1,004 generated
item/recipe scripts, and 1,538 UI PNGs, as of Steam buildid 24775755.

Scope every search to a subtree and a file type. `media/` also holds maps,
models, sound and textures, so an unfiltered recursive walk over the whole
folder does not finish — `du -sh` on it timed out after two minutes.

A hit under `lua/server/` is what proves a call is server-safe; a hit only
under `client/DebugUIs/` proves nothing about the shipped game.
