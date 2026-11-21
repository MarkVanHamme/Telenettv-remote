import SwiftUI
import WebKit

/// Toont de officiële Telenet TV-website. Je meldt je daar aan met je Telenet-login;
/// zodra de site een `refreshToken` van het Telenet-platform ontvangt, pikt de app dat op.
/// Je wachtwoord passeert nooit langs de app zelf.
struct TelenetLoginWebView: UIViewRepresentable {
    static let startURL = URL(string: "https://www.telenet.tv/")!

    let onToken: (String) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(onToken: onToken) }

    func makeUIView(context: Context) -> WKWebView {
        let controller = WKUserContentController()
        controller.add(context.coordinator, name: "token")
        controller.addUserScript(WKUserScript(source: Self.hookScript,
                                              injectionTime: .atDocumentStart,
                                              forMainFrameOnly: false))
        let config = WKWebViewConfiguration()
        config.userContentController = controller
        config.websiteDataStore = .default()

        let webView = WKWebView(frame: .zero, configuration: config)
        // De Telenet TV-site verwijst mobiele browsers door naar de App Store;
        // met een desktop-user-agent krijg je de gewone loginpagina.
        webView.customUserAgent =
            "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.5 Safari/605.1.15"
        webView.load(URLRequest(url: Self.startURL))
        return webView
    }

    func updateUIView(_ uiView: WKWebView, context: Context) {}

    static func dismantleUIView(_ uiView: WKWebView, coordinator: Coordinator) {
        uiView.stopLoading()
        uiView.configuration.userContentController.removeScriptMessageHandler(forName: "token")
    }

    @MainActor
    final class Coordinator: NSObject, WKScriptMessageHandler {
        let onToken: (String) -> Void
        private var delivered = false

        init(onToken: @escaping (String) -> Void) { self.onToken = onToken }

        func userContentController(_ userContentController: WKUserContentController,
                                   didReceive message: WKScriptMessage) {
            guard !delivered, let token = message.body as? String, token.count > 20 else { return }
            delivered = true
            onToken(token)
        }
    }

    /// Luistert mee met fetch/XHR-antwoorden en localStorage op zoek naar een refreshToken.
    private static let hookScript = """
    (function () {
      function check(text) {
        try {
          if (!text || typeof text !== 'string') return;
          var m = text.match(/"refreshToken"\\s*:\\s*"([^"]+)"/);
          if (m) window.webkit.messageHandlers.token.postMessage(m[1]);
        } catch (e) {}
      }
      var origFetch = window.fetch;
      if (origFetch) {
        window.fetch = function () {
          return origFetch.apply(this, arguments).then(function (resp) {
            try { resp.clone().text().then(check); } catch (e) {}
            return resp;
          });
        };
      }
      var origSend = XMLHttpRequest.prototype.send;
      XMLHttpRequest.prototype.send = function () {
        this.addEventListener('load', function () {
          try {
            if (this.responseType === '' || this.responseType === 'text') check(this.responseText);
            else if (this.responseType === 'json') check(JSON.stringify(this.response));
          } catch (e) {}
        });
        return origSend.apply(this, arguments);
      };
      setInterval(function () {
        try {
          for (var i = 0; i < localStorage.length; i++) check(localStorage.getItem(localStorage.key(i)));
          for (var j = 0; j < sessionStorage.length; j++) check(sessionStorage.getItem(sessionStorage.key(j)));
        } catch (e) {}
      }, 1500);
    })();
    """
}
