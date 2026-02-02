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
    static let clientId = "198761"
    static let clientSecret = "de4a3a949a7272943273251f70bcfb738b94790b"
    
    // MARK: - OAuth Configuration
    static let redirectUri = "capowhr://localhost"
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
    
    // MARK: - Shared Access (iOS ⟷ watchOS)
    /// Keychain access group for sharing tokens between iOS and watchOS
    /// Format: $(AppIdentifierPrefix)com.MulcahyHeavyIndustries.CaPowHr
    static let keychainAccessGroup = "UX8Q7W992R.com.MulcahyHeavyIndustries.CaPowHr"
    
    /// App Group for shared container access
    static let appGroupId = "group.com.MulcahyHeavyIndustries.CaPowHr"
    
    // MARK: - WatchConnectivity Message Keys
    static let wcMessageKeyAction = "action"
    static let wcActionStartAuth = "startStravaAuth"
    static let wcActionTokensUpdated = "tokensUpdated"
    static let wcKeyAccessToken = "accessToken"
    static let wcKeyRefreshToken = "refreshToken"
    static let wcKeyExpiresAt = "expiresAt"
    static let wcKeyAthleteId = "athleteId"
    static let wcKeyAthleteName = "athleteName"
}
