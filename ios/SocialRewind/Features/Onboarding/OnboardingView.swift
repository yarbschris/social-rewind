import FamilyControls
import RewindCore
import SwiftUI
import UserNotifications

/// welcome → Screen Time authorization → pick each platform's app → notifications → done.
struct OnboardingView: View {
    @Environment(AppModel.self) private var model

    enum Step: Hashable {
        case welcome
        case authorize
        case pick(Platform)
        case notifications
    }

    @State private var step: Step
    @State private var errorMessage: String?

    init(startAt step: Step = .welcome, debugError: Bool = false) {
        _step = State(initialValue: step)
        if debugError {
            _errorMessage = State(initialValue: "Screen Time access is needed to lock apps. Try again, or continue without locking: the filtered view still works, and you can lock apps later.")
        }
    }

    private var platforms: [Platform] { Platform.allCases.filter(\.isAvailable) }

    /// Every step in order, for the progress label and Back.
    private var steps: [Step] { [.welcome, .authorize] + platforms.map(Step.pick) + [.notifications] }

    var body: some View {
        VStack(spacing: 24) {
            header
            Spacer()
            switch step {
            case .welcome: welcome
            case .authorize: authorize
            case .pick(let platform): pick(platform)
            case .notifications: notifications
            }
            if let errorMessage {
                Text(errorMessage).font(.footnote).foregroundStyle(.red).multilineTextAlignment(.center)
            }
            Spacer()
        }
        .padding(24)
        .animation(.default, value: step)
    }

    /// Back button and "Step n of m", hidden on the welcome screen.
    @ViewBuilder private var header: some View {
        if let index = steps.firstIndex(of: step), index > 0 {
            HStack {
                Button {
                    errorMessage = nil
                    step = steps[index - 1]
                } label: {
                    Label("Back", systemImage: "chevron.backward")
                }
                Spacer()
                Text("Step \(index) of \(steps.count - 1)")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        } else {
            Color.clear.frame(height: 22)
        }
    }

    // MARK: Steps

    private var welcome: some View {
        StepView(systemImage: "gobackward",
                 title: "Social media, minus the bits built to keep you scrolling",
                 message: "Social Rewind locks the apps on your phone and lets you back in through a filtered view: no Reels, no suggested posts, no ads, unless you want them.",
                 actionTitle: "Get started") {
            step = .authorize
        }
    }

    private var authorize: some View {
        StepView(systemImage: "hourglass",
                 title: "Allow Screen Time access",
                 message: "Social Rewind uses Apple's Screen Time to lock apps. Everything stays on your phone, and nothing is sent anywhere.",
                 actionTitle: "Continue") {
            Task {
                do {
                    try await AuthorizationCenter.shared.requestAuthorization(for: .individual)
                    errorMessage = nil
                    if let first = platforms.first { step = .pick(first) } else { step = .notifications }
                } catch {
                    errorMessage = "Screen Time access is needed to lock apps. Try again, or continue without locking: the filtered view still works, and you can lock apps later."
                }
            }
        } secondary: {
            if errorMessage != nil {
                Button("Continue without locking") {
                    errorMessage = nil
                    step = .notifications
                }
                .font(.footnote)
            }
        }
    }

    private func pick(_ platform: Platform) -> some View {
        VStack(spacing: 20) {
            Text("Select \(platform.displayName)")
                .font(.title2.weight(.semibold))
            Text("Find \(platform.displayName) in the list and select only that app. Social Rewind can't see which app you picked, only that it should lock it.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
            AppPickerRow(platform: platform)
                .padding()
                .background(.background.secondary, in: RoundedRectangle(cornerRadius: 12))
            Button("Continue") { advance(from: platform) }
                .buttonStyle(.borderedProminent)
                .disabled(model.selections[platform]?.applicationTokens.isEmpty ?? true)
            Button("Skip \(platform.displayName)") { advance(from: platform) }
                .font(.footnote)
        }
    }

    private var notifications: some View {
        StepView(systemImage: "bell.badge",
                 title: "One more thing",
                 message: "When you open a locked app, Social Rewind sends a notification you can tap to continue in the filtered view. Apple doesn't let the lock screen open apps directly.",
                 actionTitle: "Allow notifications") {
            Task {
                _ = try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound])
                finish()
            }
        }
    }

    // MARK: Navigation

    private func advance(from platform: Platform) {
        errorMessage = nil
        if let index = platforms.firstIndex(of: platform), index + 1 < platforms.count {
            step = .pick(platforms[index + 1])
        } else {
            step = .notifications
        }
    }

    private func finish() {
        model.applyShields()
        model.onboardingComplete = true
    }
}

private struct StepView<Secondary: View>: View {
    let systemImage: String
    let title: String
    let message: String
    let actionTitle: String
    let action: () -> Void
    @ViewBuilder var secondary: Secondary

    init(systemImage: String, title: String, message: String, actionTitle: String,
         action: @escaping () -> Void, @ViewBuilder secondary: () -> Secondary = { EmptyView() }) {
        self.systemImage = systemImage
        self.title = title
        self.message = message
        self.actionTitle = actionTitle
        self.action = action
        self.secondary = secondary()
    }

    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: systemImage)
                .font(.system(size: 44, weight: .medium))
                .foregroundStyle(.tint)
                .accessibilityHidden(true)
            Text(title)
                .font(.title.weight(.semibold))
                .multilineTextAlignment(.center)
            Text(message)
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
            Button(action: action) {
                Text(actionTitle).frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            secondary
        }
    }
}
