# CaPowHr — Product Requirements

> **DRAFT — needs human review.** Reverse-engineered from the code on `main`
> (commit `df2d468`, 2026-10-11), README, AppStoreCopy.md and git history.
> Statements marked **[?]** are guesses or open questions for the owner.

## Problem
Indoor workouts on Bluetooth gym equipment (smart bikes, treadmills, rowers)
produce good data, such as power, cadence, distance and machine HR, that never reaches
Apple Health unless the user runs a phone app or a vendor app. Apple Watch's
built-in indoor workouts estimate distance and ignore the machine. Users who
train indoors want one Watch-only tap to record the machine's real numbers
into Health, closing their rings correctly.

## Target user
A person who does indoor cardio on BLE-equipped equipment (FTMS bike,
treadmill or rower, or a bike with Cycling Power / CSC sensors), wears an
Apple Watch (Series 4+, watchOS 11.5+), and wants the workout in Apple Health
without carrying or using an iPhone during the session. Secondary: riders
who also log to Strava. **[?]** Is Strava still a target? See Open questions.

## Core features (as built)
1. **Start a workout** of type Ride, Run, Walk or Row from the watch, with or
   without sensors pre-connected. The app scans and connects during the workout.
2. **Connect BLE equipment**: FTMS (0x1826) bike/treadmill/rower data,
   Cycling Power (0x1818), CSC (0x1816). Auto-detects device type. Trusted
   devices are remembered and auto-reconnected, including after a mid-workout drop.
3. **Live metrics** per workout type with a user-customizable 4-metric layout:
   HR, power, cadence, speed, distance, incline, pace/500 m, stroke rate, calories.
4. **Heart-rate source**: Auto (prefer equipment HR), Equipment, or Apple Watch.
5. **Calorie source**: Apple Watch estimate (default, matches Move ring) or
   the machine's own counter.
6. **Distance**: FTMS total distance → CSC wheel revolutions → speed integration fallback.
7. **Pause/resume, manual laps, confirm-before-stop.**
8. **Post-workout summary** (averages, laps), then Save or Discard; or
   **auto-save** mode that skips the summary.
9. **Save to Apple Health**: the workout plus HR, power, cadence, distance, speed and active energy.
   **Display-only mode** when Health write permission is denied (nothing saved).
10. **Units**: miles or kilometers.
11. **FIT export** (opt-in setting) from the summary screen via the share sheet.
12. **Strava upload** (optional): on-watch OAuth; after save, creates a manual
    activity (name, type, time, distance, averages).
13. **Watch complication**: quick-start the last workout type.
14. **BLE log capture** (Settings): 20-second diagnostic recording shared via
    the system share sheet (Messages/Mail).

## Non-goals (inferred)
- No iPhone app. The companion app was removed (PR #14, 2026-09-03).
- No outdoor/GPS workouts.
- No structured workouts, training zones or zone banners (removed, PR #4).
- No equipment control (resistance/incline) yet. **[?]** Backlog item, since the FTMS Control Point handshake now exists.
- No accounts or backend of our own; no analytics.
- No in-app purchases.

## Open questions for the owner
- **[?] Strava.** The code, README and FeatureFlags still ship Strava, but a local
  `remove-strava-integration` branch exists. Keep, hide, or remove for 3.0?
- **[?] 3.0 scope.** STATE.md says "decide the rest of the 3.0 scope". What's in it?
- **[?] Distance unit default.** It's hard-coded to miles; the backlog suggests using the locale.
- **[?] Success metric.** What does "working" mean? E.g. the saved workout's
  distance/calories match the machine within X%.
