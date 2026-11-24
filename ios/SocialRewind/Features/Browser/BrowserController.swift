import Observation
import RewindCore
import WebKit
import os

private let log = Logger(subsystem: "app.socialrewind", category: "Browser")

/// State for one filtered browsing session, plus a handle on its web view.
@MainActor
@Observable
final class BrowserController {
    enum FilterState: Equatable {
        /// Waiting for the engine's `ready` event. The page stays covered meanwhile (fail closed).
        case loading
        case ready
        case failed(String)
    }

    struct Reminder: Identifiable, Equatable {
        let id = UUID()
        let posts: Int
        let minutes: Int
    }

    static let readyTimeout: Duration = .seconds(10)

    let platform: Platform
    private(set) var filterState: FilterState = .loading
    private(set) var sessionPosts = 0
    private(set) var sessionMinutes = 0
    private(set) var lastBlockedPath: String?
    var reminder: Reminder?

    @ObservationIgnored weak var webView: WKWebView?
    /// Forwards validated engine events to the app model (stats, identity).
    @ObservationIgnored var onEvent: ((BridgeEvent) -> Void)?
    @ObservationIgnored var reminderSettings = ReminderSettings()
    /// Native route backstop; refreshed whenever settings or the username change.
    @ObservationIgnored var routeGuard: RouteGuard?

    @ObservationIgnored private var seenKeys = Set<String>()
    @ObservationIgnored private var readyTimeoutTask: Task<Void, Never>?
    @ObservationIgnored private var stateBeforeNavigation: FilterState?
    /// The provisional navigation we're waiting on; failures of superseded navigations are ignored.
    @ObservationIgnored private var currentNavigation: ObjectIdentifier?
    /// Bridge messages are untrusted: cap how fast they can move counters.
    @ObservationIgnored private var postViewedLimiter = SlidingWindowLimiter(limit: 5, window: 1)
    /// Loop breaker: more than 3 forced navigations in 10s stops native route enforcement.
    @ObservationIgnored private var forcedNavigationLimiter = SlidingWindowLimiter(limit: 3, window: 10)
    @ObservationIgnored private(set) var routeEnforcementDisabled = false

    init(platform: Platform) {
        self.platform = platform
    }

    // MARK: Engine events

    func receive(_ untrusted: BridgeEvent) {
        guard let event = untrusted.validated() else { return }
        switch event {
        case .ready:
            readyTimeoutTask?.cancel()
            filterState = .ready
        case .error(let message):
            // Engine errors after `ready` are logged but don't unblock raw content.
            if filterState != .ready { filterState = .failed(message) }
        case .postViewed(let key, _):
            guard postViewedLimiter.allow() else { return }
            guard seenKeys.insert(key).inserted else { return }
            sessionPosts += 1
            if reminderSettings.shouldRemind(afterPosts: sessionPosts) {
                reminder = Reminder(posts: sessionPosts, minutes: sessionMinutes)
            }
        case .routeBlocked(let path, _, _):
            lastBlockedPath = path
        case .identity, .ruleHit, .unknown:
            break
        }
        // Only counters/stats and the (validated) username are acted on by the model.
        onEvent?(event)
    }

    // MARK: Navigation lifecycle

    /// Called when a main-frame navigation starts (before the new document exists, so the
    /// new page's `ready` can't arrive first). Every full page load re-runs the engine.
    func navigationStarted(_ navigation: ObjectIdentifier? = nil) {
        currentNavigation = navigation
        stateBeforeNavigation = filterState
        filterState = .loading
        readyTimeoutTask?.cancel()
        readyTimeoutTask = Task { [weak self] in
            try? await Task.sleep(for: Self.readyTimeout)
            guard !Task.isCancelled, let self, self.filterState == .loading else { return }
            self.filterState = .failed("Filters didn't load in time.")
        }
    }

    /// A provisional navigation failed, so the previous page (if any) is still showing.
    func navigationFailed(_ navigation: ObjectIdentifier?) {
        guard filterState == .loading, navigation == currentNavigation else { return }
        readyTimeoutTask?.cancel()
        // Only a page whose engine was already running may be shown again. A failed first load
        // (offline, say) must show the error and Retry, not spin.
        filterState = stateBeforeNavigation == .ready ? .ready : .failed("Couldn't load. Check your connection and try again.")
    }

    /// A main-frame navigation committed on an allowed host that isn't the platform itself
    /// (e.g. "Log in with Facebook"). The engine doesn't filter there, so there's no `ready` to wait for.
    func committedOffPlatform() {
        readyTimeoutTask?.cancel()
        filterState = .ready
    }

    /// Native backstop. `WKWebView.url` changes on pushState too, so this catches in-app
    /// navigations even if the page-world history patch was tampered with.
    func urlChanged(_ url: URL?) {
        guard let url, !routeEnforcementDisabled, let routeGuard,
              ["http", "https"].contains(url.scheme?.lowercased() ?? "") else { return }
        let target: String
        if !HostPolicy.for(platform).isAllowedWebURL(url) {
            // e.g. a pushState on an allowed auth host to a path outside its allowlist.
            target = routeGuard.fallback
        } else if url.host?.lowercased() != platform.origin.host?.lowercased() {
            return // allowed auth/CDN host: platform routes don't apply
        } else if case .navigate(let path) = routeGuard.evaluate(path: url.path) {
            target = path
        } else {
            return
        }

        guard forcedNavigationLimiter.allow() else {
            routeEnforcementDisabled = true
            log.error("Route backstop disabled: too many forced navigations (last: \(url.path, privacy: .public) → \(target, privacy: .public))")
            return
        }
        guard let destination = URL(string: target, relativeTo: platform.origin)?.absoluteURL else { return }
        lastBlockedPath = url.path
        webView?.load(URLRequest(url: destination))
    }

    // MARK: Timers and notices

    func minuteElapsed() {
        sessionMinutes += 1
        let every = reminderSettings.everyMinutes
        if reminderSettings.enabled, every > 0, sessionMinutes % every == 0, reminder == nil {
            reminder = Reminder(posts: sessionPosts, minutes: sessionMinutes)
        }
    }

    func clearBlockedNotice() { lastBlockedPath = nil }

    // MARK: Web view control

    /// Installs new scripts for future loads. With `reload`, the page reloads now so both worlds
    /// pick up the new config; otherwise the isolated world gets a CSS/DOM-only live update.
    func apply(_ scripts: InjectedScripts, liveUpdate: String?, reload: Bool) {
        guard let webView else { return }
        scripts.install(in: webView.configuration.userContentController)
        if reload {
            routeEnforcementDisabled = false
            forcedNavigationLimiter.reset()
            webView.reload()
        } else if let liveUpdate {
            webView.evaluateJavaScript(liveUpdate, in: nil, in: InjectedScripts.isolatedWorld, completionHandler: nil)
        }
    }

    func retry() {
        routeEnforcementDisabled = false
        forcedNavigationLimiter.reset()
        navigationStarted()
        webView?.reload()
    }
}
