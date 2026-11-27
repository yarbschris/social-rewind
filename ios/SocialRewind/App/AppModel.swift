import SwiftUI
import Observation
import FamilyControls
import DeviceActivity
import RewindCore
import UserNotifications
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

    /// Optional PIN for changes that loosen restrictions. nil = off.
    private(set) var settingsPin: SettingsPin?
    /// A loosening change waiting for the PIN. RootView presents it.
    var pinPrompt: PinPrompt?
    @ObservationIgnored private var unlockedUntil: Date?

    /// Whether Social Rewind may post notifications. nil until checked. The shield's "Open in
    /// Social Rewind" button can only reach the app through a notification, so locking is a dead
    /// end without them.
    private(set) var notificationsAllowed: Bool?

    /// Native apps unlocked so the user can approve a login there (Instagram's two-factor). They
    /// lock again when Social Rewind comes back from the background, or when a 16-minute Screen
    /// Time window ends, whichever is first.
    private(set) var signInUnlocks: Set<Platform> = []
    @ObservationIgnored private var wasInBackground = false

    var onboardingComplete: Bool {
        didSet { store.onboardingComplete = onboardingComplete }
    }

    /// Change through `setReminders`, which asks for the PIN when a change loosens them.
    private(set) var reminders: ReminderSettings {
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
        settingsPin = store.settingsPin
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
        applyDuePinReset()
    }

    // MARK: Settings

    func rulePack(for platform: Platform) -> LoadedRulePack? { rulePacks[platform] }

    func settings(for platform: Platform) -> PlatformSettings {
        if let s = settings[platform] { return s }
        if let pack = rulePacks[platform]?.pack { return .defaults(for: pack) }
        return PlatformSettings()
    }

    /// Applies the change, or holds it for the PIN if it loosens a restriction.
    func updateSettings(for platform: Platform, _ mutate: (inout PlatformSettings) -> Void) {
        let old = settings(for: platform)
        var new = old
        mutate(&new)
        guard new != old else { return }
        let loosens = rulePacks[platform].map { Loosening.platformSettings(from: old, to: new, pack: $0.pack) } ?? true
        guarded(loosens: loosens, "Loosening \(platform.displayName)'s filters needs your settings PIN.",
                undo: { $0.settings[platform] = old }) { model in
            model.settings[platform] = new
            model.store.setSettings(new, for: platform)
        }
    }

    func setReminders(_ new: ReminderSettings) {
        let old = reminders
        guard new != old else { return }
        guarded(loosens: Loosening.reminders(from: old, to: new), "Making reminders less frequent needs your settings PIN.",
                undo: { $0.reminders = old }) { $0.reminders = new }
    }

    // MARK: Settings PIN

    /// True when there's no PIN, or it was entered in the last few minutes.
    var settingsUnlocked: Bool {
        guard settingsPin != nil else { return true }
        return unlockedUntil.map { $0 > .now } ?? false
    }

    /// Runs `action` now unless it loosens a restriction while a PIN is set; then it waits for
    /// the PIN. `undo` re-assigns the current value so a control the user flipped snaps back.
    func guarded(loosens: Bool, _ reason: String,
                 undo: ((AppModel) -> Void)? = nil, _ action: @escaping (AppModel) -> Void) {
        if !loosens || settingsUnlocked {
            action(self)
        } else {
            undo?(self)
            pinPrompt = PinPrompt(reason: reason) { [weak self] in if let self { action(self) } }
        }
    }

    /// Checks the PIN for the pending prompt; on success, unlocks for a few minutes and runs it.
    func enterPin(_ pin: String) -> SettingsPin.Attempt {
        guard var lock = settingsPin else { return .correct }
        let result = lock.attempt(pin)
        settingsPin = lock
        store.settingsPin = lock
        if result == .correct {
            unlockedUntil = Date.now.addingTimeInterval(SettingsPin.unlockDuration)
            let action = pinPrompt?.action
            pinPrompt = nil
            action?()
        }
        return result
    }

    /// Turns the PIN on, or changes it. Changing an existing PIN goes through `guarded` first.
    @discardableResult
    func setPin(_ pin: String) -> Bool {
        guard let lock = SettingsPin(pin: pin) else { return false }
        settingsPin = lock
        store.settingsPin = lock
        unlockedUntil = nil
        return true
    }

    func removePin() {
        guarded(loosens: true, "Turning off the settings PIN needs the PIN.") { model in
            model.settingsPin = nil
            model.store.settingsPin = nil
            model.unlockedUntil = nil
        }
    }

    func requestPinReset() {
        guard var lock = settingsPin else { return }
        lock.requestReset()
        settingsPin = lock
        store.settingsPin = lock
    }

    func cancelPinReset() {
        guard var lock = settingsPin else { return }
        lock.cancelReset()
        settingsPin = lock
        store.settingsPin = lock
    }

    /// "Forgot PIN" removes the PIN once its waiting period has passed. Checked at launch and on
    /// returning to the app.
    func applyDuePinReset() {
        guard settingsPin?.resetIsDue() == true else { return }
        settingsPin = nil
        store.settingsPin = nil
    }

    /// Leaving the app locks settings again.
    func lockSettings() {
        unlockedUntil = nil
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

    /// Picking an app where none was picked is stricter; swapping one out could unlock it.
    func setSelection(_ selection: FamilyActivitySelection, for platform: Platform) {
        let old = selections[platform]
        let loosens = !(old?.applicationTokens.isEmpty ?? true) && old != selection
        guarded(loosens: loosens, "Changing which app is locked needs your settings PIN.",
                undo: { $0.selections[platform] = old }) { model in
            model.selections[platform] = selection
            model.store.setSelection(selection, for: platform)
            model.applyShields()
        }
    }

    func setLocked(_ locked: Bool, for platform: Platform) {
        let wasLocked = lockedPlatforms.contains(platform)
        guarded(loosens: wasLocked && !locked, "Unlocking \(platform.displayName) needs your settings PIN.",
                undo: { $0.lockedPlatforms = $0.lockedPlatforms }) { model in
            if locked { model.lockedPlatforms.insert(platform) } else { model.lockedPlatforms.remove(platform) }
            model.store.setLocked(locked, for: platform)
            model.applyShields()
        }
    }

    func applyShields() {
        let active = selections.filter { lockedPlatforms.contains($0.key) && !signInUnlocks.contains($0.key) }.map(\.value)
        shields.apply(active)
        Task { await refreshNotificationPermission() }
    }

    /// Whether the platform's native app is locked right now (picked, locked, not unlocked for a sign-in).
    func isAppLocked(_ platform: Platform) -> Bool {
        BuildFeatures.screenTime && lockedPlatforms.contains(platform) && !signInUnlocks.contains(platform)
            && !(selections[platform]?.applicationTokens.isEmpty ?? true)
    }

    /// Unlocks the native app so a login can be approved there. Starts the Screen Time backstop
    /// first and stays locked if that fails. Callers check the settings PIN first.
    func unlockForSignIn(_ platform: Platform) -> Bool {
        guard isAppLocked(platform) else { return false }
        let now = Date.now
        let calendar = Calendar.current
        let parts: Set<Calendar.Component> = [.hour, .minute, .second]
        // Screen Time intervals must be at least 15 minutes long.
        let schedule = DeviceActivitySchedule(intervalStart: calendar.dateComponents(parts, from: now),
                                              intervalEnd: calendar.dateComponents(parts, from: now.addingTimeInterval(16 * 60)),
                                              repeats: false)
        do {
            try DeviceActivityCenter().startMonitoring(DeviceActivityName(ShieldState.signInActivity(for: platform)), during: schedule)
        } catch {
            log.error("Sign-in unlock not started: \(error.localizedDescription, privacy: .public)")
            return false
        }
        signInUnlocks.insert(platform)
        applyShields()
        return true
    }

    func appDidEnterBackground() {
        wasInBackground = true
        lockSettings()
    }

    /// Coming back from the background ends any sign-in unlock: the login has been approved or abandoned.
    func appDidBecomeActive() {
        applyDuePinReset()
        Task { await refreshNotificationPermission() }
        guard wasInBackground else { return }
        wasInBackground = false
        guard !signInUnlocks.isEmpty else { return }
        let names = signInUnlocks.map { DeviceActivityName(ShieldState.signInActivity(for: $0)) }
        DeviceActivityCenter().stopMonitoring(names)
        signInUnlocks = []
        applyShields()
    }

    /// At least one platform's native app is actually shielded.
    var hasActiveLocks: Bool {
        BuildFeatures.screenTime && lockedPlatforms.contains { !(selections[$0]?.applicationTokens.isEmpty ?? true) }
    }

    /// Asks for notification permission once an app is locked, if it was never asked (e.g. after
    /// onboarding on a build without Screen Time), then records whether it's allowed.
    func refreshNotificationPermission() async {
        var status = await Self.notificationStatus()
        if status == .notDetermined, hasActiveLocks, onboardingComplete {
            _ = try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound])
            status = await Self.notificationStatus()
        }
        notificationsAllowed = [.authorized, .provisional, .ephemeral].contains(status)
    }

    /// Off the main actor, so the non-Sendable `UNNotificationSettings` never crosses actors
    /// (older SDKs reject that); only the Sendable status comes back.
    private nonisolated static func notificationStatus() async -> UNAuthorizationStatus {
        await UNUserNotificationCenter.current().notificationSettings().authorizationStatus
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

/// A loosening change held until the settings PIN is entered.
struct PinPrompt: Identifiable {
    let id = UUID()
    let reason: String
    let action: @MainActor () -> Void
}
