//
//  StravaConfig.swift
//  CaPowHr Watch App
//
//  Configuration for Strava API integration.
//

import Foundation

enum StravaConfig {
    // MARK: - API Credentials
    // TODO: Replace these with your actual Strava API credentials
    // Get them from: https://www.strava.com/settings/api
    static let clientId = "YOUR_CLIENT_ID"
    static let clientSecret = "YOUR_CLIENT_SECRET"
    
    // MARK: - OAuth Configuration
    static let redirectUri = "capowhr://strava-callback"
    static let scope = "activity:write"
    
    // MARK: - API Endpoints
    static let authorizationUrl = "https://www.strava.com/oauth/authorize"
    static let tokenUrl = "https://www.strava.com/oauth/token"
    static let apiBaseUrl = "https://www.strava.com/api/v3"
    
    // MARK: - Keychain Keys
    static let keychainService = "com.capowhr.strava"
    static let accessTokenKey = "strava_access_token"
    static let refreshTokenKey = "strava_refresh_token"
    static let expiresAtKey = "strava_expires_at"
    static let athleteIdKey = "strava_athlete_id"
}
