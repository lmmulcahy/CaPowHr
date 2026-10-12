# Decisions log

Append-only. Newest at the bottom. Each entry: date, decision, why,
alternatives rejected. Entries before 2026-10-11 were reconstructed from git
history and code during workflow setup. **[?]** marks reasons inferred, not recorded.

---

### 2025-09-15 — Standalone watch app; equipment data over Watch estimates
- **Decision:** Record from BLE equipment directly on Apple Watch; write the app's own HR and distance samples and disable HealthKit's automatic collection of those types.
- **Why:** The machine's distance/HR is the ground truth for indoor work; letting both write would double-count totals (comment in `HealthKitManager.beginWorkout`).
- **Rejected:** Letting HealthKit auto-collect everything (double counting); phone-hosted recording.

### 2026-07-10 — Trim the 2.3 feature set
- **Decision:** Remove structured workouts, training zones/zone banner, and the tested-equipment log; make FIT export opt-in.
- **Why:** Barely surfaced in the UI (e.g. structured workouts defaulted to "Free" with no phases); reduce surface area before release.
- **Rejected:** Keeping little-used features.

### 2026-07-10 — Shared code lives in `Shared/`
- **Decision:** Deduplicate cross-target files (Keychain, Strava config) into `Shared/`.
- **Why:** Copies had drifted between targets.

### 2026-08-08 — Apple owns workout calories by default
- **Decision:** Active energy comes from Apple's HR-based estimate (matches the Move ring) unless the machine demonstrably reports rising energy and the user picked Equipment (`EnergyOwnership`). Made user-selectable 2026-08-25 (`calorieSource`).
- **Why:** Field report: a ride the machine scored ~375 kcal saved as ~62 kcal and dropped the Move ring. Machines without FTMS Expended Energy fell through to power-integrated energy, which reads far low.
- **Rejected:** Always trusting the machine; always ignoring it.

### 2026-08-08 — Two release trains
- **Decision:** `release/2.2.1` gets fixes only; `main` is relabeled 3.0 for new work.
- **Why:** Ship field fixes without waiting on 3.0 scope.

### 2026-08-08 — Declare `bluetooth-central` background mode; reconnect after drops
- **Decision:** Keep BLE alive in background and auto-reconnect the machine mid-workout.
- **Why:** `workout-processing` alone keeps the app running but not Core Bluetooth delivery while backgrounded (power/cadence gaps when the user crowned out). A device log then showed the bike dropping mid-ride and the app never reconnecting, because on disconnect it only rescanned. The log overturned the earlier diagnosis from field reports.

### 2026-08-22 — FTMS Control Point handshake
- **Decision:** Write Request Control + Start/Resume to the FTMS Control Point; discover only characteristics actually used.
- **Why:** [?] Not recorded in the commit; presumably some machines only stream or behave correctly once a client takes control. Not yet verified on hardware (STATE.md next step).
- **Rejected:** Passive notify-only.

### 2026-08-25 — Secrets via gitignored local xcconfig
- **Decision:** Track a blank `Config/Secrets.xcconfig` that includes gitignored `Secrets.local.xcconfig`.
- **Why:** Xcode Cloud must build from a clean checkout; secrets must not be in git.

### 2026-09-03 — Watch-only; remove the iOS companion
- **Decision:** Remove the incomplete iOS companion app and WatchConnectivity bridge; keep an empty iOS container target for App Store packaging.
- **Why:** Companion was incomplete; Strava OAuth works on-watch; ITMS validation needed a clean watch-only container.
- **Rejected:** Finishing the companion.

### 2026-10-10 — Share BLE logs via the share sheet
- **Decision:** BLE diagnostic logs are shared through the system share sheet (Messages/Mail).
- **Why:** The previous GitHub-issue upload required bundling a token in the app.
- **Rejected:** GitHub API upload with a bundled token.

### 2026-10-11 — Spec-driven, verify-don't-review workflow
- **Decision:** Full-Path changes go `/spec` → approval → `/build` (tests first, human-locked) → `/ship` (verify + independent reviewer). Enforcement by hooks: `scripts/verify.sh` gate on Stop and pre-commit, PreToolUse test lock.
- **Why:** The owner approves specs and uses the app rather than reading diffs; correctness has to be enforced mechanically.
- **Rejected:** Running the full verify on every Stop (90 s per reply). Instead it runs only when the build-relevant fingerprint changed. Also rejected adding SwiftLint during setup (new dependency).
