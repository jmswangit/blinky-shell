import Foundation

/// Tautulli's Plex OAuth helper calls `plex_oauth_window.document.body`
/// immediately after `window.open('')`. In a WKWebView popup that document is
/// not synchronously available, which throws and aborts the whole login before
/// it ever requests a Plex PIN. Re-implement the same flow without that
/// synchronous document access.
enum TautulliFix {
    static let source = #"""
    (function () {
      if (window.__blinkyPlexOAuthPatched) { return; }
      if (typeof window.PlexOAuth !== 'function') { return; }
      window.__blinkyPlexOAuthPatched = true;

      window.PlexOAuth = function (successCallback, errorCallback, maxRetryCallback, pollingCallback, preFunction, clientID) {
        if (typeof preFunction === 'function') { preFunction(); }
        if (window.plex_oauth_window) {
          try { window.plex_oauth_window.close(); } catch (e) {}
        }

        var win = window.open('', 'Plex-OAuth', 'width=600,height=700');
        window.plex_oauth_window = win;
        if (!win) {
          if (typeof errorCallback === 'function') { errorCallback(); }
          return;
        }

        try { $(win.document.body).html(plex_oauth_loader); } catch (e) {}

        getPlexOAuthPin(clientID).then(function (data) {
          var headers = getPlexHeaders(clientID);
          var pin = data.pin;
          var code = data.code;
          var params = {
            'clientID': headers['X-Plex-Client-Identifier'],
            'context[device][product]': headers['X-Plex-Product'],
            'context[device][version]': headers['X-Plex-Version'],
            'context[device][platform]': headers['X-Plex-Platform'],
            'context[device][platformVersion]': headers['X-Plex-Platform-Version'],
            'context[device][device]': headers['X-Plex-Device'],
            'context[device][deviceName]': headers['X-Plex-Device-Name'],
            'context[device][model]': headers['X-Plex-Model'],
            'context[device][screenResolution]': headers['X-Plex-Device-Screen-Resolution'],
            'context[device][layout]': 'desktop',
            'code': code
          };

          try { win.location = 'https://app.plex.tv/auth/#!?' + encodeData(params); } catch (e) {}

          window.polling = pin;
          var maxPollCount = 120;

          (function poll() {
            maxPollCount--;
            $.ajax({
              url: 'https://plex.tv/api/v2/pins/' + pin,
              type: 'GET',
              headers: headers,
              success: function (data) {
                if (data.authToken) {
                  window.polling = null;
                  try { win.close(); } catch (e) {}
                  if (typeof successCallback === 'function') { successCallback(data.authToken); }
                }
              },
              complete: function () {
                if (maxPollCount <= 0) {
                  try { win.close(); } catch (e) {}
                  if (typeof maxRetryCallback === 'function') { maxRetryCallback(); }
                } else if (window.polling === pin) {
                  setTimeout(poll, 1000);
                  if (typeof pollingCallback === 'function') { pollingCallback(maxPollCount); }
                }
              },
              timeout: 1000
            });
          })();
        }, function () {
          try { win.close(); } catch (e) {}
          if (typeof errorCallback === 'function') { errorCallback(); }
        });
      };
    })();
    """#
}
