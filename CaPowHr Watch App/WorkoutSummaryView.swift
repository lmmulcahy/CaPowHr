import SwiftUI

struct WorkoutControlsView: View {
    @ObservedObject var workoutManager: WorkoutManager
    var onStop: () -> Void

    var body: some View {
        VStack(spacing: 6) {
            if workoutManager.isConnectingDuringWorkout {
                HStack(spacing: 6) {
                    ProgressView()
                        .scaleEffect(0.8)
                    Text("Connecting sensors…")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }

            if let phase = workoutManager.structuredWorkout.currentPhase {
                Text("\(phase.name) · \(DurationFormatter.minutesSeconds(workoutManager.structuredWorkout.currentPhaseRemainingSeconds))")
                    .font(.caption2)
                    .foregroundColor(.orange)
            }

            HStack(spacing: 6) {
                Button(workoutManager.isWorkoutPaused ? "Resume" : "Pause") {
                    if workoutManager.isWorkoutPaused {
                        workoutManager.resumeWorkout()
                    } else {
                        workoutManager.pauseWorkout()
                    }
                }
                .font(.caption)
                .foregroundColor(.yellow)

                Button("Lap") {
                    workoutManager.recordLap()
                }
                .font(.caption)
                .foregroundColor(.blue)

                Button("Stop") {
                    onStop()
                }
                .font(.caption)
                .fontWeight(.bold)
                .foregroundColor(.white)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(Color.red)
                .cornerRadius(8)
            }
        }
    }

}

struct WorkoutSummaryView: View {
    let summary: WorkoutSummaryData
    @ObservedObject var stravaUploader: StravaUploader
    var onSave: () -> Void
    var onDiscard: () -> Void
    @AppStorage(AppSettings.fitExportEnabledKey) private var fitExportEnabled: Bool = false
    @State private var fitExportURL: URL?
    @State private var exportError: String?

    var body: some View {
        ScrollView {
            VStack(spacing: 10) {
                Text("Workout Summary")
                    .font(.headline)
                    .fontWeight(.bold)

                summaryRow("Duration", DurationFormatter.hoursMinutesSeconds(summary.durationSeconds))
                summaryRow("Distance", formattedDistance)
                if let hr = summary.averageHeartRate, hr > 0 {
                    summaryRow("Avg HR", "\(Int(hr)) bpm")
                }
                if let power = summary.averagePower, power > 0 {
                    summaryRow("Avg Power", "\(Int(power)) W")
                }
                if let cadence = summary.averageCadence, cadence > 0 {
                    summaryRow("Avg Cadence", "\(Int(cadence)) rpm")
                }
                if !summary.laps.isEmpty {
                    summaryRow("Laps", "\(summary.laps.count)")
                }

                if summary.isDisplayOnlyMode {
                    Text("Display-only mode — workout will not be saved to Health.")
                        .font(.caption2)
                        .foregroundColor(.orange)
                        .multilineTextAlignment(.center)
                }

                if fitExportEnabled {
                    if let exportError {
                        Text(exportError)
                            .font(.caption2)
                            .foregroundColor(.red)
                    }

                    Button("Export FIT File") {
                        exportFIT()
                    }
                    .font(.caption)

                    if let fitExportURL {
                        ShareLink(item: fitExportURL) {
                            Text("Share FIT")
                                .font(.caption)
                        }
                    }
                }

                Button("Save Workout") { onSave() }
                    .font(.headline)
                    .fontWeight(.bold)
                    .foregroundColor(.green)

                Button("Discard Workout", role: .destructive) { onDiscard() }
                    .font(.headline)
            }
            .padding(.horizontal, 8)
        }
    }

    private var formattedDistance: String {
        let formatted = DistanceFormatter.formatDistance(summary.distanceMeters)
        return "\(formatted.value) \(formatted.unit)"
    }

    private func summaryRow(_ title: String, _ value: String) -> some View {
        HStack {
            Text(title)
                .font(.caption)
                .foregroundColor(.secondary)
            Spacer()
            Text(value)
                .font(.caption)
                .fontWeight(.semibold)
        }
    }

    private func exportFIT() {
        do {
            fitExportURL = try FITExporter.exportWorkout(summary)
            exportError = nil
        } catch {
            exportError = error.localizedDescription
        }
    }
}

#if DEBUG
#Preview {
    WorkoutSummaryView(
        summary: WorkoutSummaryData(
            workoutType: .indoorCycle,
            durationSeconds: 1800,
            distanceMeters: 15000,
            averageHeartRate: 142,
            averagePower: 210,
            averageCadence: 88,
            laps: [],
            isDisplayOnlyMode: false,
            startDate: Date().addingTimeInterval(-1800)
        ),
        stravaUploader: StravaUploader(authManager: StravaAuthManager()),
        onSave: {},
        onDiscard: {}
    )
}
#endif
