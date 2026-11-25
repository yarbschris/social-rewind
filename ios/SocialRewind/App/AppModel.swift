import SwiftUI
import Observation
import FamilyControls
import RewindCore
import os

private let log = Logger(subsystem: "app.socialrewind", category: "AppModel")

@MainActor
@Observable
final class AppModel {
    @ObservationIgnored private let store = SharedStore()
    @ObservationIgnored private let shields = ShieldManager()

    private(set) var rulePacks: [Platform: LoadedRulePack] = [:]
    private(set) var settings: [Platform: PlatformSettings] = [:]
    private(set) var selections: [Platform: FamilyActivitySelection] = [:]
    private(set) var lockedPlatforms: Set<Platform> = []
    private(set) var stats: ViewStats
    private(set) var lastRuleRefresh: Date?
    /// Known account handles. A change makes an open browser reload so the page-world bundle gets it.
    private(set) var usernames: [Platform: String] = [:]
    private(set) var ruleRefreshStatus: String?

    /// The platform shown full screen in a filtered browser.
    var openPlatform: Platform?

    var onboardingComplete: Bool {
        didSet { store.onboardingComplete = onboardingComplete }
    }

    var reminders: ReminderSettings {
        didSet { store.reminders = reminders }
    }

    var developer: DeveloperSettings {
        didSet {
            store.developer = developer
            if developer.autoUpdateRules && !oldValue.autoUpdateRules {
                Task { await refreshRulesIfNeeded(force: true) }
            }
        }
    }

    init() {
        onboardingComplete = store.onboardingComplete
        reminders = store.reminders
        developer = store.developer
        stats = store.stats
        lastRuleRefresh = store.lastRuleRefresh
        for platform in Platform.allCases where platform.isAvailable {
            if let pack = RulePackLoader.load(platform) {
                rulePacks[platform] = pack
            } else {
                log.error("No rule pack for \(platform.rawValue, privacy: .public). Did the engine build script run?")
            }
            settings[platform] = store.settings(for: platform)
            usernames[platform] = store.username(for: platform)
            selections[platform] = store.selection(for: platform)
            if store.isLocked(platform) { lockedPlatforms.insert(platform) }
        }
    }

    // MARK: Settings

    func rulePack(for platform: Platform) -> LoadedRulePack? { rulePacks[platform] }

    func settings(for platform: Platform) -> PlatformSettings {
        if let s = settings[platform] { return s }
        if let pack = rulePacks[platform]?.pack { return .defaults(for: pack) }
        return PlatformSettings()
    }

    func updateSettings(for platform: Platform, _ mutate: (inout PlatformSettings) -> Void) {
        var s = settings(for: platform)
        mutate(&s)
        settings[platform] = s
        store.setSettings(s, for: platform)
    }

    func username(for platform: Platform) -> String? { usernames[platform] }

    /// Sets (or clears, with nil/empty) the account handle. Returns false if it's invalid.
    @discardableResult
    func setUsername(_ username: String?, for platform: Platform) -> Bool {
        let trimmed = username?.trimmingCharacters(in: .whitespacesAndNewlines).trimmingCharacters(in: CharacterSet(charactersIn: "@"))
        guard let trimmed, !trimmed.isEmpty else {
            usernames[platform] = nil
            store.setUsername(nil, for: platform)
            return true
        }
        guard Username.isValid(trimmed) else { return false }
        if usernames[platform] != trimmed {
            usernames[platform] = trimmed
            store.setUsername(trimmed, for: platform)
        }
        return true
    }

    // MARK: Browser support

    /// Both engine bundles, each wrapped with the config as a closure constant. nil → fail closed.
    func injectedScripts(for platform: Platform) -> InjectedScripts? {
        guard let pack = rulePacks[platform], let sources = RulePackLoader.engineSources() else { return nil }
        #if DEBUG
        let (debug, experimental) = (developer.debugOverlay, developer.experimentalNetworkFiltering)
        #else
        // The Developer section only exists in development builds; never carry its switches over.
        let (debug, experimental) = (false, false)
        #endif
        let config = EngineConfig(platform: platform,
                                  settings: settings(for: platform),
                                  rules: pack,
                                  username: usernames[platform],
                                  debug: debug,
                                  experimental: experimental)
        do {
            return InjectedScripts(page: try EngineConfigBuilder.wrap(bundleSource: sources.page, config: config),
                                   isolated: try EngineConfigBuilder.wrap(bundleSource: sources.isolated, config: config))
        } catch {
            log.error("Config build failed: \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }

    func routeGuard(for platform: Platform) -> RouteGuard? {
        guard let pack = rulePacks[platform]?.pack else { return nil }
        return RouteGuard(pack: pack, settings: settings(for: platform), username: usernames[platform])
    }

    func liveUpdateScript(for platform: Platform) -> String? {
        guard let pack = rulePacks[platform]?.pack else { return nil }
        return try? EngineConfigBuilder.updateScript(settings: settings(for: platform), rules: pack)
    }

    func handle(_ untrusted: BridgeEvent, from platform: Platform) {
        guard let event = untrusted.validated() else { return }
        switch event {
        case .postViewed(let key, _):
            stats.record(platform: platform, key: key)
            stats.prune()
            store.stats = stats
        case .identity(let username):
            // The page is untrusted and the identity selector unverified, so it only fills in a
            // missing username. A username the user typed always wins.
            if usernames[platform] == nil { setUsername(username, for: platform) }
        case .error(let message):
            log.error("Engine error: \(message, privacy: .public)")
        case .ready(let engineVersion, let revision):
            log.debug("Engine \(engineVersion) ready with rules r\(revision)")
        case .routeBlocked, .ruleHit, .unknown:
            break
        }
    }

    // MARK: Deep links

    func handle(url: URL) {
        guard let link = DeepLink(url: url) else { return }
        switch link {
        case .open(let platform):
            guard platform.isAvailable, onboardingComplete else { return }
            openPlatform = platform
        }
    }

    // MARK: Screen Time

    func setSelection(_ selection: FamilyActivitySelection, for platform: Platform) {
        selections[platform] = selection
        store.setSelection(selection, for: platform)
        applyShields()
    }

    func setLocked(_ locked: Bool, for platform: Platform) {
        if locked { lockedPlatforms.insert(platform) } else { lockedPlatforms.remove(platform) }
        store.setLocked(locked, for: platform)
        applyShields()
    }

    func applyShields() {
        let active = selections.filter { lockedPlatforms.contains($0.key) }.map(\.value)
        shields.apply(active)
    }

    // MARK: Rule refresh (opt-in, docs/decisions/0002)

    func refreshRulesIfNeeded(force: Bool = false) async {
        guard developer.autoUpdateRules else { return }
        if !force, let last = lastRuleRefresh, Date.now.timeIntervalSince(last) < RuleRefresher.minimumInterval { return }
        var messages: [String] = []
        for (platform, current) in rulePacks {
            switch await RuleRefresher().refresh(platform, current: current) {
            case .updated(let pack):
                rulePacks[platform] = pack
                messages.append("\(platform.displayName): updated to r\(pack.pack.revision)")
            case .upToDate:
                messages.append("\(platform.displayName): up to date")
            case .failed(let reason):
                messages.append("\(platform.displayName): \(reason)")
            }
        }
        lastRuleRefresh = .now
        store.lastRuleRefresh = lastRuleRefresh
        ruleRefreshStatus = messages.joined(separator: "\n")
    }
}
