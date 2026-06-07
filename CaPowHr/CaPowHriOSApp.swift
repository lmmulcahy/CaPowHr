import SwiftUI
import WatchConnectivity

@main
struct CaPowHriOSApp: App {
    @StateObject private var authManager = StravaAuthManageriOS()

    init() {
        WatchConnectivityManager.shared.activate()
    }

    var body: some Scene {
        WindowGroup {
            CompanionContentView()
                .environmentObject(authManager)
                .onAppear {
                    WatchConnectivityManager.shared.delegate = authManager
                }
        }
    }
}
