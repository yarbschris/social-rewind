import RewindCore
import SwiftUI
import UIKit
import WebKit

/// A WKWebView for one platform with the two engine bundles injected at document start.
struct WebViewContainer: UIViewRepresentable {
    static let messageHandlerName = "socialRewind"

    let platform: Platform
    let startURL: URL
    let scripts: InjectedScripts
    let controller: BrowserController

    func makeCoordinator() -> Coordinator {
        Coordinator(platform: platform, controller: controller)
    }

    func makeUIView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        // Separate, persistent cookie jar per platform (iOS 17+).
        configuration.websiteDataStore = WKWebsiteDataStore(forIdentifier: platform.websiteDataStoreID)
        configuration.allowsInlineMediaPlayback = true
        // No autoplay with sound.
        configuration.mediaTypesRequiringUserActionForPlayback = .audio
        // Identify as Mobile Safari, not an unknown embedded browser, so the platform's login offers
        // its normal two-factor options (see BrowserIdentity).
        configuration.applicationNameForUserAgent = BrowserIdentity.safariApplicationName(systemVersion: UIDevice.current.systemVersion)

        let contentController = configuration.userContentController
        scripts.install(in: contentController)
        // Registered only in the isolated world, so the page's own scripts can't see or call it.
        contentController.add(WeakScriptMessageHandler(context.coordinator),
                              contentWorld: InjectedScripts.isolatedWorld, name: Self.messageHandlerName)

        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.navigationDelegate = context.coordinator
        webView.uiDelegate = context.coordinator
        webView.allowsBackForwardNavigationGestures = true
        #if DEBUG
        webView.isInspectable = true // Safari → Develop menu; the spikes depend on this
        #endif

        controller.webView = webView
        context.coordinator.observeURL(of: webView)
        webView.load(URLRequest(url: startURL))
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {}

    static func dismantleUIView(_ webView: WKWebView, coordinator: Coordinator) {
        coordinator.stopObserving()
        webView.stopLoading()
        webView.configuration.userContentController.removeScriptMessageHandler(
            forName: messageHandlerName, contentWorld: InjectedScripts.isolatedWorld)
    }

    // MARK: - Coordinator

    @MainActor
    final class Coordinator: NSObject, WKNavigationDelegate, WKUIDelegate, WKScriptMessageHandler {
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
