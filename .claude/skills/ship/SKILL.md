---
name: ship
description: Verify a finished feature, draft the PR description, get an independent reviewer verdict, and open the PR.
argument-hint: <feature-slug>
disable-model-invocation: true
---

# /ship $ARGUMENTS

The first word of the arguments is the feature slug. Spec: `docs/specs/<feature>.md`.

## 1. Preconditions
- All Plan checkboxes in the spec are ticked. If not, stop and list what's left.
- Working tree is clean (everything committed). Branch is not `main`.

## 2. Verify (full, including UI tests)
Run `VERIFY_UI=1 scripts/verify.sh`. If it fails, fix (never weaken tests) and
re-run. The evidence is the block from `=== VERIFY SUMMARY ===` to the end of
`.claude/last-verify.log`, and its commit hash must equal `git rev-parse --short HEAD`.

## 3. Draft the PR description
Write `docs/specs/<feature>.pr.md` following `.github/pull_request_template.md`:
- **Summary**: behavior changes in plain language, each tagged with AC numbers.
- **Deviations from spec**: copied from the spec's Deviations, or "none".
- **Verification evidence**: paste the summary block verbatim. Do not paraphrase.
- **Tests**: list added/changed test files and tests. List any changed
  assertion explicitly (should normally be none).
- **Human eyeball**: every changed file that's on the CLAUDE.md risk-path list,
  with one line each, or "none". Check with
  `git diff --name-only main...HEAD` against the list. Don't rely on memory.
- **Reviewer verdict**: leave as "pending".
- **Dogfood**: leave the checkbox unticked. Only the human ticks it.

## 4. Independent review
Launch the `reviewer` subagent (Agent tool, `subagent_type: reviewer`) with:
the feature slug, base branch `main`, spec path, and PR draft path. Do not
summarize the change for it. It must form its own view from the diff.

- **FAIL**: fix each finding (code, tests-not-locked, or docs, never locked
  tests), commit, return to step 2. After 3 FAIL rounds, stop and show the
  human the findings instead of looping.
- **PASS / PASS WITH NOTES**: paste the verdict and any notes into the
  Reviewer verdict section.

## 5. Open the PR
- Set the spec Status to `shipped` and commit the spec + `.pr.md`.
- Push the branch and run
  `gh pr create --base main --title "<feature>: <short summary>" --body-file docs/specs/<feature>.pr.md`.
  If `gh` is unavailable or fails, leave the description in
  `docs/specs/<feature>.pr.md` and tell the human.
- Do not merge. Report the PR URL, the verdict, and the Human eyeball list.
  Remind the human the Dogfood checkbox is the merge gate.
