import Foundation

/// Tautulli's Plex OAuth flow does a cross-origin `$.ajax` to plex.tv and then
/// drives a popup via `plex_oauth_window.document`. Both are unreliable inside
/// WKWebView. Hand the whole ceremony to native code instead: request the Plex
/// PIN with URLSession, show the Plex auth page in a native popup, poll the PIN
/// natively, then call Tautulli's own `signIn(true, token)`.
enum TautulliFix {
    static let source = #"""
    (function () {
      if (window.__blinkyPlexOAuthPatched) { return; }
      if (typeof window.PlexOAuth !== 'function') { return; }
      window.__blinkyPlexOAuthPatched = true;

      window.PlexOAuth = function (successCallback, errorCallback, maxRetryCallback, pollingCallback, preFunction, clientID) {
        if (typeof preFunction === 'function') { preFunction(); }
        try {
          window.webkit.messageHandlers.blinkyPlex.postMessage({ clientID: clientID || '' });
        } catch (e) {
          if (typeof errorCallback === 'function') { errorCallback(); }
        }
      };
    })();
    """#
}
