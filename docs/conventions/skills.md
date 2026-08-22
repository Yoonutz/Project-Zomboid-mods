# Skills

Auto-loaded into every session via `CLAUDE.md`. Rules, not background.

The global superpowers catalog in `~/.claude/CLAUDE.md` applies here as written.
Invoking a matching skill is mandatory, not advisory. This file does not repeat the
catalog — it records what each skill collides with **in this repo**, because most of
them meet a constraint here that changes how they run.

## Branching: there is none

**Work directly on `master` and push there.** No feature branches, no
worktrees, no pull requests. Set 2026-08-22 by the repo owner, replacing the
earlier PR-based flow.

The practical consequences, since several skills below assume otherwise:

- Commit to `master` as work completes, and `git push origin master`.
- Never create a branch "for safety" and never suggest one. If work needs to be
  undone, that is what the commit history is for.
- A plan's status banner names a version and a date, not a branch.

## Before writing code

- `superpowers:brainstorming` — before any new mod, new UI surface, or behaviour
  change. **Invoke it as the first action of the turn, before reading a single
  source file.** Exploring the code first is the failure mode this rule exists to
  stop: it looks like diligence, it silently commits to the existing design, and it
  arrives at the skill with an answer already formed. "I am only orienting myself"
  is not an exemption — a request to redesign, restructure, or make something
  "more intuitive" is creative work from its first word, and the skill runs first.
  Its visual-companion scratch lands in `.superpowers/`, which is gitignored on
  purpose: mockups and session state are local, never committed.
- `superpowers:writing-plans` — before multi-step mod work. Plans live in
  `docs/superpowers/plans/<date>-<slug>.md` and are committed. Two sections
  below are mandatory in every plan: the status banner and the implementer
  context.
- `superpowers:writing-skills` — before creating or editing a skill. New skill
  creation needs prior approval, and a project skill gets a row in this file.

## While implementing

- `superpowers:test-driven-development` — required **before** writing any test,
  probe, benchmark, or instrumented copy of a source file. No skill invocation
  means no test: make the fix and verify by diff instead. Tests improvised
  after the fact cannot fail, so they prove nothing. Running the checks this
  repo already has (`npm run check` in `two-man-crew/`) is not authoring a
  test. There is no local test suite to add cases to: see the deleted-harness
  note in `lua-and-checks.md`. A behaviour claim is proved in-game or not at
  all.
- `superpowers:executing-plans` — running a committed plan in a fresh session,
  task-by-task with checkpoints. Preferred when the plan's tasks are sequential
  or share files.
- `superpowers:subagent-driven-development` and
  `superpowers:dispatching-parallel-agents` — running independent plan tasks.
  **Partition agents by file, never by task number** — tasks here overlap
  heavily and task-partitioned agents collide. Agents are forbidden from
  committing, editing `mod.info`, touching `types/pz.lua`, or running
  `lua-language-server` (it is whole-repo, so it reports other agents'
  in-progress edits as phantom errors). The controller commits once and bumps
  `modversion` once for the batch, then checks the cross-file seams by hand —
  no agent can see across its own boundary. Full protocol:
  `.claude/memory/parallel-agents-by-file-ownership.md`.
- `superpowers:using-git-worktrees` — **do not use it here.** Work happens
  directly on `master` and is pushed there; see the branching rule below.

## Debugging

- `superpowers:systematic-debugging` — before proposing a fix for any bug, test
  failure, or odd behaviour. In this repo its evidence step usually cannot be
  satisfied locally: a fault that only reproduces in-game gets
  **instrumentation first, fix second**. Add `print()` at each candidate break
  point, ship that, ask for one run, then fix what the log names.
  `npm run diagnose` reads the newest log and prints the command chain in
  order, so the first `NO` is the broken link. Check the log's timestamp
  against the install's — an old log has twice nearly produced a false
  conclusion.

## Closing out

- `superpowers:verification-before-completion` — invoked in the closing turn of
  any delivered work, alongside the `- [x]` evidence checklist.
- `superpowers:requesting-code-review` — on finishing a major feature. There
  is no merge to gate now, so review happens before the push rather than
  before a merge.
- `superpowers:receiving-code-review` — when acting on review feedback,
  especially feedback that looks wrong. Verify the claim against the game
  source before agreeing or dismissing; see
  `.claude/memory/pz-vanilla-source-is-the-api-reference.md`.
- `superpowers:finishing-a-development-branch` — **not applicable.** There is
  no development branch to finish: commit to `master` and push. "Checks pass"
  here means `npm run check`, which does **not** mean the mod works in-game.

Nothing in this repo can be verified by running the game, so anything needing a
live load is reported unverified rather than propped up with scaffolding built
to manufacture proof.

## What every plan must carry

These two sections are the plan format, not a template to copy from some other
file. A plan missing either one is incomplete.

### 1. The status banner

First thing in the file, before any task. It answers one question: has this code
ever run inside Project Zomboid? Almost always the answer is no, and the banner
says so in those words rather than implying otherwise.

```markdown
> **STATUS: written, NOT TESTED. <date>, version `<x.y.z>`.**
>
> **This code has never been executed.** No Project Zomboid session has loaded
> it. Nothing below is known to work.
>
> What actually ran: <name only the checks that ran>. None of that executes a
> line of the mod. It is proofreading, not testing — it cannot catch a wrong
> method name, a nil at runtime, a wrong event, or a UI that draws garbage.
>
> Every in-game check is OPEN.
```

The trap this exists to stop: `npm run check`, `lua-language-server` and
`prettier` all passing reads as "implemented". It is not. A banner once said
"implemented" and listed those passing gates, which is why the wording is fixed
here. Name the checks that ran, then say what they cannot prove.

Update the banner when the status genuinely changes — a real game load, not a
green check. Version numbers in a plan drift too: per-task version ladders
predict one number and batched commits produce another. Record what actually
happened rather than what the ladder predicted.

### 2. Context for the implementer

Agents arrive with zero repo knowledge, and this codebase has constraints that
cannot be guessed from reading it. State them, or they get "simplified" away.

Cover at least:

- **What the mod is** — one paragraph, including that co-op is the assumption.
- **The constraint that will be violated** — for anything touching world
  geometry, that is chunk loading. A building far from a player is _unreadable_,
  not unrestored: `getCell():getGridSquare(x, y, z)` returns `nil` for unloaded
  ground, so the three-state verdict (`restored` / `not_restored` / `unknown`)
  is load-bearing and must not be collapsed to a boolean. `BuildingDef` and
  `RoomDef` come from the MetaGrid instead, readable anywhere, no chunk loading.
- **How verification works here** — there is no unit-test harness for engine
  code, because it calls globals (`getCell`, `getWorld`, `IsoPlayer`,
  `instanceof`) that exist only inside the running game. Do not have an agent
  invent a mock harness mid-plan. Name the real gates and their limits.
- **Which sub-skill implements the plan** — `superpowers:subagent-driven-development`
  or `superpowers:executing-plans`, with tasks as `- [ ]` checkboxes.
