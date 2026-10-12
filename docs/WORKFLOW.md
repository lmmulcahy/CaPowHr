# How work gets done here (for future me)

You don't read diffs. You **approve specs**, **approve tests**, **read PR
summaries backed by machine evidence**, and **use the app on your watch**.
Everything else is enforced by the repo.

## The loop
```
/spec <feature>  →  you approve the spec  →  /build <feature>  →  tests written, shown failing
      →  you approve & lock the tests  →  /build <feature> (one task per run, or "continue through the plan")
      →  /ship <feature>  →  PR with evidence + reviewer verdict  →  you dogfood on the watch  →  you merge
```

| Command | What Claude does | What you do |
|---|---|---|
| `/spec <slug>` | Plan mode; interviews you; writes `docs/specs/<slug>.md` (Status: draft). No code. | Answer questions, read the spec, say "approved" (or edit it). |
| `/build <slug>` (1st run) | Writes tests from the acceptance criteria, runs them, shows they fail. | Read the test names/assertions, then lock: `! scripts/lock-tests.sh "CaPowHr Watch AppTests/<Name>Tests.swift"` |
| `/build <slug>` | Implements the next plan task, runs verify, ticks the box, logs deviations, commits. | Nothing, or say "continue through the plan". |
| `/ship <slug>` | Full verify (incl. UI tests), drafts the PR, runs the independent `reviewer`, opens the PR. | Read Summary, ⚠️ Human eyeball, and Reviewer verdict. **Install it on your watch and use it.** Tick Dogfood. Merge. |
| `/drift` | Audits CLAUDE.md / PRD / ARCHITECTURE / open specs vs. code → `docs/drift/YYYY-MM-DD.md`. | Pick which fixes to apply. Run monthly-ish. |

**Quick Path** (typo, one-liner, copy, obvious bug, no risk path) skips all of
this: Claude fixes it, verify passes, commit.

## What's enforced (and by what)
| Guardrail | Mechanism | Notes |
|---|---|---|
| Build + unit tests pass | `scripts/verify.sh` | Log with commit hash: `.claude/last-verify.log` (gitignored). That log is the PR evidence. |
| Claude can't stop with a broken build | Stop hook `.claude/hooks/stop-verify.sh` | Runs verify only if uncommitted Swift/project files changed since the last pass. Gives up after 3 retries and tells you. |
| Docs get updated | Same Stop hook | One non-blocking reminder when code changed on the branch but `docs/` didn't. |
| Commits build | `.githooks/pre-commit` | Only when Swift/project files are staged; skipped if that exact tree already passed. `--no-verify` is blocked for Claude. |
| Approved tests can't be bent | PreToolUse hooks `guard-edits.sh` + `guard-bash.sh` | Blocks edits to anything in `.claude/test-lock`, and to the lock, hooks, settings and lock scripts. |
| Someone other than the author checks | `reviewer` subagent | Read-only. Phantom/unreported changes, AC coverage, test weakening, scope creep, risk paths, docs drift. |

The pre-existing test files are locked from day one.

## Your commands
- `scripts/setup.sh`: once per clone/worktree (sets `core.hooksPath=.githooks`).
- `scripts/lock-tests.sh <glob>...`: lock approved tests (also ends the "red phase").
- `scripts/unlock-tests.sh <glob>`: unlock when you agree a test is wrong. No args = list locks.
- `scripts/verify.sh` / `VERIFY_UI=1 scripts/verify.sh`: run the gate yourself.
- Run these in a terminal, or prefix with `!` in Claude Code. Claude itself is
  blocked from running the lock scripts.

## Risk paths
Listed in `CLAUDE.md`: Strava auth/Keychain, stored settings & formats,
HealthKit writes, deletes, Strava/BLE contracts, Info.plist/entitlements,
and the workflow guardrails themselves. A PR touching these lists them under
**⚠️ Human eyeball**. That's the part of a PR worth reading closely, or
testing deliberately on the watch.

## What the machine can't check
- Real BLE equipment, background BLE, HealthKit saving and the Move ring only
  behave for real on a watch. The simulator has no Bluetooth. The **Dogfood**
  checkbox is the actual merge gate.
- The test lock's Bash guard is pattern-based: it stops accidents and
  shortcuts, not a determined adversary. The reviewer is the second line.

## Parallel work
Default to **serial**: one feature at a time. If you want two at once, use a
git worktree per feature (`git worktree add ../CaPowHr-<slug> -b feature/<slug>`,
then `scripts/setup.sh` in it), with one spec per worktree. Folder-synced
Xcode groups mean `project.pbxproj` rarely conflicts. **Integration deserves
extra verification**, since nobody reviews the merge: after merging the first
PR, rebase the second, re-run `/ship` (fresh verify + reviewer), and dogfood
both features together.

## Changing the guardrails
Claude can't edit `.claude/settings.json`, `.claude/hooks/`, `.githooks/`,
`.claude/test-lock`, or the lock scripts. You edit those by hand. Claude
*can* propose the change and explain it. `scripts/verify.sh` is editable
(e.g. to add SwiftLint later) but is on the risk-path list.
