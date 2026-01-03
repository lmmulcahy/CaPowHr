import SwiftUI

struct SettingsView: View {
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
                        GitHubUploadView()
                    } label: {
                        HStack {
                            Image(systemName: "arrow.up.doc")
                            Text("Upload BLE Log")
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
    NavigationStack {
        SettingsView()
    }
}
#endif

