//
//  StravaClient.swift
//  CaPowHr Watch App
//
//  API client for Strava REST endpoints.
//

import Foundation

/// Represents a Strava activity type for upload
enum StravaActivityType: String {
    case virtualRide = "VirtualRide"
    case virtualRun = "VirtualRun"
    case walk = "Walk"
    case rowing = "Rowing"
    
    /// Maps WorkoutType to Strava activity type
    static func from(workoutType: WorkoutType) -> StravaActivityType {
        switch workoutType {
        case .indoorCycle:
            return .virtualRide
        case .indoorRun:
            return .virtualRun
        case .indoorWalk:
            return .walk
        case .indoorRow:
            return .rowing
        }
    }
    
    /// The sport_type for Strava API (same as type for these activities)
    var sportType: String {
        return rawValue
    }
}

/// Result of creating a Strava activity
struct StravaActivityResult {
    let activityId: Int
    let name: String
}

/// Error types for Strava API calls
enum StravaClientError: Error, LocalizedError {
    case notAuthenticated
    case invalidResponse
    case httpError(statusCode: Int, message: String?)
    case networkError(underlying: Error)
    
    var errorDescription: String? {
        switch self {
        case .notAuthenticated:
            return "Not authenticated with Strava"
        case .invalidResponse:
            return "Invalid response from Strava"
        case .httpError(let statusCode, let message):
            if let message = message {
                return "Strava error (\(statusCode)): \(message)"
            }
            return "Strava error (HTTP \(statusCode))"
        case .networkError(let underlying):
            return "Network error: \(underlying.localizedDescription)"
        }
    }
}

final class StravaClient {
    private let authManager: StravaAuthManager
    
    init(authManager: StravaAuthManager) {
        self.authManager = authManager
    }
    
    /// Creates a manual activity on Strava
    /// - Parameters:
    ///   - name: Activity name (e.g., "Morning Ride")
    ///   - type: Activity type
    ///   - startDate: Local start time of the activity
    ///   - elapsedTimeSeconds: Total elapsed time in seconds
    ///   - distanceMeters: Total distance in meters (optional)
    ///   - description: Activity description (optional)
    /// - Returns: The created activity result
    func createActivity(
        name: String,
        type: StravaActivityType,
        startDate: Date,
        elapsedTimeSeconds: Int,
        distanceMeters: Double? = nil,
        description: String? = nil
    ) async throws -> StravaActivityResult {
        guard let accessToken = await authManager.getAccessToken() else {
            throw StravaClientError.notAuthenticated
        }
        
        let url = URL(string: "\(StravaConfig.apiBaseUrl)/activities")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        
        // Format date as ISO 8601 local time
        let dateFormatter = ISO8601DateFormatter()
        dateFormatter.formatOptions = [.withInternetDateTime]
        let startDateLocal = dateFormatter.string(from: startDate)
        
        var bodyParams: [String: String] = [
            "name": name,
            "type": type.rawValue,
            "sport_type": type.sportType,
            "start_date_local": startDateLocal,
            "elapsed_time": String(elapsedTimeSeconds)
        ]
        
        if let distance = distanceMeters, distance > 0 {
            bodyParams["distance"] = String(format: "%.1f", distance)
        }
        
        if let desc = description, !desc.isEmpty {
            bodyParams["description"] = desc
        }
        
        request.httpBody = bodyParams
            .map { key, value in
                let escapedValue = value.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? value
                return "\(key)=\(escapedValue)"
            }
            .joined(separator: "&")
            .data(using: .utf8)
        
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            
            guard let httpResponse = response as? HTTPURLResponse else {
                throw StravaClientError.invalidResponse
            }
            
            if httpResponse.statusCode == 201 {
                // Success - parse activity ID
                guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                      let activityId = json["id"] as? Int else {
                    throw StravaClientError.invalidResponse
                }
                
                let activityName = json["name"] as? String ?? name
                return StravaActivityResult(activityId: activityId, name: activityName)
                
            } else {
                // Error response
                var errorMessage: String? = nil
                if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                   let message = json["message"] as? String {
                    errorMessage = message
                }
                throw StravaClientError.httpError(statusCode: httpResponse.statusCode, message: errorMessage)
            }
            
        } catch let error as StravaClientError {
            throw error
        } catch {
            throw StravaClientError.networkError(underlying: error)
        }
    }
}
