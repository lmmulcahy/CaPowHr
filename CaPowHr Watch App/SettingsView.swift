import SwiftUI

struct SettingsView: View {
    var body: some View {
        ScrollView {
            VStack(spacing: 12) {
                Text("Settings")
                    .font(.headline)
                    .fontWeight(.bold)
                    .padding(.top, 8)
                
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

