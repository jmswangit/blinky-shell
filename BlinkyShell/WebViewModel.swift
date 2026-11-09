import Foundation
import WebKit

final class WebViewModel: ObservableObject {
    @Published var canGoBack = false
    @Published var canGoForward = false
    @Published var isLoading = false
    @Published var progress: Double = 0
    @Published var title = ""
    @Published var currentURL: URL?
    @Published var errorMessage: String?

    weak var webView: WKWebView?

    func goBack() {
        webView?.goBack()
    }

    func goForward() {
        webView?.goForward()
    }

    func reload() {
        webView?.reload()
    }

    func stop() {
        webView?.stopLoading()
    }

    func goHome() {
        guard let url = Settings.shared.homeURL else { return }
        webView?.load(URLRequest(url: url))
    }

    func setCookies(_ cookies: [HTTPCookie]) {
        guard !cookies.isEmpty,
              let store = webView?.configuration.websiteDataStore.httpCookieStore else {
            return
        }

        let group = DispatchGroup()
        for cookie in cookies {
            group.enter()
            store.setCookie(cookie) { group.leave() }
        }
        group.notify(queue: .main) { [weak self] in
            self?.reload()
        }
    }
}

}
