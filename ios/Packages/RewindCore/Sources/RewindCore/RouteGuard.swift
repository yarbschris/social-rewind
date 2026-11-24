import Foundation

/// Native backstop for the engine's router guard. The engine's history patch runs in the
/// page world, where the site can tamper with it, so native re-checks every URL change
/// (WKWebView.url updates on pushState) and forces a navigation when the path isn't allowed.
///
/// Deliberately minimal: mode allowlists, `alwaysAllowRoutes`, and route rules with
/// action "block". "redirect" rules stay the engine's job.
public struct RouteGuard: Sendable {
    public enum Decision: Equatable, Sendable {
        case allow
        /// Load this same-origin path instead.
        case navigate(String)
    }

    public let pack: RulePack
    public let settings: PlatformSettings
    public let username: String?

    public init(pack: RulePack, settings: PlatformSettings, username: String?) {
        self.pack = pack
        self.settings = settings
        self.username = username
    }

    /// The active mode's home with `{username}` filled in. nil if the mode needs a username we don't have.
    public var modeHome: String? {
        let mode = settings.effectiveMode(for: pack)
        guard let def = pack.modes?[mode] else { return nil }
        guard def.home.contains("{username}") else { return def.home }
        guard let username, Username.isValid(username) else { return nil }
        return def.home.replacingOccurrences(of: "{username}", with: username)
    }

    /// Where to go when a path is disallowed: the mode's home, else the pack's start path.
    public var fallback: String { modeHome ?? pack.startPath }

    public func evaluate(path rawPath: String) -> Decision {
        let path = rawPath.isEmpty ? "/" : rawPath

        if matchesAny(pack.alwaysAllowRoutes ?? [], path) { return .allow }

        let mode = settings.effectiveMode(for: pack)
        if let def = pack.modes?[mode] {
            if let home = modeHome {
                if Self.samePath(path, home) { return .allow }
                if !matchesAny(def.allowRoutes, path) { return redirect(from: path, to: home) }
            } else if !Self.samePath(path, pack.startPath) && !matchesAny(def.allowRoutes, path) {
                // Home needs a username we don't have yet: tolerate the start path (the mode's CSS
                // hides its content) rather than looping.
                return redirect(from: path, to: pack.startPath)
            }
        }

        for rule in activeBlockRules where Self.matches(rule.pattern, path) {
            return redirect(from: path, to: fallback)
        }
        return .allow
    }

    private var activeBlockRules: [RulePack.RouteRule] {
        let enabled = settings.effectiveFeatures(for: pack)
        var rules: [RulePack.RouteRule] = []
        for (id, def) in pack.features where enabled[id] == true {
            rules += def.rules.routes ?? []
        }
        let mode = settings.effectiveMode(for: pack)
        rules += pack.modes?[mode]?.rules?.routes ?? []
        return rules.filter { $0.action == .block }
    }

    private func redirect(from path: String, to target: String) -> Decision {
        // Never "redirect" to where we already are.
        Self.samePath(path, target) ? .allow : .navigate(target)
    }

    private func matchesAny(_ patterns: [String], _ path: String) -> Bool {
        patterns.contains { Self.matches($0, path) }
    }

    /// ICU regex, close enough to JS for the anchored patterns rule packs use (lookahead included).
    /// Invalid patterns match nothing.
    static func matches(_ pattern: String, _ path: String) -> Bool {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return false }
        return regex.firstMatch(in: path, range: NSRange(path.startIndex..., in: path)) != nil
    }

    static func samePath(_ a: String, _ b: String) -> Bool {
        func norm(_ s: String) -> String { s.count > 1 && s.hasSuffix("/") ? String(s.dropLast()) : s }
        return norm(a) == norm(b)
    }
}

/// Allows at most `limit` events per sliding `window`. Used to rate-limit untrusted bridge
/// events and to stop forced-navigation loops.
public struct SlidingWindowLimiter: Sendable {
    public let limit: Int
    public let window: TimeInterval
    private var timestamps: [Date] = []

    public init(limit: Int, window: TimeInterval) {
        self.limit = limit
        self.window = window
    }

    /// Records an attempt. Returns false (and doesn't record it) if over the limit.
    public mutating func allow(at now: Date = .now) -> Bool {
        timestamps.removeAll { now.timeIntervalSince($0) >= window }
        guard timestamps.count < limit else { return false }
        timestamps.append(now)
        return true
    }

    public mutating func reset() { timestamps.removeAll() }
}
