import Foundation

/// Mirror of `PlatformSettings` in `engine/src/core/types.ts`.
public struct PlatformSettings: Codable, Sendable, Equatable {
    public static let normalMode = "normal"

    /// "normal" or a key of `RulePack.modes` (e.g. "dmsOnly", "savedOnly").
    public var mode: String
    /// Explicit user choices. Missing keys fall back to the feature's default.
    public var features: [String: Bool]
    public var grayscale: Bool
    public var postCounter: Bool

    public init(mode: String = PlatformSettings.normalMode,
                features: [String: Bool] = [:],
                grayscale: Bool = false,
                postCounter: Bool = true) {
        self.mode = mode
        self.features = features
        self.grayscale = grayscale
        self.postCounter = postCounter
    }

    public static func defaults(for pack: RulePack) -> PlatformSettings {
        var s = PlatformSettings()
        s.features = pack.features.mapValues { $0.isAvailable && $0.default }
        return s
    }

    /// Every feature in the pack resolved to on/off: missing → default, unavailable → off.
    /// Toggles for features no longer in the pack are dropped.
    public func effectiveFeatures(for pack: RulePack) -> [String: Bool] {
        pack.features.reduce(into: [:]) { result, entry in
            let (id, def) = entry
            result[id] = def.isAvailable && (features[id] ?? def.default)
        }
    }

    /// The mode if the pack defines it, otherwise "normal".
    public func effectiveMode(for pack: RulePack) -> String {
        if mode == Self.normalMode { return mode }
        return pack.modes?[mode] != nil ? mode : Self.normalMode
    }

    /// Settings exactly as the engine should receive them.
    public func resolved(for pack: RulePack) -> PlatformSettings {
        PlatformSettings(mode: effectiveMode(for: pack),
                         features: effectiveFeatures(for: pack),
                         grayscale: grayscale,
                         postCounter: postCounter)
    }
}

/// Scroll reminders. Native only; the engine just reports posts viewed.
public struct ReminderSettings: Codable, Sendable, Equatable {
    public var enabled: Bool
    /// Remind after every N posts viewed in a session. 0 disables.
    public var everyPosts: Int
    /// Remind after every N minutes in a session. 0 disables.
    public var everyMinutes: Int

    public init(enabled: Bool = true, everyPosts: Int = 30, everyMinutes: Int = 15) {
        self.enabled = enabled
        self.everyPosts = everyPosts
        self.everyMinutes = everyMinutes
    }

    /// Whether reaching `sessionCount` posts should trigger a reminder.
    public func shouldRemind(afterPosts sessionCount: Int) -> Bool {
        enabled && everyPosts > 0 && sessionCount > 0 && sessionCount % everyPosts == 0
    }
}

/// Developer and advanced options, shared across platforms.
public struct DeveloperSettings: Codable, Sendable, Equatable {
    /// Outline hidden elements instead of hiding them.
    public var debugOverlay: Bool
    /// Apply network rules marked `verified: false`.
    public var experimentalNetworkFiltering: Bool
    /// Opt-in fetch of rule packs from GitHub. Off by default (docs/decisions/0002).
    public var autoUpdateRules: Bool

    public init(debugOverlay: Bool = false,
                experimentalNetworkFiltering: Bool = false,
                autoUpdateRules: Bool = false) {
        self.debugOverlay = debugOverlay
        self.experimentalNetworkFiltering = experimentalNetworkFiltering
        self.autoUpdateRules = autoUpdateRules
    }
}
