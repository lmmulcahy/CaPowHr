import SwiftUI

struct SettingsView: View {
    @ObservedObject var workoutManager: WorkoutManager
    @ObservedObject var stravaAuthManager: StravaAuthManager
    @ObservedObject var stravaUploader: StravaUploader
    @AppStorage("heartRateSource") private var heartRateSource: String = HeartRateSource.auto.rawValue
    
    private var heartRateSourceBinding: Binding<HeartRateSource> {
        Binding(
            get: {
                HeartRateSource(rawValue: heartRateSource) ?? .auto
            },
            set: { newValue in
                heartRateSource = newValue.rawValue
            }
        )
    }
    
    private var heartRateSourceOrder: [HeartRateSource] {
        [.auto, .bike, .watch]
    }
    
    var body: some View {
        ScrollView {
            VStack(spacing: 12) {
                Text("Settings")
                    .font(.headline)
                    .fontWeight(.bold)
                    .padding(.top, 8)
                
                // Heart Rate Source Selection
                VStack(alignment: .leading, spacing: 8) {
                    Picker("Heart Rate Source", selection: heartRateSourceBinding) {
                        ForEach(heartRateSourceOrder, id: \.self) { source in
                            Text(source.displayName).tag(source)
                        }
                    }
                    .pickerStyle(.navigationLink)
                }
                .padding(.horizontal, 8)
                
                if FeatureFlags.showBLELogUpload {
                    NavigationLink {
                        BLELogCaptureView(workoutManager: workoutManager)
                    } label: {
                        HStack {
                            Image(systemName: "antenna.radiowaves.left.and.right")
                            Text("Capture BLE Log")
                        }
                        .font(.footnote)
                    }
                }
                
                // Strava Integration
                NavigationLink {
                    StravaSettingsView(
                        authManager: stravaAuthManager,
                        uploader: stravaUploader
                    )
                } label: {
                    HStack {
                        Image(systemName: "figure.run.circle")
                            .foregroundColor(.orange)
                        Text("Strava")
                        Spacer()
                        if stravaAuthManager.isAuthenticated {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundColor(.green)
                                .font(.caption)
                        }
                    }
                    .font(.footnote)
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

