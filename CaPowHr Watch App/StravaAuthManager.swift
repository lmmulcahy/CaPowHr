//
//  StravaAuthManager.swift
//  CaPowHr Watch App
//
//  Handles OAuth 2.0 authentication with Strava.
//

import Foundation
import AuthenticationServices

@MainActor
final class StravaAuthManager: NSObject, ObservableObject {
    @Published var isAuthenticated: Bool = false
    @Published var isAuthenticating: Bool = false
    @Published var authError: String? = nil
    @Published var athleteName: String? = nil
    
    private let keychain = KeychainStore(service: StravaConfig.keychainService)
    private var webAuthSession: ASWebAuthenticationSession?
    
    override init() {
        super.init()
        Task {
            checkAuthenticationStatus()
        }
    }
    
    // MARK: - Public Methods
    
    func checkAuthenticationStatus() {
        do {
            if let token = try keychain.readString(account: StravaConfig.accessTokenKey),
               !token.isEmpty {
                // Check if token is expired
                if let expiresAtString = try keychain.readString(account: StravaConfig.expiresAtKey),
                   let expiresAt = Double(expiresAtString) {
                    let expirationDate = Date(timeIntervalSince1970: expiresAt)
                    if expirationDate > Date() {
                        isAuthenticated = true
                        return
                    } else {
                        // Token expired, try to refresh
                        Task {
                            await refreshTokenIfNeeded()
                        }
                        return
                    }
                }
                isAuthenticated = true
            } else {
                isAuthenticated = false
            }
        } catch {
            print("Error checking auth status: \(error)")
            isAuthenticated = false
        }
    }
    
    func authenticate() {
        guard !isAuthenticating else { return }
        isAuthenticating = true
        authError = nil
        
        // Build authorization URL
        var components = URLComponents(string: StravaConfig.authorizationUrl)!
        components.queryItems = [
            URLQueryItem(name: "client_id", value: StravaConfig.clientId),
            URLQueryItem(name: "redirect_uri", value: StravaConfig.redirectUri),
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "scope", value: StravaConfig.scope),
            URLQueryItem(name: "approval_prompt", value: "auto")
        ]
        
        guard let authUrl = components.url else {
            authError = "Failed to build authorization URL"
            isAuthenticating = false
            return
        }
        
        // Extract scheme from redirect URI
        guard let callbackScheme = URL(string: StravaConfig.redirectUri)?.scheme else {
            authError = "Invalid redirect URI configuration"
            isAuthenticating = false
            return
        }
        
        // Create and start web authentication session
        webAuthSession = ASWebAuthenticationSession(
            url: authUrl,
            callbackURLScheme: callbackScheme
        ) { [weak self] callbackUrl, error in
            Task { @MainActor in
                guard let self = self else { return }
                self.isAuthenticating = false
                
                if let error = error {
                    if (error as NSError).code == ASWebAuthenticationSessionError.canceledLogin.rawValue {
                        self.authError = "Login cancelled"
                    } else {
                        self.authError = "Authentication failed: \(error.localizedDescription)"
                    }
                    return
                }
                
                guard let callbackUrl = callbackUrl,
                      let components = URLComponents(url: callbackUrl, resolvingAgainstBaseURL: false),
                      let code = components.queryItems?.first(where: { $0.name == "code" })?.value else {
                    self.authError = "Failed to get authorization code"
                    return
                }
                
                await self.exchangeCodeForTokens(code: code)
            }
        }
        
        webAuthSession?.prefersEphemeralWebBrowserSession = false
        webAuthSession?.start()
    }
    
    func logout() {
        do {
            try keychain.delete(account: StravaConfig.accessTokenKey)
            try keychain.delete(account: StravaConfig.refreshTokenKey)
            try keychain.delete(account: StravaConfig.expiresAtKey)
            try keychain.delete(account: StravaConfig.athleteIdKey)
            isAuthenticated = false
            athleteName = nil
        } catch {
            print("Error clearing tokens: \(error)")
        }
    }
    
    func getAccessToken() async -> String? {
        // Check if we need to refresh
        await refreshTokenIfNeeded()
        
        do {
            return try keychain.readString(account: StravaConfig.accessTokenKey)
        } catch {
            print("Error reading access token: \(error)")
            return nil
        }
    }
    
    // MARK: - Private Methods
    
    private func exchangeCodeForTokens(code: String) async {
        var request = URLRequest(url: URL(string: StravaConfig.tokenUrl)!)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        
        let bodyParams = [
            "client_id": StravaConfig.clientId,
            "client_secret": StravaConfig.clientSecret,
            "code": code,
            "grant_type": "authorization_code"
        ]
        
        request.httpBody = bodyParams
            .map { "\($0.key)=\($0.value)" }
            .joined(separator: "&")
            .data(using: .utf8)
        
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            
            guard let httpResponse = response as? HTTPURLResponse,
                  httpResponse.statusCode == 200 else {
                let statusCode = (response as? HTTPURLResponse)?.statusCode ?? 0
                authError = "Token exchange failed (HTTP \(statusCode))"
                return
            }
            
            try parseAndStoreTokenResponse(data: data)
            isAuthenticated = true
            
        } catch {
            authError = "Token exchange failed: \(error.localizedDescription)"
        }
    }
    
    private func refreshTokenIfNeeded() async {
        do {
            // Check expiration
            guard let expiresAtString = try keychain.readString(account: StravaConfig.expiresAtKey),
                  let expiresAt = Double(expiresAtString) else {
                return
            }
            
            let expirationDate = Date(timeIntervalSince1970: expiresAt)
            // Refresh if token expires in less than 5 minutes
            guard expirationDate.timeIntervalSinceNow < 300 else {
                return
            }
            
            guard let refreshToken = try keychain.readString(account: StravaConfig.refreshTokenKey) else {
                isAuthenticated = false
                return
            }
            
            var request = URLRequest(url: URL(string: StravaConfig.tokenUrl)!)
            request.httpMethod = "POST"
            request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
            
            let bodyParams = [
                "client_id": StravaConfig.clientId,
                "client_secret": StravaConfig.clientSecret,
                "refresh_token": refreshToken,
                "grant_type": "refresh_token"
            ]
            
            request.httpBody = bodyParams
                .map { "\($0.key)=\($0.value)" }
                .joined(separator: "&")
                .data(using: .utf8)
            
            let (data, response) = try await URLSession.shared.data(for: request)
            
            guard let httpResponse = response as? HTTPURLResponse,
                  httpResponse.statusCode == 200 else {
                print("Token refresh failed")
                isAuthenticated = false
                return
            }
            
            try parseAndStoreTokenResponse(data: data)
            isAuthenticated = true
            
        } catch {
            print("Error refreshing token: \(error)")
            isAuthenticated = false
        }
    }
    
    private func parseAndStoreTokenResponse(data: Data) throws {
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw NSError(domain: "StravaAuth", code: 1, userInfo: [NSLocalizedDescriptionKey: "Invalid JSON response"])
        }
        
        guard let accessToken = json["access_token"] as? String,
              let refreshToken = json["refresh_token"] as? String,
              let expiresAt = json["expires_at"] as? Double else {
            throw NSError(domain: "StravaAuth", code: 2, userInfo: [NSLocalizedDescriptionKey: "Missing token fields"])
        }
        
        try keychain.upsertString(accessToken, account: StravaConfig.accessTokenKey)
        try keychain.upsertString(refreshToken, account: StravaConfig.refreshTokenKey)
        try keychain.upsertString(String(expiresAt), account: StravaConfig.expiresAtKey)
        
        // Store athlete info if available
        if let athlete = json["athlete"] as? [String: Any],
           let athleteId = athlete["id"] as? Int {
            try keychain.upsertString(String(athleteId), account: StravaConfig.athleteIdKey)
            
            if let firstName = athlete["firstname"] as? String {
                athleteName = firstName
            }
        }
    }
}
