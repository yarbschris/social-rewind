import Foundation
import FamilyControls
import ManagedSettings
import RewindCore

/// The App Group shared by the app and its Screen Time extensions.
/// Comes from the `SRAppGroupIdentifier` Info.plist key (set from `SR_APP_GROUP`
/// in ios/Config/Base.xcconfig), so forks can use their own group.
enum AppGroup {
    static var identifier: String {
        (Bundle.main.object(forInfoDictionaryKey: "SRAppGroupIdentifier") as? String)
            .flatMap { $0.isEmpty ? nil : $0 } ?? "group.app.socialrewind"
    }

    static var containerURL: URL? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: identifier)
    }
}

/// On-device persistence in App Group UserDefaults. Nothing here ever leaves the device.
///
/// Not thread-safe by design: the app uses it from the main actor, and each extension
/// invocation creates its own instance.
final class SharedStore {
    private enum Key {
        static let onboardingComplete = "onboardingComplete"
        static let reminders = "reminders"
        static let developer = "developer"
        static let stats = "stats"
        static let lastRuleRefresh = "lastRuleRefresh"
        static func settings(_ p: Platform) -> String { "settings.\(p.rawValue)" }
        static func selection(_ p: Platform) -> String { "selection.\(p.rawValue)" }
        static func locked(_ p: Platform) -> String { "locked.\(p.rawValue)" }
        static func username(_ p: Platform) -> String { "username.\(p.rawValue)" }
    }

    private let defaults: UserDefaults

    init(defaults: UserDefaults? = UserDefaults(suiteName: AppGroup.identifier)) {
        self.defaults = defaults ?? .standard
    }

    // MARK: Onboarding

    var onboardingComplete: Bool {
        get { defaults.bool(forKey: Key.onboardingComplete) }
        set { defaults.set(newValue, forKey: Key.onboardingComplete) }
    }

    // MARK: Settings

    func settings(for platform: Platform) -> PlatformSettings? { load(Key.settings(platform)) }
    func setSettings(_ settings: PlatformSettings, for platform: Platform) { save(settings, Key.settings(platform)) }

    var reminders: ReminderSettings {
        get { load(Key.reminders) ?? ReminderSettings() }
        set { save(newValue, Key.reminders) }
    }

    var developer: DeveloperSettings {
        get { load(Key.developer) ?? DeveloperSettings() }
        set { save(newValue, Key.developer) }
    }

    func username(for platform: Platform) -> String? { defaults.string(forKey: Key.username(platform)) }
    func setUsername(_ username: String?, for platform: Platform) { defaults.set(username, forKey: Key.username(platform)) }

    var lastRuleRefresh: Date? {
        get { defaults.object(forKey: Key.lastRuleRefresh) as? Date }
        set { defaults.set(newValue, forKey: Key.lastRuleRefresh) }
    }

    // MARK: Stats

    var stats: ViewStats {
        get { load(Key.stats) ?? ViewStats() }
        set { save(newValue, Key.stats) }
    }

    // MARK: Screen Time

    /// The app(s) the user picked for a platform in FamilyActivityPicker. Tokens are opaque.
    func selection(for platform: Platform) -> FamilyActivitySelection? { load(Key.selection(platform)) }
    func setSelection(_ selection: FamilyActivitySelection?, for platform: Platform) {
        if let selection { save(selection, Key.selection(platform)) } else { defaults.removeObject(forKey: Key.selection(platform)) }
    }

    /// Whether the user wants this platform's native app shielded.
    func isLocked(_ platform: Platform) -> Bool {
        defaults.object(forKey: Key.locked(platform)) as? Bool ?? true
    }
    func setLocked(_ locked: Bool, for platform: Platform) { defaults.set(locked, forKey: Key.locked(platform)) }

    /// Which platform a shielded app token belongs to (used by the ShieldAction extension).
    func platform(for token: ApplicationToken) -> Platform? {
        Platform.allCases.first { selection(for: $0)?.applicationTokens.contains(token) == true }
    }

    // MARK: Coding

    private func load<T: Decodable>(_ key: String) -> T? {
        guard let data = defaults.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(T.self, from: data)
    }

    private func save<T: Encodable>(_ value: T, _ key: String) {
        if let data = try? JSONEncoder().encode(value) { defaults.set(data, forKey: key) }
    }
}
