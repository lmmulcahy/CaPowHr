//
//  CaPowHriOSApp.swift
//  CaPowHr
//
//  iOS companion app for CaPowHr watchOS - handles Strava authentication.
//

import SwiftUI
import WatchConnectivity

@main
struct CaPowHriOSApp: App {
    @StateObject private var authManager = StravaAuthManageriOS()
    @StateObject private var connectivityManager = WatchConnectivityManager.shared
    
    init() {
        // Activate WatchConnectivity early
        WatchConnectivityManager.shared.activate()
    }
    
    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(authManager)
                .environmentObject(connectivityManager)
                .onAppear {
                    // Set the delegate for WatchConnectivity
                    WatchConnectivityManager.shared.delegate = authManager
                }
        }
    }
}
