---
name: work-on-master-no-branches
description: "Standing instruction from 2026-08-22: commit directly to master and push there - no feature branches, no worktrees, no pull requests, and never suggest one"
metadata:
  node_type: memory
  type: feedback
---

**Commit directly to `master` and `git push origin master`.** No feature branches, no git
worktrees, no pull requests.

Set 2026-08-22, in these words: _"Stop doing branches. Push everything on main."_ It replaced
the earlier flow, which had produced `Merge pull request #1` and a
`feature/campaign-task-cards` branch that was merged and deleted the same day it was made.

**Why:** the branch was pure ceremony here. One person works in this repo, nothing reviewed the
branch before it merged, and every branch created a merge step whose only output was moving the
same commits to the same place. The history is the safety net; a branch was not adding one.

**How to apply:**

- Commit to `master` as work completes, and push. Do not ask whether to branch first.
- The global rule "if on the default branch, branch first" is **overridden in this repo**. So is
  `superpowers:using-git-worktrees`, and `superpowers:finishing-a-development-branch` has
  nothing to finish. `docs/conventions/skills.md` records all three.
- Never create a branch "just to be safe", and never offer one as an option. If something needs
  undoing, use the commit history.
- A plan's status banner names a date and a version, never a branch.
- Pushing is still a change, not evidence. It never upgrades a claim: work that has not run in
  Project Zomboid is still reported `Unverified` after a push
  ([[pz-verification-is-ingame-only]]).

Related: [[pz-verification-is-ingame-only]].
