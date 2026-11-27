import AppIntents
import RewindCore

/// The platforms a shortcut can open. App Intents reads enum cases at build time, so this can't be
/// derived from `Platform.isAvailable`: add a case here when a platform becomes available.
enum ShortcutPlatform: String, AppEnum {
    case instagram

    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Platform"
    static let caseDisplayRepresentations: [ShortcutPlatform: DisplayRepresentation] = [
        .instagram: "Instagram",
    ]

    var platform: Platform? { Platform(rawValue: rawValue) }
}

/// Opens a platform's filtered web view. Users can put it on the Home Screen through the Shortcuts
/// app, or run it from Siri, Spotlight or the Action button.
struct OpenPlatformIntent: AppIntent {
    static let title: LocalizedStringResource = "Open in Social Rewind"
    static let description = IntentDescription("Opens a platform's filtered view in Social Rewind.")
    // `supportedModes` replaces this from iOS 26, but the app supports iOS 17.
    static let openAppWhenRun = true

    @Parameter(title: "Platform")
    var platform: ShortcutPlatform

    static var parameterSummary: some ParameterSummary {
        Summary("Open \(\.$platform) in Social Rewind")
    }

    init() {}

    init(platform: ShortcutPlatform) {
        self.platform = platform
    }

    @MainActor
    func perform() async throws -> some IntentResult {
        // Same path as the shield's notification, so the same checks apply (available platform,
        // onboarding finished).
        if let platform = platform.platform {
            DeepLinkRouter.shared.open(DeepLink.open(platform).url)
        }
        return .result()
    }
}

/// Listed under Social Rewind in the Shortcuts app as soon as the app is installed, one per platform.
struct SocialRewindShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: OpenPlatformIntent(),
            phrases: [
                "Open \(\.$platform) in \(.applicationName)",
                "Rewind \(\.$platform) with \(.applicationName)",
            ],
            shortTitle: "Open",
            systemImageName: "arrow.counterclockwise"
        )
    }
}
