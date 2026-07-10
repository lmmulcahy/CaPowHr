import SwiftUI

struct CompanionContentView: View {
    @EnvironmentObject var authManager: StravaAuthManageriOS

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    Image(systemName: "figure.indoor.cycle")
                        .font(.system(size: 56))
                        .foregroundStyle(.orange)

                    Text("CaPowHr Companion")
                        .font(.title2.bold())

                    Text("Connect Strava on iPhone and sync credentials to your Apple Watch.")
                        .font(.footnote)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)

                    stravaSection
                }
                .padding()
            }
            .navigationTitle("CaPowHr")
        }
    }

    private var stravaSection: some View {
        VStack(spacing: 12) {
            HStack {
                Image(systemName: authManager.isAuthenticated ? "checkmark.circle.fill" : "xmark.circle")
                    .foregroundColor(authManager.isAuthenticated ? .green : .secondary)
                Text(authManager.isAuthenticated ? "Strava Connected" : "Strava Not Connected")
                    .font(.headline)
                Spacer()
            }

            if let error = authManager.authError {
                Text(error)
                    .font(.caption)
                    .foregroundColor(.red)
                    .multilineTextAlignment(.center)
            }

            if authManager.isAuthenticating {
                ProgressView("Connecting…")
            } else if authManager.isAuthenticated {
                Button("Sync to Apple Watch") {
                    authManager.syncToWatch()
                }
                .buttonStyle(.borderedProminent)

                Button("Disconnect", role: .destructive) {
                    authManager.logout()
                }
                .buttonStyle(.bordered)
            } else {
                Button("Connect to Strava") {
                    authManager.authenticate()
                }
                .buttonStyle(.borderedProminent)
                .tint(.orange)
            }
        }
        .padding()
        .background(Color(.secondarySystemBackground))
        .cornerRadius(12)
    }
}

#Preview {
    CompanionContentView()
        .environmentObject(StravaAuthManageriOS())
}
