//
//  ContentView.swift
//  CaPowHr (iOS)
//
//  Main view for the iOS companion app.
//

import SwiftUI

struct ContentView: View {
    @EnvironmentObject var authManager: StravaAuthManageriOS
    @EnvironmentObject var connectivityManager: WatchConnectivityManager
    
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    // App Header
                    headerSection
                    
                    // Strava Connection Card
                    stravaCard
                    
                    // Watch Connectivity Status
                    watchStatusCard
                    
                    Spacer(minLength: 40)
                }
                .padding()
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("CaPowHr")
        }
    }
    
    // MARK: - Header Section
    
    private var headerSection: some View {
        VStack(spacing: 8) {
            Image(systemName: "figure.outdoor.cycle")
                .font(.system(size: 60))
                .foregroundStyle(.linearGradient(
                    colors: [.orange, .red],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ))
            
            Text("Companion App")
                .font(.headline)
                .foregroundColor(.secondary)
        }
        .padding(.top, 20)
    }
    
    // MARK: - Strava Card
    
    private var stravaCard: some View {
        VStack(spacing: 16) {
            HStack {
                Image(systemName: "figure.run")
                    .font(.title2)
                    .foregroundColor(.orange)
                Text("Strava")
                    .font(.title2.bold())
                Spacer()
            }
            
            Divider()
            
            // Status
            HStack {
                Circle()
                    .fill(authManager.isAuthenticated ? Color.green : Color.gray)
                    .frame(width: 12, height: 12)
                
                Text(authManager.isAuthenticated ? "Connected" : "Not Connected")
                    .font(.headline)
                
                Spacer()
                
                if let name = authManager.athleteName {
                    Text(name)
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
            }
            
            // Error message
            if let error = authManager.authError {
                Text(error)
                    .font(.caption)
                    .foregroundColor(.red)
                    .multilineTextAlignment(.center)
            }
            
            // Action buttons
            if authManager.isAuthenticating {
                ProgressView("Connecting...")
                    .padding()
            } else if authManager.isAuthenticated {
                VStack(spacing: 12) {
                    // Sync to Watch button
                    Button {
                        authManager.syncToWatch()
                    } label: {
                        HStack {
                            Image(systemName: "applewatch")
                            Text(authManager.syncedToWatch ? "Synced to Watch" : "Sync to Watch")
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(authManager.syncedToWatch ? .green : .blue)
                    
                    // Disconnect button
                    Button(role: .destructive) {
                        authManager.logout()
                    } label: {
                        HStack {
                            Image(systemName: "xmark.circle")
                            Text("Disconnect")
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                }
            } else {
                Button {
                    authManager.authenticate()
                } label: {
                    HStack {
                        Image(systemName: "link")
                        Text("Connect to Strava")
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 4)
                }
                .buttonStyle(.borderedProminent)
                .tint(.orange)
            }
        }
        .padding()
        .background(Color(.systemBackground))
        .cornerRadius(16)
        .shadow(color: .black.opacity(0.05), radius: 8, y: 4)
    }
    
    // MARK: - Watch Status Card
    
    private var watchStatusCard: some View {
        VStack(spacing: 16) {
            HStack {
                Image(systemName: "applewatch")
                    .font(.title2)
                    .foregroundColor(.blue)
                Text("Apple Watch")
                    .font(.title2.bold())
                Spacer()
            }
            
            Divider()
            
            VStack(spacing: 12) {
                statusRow(
                    icon: "antenna.radiowaves.left.and.right",
                    label: "Reachable",
                    status: connectivityManager.isReachable
                )
                
                statusRow(
                    icon: "link",
                    label: "Paired",
                    status: connectivityManager.isPaired
                )
                
                statusRow(
                    icon: "app.badge.checkmark",
                    label: "Watch App Installed",
                    status: connectivityManager.isWatchAppInstalled
                )
            }
            
            if !connectivityManager.isPaired {
                Text("Pair your Apple Watch to sync Strava credentials")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
            }
        }
        .padding()
        .background(Color(.systemBackground))
        .cornerRadius(16)
        .shadow(color: .black.opacity(0.05), radius: 8, y: 4)
    }
    
    private func statusRow(icon: String, label: String, status: Bool) -> some View {
        HStack {
            Image(systemName: icon)
                .frame(width: 24)
                .foregroundColor(.secondary)
            
            Text(label)
                .font(.subheadline)
            
            Spacer()
            
            Image(systemName: status ? "checkmark.circle.fill" : "xmark.circle")
                .foregroundColor(status ? .green : .gray)
        }
    }
}

#Preview {
    ContentView()
        .environmentObject(StravaAuthManageriOS())
        .environmentObject(WatchConnectivityManager.shared)
}
