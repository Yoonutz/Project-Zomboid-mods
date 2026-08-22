---
name: pz-api-doc-sources-ranked
description: "Which external PZ modding doc source to trust for what, and the User-Agent needed to fetch two of them"
metadata:
  node_type: memory
  type: reference
  originSessionId: 688ba461-5b6d-450d-9ebb-0e2c1c38517a
  modified: 2026-08-21T23:36:51.721Z
---

Ranked in `docs/api-documentation-sources.md` (checked 2026-08-22). The short version:

- **Official JavaDocs** (`projectzomboid.com/modding/index.html`) — regenerated
  2026-08-19, tracks the live build. Ground truth for Java method signatures
  exposed to Lua. Use its Index/Search, not package browsing.
- **PZwiki "PZ API Documentation"** — a pointer page, not a reference. The real
  artifact is <https://pz-wiki-modding.github.io/PZ-API-Docs/>, generated from the
  game's data files: script fields, distributions, tile properties, translations.
  The wiki page also carries a per-build "Modding News" changelog.
- **FWolfe/Zomboid-Modding-Guide** — archived 2026-07-25, targets Build 40/41.
  Background reading only. Never copy its script syntax into a B42 mod; this repo
  already vendors a newer B42 guide at `docs/pz-modding-guide/`.

**Why this is worth remembering:** `pzwiki.net` and `projectzomboid.com` both return
HTTP 403 to the default WebFetch agent, so a fetch failure reads as "page gone" when
the page is fine. Both serve normally to curl with a browser User-Agent. Don't
re-diagnose this each time.

**How to apply:** signature question goes to the JavaDocs, data/script-field question
goes to PZ-API-Docs, anything ambiguous goes to the installed game's own Lua source
([[pz-vanilla-source-is-the-api-reference]]). Lua events and class-to-file mapping
still come from LuaDocs, per `docs/luadocs-wiki-note.md`.
