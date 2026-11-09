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

    func copySelection(completion: @escaping (String) -> Void) {
        webView?.evaluateJavaScript("window.getSelection().toString()") { result, _ in
            completion((result as? String) ?? "")
        }
    }

    func pasteText(_ text: String, completion: @escaping (Bool) -> Void) {
        guard let data = try? JSONSerialization.data(withJSONObject: [text]),
              let json = String(data: data, encoding: .utf8) else {
            completion(false)
            return
        }

        let js = """
        (function(args) {
          var text = args[0];
          var el = document.activeElement;
          if (!el) { return false; }
          var tag = (el.tagName || '').toLowerCase();
          if (tag === 'input' || tag === 'textarea') {
            var start = el.selectionStart != null ? el.selectionStart : el.value.length;
            var end = el.selectionEnd != null ? el.selectionEnd : el.value.length;
            el.value = el.value.slice(0, start) + text + el.value.slice(end);
            el.selectionStart = el.selectionEnd = start + text.length;
            el.dispatchEvent(new Event('input', { bubbles: true }));
            el.dispatchEvent(new Event('change', { bubbles: true }));
            return true;
          }
          if (el.isContentEditable) {
            document.execCommand('insertText', false, text);
            return true;
          }
          return false;
        })(\(json));
        """

        webView?.evaluateJavaScript(js) { result, _ in
            completion((result as? Bool) ?? false)
        }
    }
}
