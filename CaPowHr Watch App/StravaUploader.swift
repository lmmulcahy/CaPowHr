//
//  StravaUploader.swift
//  CaPowHr Watch App
//
//  Handles uploading completed workouts to Strava.
//

import Foundation

/// Data structure containing workout information to upload to Strava
struct WorkoutUploadData {
    let workoutType: WorkoutType
    let startDate: Date
    let durationSeconds: TimeInterval
    let distanceMeters: Double
    let averageHeartRate: Double?
    let averagePower: Double?
    let averageCadence: Double?
    
    /// Generates a default activity name based on workout type and time
    var defaultName: String {
        let timeFormatter = DateFormatter()
        timeFormatter.dateFormat = "h:mm a"
        let timeString = timeFormatter.string(from: startDate)
        
        let calendar = Calendar.current
        let hour = calendar.component(.hour, from: startDate)
        
        let timeOfDay: String
        switch hour {
        case 5..<12:
            timeOfDay = "Morning"
        case 12..<17:
            timeOfDay = "Afternoon"
        case 17..<21:
            timeOfDay = "Evening"
        default:
            timeOfDay = "Night"
        }
        
        switch workoutType {
        case .indoorCycle:
            return "\(timeOfDay) Indoor Ride"
        case .indoorRun:
            return "\(timeOfDay) Indoor Run"
        case .indoorWalk:
            return "\(timeOfDay) Indoor Walk"
        case .indoorRow:
            return "\(timeOfDay) Row"
        }
    }
    
    /// Generates a description with workout stats
    var description: String {
        var parts: [String] = ["Recorded with CaPowHr"]
        
        if let hr = averageHeartRate, hr > 0 {
            parts.append("Avg HR: \(Int(hr)) bpm")
        }
        
        if let power = averagePower, power > 0 {
            parts.append("Avg Power: \(Int(power)) W")
        }
        
        if let cadence = averageCadence, cadence > 0 {
            parts.append("Avg Cadence: \(Int(cadence)) rpm")
        }
        
        return parts.joined(separator: " | ")
    }
}

/// Manages uploading workouts to Strava
@MainActor
final class StravaUploader: ObservableObject {
    @Published var isUploading: Bool = false
    @Published var lastUploadError: String? = nil
    @Published var lastUploadSuccess: Bool = false
    
    private let authManager: StravaAuthManager
    private let client: StravaClient
    
    /// Whether Strava sync is enabled (stored in UserDefaults)
    var isSyncEnabled: Bool {
        get { UserDefaults.standard.bool(forKey: "stravaSyncEnabled") }
        set { UserDefaults.standard.set(newValue, forKey: "stravaSyncEnabled") }
    }
    
    init(authManager: StravaAuthManager) {
        self.authManager = authManager
        self.client = StravaClient(authManager: authManager)
        
        // Default to enabled if not set
        if UserDefaults.standard.object(forKey: "stravaSyncEnabled") == nil {
            UserDefaults.standard.set(true, forKey: "stravaSyncEnabled")
        }
    }
    
    /// Uploads a workout to Strava if sync is enabled and user is authenticated
    /// - Parameter data: The workout data to upload
    /// - Returns: True if upload succeeded, false otherwise
    @discardableResult
    func uploadWorkout(_ data: WorkoutUploadData) async -> Bool {
        // Check if sync is enabled
        guard isSyncEnabled else {
            print("Strava sync disabled, skipping upload")
            return false
        }
        
        // Check if authenticated
        guard authManager.isAuthenticated else {
            print("Not authenticated with Strava, skipping upload")
            return false
        }
        
        isUploading = true
        lastUploadError = nil
        lastUploadSuccess = false
        
        defer {
            isUploading = false
        }
        
        do {
            let activityType = StravaActivityType.from(workoutType: data.workoutType)
            
            let result = try await client.createActivity(
                name: data.defaultName,
                type: activityType,
                startDate: data.startDate,
                elapsedTimeSeconds: Int(data.durationSeconds),
                distanceMeters: data.distanceMeters,
                description: data.description
            )
            
            print("Successfully uploaded to Strava: \(result.name) (ID: \(result.activityId))")
            lastUploadSuccess = true
            return true
            
        } catch {
            print("Failed to upload to Strava: \(error.localizedDescription)")
            lastUploadError = error.localizedDescription
            return false
        }
    }
    
    /// Resets upload status (call when starting a new workout)
    func resetStatus() {
        lastUploadError = nil
        lastUploadSuccess = false
        isUploading = false
    }
}
