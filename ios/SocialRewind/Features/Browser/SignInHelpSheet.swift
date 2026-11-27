import RewindCore
import SwiftUI
import UIKit

/// Help for platforms whose two-factor check asks you to approve the login in their own app,
/// which Social Rewind has locked. It can unlock that app just long enough to approve.
struct SignInHelpSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let platform: Platform
    @State private var enteringPin = false
    @State private var problem: String?

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Text("If \(platform.displayName) asks you to approve this login in its app, Social Rewind can unlock the app for a moment.")
                }

                approveSection

                Section {
                    Text("On \(platform.displayName)'s verification page, tap **Try another way** to use a text message, an authenticator app or a backup code instead, if your account has one set up.")
                } header: {
                    Text("Or use another method")
                }
            }
            .navigationTitle("Sign-in help")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
            .navigationDestination(isPresented: $enteringPin) {
                PasscodeEntry(title: "Enter Settings PIN",
                              message: "Unlocking \(platform.displayName) needs your settings PIN.",
                              length: model.settingsPin?.length,
                              submit: submitPin) { EmptyView() }
            }
        }
    }

    @ViewBuilder private var approveSection: some View {
        Section {
            if model.signInUnlocks.contains(platform) {
                Text("\(platform.displayName) is unlocked. Approve the login there, then come back here. It locks again as soon as you return, or after 15 minutes.")
                openAppButton
            } else if model.isAppLocked(platform) {
                Button("Unlock \(platform.displayName) to approve") {
                    if model.settingsUnlocked { unlock() } else { enteringPin = true }
                }
                if let problem {
                    Text(problem).font(.footnote).foregroundStyle(.red)
                }
            } else {
                Text("The \(platform.displayName) app isn't locked, so you can approve the login there now.")
                openAppButton
            }
        } header: {
            Text("Approve in the \(platform.displayName) app")
        }
    }

    @ViewBuilder private var openAppButton: some View {
        if let url = platform.nativeAppURL {
            Button("Open \(platform.displayName)") { UIApplication.shared.open(url) }
        }
    }

    private func submitPin(_ pin: String) -> PasscodeResult {
        guard model.enterPin(pin) == .correct else { return .rejected }
        enteringPin = false
        unlock()
        return .accepted
    }

    private func unlock() {
        if model.unlockForSignIn(platform) {
            problem = nil
            if let url = platform.nativeAppURL { UIApplication.shared.open(url) }
        } else {
            problem = "Couldn't unlock it. Turn off the lock in Locked apps on the Home screen instead, then turn it back on after signing in."
        }
    }
}
