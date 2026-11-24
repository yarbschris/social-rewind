import FamilyControls
import ManagedSettings

/// Applies Screen Time shields to the native apps the user picked.
struct ShieldManager {
    private let store = ManagedSettingsStore(named: ManagedSettingsStore.Name("socialRewind"))

    func apply(_ selections: [FamilyActivitySelection]) {
        let tokens = selections.reduce(into: Set<ApplicationToken>()) { $0.formUnion($1.applicationTokens) }
        store.shield.applications = tokens.isEmpty ? nil : tokens
        // TODO(spike 0.5): also shield the platform's web domains in Safari, once we've
        // confirmed that doesn't block our own WKWebView.
    }

    func clearAll() {
        store.clearAllSettings()
    }
}
