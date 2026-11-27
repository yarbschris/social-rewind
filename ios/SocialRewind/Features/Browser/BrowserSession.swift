import RewindCore
import UIKit
import WebKit

/// One platform's filtered browser, kept alive between opens. Closing the browser only hides the
/// web view, so reopening shows the page where the user left it instead of loading the platform
/// again and restarting its code.
///
/// Filters stay fail-closed: the engine keeps running in the hidden page, settings changed while
/// it was closed reload it on the next open (`PlatformBrowserView`), and a page whose web content
/// process was killed reloads behind the filter cover.
@MainActor
final class BrowserSession {
    let platform: Platform
    let controller: BrowserController
    private(set) var webView: WKWebView?
    /// Held here because the web view's delegates are weak.
    private var delegate: WebViewContainer.Delegate?
    private(set) var isOnScreen = false

    init(platform: Platform) {
        self.platform = platform
        self.controller = BrowserController(platform: platform)
    }

    /// The existing web view, or a new one that starts loading `startURL` with `scripts`.
    func webView(startURL: URL, scripts: InjectedScripts) -> WKWebView {
        if let webView { return webView }
        let delegate = WebViewContainer.Delegate(platform: platform, controller: controller)
        let webView = WebViewContainer.makeWebView(platform: platform, scripts: scripts, delegate: delegate)
        controller.webView = webView
        controller.installedScripts = scripts
        delegate.observeURL(of: webView)
        self.delegate = delegate
        self.webView = webView
        webView.load(URLRequest(url: startURL))
        return webView
    }

    /// The browser is showing: a new visit for the counter and reminders, and media may play again.
    func didOpen() {
        isOnScreen = true
        controller.beginVisit()
        webView?.setAllMediaPlaybackSuspended(false, completionHandler: nil)
    }

    /// The browser closed. Nothing keeps playing while it's hidden.
    func didClose() {
        isOnScreen = false
        webView?.setAllMediaPlaybackSuspended(true, completionHandler: nil)
    }

    func tearDown() {
        delegate?.stopObserving()
        if let webView {
            webView.stopLoading()
            webView.configuration.userContentController.removeScriptMessageHandler(
                forName: WebViewContainer.messageHandlerName, contentWorld: InjectedScripts.isolatedWorld)
            webView.removeFromSuperview()
        }
        webView = nil
        delegate = nil
    }
}

/// The kept sessions, one per platform. On a memory warning, sessions that aren't showing are
/// dropped; the next open starts a fresh page.
@MainActor
final class BrowserSessionStore {
    private var sessions: [Platform: BrowserSession] = [:]
    private var memoryWarning: NSObjectProtocol?

    init() {
        memoryWarning = NotificationCenter.default.addObserver(
            forName: UIApplication.didReceiveMemoryWarningNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.discardHidden() }
        }
    }

    func session(for platform: Platform) -> BrowserSession {
        if let session = sessions[platform] { return session }
        let session = BrowserSession(platform: platform)
        sessions[platform] = session
        return session
    }

    func discardHidden() {
        for (platform, session) in sessions where !session.isOnScreen {
            session.tearDown()
            sessions[platform] = nil
        }
    }
}
