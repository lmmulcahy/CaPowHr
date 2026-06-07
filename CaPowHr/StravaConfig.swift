import Foundation

enum StravaConfig {
    private static func plistString(_ key: String) -> String? {
        Bundle.main.object(forInfoDictionaryKey: key) as? String
    }

    static var clientId: String {
        let value = plistString("StravaClientId") ?? ""
        return value.isEmpty || value.hasPrefix("$(") ? "YOUR_CLIENT_ID" : value
    }

    static var clientSecret: String {
        let value = plistString("StravaClientSecret") ?? ""
        return value.isEmpty || value.hasPrefix("$(") ? "YOUR_CLIENT_SECRET" : value
    }

    static let redirectUri = "capowhr://strava-callback"
    static let scope = "activity:write"
    static let authorizationUrl = "https://www.strava.com/oauth/authorize"
    static let tokenUrl = "https://www.strava.com/oauth/token"
    static let apiBaseUrl = "https://www.strava.com/api/v3"
    static let keychainService = "com.capowhr.strava"
    static let accessTokenKey = "strava_access_token"
    static let refreshTokenKey = "strava_refresh_token"
    static let expiresAtKey = "strava_expires_at"
    static let athleteIdKey = "strava_athlete_id"
    static let wcMessageKeyAction = "action"
    static let wcActionStartAuth = "startStravaAuth"
    static let wcActionTokensUpdated = "tokensUpdated"
    static let wcKeyAccessToken = "accessToken"
    static let wcKeyRefreshToken = "refreshToken"
    static let wcKeyExpiresAt = "expiresAt"
    static let wcKeyAthleteId = "athleteId"
    static let wcKeyAthleteName = "athleteName"
}
