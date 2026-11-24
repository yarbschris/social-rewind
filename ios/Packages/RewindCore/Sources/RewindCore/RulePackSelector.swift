import Foundation

/// Decides between the rule pack bundled with the app and a refreshed one (docs/decisions/0002).
public enum RulePackSelector {
    public enum RejectionReason: Error, Equatable, Sendable {
        case undecodable
        case unsupportedSchema(Int)
        case wrongPlatform(String)
        case needsNewerEngine(Int)
        case notNewer(revision: Int, current: Int)
        case tooLarge(bytes: Int)
        case tooManySelectors(Int)
        case regexTooLong(String)
        case unsafePath(String)
    }

    public static let maxPackBytes = 256 * 1024
    public static let maxSelectors = 500
    public static let maxRegexLength = 300

    /// Validates a downloaded pack against what this build can use.
    /// Doesn't check `revision`; see `select`.
    public static func validate(_ data: Data,
                                platform: Platform,
                                engineVersion: Int = EngineInfo.version) throws(RejectionReason) -> LoadedRulePack {
        guard data.count < maxPackBytes else { throw .tooLarge(bytes: data.count) }
        let loaded: LoadedRulePack
        do {
            loaded = try LoadedRulePack(data: data)
        } catch {
            throw .undecodable
        }
        let pack = loaded.pack
        guard pack.schemaVersion == 1 else { throw .unsupportedSchema(pack.schemaVersion) }
        guard pack.platform == platform.rawValue else { throw .wrongPlatform(pack.platform) }
        guard pack.minEngineVersion <= engineVersion else { throw .needsNewerEngine(pack.minEngineVersion) }
        try checkLimits(pack)
        return loaded
    }

    /// Structural limits a refreshed pack must respect: redirect targets stay on the platform's
    /// origin, and no pack can make the engine do unbounded work.
    static func checkLimits(_ pack: RulePack) throws(RejectionReason) {
        var ruleSets = pack.features.values.map(\.rules)
        ruleSets += (pack.modes ?? [:]).values.compactMap(\.rules)

        let selectorCount = ruleSets.reduce(0) { $0 + ($1.css?.count ?? 0) }
        guard selectorCount <= maxSelectors else { throw .tooManySelectors(selectorCount) }

        var paths = [pack.startPath]
        paths += (pack.modes ?? [:]).values.map(\.home)
        paths += ruleSets.flatMap { ($0.routes ?? []).compactMap(\.to) }
        for path in paths where !isSameOriginPath(path) { throw .unsafePath(path) }

        var regexes = pack.alwaysAllowRoutes ?? []
        regexes += (pack.modes ?? [:]).values.flatMap(\.allowRoutes)
        regexes += ruleSets.flatMap { ($0.routes ?? []).map(\.pattern) }
        regexes += ruleSets.flatMap { ($0.network ?? []).compactMap { $0.stringValue(at: "url") } }
        regexes += [pack.counter?.stringValue(at: "key", "pattern"), pack.identity?.stringValue(at: "pattern")].compactMap { $0 }
        for regex in regexes where regex.count > maxRegexLength { throw .regexTooLong(String(regex.prefix(40))) }
    }

    /// A plain path on the current origin: "/x", never "//host", "\\host" or "scheme://".
    static func isSameOriginPath(_ path: String) -> Bool {
        path.hasPrefix("/") && !path.hasPrefix("//") && !path.contains("\\") && !path.contains("://")
    }

    /// Returns the refreshed pack only if it's valid and strictly newer than the bundled one.
    public static func select(bundled: LoadedRulePack,
                              refreshed: Data?,
                              platform: Platform,
                              engineVersion: Int = EngineInfo.version) -> LoadedRulePack {
        guard let refreshed else { return bundled }
        guard let candidate = try? accept(refreshed, over: bundled, platform: platform, engineVersion: engineVersion) else {
            return bundled
        }
        return candidate
    }

    /// Like `select`, but reports why a refreshed pack was rejected.
    public static func accept(_ data: Data,
                              over current: LoadedRulePack,
                              platform: Platform,
                              engineVersion: Int = EngineInfo.version) throws(RejectionReason) -> LoadedRulePack {
        let candidate = try validate(data, platform: platform, engineVersion: engineVersion)
        guard candidate.pack.revision > current.pack.revision else {
            throw .notNewer(revision: candidate.pack.revision, current: current.pack.revision)
        }
        return candidate
    }
}
