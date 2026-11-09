import SwiftUI
import WebKit
import UIKit
import UniformTypeIdentifiers

struct WebView: UIViewRepresentable {
    @ObservedObject var model: WebViewModel
    let initialURL: URL

    func makeCoordinator() -> Coordinator {
        Coordinator(model: model)
    }

    func makeUIView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .default()
        configuration.defaultWebpagePreferences.allowsContentJavaScript = true
        configuration.allowsInlineMediaPlayback = true
        configuration.mediaTypesRequiringUserActionForPlayback = []
        configuration.preferences.isElementFullscreenEnabled = true
        configuration.preferences.isTextInteractionEnabled = true
        configuration.preferences.javaScriptCanOpenWindowsAutomatically = true

        let script = WKUserScript(
            source: DuoFit.source,
            injectionTime: .atDocumentStart,
            forMainFrameOnly: true
        )
        configuration.userContentController.addUserScript(script)

        let tautulliScript = WKUserScript(
            source: TautulliFix.source,
            injectionTime: .atDocumentEnd,
            forMainFrameOnly: true
        )
        configuration.userContentController.addUserScript(tautulliScript)

        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.navigationDelegate = context.coordinator
        webView.uiDelegate = context.coordinator
        webView.allowsBackForwardNavigationGestures = false
        webView.scrollView.contentInsetAdjustmentBehavior = .never
        webView.scrollView.bounces = true
        webView.isOpaque = false
        webView.backgroundColor = .black
        webView.scrollView.backgroundColor = .black
        webView.isInspectable = true
        webView.allowsLinkPreview = true

        let backGesture = UIScreenEdgePanGestureRecognizer(
            target: context.coordinator,
            action: #selector(Coordinator.handleBackEdge(_:))
        )
        backGesture.edges = .left
        backGesture.delegate = context.coordinator
        backGesture.cancelsTouchesInView = false
        webView.addGestureRecognizer(backGesture)

        let forwardGesture = UIScreenEdgePanGestureRecognizer(
            target: context.coordinator,
            action: #selector(Coordinator.handleForwardEdge(_:))
        )
        forwardGesture.edges = .right
        forwardGesture.delegate = context.coordinator
        forwardGesture.cancelsTouchesInView = false
        webView.addGestureRecognizer(forwardGesture)

        if #available(iOS 26.0, *) {
            webView.obscuredContentInsets = .zero
        }

        context.coordinator.attach(webView)
        model.webView = webView
        webView.load(URLRequest(url: initialURL))
        return webView
    }

    func updateUIView(_ uiView: WKWebView, context: Context) {
        // Navigation is driven by the coordinator and the toolbar.
    }
}

extension WebView {
    final class Coordinator: NSObject, WKNavigationDelegate, WKUIDelegate, WKDownloadDelegate, UIDocumentPickerDelegate, UIGestureRecognizerDelegate {
        private let model: WebViewModel
        private weak var webView: WKWebView?
        private var observations: [NSKeyValueObservation] = []
        private var filePickerCompletion: (([URL]?) -> Void)?
        private var downloadDestinations: [ObjectIdentifier: URL] = [:]
        private var popups: [(controller: UIViewController, webView: WKWebView)] = []

        init(model: WebViewModel) {
            self.model = model
        }

        func attach(_ webView: WKWebView) {
            self.webView = webView
            observations = [
                webView.observe(\.canGoBack, options: [.initial, .new]) { [weak self] webView, _ in
                    self?.onMain { self?.model.canGoBack = webView.canGoBack }
                },
                webView.observe(\.canGoForward, options: [.initial, .new]) { [weak self] webView, _ in
                    self?.onMain { self?.model.canGoForward = webView.canGoForward }
                },
                webView.observe(\.estimatedProgress, options: [.initial, .new]) { [weak self] webView, _ in
                    self?.onMain { self?.model.progress = webView.estimatedProgress }
                },
                webView.observe(\.title, options: [.initial, .new]) { [weak self] webView, _ in
                    self?.onMain { self?.model.title = webView.title ?? "" }
                },
                webView.observe(\.url, options: [.initial, .new]) { [weak self] webView, _ in
                    self?.onMain { self?.model.currentURL = webView.url }
                },
                webView.observe(\.isLoading, options: [.initial, .new]) { [weak self] webView, _ in
                    self?.onMain { self?.model.isLoading = webView.isLoading }
                }
            ]
        }

        private func onMain(_ block: @escaping () -> Void) {
            if Thread.isMainThread {
                block()
            } else {
                DispatchQueue.main.async(execute: block)
            }
        }

        // MARK: - Edge swipe navigation

        @objc func handleBackEdge(_ gesture: UIScreenEdgePanGestureRecognizer) {
            guard gesture.state == .ended else { return }
            let translation = gesture.translation(in: gesture.view)
            let velocity = gesture.velocity(in: gesture.view)
            if translation.x > 60 || velocity.x > 500 {
                webView?.goBack()
            }
        }

        @objc func handleForwardEdge(_ gesture: UIScreenEdgePanGestureRecognizer) {
            guard gesture.state == .ended else { return }
            let translation = gesture.translation(in: gesture.view)
            let velocity = gesture.velocity(in: gesture.view)
            if translation.x < -60 || velocity.x < -500 {
                webView?.goForward()
            }
        }

        func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
            guard let webView = webView,
                  let edge = gestureRecognizer as? UIScreenEdgePanGestureRecognizer else {
                return true
            }
            return edge.edges == .left ? webView.canGoBack : webView.canGoForward
        }

        // MARK: - Navigation policy

        func webView(_ webView: WKWebView,
                     decidePolicyFor navigationAction: WKNavigationAction,
                     decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
            guard let url = navigationAction.request.url else {
                decisionHandler(.cancel)
                return
            }

            switch (url.scheme ?? "").lowercased() {
            case "http", "https", "about", "blob", "data":
                decisionHandler(.allow)
            case "mailto", "tel", "sms", "facetime", "itms", "itms-apps":
                UIApplication.shared.open(url, options: [:], completionHandler: nil)
                decisionHandler(.cancel)
            default:
                decisionHandler(.cancel)
            }
        }

        func webView(_ webView: WKWebView,
                     decidePolicyFor navigationResponse: WKNavigationResponse,
                     decisionHandler: @escaping (WKNavigationResponsePolicy) -> Void) {
            if navigationResponse.canShowMIMEType {
                decisionHandler(.allow)
            } else {
                decisionHandler(.download)
            }
        }

        // MARK: - Errors

        func webView(_ webView: WKWebView,
                     didFailProvisionalNavigation navigation: WKNavigation!,
                     withError error: Error) {
            report(error)
        }

        func webView(_ webView: WKWebView,
                     didFail navigation: WKNavigation!,
                     withError error: Error) {
            report(error)
        }

        private func report(_ error: Error) {
            let nsError = error as NSError
            if nsError.domain == NSURLErrorDomain && nsError.code == NSURLErrorCancelled {
                return
            }
            onMain { [weak self] in
                self?.model.errorMessage = error.localizedDescription
            }
        }

        // MARK: - Authentication

        func webView(_ webView: WKWebView,
                     didReceive challenge: URLAuthenticationChallenge,
                     completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void) {
            completionHandler(.performDefaultHandling, nil)
        }

        // MARK: - target=_blank / window.open

        func webView(_ webView: WKWebView,
                     createWebViewWith configuration: WKWebViewConfiguration,
                     for navigationAction: WKNavigationAction,
                     windowFeatures: WKWindowFeatures) -> WKWebView? {
            let requestURL = navigationAction.request.url
            let scheme = (requestURL?.scheme ?? "").lowercased()
            let isBlank = requestURL == nil || (scheme == "about" && (requestURL?.absoluteString.hasPrefix("about:blank") ?? false))
            let isWeb = scheme == "http" || scheme == "https"

            if !isWeb && !isBlank {
                if let requestURL {
                    UIApplication.shared.open(requestURL, options: [:], completionHandler: nil)
                }
                return nil
            }

            let host = (requestURL?.host ?? "").lowercased()
            let authHosts = [
                "plex.tv", "app.plex.tv",
                "accounts.google.com",
                "auth.swan.cool",
                "login.microsoftonline.com",
                "appleid.apple.com"
            ]
            let isAuthHost = authHosts.contains { host == $0 || host.hasSuffix("." + $0) }
            let isFromPopup = popups.contains { $0.webView === webView }
            let wantsPopup = isBlank
                || isAuthHost
                || isFromPopup
                || windowFeatures.width != nil
                || windowFeatures.height != nil
                || navigationAction.navigationType == .other

            // Normal target=_blank links stay in the main webview.
            if !wantsPopup {
                webView.load(navigationAction.request)
                return nil
            }

            // OAuth/SSO and JS-opened windows need a real popup so
            // window.open() returns a valid WindowProxy and window.close()
            // works. Popups share the opener's process pool and cookie store.
            let popup = WKWebView(frame: .zero, configuration: configuration)
            popup.navigationDelegate = self
            popup.uiDelegate = self
            popup.allowsBackForwardNavigationGestures = true
            popup.scrollView.contentInsetAdjustmentBehavior = .never
            popup.isOpaque = false
            popup.backgroundColor = .black
            popup.scrollView.backgroundColor = .black
            popup.isInspectable = true
            if #available(iOS 26.0, *) {
                popup.obscuredContentInsets = .zero
            }

            let controller = PopupViewController(webView: popup)
            let navigation = UINavigationController(rootViewController: controller)
            navigation.modalPresentationStyle = .pageSheet

            controller.onClose = { [weak self, weak navigation] in
                guard let self, let navigation else { return }
                self.popups.removeAll { $0.controller === navigation }
            }

            popups.append((controller: navigation, webView: popup))
            present(navigation)
            return popup
        }

        func webViewDidClose(_ webView: WKWebView) {
            guard let index = popups.firstIndex(where: { $0.webView === webView }) else { return }
            let entry = popups.remove(at: index)
            entry.controller.dismiss(animated: true)
        }

        // MARK: - JavaScript dialogs

        func webView(_ webView: WKWebView,
                     runJavaScriptAlertPanelWithMessage message: String,
                     initiatedByFrame frame: WKFrameInfo,
                     completionHandler: @escaping () -> Void) {
            let alert = UIAlertController(title: nil, message: message, preferredStyle: .alert)
            alert.addAction(UIAlertAction(title: "OK", style: .default) { _ in completionHandler() })
            present(alert)
        }

        func webView(_ webView: WKWebView,
                     runJavaScriptConfirmPanelWithMessage message: String,
                     initiatedByFrame frame: WKFrameInfo,
                     completionHandler: @escaping (Bool) -> Void) {
            let alert = UIAlertController(title: nil, message: message, preferredStyle: .alert)
            alert.addAction(UIAlertAction(title: "Cancel", style: .cancel) { _ in completionHandler(false) })
            alert.addAction(UIAlertAction(title: "OK", style: .default) { _ in completionHandler(true) })
            present(alert)
        }

        func webView(_ webView: WKWebView,
                     runJavaScriptTextInputPanelWithPrompt prompt: String,
                     defaultText: String?,
                     initiatedByFrame frame: WKFrameInfo,
                     completionHandler: @escaping (String?) -> Void) {
            let alert = UIAlertController(title: nil, message: prompt, preferredStyle: .alert)
            alert.addTextField { field in field.text = defaultText }
            alert.addAction(UIAlertAction(title: "Cancel", style: .cancel) { _ in completionHandler(nil) })
            alert.addAction(UIAlertAction(title: "OK", style: .default) { _ in
                completionHandler(alert.textFields?.first?.text)
            })
            present(alert)
        }

        // MARK: - File upload

        @available(iOS 18.4, *)
        func webView(_ webView: WKWebView,
                     runOpenPanelWith parameters: WKOpenPanelParameters,
                     initiatedByFrame frame: WKFrameInfo,
                     completionHandler: @escaping ([URL]?) -> Void) {
            filePickerCompletion = completionHandler
            let picker = UIDocumentPickerViewController(forOpeningContentTypes: [.item], asCopy: true)
            picker.delegate = self
            picker.allowsMultipleSelection = parameters.allowsMultipleSelection
            present(picker)
        }

        func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
            filePickerCompletion?(urls)
            filePickerCompletion = nil
        }

        func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
            filePickerCompletion?(nil)
            filePickerCompletion = nil
        }

        // MARK: - Downloads

        func webView(_ webView: WKWebView,
                     navigationAction: WKNavigationAction,
                     didBecome download: WKDownload) {
            download.delegate = self
        }

        func webView(_ webView: WKWebView,
                     navigationResponse: WKNavigationResponse,
                     didBecome download: WKDownload) {
            download.delegate = self
        }

        func download(_ download: WKDownload,
                      decideDestinationUsing response: URLResponse,
                      suggestedFilename: String,
                      completionHandler: @escaping (URL?) -> Void) {
            let directory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            var destination = directory.appendingPathComponent(suggestedFilename)
            var counter = 1

            while FileManager.default.fileExists(atPath: destination.path) {
                let base = (suggestedFilename as NSString).deletingPathExtension
                let ext = (suggestedFilename as NSString).pathExtension
                let name = ext.isEmpty ? "\(base)-\(counter)" : "\(base)-\(counter).\(ext)"
                destination = directory.appendingPathComponent(name)
                counter += 1
            }

            downloadDestinations[ObjectIdentifier(download)] = destination
            completionHandler(destination)
        }

        func downloadDidFinish(_ download: WKDownload) {
            guard let destination = downloadDestinations.removeValue(forKey: ObjectIdentifier(download)) else {
                return
            }
            onMain { [weak self] in
                self?.share(destination)
            }
        }

        func download(_ download: WKDownload, didFailWithError error: Error, resumeData: Data?) {
            downloadDestinations.removeValue(forKey: ObjectIdentifier(download))
            report(error)
        }

        // MARK: - Helpers

        private func present(_ viewController: UIViewController) {
            onMain { [weak self] in
                guard let presenter = self?.topViewController() else { return }
                presenter.present(viewController, animated: true)
            }
        }

        private func share(_ url: URL) {
            guard let presenter = topViewController() else { return }
            let activity = UIActivityViewController(activityItems: [url], applicationActivities: nil)
            if let popover = activity.popoverPresentationController {
                popover.sourceView = presenter.view
                popover.sourceRect = CGRect(x: presenter.view.bounds.midX,
                                            y: presenter.view.bounds.midY,
                                            width: 1,
                                            height: 1)
                popover.permittedArrowDirections = []
            }
            presenter.present(activity, animated: true)
        }

        private func topViewController() -> UIViewController? {
            let scenes = UIApplication.shared.connectedScenes
            let windowScene = scenes.first { $0.activationState == .foregroundActive } as? UIWindowScene
            let window = windowScene?.windows.first { $0.isKeyWindow } ?? windowScene?.windows.first
            var controller = window?.rootViewController
            while let presented = controller?.presentedViewController {
                controller = presented
            }
            return controller
        }
    }
}

final class PopupViewController: UIViewController {
    private let webView: WKWebView
    var onClose: (() -> Void)?

    init(webView: WKWebView) {
        self.webView = webView
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black

        webView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(webView)
        NSLayoutConstraint.activate([
            webView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            webView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            webView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            webView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])

        navigationItem.title = "Sign in"
        navigationItem.rightBarButtonItem = UIBarButtonItem(
            barButtonSystemItem: .done,
            target: self,
            action: #selector(done)
        )
    }

    @objc private func done() {
        onClose?()
        dismiss(animated: true)
    }
}
