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
    @Environment(\.scenePhase) private var scenePhase
    #if DEBUG
    @State private var debugScreen = DebugScreen.requested
    #endif

    var body: some View {
        #if DEBUG
        if let screen = debugScreen {
            DebugScreenView(screen: screen)
                // Finishing onboarding from a debug screen continues into the real app.
                .onChange(of: model.onboardingComplete) { _, done in if done { debugScreen = nil } }
        } else {
            main
        }
        #else
        main
        #endif
    }

    @ViewBuilder private var main: some View {
        @Bindable var model = model
        Group {
            if model.onboardingComplete {
                HomeView()
            } else {
                OnboardingView()
            }
        }
        // Any screen can hold back a loosening change for the settings PIN.
        .sheet(item: $model.pinPrompt) { prompt in
            PinPromptView(prompt: prompt)
        }
        .onChange(of: scenePhase) { _, phase in
            switch phase {
            case .active:
                model.applyDuePinReset()
                // Notification permission can change in iOS Settings while the app is in the background.
                Task { await model.refreshNotificationPermission() }
            case .background:
                model.lockSettings()
            default:
                break
            }
        }
        .task { await model.refreshNotificationPermission() }
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

    // Completion-handler versions, not the async ones: iOS may call these off the main thread, and
    // the async bridging plus Swift 6's executor checks is a known crash. Each copies out what it
    // needs, hops to the main actor itself, and calls the handler there.
    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter,
                                            didReceive response: UNNotificationResponse,
                                            withCompletionHandler completionHandler: @escaping () -> Void) {
        let link = (response.notification.request.content.userInfo[NotificationKeys.url] as? String).flatMap(URL.init(string:))
        nonisolated(unsafe) let done = completionHandler
        Task { @MainActor in
            if let link { self.open(link) }
            done()
        }
    }

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter,
                                            willPresent notification: UNNotification,
                                            withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner])
    }
}
