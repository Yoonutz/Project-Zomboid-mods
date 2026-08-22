---
name: pz-sendservercommand-is-mp-only
description: "sendServerCommand is a network send and reaches nobody in singleplayer - OnServerCommand never fires solo, so any request/reply feature needs a local dispatch path"
metadata:
  node_type: memory
  type: project
  originSessionId: 22191151-f982-426b-8b95-9c0e6caccbb7
  modified: 2026-08-22T09:55:26.687Z
---

`sendServerCommand(player, module, command, args)` is a **network** send. In singleplayer there
is no network client to deliver to, so `Events.OnServerCommand` never fires and the reply is
silently dropped. `sendClientCommand` / `Events.OnClientCommand` **do** work solo, which makes
this maximally confusing: the request arrives, the handler runs, and only the answer vanishes.

Measured in the live game 2026-08-22: the log showed the server receiving 14 commands and
replying to none. Refresh looked dead and Claim hung on "Surveying the block..." for that
reason alone - both halves were otherwise working.

Vanilla never trips over this because nothing solo depends on that path:

- `server/Foraging/forageServer.lua:1` returns unless `isServer()`.
- `server/ClientCommands.lua`'s only reply targets a player from `getPlayerByOnlineID`, a
  multiplayer lookup.
- Client code makes the round trip conditional instead: `if isClient() and _character then`
  at `client/Foraging/forageClient.lua:40`, calling the logic directly when solo.

**Why:** three consecutive builds were shipped against wrong theories for this symptom, because
the code reads as though it must work - the send is right there and the handler is registered.
Only running the game and reading `~/Zomboid/Logs/` showed which link was broken.

**How to apply:**

- Anything expecting a REPLY goes through the mod's own helpers in
  `shared/TwoManCrew/TwoManCrew_Config.lua`: `TwoManCrew.requestFromServer` and
  `TwoManCrew.replyToPlayer`. Never call `sendClientCommand`/`sendServerCommand` directly for a
  request/reply pair.
- Every server module registers its handler with `TwoManCrew.registerLocalHandler(command, fn)`
  next to its `Events.OnClientCommand.Add`, so one implementation serves both worlds.
- `isClient()` and `isServer()` are BOTH false in singleplayer, which is what makes
  `TwoManCrew.isNetworked()` a reliable single test.
- Fire-and-forget commands (XP awards, danger warnings) are unaffected - only the reply is lost.
- **Beware ordering once the reply is inline.** Solo, `replyToPlayer` runs before
  `requestFromServer` returns. Set any pending flag or optimistic message BEFORE dispatching, or
  the reply clears it and the next line re-raises it forever. That bug cost a build on its own.

Related: [[pz-instrument-before-fixing-runtime-faults]], [[server-files-need-isclient-guard]].
