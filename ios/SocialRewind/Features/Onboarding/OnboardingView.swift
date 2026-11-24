import FamilyControls
import RewindCore
import SwiftUI
import UserNotifications

/// welcome → Screen Time authorization → pick each platform's app → notifications → done.
struct OnboardingView: View {
    @Environment(AppModel.self) private var model

    private enum Step: Hashable {
        case welcome
        case authorize
        case pick(Platform)
        case notifications
    }

    @State private var step: Step = .welcome
    @State private var errorMessage: String?

    private var platforms: [Platform] { Platform.allCases.filter(\.isAvailable) }

    var body: some View {
        VStack(spacing: 24) {
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

    // MARK: Steps

    private var welcome: some View {
        StepView(title: "Social media, minus the bits built to keep you scrolling",
                 message: "Social Rewind locks the apps on your phone and lets you back in through a filtered view: no Reels, no suggested posts, no ads, unless you want them.",
                 actionTitle: "Get started") {
            step = .authorize
        }
    }

    private var authorize: some View {
        StepView(title: "Allow Screen Time access",
                 message: "Social Rewind uses Apple's Screen Time to lock apps. Everything stays on your phone, and nothing is sent anywhere.",
                 actionTitle: "Continue") {
            Task {
                do {
                    try await AuthorizationCenter.shared.requestAuthorization(for: .individual)
                    errorMessage = nil
                    if let first = platforms.first { step = .pick(first) } else { step = .notifications }
                } catch {
                    errorMessage = "Screen Time access is needed to lock apps. You can try again, or allow it later in Settings."
                }
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
        StepView(title: "One more thing",
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

private struct StepView: View {
    let title: String
    let message: String
    let actionTitle: String
    let action: () -> Void

    var body: some View {
        VStack(spacing: 20) {
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
        }
    }
}
