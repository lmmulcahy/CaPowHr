---
name: spec
description: Interview the human about a feature until its acceptance criteria are unambiguous, then write docs/specs/<feature>.md (Status draft). No code changes.
argument-hint: <feature-slug> [one-line idea]
disable-model-invocation: true
---

# /spec $ARGUMENTS

You are writing a feature spec for CaPowHr. The first word of the arguments is
the feature slug (kebab-case, e.g. `pause-reminder`); anything after it is the
human's initial idea. If no slug was given, ask for one.

**Do not touch code, tests, or project files in this command.** The only file
you write is `docs/specs/<feature>.md`.

## 1. Ground yourself (read-only)
- Read `CLAUDE.md`, `docs/PRD.md`, `docs/ARCHITECTURE.md`, `docs/specs/_TEMPLATE.md`.
- If `docs/specs/<feature>.md` already exists, read it: you are revising, not starting over.
- Read the code the feature will touch so your questions are concrete.

## 2. Enter plan mode and interview
Call `EnterPlanMode`. Interview the human with `AskUserQuestion` (batch up to
4 questions per round, offer concrete options with a recommended default).
Keep going until every acceptance criterion is testable and unambiguous. Cover:
- The exact user-visible behavior, on the watch, step by step.
- Edge cases: no sensor connected, sensor drops mid-workout, paused workout,
  display-only mode (HealthKit denied), each workout type (ride/run/walk/row),
  units (mi/km), auto-save vs ask-every-time, app backgrounded.
- Failure states and what the user sees.
- Persistence: does anything new get stored (UserDefaults, App Group, Keychain,
  HealthKit, files)? What happens to existing users' stored values?
- Which risk paths in `CLAUDE.md` are touched.
- What is explicitly **out of scope**.
- How each AC will be tested: unit test (preferred: pure logic extracted from
  managers/views), UI test, or manual-only (must be justified).

Don't ask what the code can answer. Don't pad with questions that don't change the spec.

## 3. Present and write
When the ACs are unambiguous, present the full draft spec via `ExitPlanMode`.
After the human accepts it, write `docs/specs/<feature>.md` from
`docs/specs/_TEMPLATE.md` with:
- `**Status:** draft`
- Numbered, individually testable ACs (AC1, AC2, ...).
- Design listing affected files, data/model changes, edge cases, risk paths touched.
- Plan: check-boxed tasks ordered by dependency. Task 1 is always
  "Write failing tests for AC…" in `CaPowHr Watch AppTests/<FeatureName>Tests.swift`.
  Each later task is small enough to implement and verify on its own.

## 4. Stop
Tell the human the spec path and ask them to review it. They approve by saying
so (you then change Status to `approved`, and only then) or by editing the file
themselves. Do not start `/build`.
