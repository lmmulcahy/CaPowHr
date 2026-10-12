---
name: drift
description: Audit CLAUDE.md, docs/PRD.md, docs/ARCHITECTURE.md and open specs against the actual code; write findings to docs/drift/YYYY-MM-DD.md without fixing anything.
disable-model-invocation: true
---

# /drift

Audit the project's documentation against the code as it is now on the
current branch. **Report only; apply no fixes until the human approves.**

## Check
- **CLAUDE.md**: commands still work as written (run `scripts/verify.sh`);
  every risk-path file/dir listed still exists, and no new file belongs on the
  list (new persistence keys, Keychain use, network calls, deletion paths,
  BLE writes, entitlements); Lessons still relevant; under ~80 lines.
- **docs/PRD.md**: features listed exist and work as described; features in
  code that are missing from the PRD; non-goals the code now violates.
- **docs/ARCHITECTURE.md**: every file, type, UserDefaults key, App Group,
  Keychain item, HealthKit type, BLE UUID and external endpoint mentioned
  still exists with that meaning; new ones are documented.
- **docs/specs/*.md** with Status other than `shipped`: plan checkboxes
  vs. code, stale `in progress` specs, approved specs never started.
- **README.md / STATE.md** contradictions with the above (report only).

Use `git ls-files`, Grep, and Read. Cite file:line for every mismatch.

## Write
Create `docs/drift/<today as YYYY-MM-DD>.md`:

```
# Drift audit YYYY-MM-DD (commit <short hash>)

| # | Doc | Claim | Reality (file:line) | Proposed fix |
|---|-----|-------|---------------------|--------------|
```
followed by a one-paragraph summary. If nothing drifted, say so.

Then stop and ask which fixes to apply.
