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

    private func handleIncoming(_ message: [String: Any]) {
        guard let action = message[StravaConfig.wcMessageKeyAction] as? String else { return }
        DispatchQueue.main.async {
            switch action {
            case StravaConfig.wcActionStartAuth:
                self.delegate?.watchConnectivityDidRequestStravaAuth()
            default:
                break
            }
        }
    }
}

extension WatchConnectivityManager: WCSessionDelegate {
    func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
        DispatchQueue.main.async {
            self.isReachable = session.isReachable
            self.isPaired = session.isPaired
            self.isWatchAppInstalled = session.isWatchAppInstalled
        }
    }

    func sessionDidBecomeInactive(_ session: WCSession) {}
    func sessionDidDeactivate(_ session: WCSession) { session.activate() }

    func sessionReachabilityDidChange(_ session: WCSession) {
        DispatchQueue.main.async { self.isReachable = session.isReachable }
    }

    func sessionWatchStateDidChange(_ session: WCSession) {
        DispatchQueue.main.async {
            self.isPaired = session.isPaired
            self.isWatchAppInstalled = session.isWatchAppInstalled
        }
    }

    func session(_ session: WCSession, didReceiveMessage message: [String: Any]) {
        handleIncoming(message)
    }

    func session(_ session: WCSession, didReceiveUserInfo userInfo: [String: Any] = [:]) {
        handleIncoming(userInfo)
    }
}
