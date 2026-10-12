# <Feature name>

**Status:** draft <!-- draft | approved | in progress | shipped -->
**Spec file:** `docs/specs/<feature-slug>.md`  ·  **Tests:** `CaPowHr Watch AppTests/<FeatureName>Tests.swift`

## Problem / goal
<!-- What the user can't do today, and what changes for them. 2–5 sentences. -->

## Acceptance criteria
<!-- Numbered; each independently testable. Tests are named after these numbers.
     Mark anything that can only be checked on a real watch as (manual). -->
1. AC1: Given …, when …, then ….
2. AC2: …

## Out of scope
- …

## Design
- **Affected files:** …
- **Data / model changes:** <!-- new UserDefaults keys, raw values, Codable fields, HealthKit types; compatibility with existing stored values -->
- **Edge cases:** <!-- no sensor, sensor drop, paused, display-only mode, each workout type, units, auto-save -->
- **Risk paths touched (from CLAUDE.md):** none / …

## Plan
<!-- Ordered by dependency; each task small enough to verify on its own. -->
- [ ] 1. Write failing tests for AC1–ACn in `CaPowHr Watch AppTests/<FeatureName>Tests.swift`; human locks them
- [ ] 2. …
- [ ] n. Update docs (ARCHITECTURE.md if structure/persistence changed; decisions.md if a real decision was made)

## Deviations
<!-- Filled in during /build: what departed from this spec, where, and why. "none" if none. -->
none
