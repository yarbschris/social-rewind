import RewindCore
import SwiftUI
import UIKit
import WebKit

/// Shows a platform's kept web view (`BrowserSession`). The web view outlives this view: closing
/// the browser takes it out of the hierarchy without tearing it down.
struct WebViewContainer: UIViewRepresentable {
    static let messageHandlerName = "socialRewind"

    let webView: WKWebView

    func makeUIView(context: Context) -> UIView {
        let host = UIView()
        host.backgroundColor = .systemBackground
        embed(in: host)
        return host
    }

    func updateUIView(_ host: UIView, context: Context) {}

    static func dismantleUIView(_ host: UIView, coordinator: ()) {
        // Leave the web view alone if another host has already taken it.
        for view in host.subviews where view is WKWebView { view.removeFromSuperview() }
    }

    private func embed(in host: UIView) {
        webView.removeFromSuperview()
        // Constraints rather than a frame: the new host starts at zero size, and shrinking the
        // kept page to nothing and back would reflow it and lose the scroll position.
        webView.translatesAutoresizingMaskIntoConstraints = false
        host.addSubview(webView)
        NSLayoutConstraint.activate([
            webView.leadingAnchor.constraint(equalTo: host.leadingAnchor),
            webView.trailingAnchor.constraint(equalTo: host.trailingAnchor),
            webView.topAnchor.constraint(equalTo: host.topAnchor),
            webView.bottomAnchor.constraint(equalTo: host.bottomAnchor),
        ])
    }

    /// A WKWebView for one platform with the two engine bundles injected at document start.
    static func makeWebView(platform: Platform, scripts: InjectedScripts, delegate: Delegate) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        // Separate, persistent cookie jar per platform (iOS 17+).
        configuration.websiteDataStore = WKWebsiteDataStore(forIdentifier: platform.websiteDataStoreID)
        configuration.allowsInlineMediaPlayback = true
        // No autoplay with sound.
        configuration.mediaTypesRequiringUserActionForPlayback = .audio

        let contentController = configuration.userContentController
        scripts.install(in: contentController)
        // Registered only in the isolated world, so the page's own scripts can't see or call it.
        contentController.add(WeakScriptMessageHandler(delegate),
                              contentWorld: InjectedScripts.isolatedWorld, name: messageHandlerName)

        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.navigationDelegate = delegate
        webView.uiDelegate = delegate
        webView.allowsBackForwardNavigationGestures = true
        #if DEBUG
        webView.isInspectable = true // Safari → Develop menu; the spikes depend on this
        #endif
        return webView
    }

    // MARK: - Delegate

    @MainActor
    final class Delegate: NSObject, WKNavigationDelegate, WKUIDelegate, WKScriptMessageHandler {
        let platform: Platform
        let policy: HostPolicy
        let controller: BrowserController
        private var urlObservation: NSKeyValueObservation?

        init(platform: Platform, controller: BrowserController) {
            self.platform = platform
            self.policy = HostPolicy.for(platform)
            self.controller = controller
        }

        func observeURL(of webView: WKWebView) {
            // WKWebView.url changes on pushState/replaceState too, which is what the route backstop needs.
            urlObservation = webView.observe(\.url, options: [.new]) { [weak self] _, _ in
                MainActor.assumeIsolated {
                    guard let self else { return }
                    self.controller.urlChanged(self.controller.webView?.url)
                }
            }
        }

        func stopObserving() {
            urlObservation?.invalidate()
            urlObservation = nil
        }

        // Engine → native, isolated world only. Still untrusted: main frame + allowed origin only,
        // and BrowserController validates and rate-limits every event.
        func userContentController(_ userContentController: WKUserContentController,
                                   didReceive message: WKScriptMessage) {
            guard message.frameInfo.isMainFrame,
                  message.world.name == EngineConfigBuilder.isolatedWorldName else { return }
            let origin = message.frameInfo.securityOrigin
            guard origin.protocol == "https",
                  let originURL = URL(string: "https://\(origin.host)"),
                  policy.isAllowedWebURL(originURL),
                  let event = try? BridgeEvent(messageBody: message.body) else { return }
            controller.receive(event)
        }

        func webView(_ webView: WKWebView,
                     decidePolicyFor navigationAction: WKNavigationAction) async -> WKNavigationActionPolicy {
            guard let url = navigationAction.request.url else { return .cancel }
            let isMainFrame = navigationAction.targetFrame?.isMainFrame ?? true
            // Only a real link tap may leave the platform (opened externally). Anything else off the allowlist is cancelled.
            let userInitiated = navigationAction.navigationType == .linkActivated
            switch policy.decide(url: url, isMainFrame: isMainFrame, isUserInitiated: userInitiated) {
            case .allow:
                // Universal links: a tap on a link to the platform's own domain could hand off to the
                // native app, but that app is shielded, so the user just sees the shield.
                return .allow
            case .openExternally(let external):
                _ = await UIApplication.shared.open(external)
                return .cancel
            case .cancel:
                return .cancel
            }
        }

        func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
            controller.navigationStarted(navigation.map(ObjectIdentifier.init))
        }

        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!,
                     withError error: Error) {
            controller.navigationFailed(navigation.map(ObjectIdentifier.init))
        }

        func webView(_ webView: WKWebView, didCommit navigation: WKNavigation!) {
            // Only ever unblocks; resetting to loading happens in didStartProvisionalNavigation.
            if webView.url?.host?.lowercased() != platform.origin.host?.lowercased() {
                controller.committedOffPlatform()
            }
        }

        func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
            webView.reload()
        }

        // target="_blank" / window.open: never create a second, unfiltered web view.
        func webView(_ webView: WKWebView,
                     createWebViewWith configuration: WKWebViewConfiguration,
                     for navigationAction: WKNavigationAction,
                     windowFeatures: WKWindowFeatures) -> WKWebView? {
            guard let url = navigationAction.request.url else { return nil }
            let userInitiated = navigationAction.navigationType == .linkActivated
            switch policy.decide(url: url, isMainFrame: true, isUserInitiated: userInitiated) {
            case .allow:
                webView.load(navigationAction.request)
            case .openExternally(let external):
                UIApplication.shared.open(external)
            case .cancel:
                break
            }
            return nil
        }
    }
}

/// WKUserContentController retains its handlers strongly; this breaks the cycle.
@MainActor
final class WeakScriptMessageHandler: NSObject, WKScriptMessageHandler {
    weak var target: WKScriptMessageHandler?

    init(_ target: WKScriptMessageHandler) {
        self.target = target
    }

    func userContentController(_ userContentController: WKUserContentController,
                               didReceive message: WKScriptMessage) {
        target?.userContentController(userContentController, didReceive: message)
    }
}
