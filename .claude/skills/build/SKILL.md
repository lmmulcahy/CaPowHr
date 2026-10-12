---
name: build
description: Implement the next unchecked task of an approved feature spec, tests first. One task per invocation unless told to continue through the plan.
argument-hint: <feature-slug> ["continue through the plan"]
disable-model-invocation: true
---

# /build $ARGUMENTS

The first word of the arguments is the feature slug. Spec: `docs/specs/<feature>.md`.

## 0. Preconditions (stop if any fail)
- The spec exists and its Status line is `approved` or `in progress`.
  If it is `draft`, stop: "Spec is still draft — approve it first."
- You are on a feature branch, not `main`. If on `main`, create
  `feature/<feature>` from an up-to-date `main` first.
- Working tree has no unrelated uncommitted changes.
- Set Status to `in progress` if it was `approved`.

## 1. Tests first
Feature tests live in `CaPowHr Watch AppTests/<FeatureName>Tests.swift`
(Swift Testing: `import Testing`, `@Test`, `#expect`). The project uses
folder-synced groups, so a new file there is picked up automatically — do not
edit `project.pbxproj`.

Read `.claude/test-lock`. If the feature's test file is **not** yet locked:
1. Write tests for every AC that is not manual-only. Name each test after its
   AC, e.g. `@Test("AC3: auto-save skips the summary screen")`. Each test must
   assert the behavior, not just exercise code.
2. If the tests need new types or functions to compile, add the **minimum**
   stubs in app code (signatures returning placeholder values) so the suite
   compiles and fails on assertions, not on compile errors.
3. Write the feature slug to `.claude/.verify-state/red-phase`. This tells the
   Stop hook that failing tests are expected, so only a broken *build* blocks
   a stop. The red phase lasts until `scripts/verify.sh` passes, which ends it
   automatically; locking the tests does not end it.
4. Run `scripts/verify.sh` and show the human the failing test names from
   the summary/log. Every new test should fail; a test that already passes is
   suspicious. Say so.
5. Stop and ask the human to review the tests and lock them:
   `! scripts/lock-tests.sh "CaPowHr Watch AppTests/<FeatureName>Tests.swift"`
   (they can also run it in a terminal). Tick the test task in the spec only
   after they lock. Do not continue until the file is in `.claude/test-lock`.
   **Do not commit yet:** the pre-commit hook rejects a red suite. The tests,
   stubs and lock line are committed together with the first task that
   turns verify green (see step 2.5).

You cannot edit `.claude/test-lock` or run the lock scripts; the hooks will
block you. Don't try to work around them.

## 2. Next task (tests are locked)
Take the first unchecked `- [ ]` task in the spec's Plan:
1. Implement it. Use existing dependencies only; touch only what the task needs.
2. Run `scripts/verify.sh`. Fix until it passes. Never edit locked tests,
   weaken assertions, add `.disabled`/`withKnownIssue`, or skip tests. If a
   locked test seems wrong, stop and explain which assertion and why.
3. Tick the task's checkbox in the spec.
4. If the implementation departed from the spec in any way, add a line to the
   spec's Deviations section (what, where, why). If a real design decision was
   made, append it to `docs/decisions.md`.
5. Commit only the files you changed (no `git add -A`), message
   `<feature>: <task>`. The pre-commit hook re-runs verify if needed.
   While the suite is still red (an earlier task's tests need a later task),
   don't commit. Tick the box, carry on to the next task, and commit all of
   them, plus the locked tests and lock line, as one commit once verify is
   green. Note the grouping in the spec's Deviations.

Then stop and report: the task done, verify result (from the log summary),
and the next task. If the human said "continue through the plan", repeat
step 2 for each remaining task, stopping immediately on anything that needs
a human decision.

When every task is ticked, say so and suggest `/ship <feature>`.
