import AuthenticationServices
import UIKit

/// Logs in to Authentik through the system Safari engine (which supports
/// passkeys) and hands the resulting session cookies back to the app so they
/// can be installed in the WKWebView's cookie store.
final class SessionImporter: NSObject, ASWebAuthenticationPresentationContextProviding {
    private var session: ASWebAuthenticationSession?

    var onCookies: (([HTTPCookie]) -> Void)?
    var onError: ((String) -> Void)?

    func start() {
        guard let url = URL(string: "https://auth.swan.cool/blinky/session") else { return }

        let session = ASWebAuthenticationSession(
            url: url,
            callbackURLScheme: "blinkyshell"
        ) { [weak self] callbackURL, error in
            if let error {
                self?.onError?(error.localizedDescription)
                return
            }
            guard let callbackURL,
                  let components = URLComponents(url: callbackURL, resolvingAgainstBaseURL: false),
                  let items = components.queryItems else {
                return
            }

            var cookies: [HTTPCookie] = []
            for item in items {
                guard let value = item.value, !value.isEmpty else { continue }
                let properties: [HTTPCookiePropertyKey: Any] = [
                    .name: item.name,
                    .value: value,
                    .domain: "auth.swan.cool",
                    .path: "/",
                    .secure: true,
                    .expires: Date().addingTimeInterval(60 * 60 * 24 * 30)
                ]
                if let cookie = HTTPCookie(properties: properties) {
                    cookies.append(cookie)
                }
            }
            self?.onCookies?(cookies)
        }

        session.presentationContextProvider = self
        session.prefersEphemeralWebBrowserSession = false
        self.session = session
        session.start()
    }

    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        let scenes = UIApplication.shared.connectedScenes
        let windowScene = scenes.first { $0.activationState == .foregroundActive } as? UIWindowScene
        return windowScene?.windows.first { $0.isKeyWindow } ?? ASPresentationAnchor()
    }
}
