import Foundation

/// Injected into every main-frame page.
///
/// Two jobs:
/// 1. Keep `maximum-scale=1` on the viewport so iOS never auto-zooms into a
///    focused text field (and never pinch-zooms). This is the same lock
///    Audiobookshelf already injects; it does not change any font sizes.
/// 2. On the iPhone Duo outer display, widen the layout viewport to the real
///    screen width so the page fills the strip the system reserves on the
///    right. Detection uses `env(safe-area-inset-right)` after forcing
///    `viewport-fit=cover`; it is ~84 px only on the Duo outer display, 0 in
///    Split View, and 44–59 px on a normal notched iPhone in landscape.
enum DuoFit {
    static let source = #"""
    (function () {
      if (window.__blinkyDuoFit) { return; }
      window.__blinkyDuoFit = true;

      var MIN = 60;
      var MAX = 160;
      var originalViewport = null;
      var applied = false;

      function ensureMeta() {
        var head = document.head || document.getElementsByTagName('head')[0];
        if (!head) { return null; }
        var meta = document.querySelector('meta[name="viewport"]');
        if (!meta) {
          meta = document.createElement('meta');
          meta.setAttribute('name', 'viewport');
          head.appendChild(meta);
        }
        return meta;
      }

      function ensureCover(meta) {
        var content = meta.getAttribute('content') || '';
        if (!/viewport-fit\s*=\s*cover/.test(content)) {
          meta.setAttribute('content', content + (content ? ', ' : '') + 'viewport-fit=cover');
        }
      }

      // Keep iOS from zooming the page when a text field is focused. Uses
      // maximum-scale only; input font sizes are left untouched.
      function ensureZoomLock(meta) {
        var content = meta.getAttribute('content') || '';
        var parts = content.split(',').map(function (s) { return s.trim(); }).filter(Boolean);
        var kept = [];
        for (var i = 0; i < parts.length; i++) {
          if (!/^(maximum-scale|user-scalable)\s*=/i.test(parts[i])) {
            kept.push(parts[i]);
          }
        }
        kept.push('maximum-scale=1');
        var next = kept.join(', ');
        if (next !== content) {
          meta.setAttribute('content', next);
        }
      }

      function readInset() {
        var inset = 0;
        try {
          var probe = document.createElement('div');
          probe.style.cssText = 'position:fixed;top:0;right:0;height:1px;width:env(safe-area-inset-right);visibility:hidden;pointer-events:none';
          var parent = document.documentElement || document.body;
          if (parent) { parent.appendChild(probe); }
          inset = Math.round(probe.getBoundingClientRect().width || 0);
          if (probe.parentNode) { probe.parentNode.removeChild(probe); }
        } catch (e) {}
        return inset;
      }

      function apply(readInsetValue) {
        try {
          var meta = ensureMeta();
          if (!meta) { return; }

          var current = meta.getAttribute('content') || '';
          if (originalViewport === null) { originalViewport = current; }

          // Make env(safe-area-inset-*) meaningful for full-screen rendering.
          ensureCover(meta);
          ensureZoomLock(meta);

          var inset = readInsetValue ? readInset() : 0;
          var outer = inset >= MIN && inset <= MAX;
          var screenW = Math.round((window.screen && window.screen.width) || 0);

          if (!outer) {
            if (applied) {
              applied = false;
              document.documentElement.removeAttribute('data-blinky-duo-fit');
              meta.setAttribute('content', originalViewport);
              ensureCover(meta);
              ensureZoomLock(meta);
              try { console.log('[Homepage] duo-fit restored'); } catch (e) {}
            }
            return;
          }

          applied = true;
          document.documentElement.setAttribute('data-blinky-duo-fit', '');
          meta.setAttribute('content',
            'width=' + screenW + ', initial-scale=1, maximum-scale=1, viewport-fit=cover');
          try {
            console.log('[Homepage] duo-fit applied', {
              screenWidth: screenW,
              innerWidth: Math.round(window.innerWidth || 0),
              inset: inset
            });
          } catch (e) {}

          if (!document.getElementById('blinky-duo-fit-style')) {
            var style = document.createElement('style');
            style.id = 'blinky-duo-fit-style';
            style.textContent = 'html[data-blinky-duo-fit],html[data-blinky-duo-fit] body{padding-right:0!important;margin-right:0!important;max-width:none!important}';
            (document.head || document.documentElement).appendChild(style);
          }
        } catch (e) {}
      }

      function boot() {
        // First pass installs viewport-fit=cover + the zoom lock; the inset is
        // only readable after WebKit has re-laid out the page.
        apply(false);
        setTimeout(function () { apply(true); }, 150);
        setTimeout(function () { apply(true); }, 600);
      }

      if (document.readyState === 'loading') {
        document.addEventListener('DOMContentLoaded', boot, { once: true });
        setTimeout(boot, 300);
      } else {
        boot();
      }

      var resizeTimer = null;
      function onResize() {
        clearTimeout(resizeTimer);
        resizeTimer = setTimeout(function () { apply(true); }, 200);
      }

      window.addEventListener('resize', onResize);
      window.addEventListener('orientationchange', onResize);
      window.addEventListener('pageshow', onResize);
    })();
    """#
}
