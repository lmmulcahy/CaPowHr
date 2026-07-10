//
//  WatchConnectivityManager.swift
//  Shared between the watch app and the iOS companion.
//
//  Carries the Strava OAuth handshake between the phone (which runs the OAuth
//  flow) and the watch (which uploads workouts).
//

import Foundation
import WatchConnectivity

protocol WatchConnectivityDelegate: AnyObject {
    func watchConnectivityDidRequestStravaAuth()
    func watchConnectivityDidReceiveTokens(
        accessToken: String,
        refreshToken: String,
        expiresAt: Double,
        athleteId: String?,
        athleteName: String?
    )
}

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

    func activate() {
        guard WCSession.isSupported() else { return }
        session = WCSession.default
        session?.delegate = self
        session?.activate()
    }

    func sendTokensToWatch(
        accessToken: String,
        refreshToken: String,
        expiresAt: Double,
        athleteId: String?,
        athleteName: String?
    ) {
        guard let session, session.activationState == .activated else { return }

        var userInfo: [String: Any] = [
            StravaConfig.wcMessageKeyAction: StravaConfig.wcActionTokensUpdated,
            StravaConfig.wcKeyAccessToken: accessToken,
            StravaConfig.wcKeyRefreshToken: refreshToken,
            StravaConfig.wcKeyExpiresAt: expiresAt
        ]
        if let athleteId { userInfo[StravaConfig.wcKeyAthleteId] = athleteId }
        if let athleteName { userInfo[StravaConfig.wcKeyAthleteName] = athleteName }
        session.transferUserInfo(userInfo)
    }

    func requestAuthFromiPhone() {
        guard let session, session.activationState == .activated else { return }
        let message: [String: Any] = [StravaConfig.wcMessageKeyAction: StravaConfig.wcActionStartAuth]
        if session.isReachable {
            session.sendMessage(message, replyHandler: nil, errorHandler: nil)
        } else {
            session.transferUserInfo(message)
        }
    }

    private func handleIncoming(_ userInfo: [String: Any]) {
        guard let action = userInfo[StravaConfig.wcMessageKeyAction] as? String else { return }
        switch action {
        case StravaConfig.wcActionStartAuth:
            DispatchQueue.main.async {
                self.delegate?.watchConnectivityDidRequestStravaAuth()
            }
        case StravaConfig.wcActionTokensUpdated:
            guard
                let accessToken = userInfo[StravaConfig.wcKeyAccessToken] as? String,
                let refreshToken = userInfo[StravaConfig.wcKeyRefreshToken] as? String,
                let expiresAt = userInfo[StravaConfig.wcKeyExpiresAt] as? Double
            else { return }
            DispatchQueue.main.async {
                self.delegate?.watchConnectivityDidReceiveTokens(
                    accessToken: accessToken,
                    refreshToken: refreshToken,
                    expiresAt: expiresAt,
                    athleteId: userInfo[StravaConfig.wcKeyAthleteId] as? String,
                    athleteName: userInfo[StravaConfig.wcKeyAthleteName] as? String
                )
            }
        default:
            break
        }
    }
}

extension WatchConnectivityManager: WCSessionDelegate {
    func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
        DispatchQueue.main.async {
            self.isReachable = session.isReachable
            #if os(iOS)
            self.isPaired = session.isPaired
            self.isWatchAppInstalled = session.isWatchAppInstalled
            #endif
        }
    }

    #if os(iOS)
    func sessionDidBecomeInactive(_ session: WCSession) {}
    func sessionDidDeactivate(_ session: WCSession) {
        session.activate()
    }

    func sessionWatchStateDidChange(_ session: WCSession) {
        DispatchQueue.main.async {
            self.isPaired = session.isPaired
            self.isWatchAppInstalled = session.isWatchAppInstalled
        }
    }
    #endif

    func sessionReachabilityDidChange(_ session: WCSession) {
        DispatchQueue.main.async {
            self.isReachable = session.isReachable
        }
    }

    func session(_ session: WCSession, didReceiveUserInfo userInfo: [String: Any] = [:]) {
        handleIncoming(userInfo)
    }

    func session(_ session: WCSession, didReceiveMessage message: [String: Any]) {
        handleIncoming(message)
    }
}
