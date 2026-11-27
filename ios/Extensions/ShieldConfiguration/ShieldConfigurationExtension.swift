import ManagedSettings
import ManagedSettingsUI
import UIKit

/// The screen iOS shows when the user opens a shielded app (e.g. Instagram).
final class ShieldConfigurationExtension: ShieldConfigurationDataSource {
    override func configuration(shielding application: Application) -> ShieldConfiguration {
        make(appName: application.localizedDisplayName)
    }

    override func configuration(shielding application: Application, in category: ActivityCategory) -> ShieldConfiguration {
        make(appName: application.localizedDisplayName)
    }

    override func configuration(shielding webDomain: WebDomain) -> ShieldConfiguration {
        make(appName: webDomain.domain)
    }

    override func configuration(shielding webDomain: WebDomain, in category: ActivityCategory) -> ShieldConfiguration {
        make(appName: webDomain.domain)
    }

    /// Fixed colours, not dynamic ones: inside the shield, .label and .systemBackground resolved to
    /// the same colour, so the primary button's text was invisible. These are the app icon's teal and cream.
    private static let buttonColor = UIColor(red: 0x2A / 255, green: 0x6B / 255, blue: 0x78 / 255, alpha: 1)
    private static let buttonTextColor = UIColor(red: 0xF4 / 255, green: 0xEB / 255, blue: 0xDD / 255, alpha: 1)

    private func make(appName: String?) -> ShieldConfiguration {
        let name = appName ?? "This app"
        return ShieldConfiguration(
            backgroundBlurStyle: .systemThickMaterial,
            backgroundColor: .systemBackground,
            icon: UIImage(systemName: "backward.end.circle"),
            title: ShieldConfiguration.Label(text: "Locked by Social Rewind", color: .label),
            subtitle: ShieldConfiguration.Label(
                text: "Tap below, then tap the notification to open \(name) in Social Rewind without the parts you blocked.",
                color: .secondaryLabel),
            primaryButtonLabel: ShieldConfiguration.Label(text: "Open in Social Rewind", color: Self.buttonTextColor),
            primaryButtonBackgroundColor: Self.buttonColor,
            secondaryButtonLabel: ShieldConfiguration.Label(text: "Close", color: .label)
        )
    }
}
