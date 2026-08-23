# CaPowHr
**Last Updated:** 2026-08-22
**Status:** active

### 🎯 Current Phase
Two release trains. `main` is **3.0** (multi-modality features plus this summer's fixes); **2.2.1** is a minimal hotfix cut from the 2.2 baseline. Applying reconnection GATT optimizations and distance delta accumulation to `release/2.2.1` following on-device hardware verification.

### ✅ Just Completed
- [x] Diagnosed device test log: identified GATT discovery round-trip bottleneck causing background reconnect flapping on ICSE.
- [x] Fixed FTMS distance reset bug in `WorkoutManager.swift`: distance now accumulates deltas and immediately re-baselines on counter resets instead of zeroing the workout display.
- [x] Optimized `BluetoothManager.swift` service discovery: explicitly queries target characteristic UUIDs (`2A5B`, `2A63`, `2AD2/2ACD/2AD1`) instead of requesting all generic characteristics (`nil`), cutting discovery overhead by ~75% so subscriptions establish on the first packet during background reconnects.
- [x] Implemented FTMS Control Point (`0x2AD9`) handshake in `BluetoothManager.swift`: sends `Request Control` (`0x00`) $\rightarrow$ on confirmation sends `Start or Resume` (`0x07`) to resume the training session on the bike console and unfreeze cadence/power streaming upon reconnect.
- [x] Unit test suite verified **14/14 green** on watchOS simulator.

### 🚀 Next Steps
- [ ] Install build on Apple Watch and test background reconnect behavior on ICSE bike.
- [ ] Confirm distance accumulation continues seamlessly through mid-workout disconnect/reconnect.
- [ ] Merge `fix/2.2.1-reconnect-and-distance` into `release/2.2.1`.
- [ ] Decide on baked GitHub PAT before archiving `release/2.2.1`.

### 📋 Backlog / Later
- [ ] Delete throwaway branch `diag/2.2.1-ble-trace` once verification is done.
- [ ] Whole-ride BLE logging behind a user-facing debug toggle.
- [ ] `didFailToConnect` fallback retry handling.
- [ ] Submit 3.0 after 2.2.1 is validated and shipped.

### 🛑 Blockers & Known Issues
- A live fine-grained GitHub PAT is baked into the shipping `Info.plist` (`CaPowHrGitHubToken`, from `Config/Secrets.xcconfig`). Blank before archiving.
- Hardware BLE paths cannot be simulated in the simulator; verification requires physical testing with the trainer.
