import Foundation
import AuthenticationServices

// MARK: - Config (fill in from Google Cloud Console)
enum GoogleOAuthConfig {
    /// Reverse-DNS of your iOS bundle ID — must match the URL Scheme you add in Xcode.
    static let bundleID       = "com.yourname.drivecarplayaudio"
    static let clientID       = "YOUR_CLIENT_ID.apps.googleusercontent.com"
    static let clientSecret   = "YOUR_CLIENT_SECRET"
    static let redirectURI    = "\(bundleID):/oauth2redirect"
    static let scope          = "https://www.googleapis.com/auth/drive.readonly"
}

// MARK: - Auth Service
final class GoogleAuthService: NSObject, ObservableObject {
    static let shared = GoogleAuthService()

    private let accessTokenKey  = "gd_access_token"
    private let refreshTokenKey = "gd_refresh_token"
    private let expiryKey       = "gd_token_expiry"

    private var accessToken: String?   { get { Keychain.load(forKey: accessTokenKey)  } set { if let v = newValue { Keychain.save(v, forKey: accessTokenKey)  } else { Keychain.delete(forKey: accessTokenKey)  } } }
    private var refreshToken: String?  { get { Keychain.load(forKey: refreshTokenKey) } set { if let v = newValue { Keychain.save(v, forKey: refreshTokenKey) } else { Keychain.delete(forKey: refreshTokenKey) } } }
    private var tokenExpiry: Date? {
        get { Keychain.load(forKey: expiryKey).flatMap { Double($0) }.map { Date(timeIntervalSince1970: $0) } }
        set { if let v = newValue { Keychain.save(String(v.timeIntervalSince1970), forKey: expiryKey) } else { Keychain.delete(forKey: expiryKey) } }
    }

    private var isTokenExpired: Bool {
        guard let expiry = tokenExpiry else { return true }
        return Date() >= expiry.addingTimeInterval(-60)
    }

    var isAuthenticated: Bool { accessToken != nil && !isTokenExpired }

    // MARK: - Public API

    /// Returns a valid access token, refreshing or re-authenticating as needed.
    func getValidToken() async throws -> String {
        if let token = accessToken, !isTokenExpired { return token }
        if let _ = refreshToken { return try await refreshAccessToken() }
        return try await authenticate()
    }

    @discardableResult
    func authenticate() async throws -> String {
        let url = buildAuthURL()
        let code: String = try await withCheckedThrowingContinuation { continuation in
            let session = ASWebAuthenticationSession(
                url: url,
                callbackURLScheme: GoogleOAuthConfig.bundleID
            ) { callbackURL, error in
                if let error = error {
                    continuation.resume(throwing: AuthError.sessionError(error))
                    return
                }
                guard let cbURL = callbackURL,
                      let codeItem = URLComponents(url: cbURL, resolvingAgainstBaseURL: false)?
                          .queryItems?.first(where: { $0.name == "code" }),
                      let code = codeItem.value
                else {
                    continuation.resume(throwing: AuthError.invalidCallback)
                    return
                }
                continuation.resume(returning: code)
            }
            session.prefersEphemeralWebBrowserSession = false
            // Must present from a UIWindowScene — set via anchor in SceneDelegate
            session.presentationContextProvider = self
            session.start()
        }
        return try await exchangeCode(code)
    }

    func signOut() {
        accessToken  = nil
        refreshToken = nil
        tokenExpiry  = nil
    }

    // MARK: - Private helpers

    private func buildAuthURL() -> URL {
        var c = URLComponents(string: "https://accounts.google.com/o/oauth2/v2/auth")!
        c.queryItems = [
            URLQueryItem(name: "client_id",      value: GoogleOAuthConfig.clientID),
            URLQueryItem(name: "redirect_uri",   value: GoogleOAuthConfig.redirectURI),
            URLQueryItem(name: "response_type",  value: "code"),
            URLQueryItem(name: "scope",          value: GoogleOAuthConfig.scope),
            URLQueryItem(name: "access_type",    value: "offline"),
            URLQueryItem(name: "prompt",         value: "consent"),
        ]
        return c.url!
    }

    private func exchangeCode(_ code: String) async throws -> String {
        let params: [String: String] = [
            "code":          code,
            "client_id":     GoogleOAuthConfig.clientID,
            "client_secret": GoogleOAuthConfig.clientSecret,
            "redirect_uri":  GoogleOAuthConfig.redirectURI,
            "grant_type":    "authorization_code",
        ]
        return try await postTokenRequest(params: params)
    }

    private func refreshAccessToken() async throws -> String {
        guard let refresh = refreshToken else { throw AuthError.noRefreshToken }
        let params: [String: String] = [
            "refresh_token": refresh,
            "client_id":     GoogleOAuthConfig.clientID,
            "client_secret": GoogleOAuthConfig.clientSecret,
            "grant_type":    "refresh_token",
        ]
        return try await postTokenRequest(params: params)
    }

    private func postTokenRequest(params: [String: String]) async throws -> String {
        var request = URLRequest(url: URL(string: "https://oauth2.googleapis.com/token")!)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = params.map { "\($0.key)=\($0.value)" }.joined(separator: "&").data(using: .utf8)

        let (data, _) = try await URLSession.shared.data(for: request)
        let resp = try JSONDecoder().decode(TokenResponse.self, from: data)

        accessToken  = resp.accessToken
        tokenExpiry  = Date().addingTimeInterval(TimeInterval(resp.expiresIn))
        if let rt = resp.refreshToken { refreshToken = rt }
        return resp.accessToken
    }

    // MARK: - Errors & Models

    enum AuthError: LocalizedError {
        case sessionError(Error)
        case invalidCallback
        case noRefreshToken

        var errorDescription: String? {
            switch self {
            case .sessionError(let e):  return "Authenticatie sessie mislukt: \(e.localizedDescription)"
            case .invalidCallback:      return "Ongeldige OAuth callback ontvangen."
            case .noRefreshToken:       return "Geen refresh token beschikbaar."
            }
        }
    }

    private struct TokenResponse: Decodable {
        let accessToken: String
        let expiresIn: Int
        let refreshToken: String?
        enum CodingKeys: String, CodingKey {
            case accessToken  = "access_token"
            case expiresIn    = "expires_in"
            case refreshToken = "refresh_token"
        }
    }
}

// MARK: - ASWebAuthenticationPresentationContextProviding
extension GoogleAuthService: ASWebAuthenticationPresentationContextProviding {
    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows)
            .first(where: \.isKeyWindow) ?? ASPresentationAnchor()
    }
}
