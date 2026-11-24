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

    private func make(appName: String?) -> ShieldConfiguration {
        let name = appName ?? "This app"
        return ShieldConfiguration(
            backgroundBlurStyle: .systemThickMaterial,
            backgroundColor: .systemBackground,
            icon: UIImage(systemName: "backward.end.circle"),
            title: ShieldConfiguration.Label(text: "Locked by Social Rewind", color: .label),
            subtitle: ShieldConfiguration.Label(
                text: "Open \(name) in Social Rewind to use it without the parts you blocked.",
                color: .secondaryLabel),
            primaryButtonLabel: ShieldConfiguration.Label(text: "Open in Social Rewind", color: .systemBackground),
            primaryButtonBackgroundColor: .label,
            secondaryButtonLabel: ShieldConfiguration.Label(text: "Close", color: .label)
        )
    }
}
