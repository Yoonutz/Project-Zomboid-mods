---
name: pz-status
description: Use when checking whether a TwoManCrew build is installed, whether the game is running, or whether the mod has thrown anything - and before reporting any claim about what the player is running or what their log says.
---

# pz-status

One pass over everything worth knowing about a TwoManCrew build: what is installed,
whether it matches the repo, whether the game is running, and what the **live** log says.

Replaces five hand-run commands that were being repeated several times an hour.

## Run it

```powershell
& ".claude/skills/pz-status/status.ps1"          # report only, changes nothing
& ".claude/skills/pz-status/status.ps1" -Sync    # copy repo -> mods folder first
```

`-Sync` refuses while the game is running, and refuses if the destination is a link.

## What it answers

| Section    | The question it settles                              |
| ---------- | ---------------------------------------------------- |
| GAME       | Is Project Zomboid running right now                 |
| SYNC       | Did the copy happen, or why it was refused           |
| INSTALL    | Does the installed tree match the repo, file by file |
| LOG        | Which log is live, and is it stale                   |
| MOD ERRORS | Which file and line threw, and how many times        |
| TIMINGS    | Worst cost per pass, flagged if over one frame       |

## Two traps it exists to stop

**A matching version number proves nothing.** A half-copied tree carries the new
`mod.info` and the old Lua. It looks correct from the outside and behaves like the
build you thought you replaced. This hashes every file instead.

**A log that stopped updating is from a session that ENDED.** Reading one and
reporting "no errors" says nothing about the build now installed. That mistake was
made here once, and produced a confidently wrong answer. The script warns when the
game is running but the newest log has gone quiet.

## What it does NOT tell you

Whether the mod works. Nothing here renders a pixel. A clean report means the code
loaded and did not throw - not that the panel is usable, laid out correctly, or
showing the right thing.

Reports still say `Unverified` until someone looks at the screen. See
`.claude/memory/pz-verification-is-ingame-only.md`.

## Hot reload

For iterating on the journal window without restarting, see
`.claude/memory/pz-hot-reload-lua-without-restarting.md`. Only that one file is safe
to reload; every other file hooks events at load and would double-register.
