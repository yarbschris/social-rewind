import FamilyControls
import ManagedSettings
import RewindCore

/// Shield state that both the app and the DeviceActivityMonitor extension need.
enum ShieldState {
    /// The named ManagedSettingsStore holding Social Rewind's shields. A computed property:
    /// ManagedSettingsStore.Name isn't Sendable, so it can't be a static let under Swift 6.
    static var storeName: ManagedSettingsStore.Name { ManagedSettingsStore.Name("socialRewind") }

    /// DeviceActivity names for "unlock to approve a sign-in" are this prefix plus the platform.
    static let signInActivityPrefix = "signin."

    static func signInActivity(for platform: Platform) -> String { signInActivityPrefix + platform.rawValue }

    /// Shields every platform the user has locked, from what's saved in the App Group. Used by the
    /// extension when a sign-in unlock runs out without the user coming back to Social Rewind.
    static func reapplyAll(from store: SharedStore = SharedStore()) {
        var tokens = Set<ApplicationToken>()
        for platform in Platform.allCases where store.isLocked(platform) {
            tokens.formUnion(store.selection(for: platform)?.applicationTokens ?? [])
        }
        ManagedSettingsStore(named: storeName).shield.applications = tokens.isEmpty ? nil : tokens
    }
}
