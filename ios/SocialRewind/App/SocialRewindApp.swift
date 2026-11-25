import SwiftUI
import UserNotifications

@main
struct SocialRewindApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var model = AppModel()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(model)
                .onOpenURL { model.handle(url: $0) }
                .onAppear { appDelegate.attach(model) }
                .task { await model.refreshRulesIfNeeded() }
        }
    }
}

struct RootView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        #if DEBUG
        if let screen = DebugScreen.requested {
            DebugScreenView(screen: screen)
        } else {
            main
        }
        #else
        main
        #endif
    }

    @ViewBuilder private var main: some View {
        if model.onboardingComplete {
            HomeView()
        } else {
            OnboardingView()
        }
    }
}

/// Handles taps on the "Open in Social Rewind" notification posted by the ShieldAction extension.
final class AppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    private weak var model: AppModel?
    /// A deep link that arrived before SwiftUI attached the model (cold launch from a notification).
    private var pendingURL: URL?

    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        UNUserNotificationCenter.current().delegate = self
        return true
    }

    func attach(_ model: AppModel) {
        self.model = model
        if let url = pendingURL {
            pendingURL = nil
            model.handle(url: url)
        }
    }

    private func open(_ url: URL) {
        if let model { model.handle(url: url) } else { pendingURL = url }
    }

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter,
                                            didReceive response: UNNotificationResponse) async {
        guard let string = response.notification.request.content.userInfo[NotificationKeys.url] as? String,
              let url = URL(string: string) else { return }
        await open(url)
    }

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter,
                                            willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
        [.banner]
    }
}
