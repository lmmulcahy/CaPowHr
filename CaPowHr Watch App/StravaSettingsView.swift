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
                
                // Connect/Disconnect Button
                connectionButton
                
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
    
    // MARK: - Connection Button
    
    private var connectionButton: some View {
        Group {
            if authManager.isAuthenticating {
                ProgressView()
                    .progressViewStyle(CircularProgressViewStyle())
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
                Button {
                    authManager.authenticate()
                } label: {
                    HStack {
                        Image(systemName: "link")
                        Text("Connect to Strava")
                    }
                    .font(.footnote)
                }
                .buttonStyle(.borderedProminent)
                .tint(.orange)
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
