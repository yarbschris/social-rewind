import Foundation
import ManagedSettings
import RewindCore
import UserNotifications

/// Handles the buttons on the shield screen.
///
/// Apple doesn't let a shield extension open its containing app. As a workaround, the
/// primary button posts a local notification that deep-links into Social Rewind.
/// UNVERIFIED (roadmap spike 0.4): that extension-posted notifications are delivered
/// reliably, and that this extension lives long enough for `add` to finish.
final class ShieldActionExtension: ShieldActionDelegate {
    override func handle(action: ShieldAction,
                         for application: ApplicationToken,
                         completionHandler: @escaping (ShieldActionResponse) -> Void) {
        switch action {
        case .primaryButtonPressed:
            // nil if the token isn't in any saved selection; still open the app.
            let platform = SharedStore().platform(for: application)
            // Callback API instead of async/await: Swift 6 rejects sending the
            // non-Sendable completion handler into a Task.
            nonisolated(unsafe) let done = completionHandler
            UNUserNotificationCenter.current().add(Self.openRequest(for: platform)) { _ in
                done(.close)
            }
        case .secondaryButtonPressed:
            completionHandler(.close)
        @unknown default:
            completionHandler(.close)
        }
    }

    override func handle(action: ShieldAction,
                         for webDomain: WebDomainToken,
                         completionHandler: @escaping (ShieldActionResponse) -> Void) {
        completionHandler(.close)
    }

    override func handle(action: ShieldAction,
                         for category: ActivityCategoryToken,
                         completionHandler: @escaping (ShieldActionResponse) -> Void) {
        completionHandler(.close)
    }

    private static func openRequest(for platform: Platform?) -> UNNotificationRequest {
        let content = UNMutableNotificationContent()
        if let platform {
            content.title = "Open \(platform.displayName)"
            content.body = "Tap to open \(platform.displayName) in Social Rewind."
            content.userInfo = [NotificationKeys.url: DeepLink.open(platform).url.absoluteString]
        } else {
            content.title = "Open Social Rewind"
            content.body = "Tap to continue in Social Rewind."
            content.userInfo = [NotificationKeys.url: "\(DeepLink.scheme)://"]
        }
        content.categoryIdentifier = NotificationKeys.openCategory
        content.interruptionLevel = .active // .timeSensitive would need an extra entitlement

        return UNNotificationRequest(identifier: "open-\(platform?.rawValue ?? "app")",
                                     content: content,
                                     trigger: nil) // deliver now
    }
}
