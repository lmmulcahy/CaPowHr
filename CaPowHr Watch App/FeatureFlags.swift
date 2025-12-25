import Foundation

enum FeatureFlags {
    /// Gate internal-only UI/flows that should not ship in production builds.
    #if DEBUG
    static let showBLELogUpload = true
    #else
    static let showBLELogUpload = false
    #endif
}


