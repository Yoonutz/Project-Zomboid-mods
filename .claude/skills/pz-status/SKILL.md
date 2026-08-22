---
name: pz-status
description: Reports what TwoManCrew build is installed and what the live log says. Use when the user asks if the mod is copied, whether the game is running, what the log shows, or before claiming anything about their install.
allowed-tools: Bash, Read
---

# pz-status

## Goal

Answer, in one pass, everything about a TwoManCrew build: whether the game is running,
whether the installed tree matches the repo file by file, which log is live, what the mod
threw and where, and the worst cost per background pass. Success is a single report that
needs no follow-up commands. It replaced five that were being re-run several times an hour.

## Inputs

- `-Sync` - copy the repo over the mods folder before reporting. Optional; reports only without it.
- `-Repo`, `-Mods`, `-Logs` - path overrides. All default to this machine's real locations.

## Scripts

- `status.ps1` - does everything below; changes nothing unless `-Sync` is passed.

## Process

1. Report only, the normal case:

   ```powershell
   & ".claude/skills/pz-status/status.ps1"
   ```

2. Copy first, then report. Refuses while the game runs, and refuses if the destination is a link:

   ```powershell
   & ".claude/skills/pz-status/status.ps1" -Sync
   ```

3. Read the INSTALL section. `identical` is the only passing state; a version match alone is not.

4. Read the LOG section for a stale warning BEFORE trusting MOD ERRORS. A quiet log during a
   running game means the errors shown belong to a session that already ended.

5. Report `Unverified` regardless of how clean the output is, until someone has looked at the screen.

## Outputs

The ONLY deliverable is the printed report. It writes nothing except during `-Sync`, which
replaces the installed mod folder.

## Edge Cases

| Situation                            | What happens                                               |
| ------------------------------------ | ---------------------------------------------------------- |
| Game running and `-Sync` passed      | Refuses. Deploying under a live session is destructive     |
| Destination is a junction or symlink | Refuses rather than writing through the link               |
| Newest log quiet while game runs     | Prints a stale warning; its errors are from a dead session |
| No claim in the save yet             | TIMINGS reports none; the pass exits early with no work    |
| Pass costs 16 ms or more             | Flagged as over one frame at 60fps                         |

Two traps this exists for, both hit in real use. A matching version number proves nothing: a
half-copied tree carries the new `mod.info` and the old Lua, so every file is hashed instead.
And a log that stopped updating is from a finished session - reading one produced a
confidently wrong "no errors" here once.

Nothing it prints means the mod works. A clean report means the code loaded and did not throw.
See `.claude/memory/pz-verification-is-ingame-only.md`, and
`.claude/memory/pz-hot-reload-lua-without-restarting.md` for iterating without a restart.

## Environment

None. No env vars, no secrets, no network. Paths default to this machine and are overridable.
