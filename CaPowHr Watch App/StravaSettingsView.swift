//
//  StravaSettingsView.swift
//  CaPowHr Watch App
//
//  Settings UI for Strava connection and sync preferences.
//

import SwiftUI

struct StravaSettingsView: View {
    @ObservedObject var authManager: StravaAuthManager
    @ObservedObject var uploader: StravaUploader
    
    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                // Connection Status
                connectionStatusSection
                
                // Sync Toggle (only show when connected)
                if authManager.isAuthenticated {
                    syncToggleSection
                }
                
                // Connect/Disconnect Buttons
                connectionButtons
                
                Spacer()
            }
            .padding(.horizontal, 8)
            .padding(.top, 8)
        }
        .navigationTitle("Strava")
        .navigationBarTitleDisplayMode(.inline)
    }
    
    // MARK: - Connection Status Section
    
    private var connectionStatusSection: some View {
        VStack(spacing: 8) {
            Image(systemName: authManager.isAuthenticated ? "checkmark.circle.fill" : "xmark.circle")
                .font(.system(size: 40))
                .foregroundColor(authManager.isAuthenticated ? .green : .secondary)
            
            Text(authManager.isAuthenticated ? "Connected" : "Not Connected")
                .font(.headline)
            
            if let name = authManager.athleteName {
                Text("Hi, \(name)!")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            if authManager.isWaitingForiPhone {
                HStack(spacing: 4) {
                    ProgressView()
                        .scaleEffect(0.8)
                    Text("Check your iPhone...")
                        .font(.caption2)
                        .foregroundColor(.orange)
                }
            }
            
            if let error = authManager.authError {
                Text(error)
                    .font(.caption2)
                    .foregroundColor(.red)
                    .multilineTextAlignment(.center)
            }
        }
    }
    
    // MARK: - Sync Toggle Section
    
    private var syncToggleSection: some View {
        Toggle(isOn: Binding(
            get: { uploader.isSyncEnabled },
            set: { uploader.isSyncEnabled = $0 }
        )) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Auto-sync")
                    .font(.footnote)
                Text("Upload workouts to Strava")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
        }
        .padding(.horizontal, 4)
    }
    
    // MARK: - Connection Buttons
    
    private var connectionButtons: some View {
        Group {
            if authManager.isAuthenticating || authManager.isWaitingForiPhone {
                VStack(spacing: 8) {
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle())
                    
                    if authManager.isWaitingForiPhone {
                        Button {
                            authManager.isWaitingForiPhone = false
                        } label: {
                            Text("Cancel")
                                .font(.caption)
                        }
                        .buttonStyle(.bordered)
                    }
                }
            } else if authManager.isAuthenticated {
                Button(role: .destructive) {
                    authManager.logout()
                } label: {
                    HStack {
                        Image(systemName: "xmark.circle")
                        Text("Disconnect")
                    }
                    .font(.footnote)
                }
                .buttonStyle(.borderedProminent)
                .tint(.red)
            } else {
                VStack(spacing: 10) {
                    // Primary: Connect via iPhone
                    Button {
                        authManager.authenticateViaiPhone()
                    } label: {
                        HStack {
                            Image(systemName: "iphone")
                            Text("Connect via iPhone")
                        }
                        .font(.footnote)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.orange)
                    
                    // Secondary: Connect on Watch (harder to use)
                    Button {
                        authManager.authenticateOnWatch()
                    } label: {
                        HStack {
                            Image(systemName: "applewatch")
                            Text("Connect on Watch")
                        }
                        .font(.caption2)
                    }
                    .buttonStyle(.bordered)
                    .foregroundColor(.secondary)
                }
            }
        }
    }
}

#if DEBUG
#Preview("Not Connected") {
    NavigationStack {
        StravaSettingsView(
            authManager: StravaAuthManager(),
            uploader: StravaUploader(authManager: StravaAuthManager())
        )
    }
}
#endif
