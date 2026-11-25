#if DEBUG
import RewindCore
import SwiftUI

/// Development builds only. Launch with `-SRScreen <name>` to open straight onto one screen,
/// e.g. `xcrun simctl launch booted app.socialrewind -SRScreen settings`. Used for screenshots
/// in the Simulator, which can't grant Screen Time access, so onboarding can't be finished there.
enum DebugScreen: String, CaseIterable {
    case welcome, authorize, pick, notifications
    case home, settings, locked, stats
    case browser, loading, failed, reminder
    case authorizeFailed

    static var requested: DebugScreen? {
        let args = ProcessInfo.processInfo.arguments
        guard let i = args.firstIndex(of: "-SRScreen"), i + 1 < args.count else { return nil }
        return DebugScreen(rawValue: args[i + 1])
    }
}

struct DebugScreenView: View {
    let screen: DebugScreen
    @State private var showReminder = true

    var body: some View {
        switch screen {
        case .welcome: OnboardingView(startAt: .welcome)
        case .authorize: OnboardingView(startAt: .authorize)
        case .authorizeFailed: OnboardingView(startAt: .authorize, debugError: true)
        case .pick: OnboardingView(startAt: .pick(.instagram))
        case .notifications: OnboardingView(startAt: .notifications)
        case .home: HomeView()
        case .settings: NavigationStack { PlatformSettingsView(platform: .instagram) }
        case .locked: NavigationStack { LockedAppsView() }
        case .stats: NavigationStack { StatsView() }
        case .browser: PlatformBrowserView(platform: .instagram)
        case .loading: FilterStatusCover(state: .loading, retry: {}, close: {})
        case .failed:
            FilterStatusCover(state: .failed("The filter engine didn't start within 10 seconds."), retry: {}, close: {})
        case .reminder:
            Color(.systemGroupedBackground).ignoresSafeArea()
                .sheet(isPresented: $showReminder) {
                    ReminderSheet(reminder: .init(posts: 50, minutes: 12), platform: .instagram) {}
                        .presentationDetents([.medium])
                }
        }
    }
}
#endif
