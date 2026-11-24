import Foundation

public enum NavigationDecision: Equatable, Sendable {
    /// Load inside the platform web view.
    case allow
    /// Hand to the system (default browser, Mail, Phone…), outside Social Rewind.
    case openExternally(URL)
    /// Drop silently.
    case cancel
}

/// Per-platform navigation allowlist. **Hardcoded on purpose**: rule packs can
/// be refreshed from the network, so they must never be able to widen this.
///
/// This governs frame navigations only. Subresources (images, XHR) are not
/// covered; that's a job for a WKContentRuleList (roadmap).
public struct HostPolicy: Sendable {
    /// Hosts allowed exactly.
    public let exactHosts: Set<String>
    /// Allowed host suffixes, written with a leading dot (".cdninstagram.com").
    public let hostSuffixes: [String]
    /// Hosts allowed only for paths matching one of these regexes (e.g. Facebook login for Instagram).
    public let restrictedHosts: [String: [String]]
    /// Link-shim hosts whose `u` query item holds the real external URL.
    public let linkShimHosts: Set<String>
    /// App schemes that would open the native (shielded) app. Always dropped.
    public let blockedSchemes: Set<String>

    public static func `for`(_ platform: Platform) -> HostPolicy {
        switch platform {
        case .instagram:
            HostPolicy(
                exactHosts: ["instagram.com", "www.instagram.com", "i.instagram.com", "about.instagram.com"],
                hostSuffixes: [".cdninstagram.com", ".fbcdn.net"],
                restrictedHosts: [
                    // "Log in with Facebook" and account checkpoints only, not browsing Facebook.
                    "www.facebook.com": facebookAuthPaths,
                    "m.facebook.com": facebookAuthPaths,
                    "accountscenter.instagram.com": ["^/"],
                ],
                linkShimHosts: ["l.instagram.com"],
                blockedSchemes: ["instagram", "instagram-stories", "fb", "fb-messenger"]
            )
        default:
            // Not available yet: allow nothing.
            HostPolicy(exactHosts: [], hostSuffixes: [], restrictedHosts: [:], linkShimHosts: [], blockedSchemes: [])
        }
    }

    private static let facebookAuthPaths = [
        "^/login(?:/|\\.php|$)",
        "^/(?:v\\d+\\.\\d+/)?dialog/oauth",
        "^/checkpoint(?:/|$)",
        "^/recover(?:/|$)",
    ]

    public init(exactHosts: Set<String>,
                hostSuffixes: [String],
                restrictedHosts: [String: [String]],
                linkShimHosts: Set<String>,
                blockedSchemes: Set<String>) {
        self.exactHosts = exactHosts
        self.hostSuffixes = hostSuffixes
        self.restrictedHosts = restrictedHosts
        self.linkShimHosts = linkShimHosts
        self.blockedSchemes = blockedSchemes
    }

    public func isAllowedWebURL(_ url: URL) -> Bool {
        guard url.scheme?.lowercased() == "https", let host = url.host?.lowercased() else { return false }
        if exactHosts.contains(host) { return true }
        if hostSuffixes.contains(where: { host.hasSuffix($0) }) { return true }
        if let patterns = restrictedHosts[host] {
            let path = url.path.isEmpty ? "/" : url.path
            return patterns.contains { path.range(of: $0, options: .regularExpression) != nil }
        }
        return false
    }

    /// - Parameters:
    ///   - isMainFrame: the navigation targets the top-level frame.
    ///   - isUserInitiated: the user tapped a link (WKNavigationType.linkActivated).
    public func decide(url: URL, isMainFrame: Bool, isUserInitiated: Bool) -> NavigationDecision {
        let scheme = url.scheme?.lowercased() ?? ""

        switch scheme {
        case "about", "blob", "data":
            return .allow
        case "mailto", "tel", "sms":
            return isUserInitiated ? .openExternally(url) : .cancel
        case "https":
            break
        case "http":
            // No cleartext. Upgrade user taps on external links, drop everything else.
            if isMainFrame, isUserInitiated, var c = URLComponents(url: url, resolvingAgainstBaseURL: false) {
                c.scheme = "https"
                if let upgraded = c.url, !isAllowedWebURL(upgraded) { return .openExternally(upgraded) }
            }
            return .cancel
        default:
            // instagram:// and other app schemes would open the shielded native app.
            return .cancel
        }

        if let host = url.host?.lowercased(), linkShimHosts.contains(host) {
            if let target = URLComponents(url: url, resolvingAgainstBaseURL: false)?
                .queryItems?.first(where: { $0.name == "u" })?.value,
               let targetURL = URL(string: target) {
                return decide(url: targetURL, isMainFrame: isMainFrame, isUserInitiated: isUserInitiated)
            }
            return .cancel
        }

        if isAllowedWebURL(url) { return .allow }

        // Off-platform link: open in the user's browser if they tapped it, otherwise drop it.
        return (isMainFrame && isUserInitiated) ? .openExternally(url) : .cancel
    }
}
