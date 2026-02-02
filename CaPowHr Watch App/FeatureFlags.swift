import Foundation

enum FeatureFlags {
    /// BLE log capture for diagnostics - available in all builds.
    static let showBLELogUpload = true
    
    /// Strava integration - hidden until OAuth flow is fully working.
    static let showStravaIntegration = false
}


