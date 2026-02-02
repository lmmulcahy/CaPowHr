//
//  WatchConnectivityManager.swift
//  CaPowHr
//
//  Manages bidirectional communication between iOS and watchOS for Strava auth.
//

import Foundation
import WatchConnectivity

/// Protocol for handling WatchConnectivity events
protocol WatchConnectivityDelegate: AnyObject {
    /// Called when iOS should start Strava authentication
    func watchConnectivityDidRequestStravaAuth()
    
    /// Called when tokens were updated from the counterpart app
    func watchConnectivityDidReceiveTokens(
        accessToken: String,
        refreshToken: String,
        expiresAt: Double,
        athleteId: String?,
        athleteName: String?
    )
}

/// Shared WatchConnectivity manager for iOS ⟷ watchOS communication
final class WatchConnectivityManager: NSObject, ObservableObject {
    static let shared = WatchConnectivityManager()
    
    weak var delegate: WatchConnectivityDelegate?
    
    @Published var isReachable: Bool = false
    @Published var isPaired: Bool = false
    @Published var isWatchAppInstalled: Bool = false
    
    private var session: WCSession?
    
    private override init() {
        super.init()
    }
    
    /// Activate the WCSession - call this early in app lifecycle
    func activate() {
        guard WCSession.isSupported() else {
            print("[WC] WCSession not supported on this device")
            return
        }
        
        session = WCSession.default
        session?.delegate = self
        session?.activate()
    }
    
    /// Check if counterpart app is reachable
    var counterpartReachable: Bool {
        session?.isReachable ?? false
    }
    
    // MARK: - iOS → watchOS: Send Tokens
    
    /// Send Strava tokens to the watch (called from iOS after successful auth)
    func sendTokensToWatch(
        accessToken: String,
        refreshToken: String,
        expiresAt: Double,
        athleteId: String?,
        athleteName: String?
    ) {
        guard let session = session, session.activationState == .activated else {
            print("[WC] Session not activated, cannot send tokens")
            return
        }
        
        var userInfo: [String: Any] = [
            StravaConfig.wcMessageKeyAction: StravaConfig.wcActionTokensUpdated,
            StravaConfig.wcKeyAccessToken: accessToken,
            StravaConfig.wcKeyRefreshToken: refreshToken,
            StravaConfig.wcKeyExpiresAt: expiresAt
        ]
        
        if let athleteId = athleteId {
            userInfo[StravaConfig.wcKeyAthleteId] = athleteId
        }
        if let athleteName = athleteName {
            userInfo[StravaConfig.wcKeyAthleteName] = athleteName
        }
        
        // Use transferUserInfo for reliable delivery even if watch app isn't running
        session.transferUserInfo(userInfo)
        print("[WC] Sent tokens to watch via transferUserInfo")
    }
    
    // MARK: - watchOS → iOS: Request Auth
    
    /// Request iOS to start Strava authentication (called from watchOS)
    func requestAuthFromiPhone() {
        guard let session = session, session.activationState == .activated else {
            print("[WC] Session not activated, cannot request auth")
            return
        }
        
        let message: [String: Any] = [
            StravaConfig.wcMessageKeyAction: StravaConfig.wcActionStartAuth
        ]
        
        if session.isReachable {
            // Use sendMessage for immediate delivery if phone is reachable
            session.sendMessage(message, replyHandler: nil) { error in
                print("[WC] Error sending auth request: \(error.localizedDescription)")
            }
            print("[WC] Sent auth request to iPhone via sendMessage")
        } else {
            // Fall back to transferUserInfo if not immediately reachable
            session.transferUserInfo(message)
            print("[WC] Sent auth request to iPhone via transferUserInfo (not reachable)")
        }
    }
}

// MARK: - WCSessionDelegate

extension WatchConnectivityManager: WCSessionDelegate {
    
    func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
        if let error = error {
            print("[WC] Activation failed: \(error.localizedDescription)")
            return
        }
        
        print("[WC] Session activated: \(activationState.rawValue)")
        
        DispatchQueue.main.async {
            self.isReachable = session.isReachable
            #if os(iOS)
            self.isPaired = session.isPaired
            self.isWatchAppInstalled = session.isWatchAppInstalled
            #endif
        }
    }
    
    func sessionReachabilityDidChange(_ session: WCSession) {
        DispatchQueue.main.async {
            self.isReachable = session.isReachable
        }
        print("[WC] Reachability changed: \(session.isReachable)")
    }
    
    // iOS only
    #if os(iOS)
    func sessionDidBecomeInactive(_ session: WCSession) {
        print("[WC] Session became inactive")
    }
    
    func sessionDidDeactivate(_ session: WCSession) {
        print("[WC] Session deactivated, reactivating...")
        session.activate()
    }
    
    func sessionWatchStateDidChange(_ session: WCSession) {
        DispatchQueue.main.async {
            self.isPaired = session.isPaired
            self.isWatchAppInstalled = session.isWatchAppInstalled
        }
    }
    #endif
    
    // Handle incoming messages (immediate)
    func session(_ session: WCSession, didReceiveMessage message: [String: Any]) {
        handleIncomingMessage(message)
    }
    
    func session(_ session: WCSession, didReceiveMessage message: [String: Any], replyHandler: @escaping ([String: Any]) -> Void) {
        handleIncomingMessage(message)
        replyHandler(["received": true])
    }
    
    // Handle incoming userInfo (queued/reliable)
    func session(_ session: WCSession, didReceiveUserInfo userInfo: [String: Any]) {
        handleIncomingMessage(userInfo)
    }
    
    private func handleIncomingMessage(_ message: [String: Any]) {
        guard let action = message[StravaConfig.wcMessageKeyAction] as? String else {
            print("[WC] Received message without action key")
            return
        }
        
        DispatchQueue.main.async {
            switch action {
            case StravaConfig.wcActionStartAuth:
                print("[WC] Received auth request from watch")
                self.delegate?.watchConnectivityDidRequestStravaAuth()
                
            case StravaConfig.wcActionTokensUpdated:
                print("[WC] Received tokens from iPhone")
                guard let accessToken = message[StravaConfig.wcKeyAccessToken] as? String,
                      let refreshToken = message[StravaConfig.wcKeyRefreshToken] as? String,
                      let expiresAt = message[StravaConfig.wcKeyExpiresAt] as? Double else {
                    print("[WC] Missing required token fields")
                    return
                }
                
                let athleteId = message[StravaConfig.wcKeyAthleteId] as? String
                let athleteName = message[StravaConfig.wcKeyAthleteName] as? String
                
                self.delegate?.watchConnectivityDidReceiveTokens(
                    accessToken: accessToken,
                    refreshToken: refreshToken,
                    expiresAt: expiresAt,
                    athleteId: athleteId,
                    athleteName: athleteName
                )
                
            default:
                print("[WC] Unknown action: \(action)")
            }
        }
    }
}
