import RewindCore
import SwiftUI

/// Turn the settings PIN on or off, change it, or cancel a pending reset.
struct SettingsPinView: View {
    @Environment(AppModel.self) private var model
    @State private var settingUp = false

    var body: some View {
        Form {
            if let pin = model.settingsPin {
                Section {
                    Button("Change PIN") {
                        if model.settingsUnlocked {
                            settingUp = true
                        } else {
                            model.guarded(loosens: true, "Enter your current PIN to change it.") { _ in
                                // Let the PIN prompt finish closing: a sheet presented while another
                                // is still dismissing can be dropped.
                                Task { @MainActor in
                                    try? await Task.sleep(for: .milliseconds(600))
                                    settingUp = true
                                }
                            }
                        }
                    }
                    Button("Turn off PIN", role: .destructive) { model.removePin() }
                } footer: {
                    Text("Turning a filter off, leaving DMs only or Saved posts only, making reminders less frequent or unlocking an app asks for this PIN. Making things stricter never does.")
                }
                if let date = pin.resetDate {
                    Section {
                        Button("Cancel reset") { model.cancelPinReset() }
                    } header: {
                        Text("Reset requested")
                    } footer: {
                        Text("The PIN will be removed \(date.formatted(.relative(presentation: .named))), on \(date.formatted(date: .abbreviated, time: .shortened)). Entering it before then cancels the reset.")
                    }
                }
            } else {
                Section {
                    Button("Turn on PIN") { settingUp = true }
                } footer: {
                    Text("With a PIN set, loosening any restriction asks for it: turning a filter off, leaving DMs only or Saved posts only, making reminders less frequent or unlocking an app. Making things stricter never does. A friend can set it for you. If it's forgotten, it can be reset after a 24-hour wait.")
                }
            }
        }
        .navigationTitle("Settings PIN")
        .sheet(isPresented: $settingUp) {
            PinSetupView(isChange: model.settingsPin != nil)
        }
    }
}

/// Choose a new PIN, then enter it again, like setting a passcode in iOS Settings.
private struct PinSetupView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let isChange: Bool
    @State private var length = 6
    @State private var first: String?
    @State private var message: String?
    @State private var showOptions = false

    var body: some View {
        NavigationStack {
            PasscodeEntry(title: first == nil ? (isChange ? "Enter a new PIN" : "Choose a PIN") : "Enter it again",
                          message: message,
                          length: length,
                          submit: submit) {
                if first == nil {
                    Button("PIN Options") { showOptions = true }
                        .font(.body)
                }
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .confirmationDialog("PIN length", isPresented: $showOptions) {
                Button("4-Digit PIN") { choose(4) }
                Button("6-Digit PIN") { choose(6) }
            }
        }
        .interactiveDismissDisabled()
    }

    private func choose(_ digits: Int) {
        length = digits
        message = nil
    }

    private func submit(_ code: String) -> PasscodeResult {
        guard let first else {
            self.first = code
            message = nil
            return .next
        }
        guard code == first else {
            self.first = nil
            message = "The PINs didn't match. Try again."
            return .rejected
        }
        model.setPin(code)
        dismiss()
        return .accepted
    }
}

/// Asks for the PIN before a loosening change goes through.
struct PinPromptView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let prompt: PinPrompt
    @State private var message: String?
    @State private var confirmReset = false

    var body: some View {
        PasscodeEntry(title: "Enter Settings PIN",
                      message: message ?? prompt.reason,
                      length: model.settingsPin?.length,
                      submit: submit) {
            HStack {
                if let date = model.settingsPin?.resetDate {
                    Text("PIN removed \(date.formatted(.relative(presentation: .named)))")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                } else {
                    Button("Forgot PIN?") { confirmReset = true }
                }
                Spacer()
                Button("Cancel") {
                    model.pinPrompt = nil
                    dismiss()
                }
            }
        }
        .presentationDetents([.large])
        .interactiveDismissDisabled()
        .confirmationDialog("Reset the PIN?", isPresented: $confirmReset, titleVisibility: .visible) {
            Button("Remove PIN in 24 hours", role: .destructive) { model.requestPinReset() }
        } message: {
            Text("The PIN will be removed after a 24-hour wait. Until then, everything stays as it is.")
        }
    }

    private func submit(_ pin: String) -> PasscodeResult {
        switch model.enterPin(pin) {
        case .correct:
            dismiss()
            return .accepted
        case .wrong(let left):
            message = left == 1 ? "Wrong PIN. 1 try left before a pause." : "Wrong PIN. \(left) tries left before a pause."
        case .paused(let until):
            message = "Too many tries. Try again \(until.formatted(.relative(presentation: .named)))."
        }
        return .rejected
    }
}
