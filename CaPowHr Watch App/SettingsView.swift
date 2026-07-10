import SwiftUI

struct SettingsView: View {
    @ObservedObject var workoutManager: WorkoutManager
    @ObservedObject var stravaAuthManager: StravaAuthManager
    @ObservedObject var stravaUploader: StravaUploader
    @AppStorage("heartRateSource") private var heartRateSource: String = HeartRateSource.auto.rawValue
    @AppStorage(AppSettings.distanceUnitKey) private var distanceUnit: String = DistanceUnit.miles.rawValue
    @AppStorage(AppSettings.workoutSaveModeKey) private var workoutSaveMode: String = WorkoutSaveMode.askEveryTime.rawValue
    @AppStorage(AppSettings.fitExportEnabledKey) private var fitExportEnabled: Bool = false
    
    private var heartRateSourceBinding: Binding<HeartRateSource> {
        Binding(
            get: { HeartRateSource(rawValue: heartRateSource) ?? .auto },
            set: { heartRateSource = $0.rawValue }
        )
    }
    
    var body: some View {
        ScrollView {
            VStack(spacing: 12) {
                Text("Settings")
                    .font(.headline)
                    .fontWeight(.bold)
                    .padding(.top, 8)
                
                Picker("Heart Rate Source", selection: heartRateSourceBinding) {
                    ForEach([HeartRateSource.auto, .bike, .watch], id: \.self) { source in
                        Text(source.displayName).tag(source)
                    }
                }
                .pickerStyle(.navigationLink)

                Picker("Distance Unit", selection: $distanceUnit) {
                    ForEach(DistanceUnit.allCases) { unit in
                        Text(unit.displayName).tag(unit.rawValue)
                    }
                }
                .pickerStyle(.navigationLink)

                Picker("After Workout", selection: $workoutSaveMode) {
                    ForEach(WorkoutSaveMode.allCases) { mode in
                        Text(mode.displayName).tag(mode.rawValue)
                    }
                }
                .pickerStyle(.navigationLink)

                Toggle("Export FIT File", isOn: $fitExportEnabled)
                    .font(.footnote)

                NavigationLink {
                    TrustedDevicesSettingsView(workoutManager: workoutManager)
                } label: {
                    Label("Trusted Devices", systemImage: "dot.radiowaves.left.and.right")
                        .font(.footnote)
                }

                NavigationLink {
                    MetricsLayoutSettingsView()
                } label: {
                    Label("Metric Layout", systemImage: "square.grid.2x2")
                        .font(.footnote)
                }

                NavigationLink {
                    TrainingSettingsView()
                } label: {
                    Label("Training", systemImage: "chart.line.uptrend.xyaxis")
                        .font(.footnote)
                }

                NavigationLink {
                    CompatibilityListView()
                } label: {
                    Label("Tested Equipment", systemImage: "checklist")
                        .font(.footnote)
                }
                
                if FeatureFlags.showBLELogUpload {
                    NavigationLink {
                        BLELogCaptureView(workoutManager: workoutManager)
                    } label: {
                        Label("Capture BLE Log", systemImage: "antenna.radiowaves.left.and.right")
                            .font(.footnote)
                    }
                }
                
                if FeatureFlags.showStravaIntegration {
                    NavigationLink {
                        StravaSettingsView(
                            authManager: stravaAuthManager,
                            uploader: stravaUploader
                        )
                    } label: {
                        HStack {
                            Label("Strava", systemImage: "figure.run.circle")
                            Spacer()
                            if stravaAuthManager.isAuthenticated {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundColor(.green)
                                    .font(.caption)
                            }
                        }
                        .font(.footnote)
                    }
                }
                
                Spacer()
            }
            .padding(.horizontal, 8)
        }
        .navigationBarTitleDisplayMode(.inline)
    }
}

#if DEBUG
#Preview {
    let authManager = StravaAuthManager()
    NavigationStack {
        SettingsView(
            workoutManager: WorkoutManager(),
            stravaAuthManager: authManager,
            stravaUploader: StravaUploader(authManager: authManager)
        )
    }
}
#endif
