import RewindCore
import SwiftUI

/// Turn the settings PIN on or off, change it, or cancel a pending reset.
struct SettingsPinView: View {
    @Environment(AppModel.self) private var model
    /// Shows the new-PIN fields: always when there's no PIN, and after "Change PIN" is unlocked.
    @State private var choosingPin = false

    var body: some View {
        Form {
            if let pin = model.settingsPin, !choosingPin {
                Section {
                    Button("Change PIN") {
                        model.guarded(loosens: true, "Changing the settings PIN needs the current PIN.") { _ in
                            choosingPin = true
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
                NewPinSection(isChange: model.settingsPin != nil) { choosingPin = false }
            }
        }
        .navigationTitle("Settings PIN")
    }
}

private struct NewPinSection: View {
    @Environment(AppModel.self) private var model
    let isChange: Bool
    let done: () -> Void
    @State private var pin = ""
    @State private var confirmation = ""
    @State private var problem: String?

    var body: some View {
        Section {
            // No textContentType: a password type would invite iOS to suggest or save "passwords",
            // and AutoFill would bring back Face ID, which the PIN deliberately avoids.
            SecureField("New PIN (4–6 digits)", text: $pin)
                .keyboardType(.numberPad)
            SecureField("Confirm PIN", text: $confirmation)
                .keyboardType(.numberPad)
            Button(isChange ? "Save new PIN" : "Turn on PIN", action: save)
                .disabled(pin.isEmpty || confirmation.isEmpty)
            if let problem {
                Text(problem).font(.footnote).foregroundStyle(.red)
            }
        } footer: {
            Text("With a PIN set, loosening any restriction asks for it: turning a filter off, leaving DMs only or Saved posts only, making reminders less frequent or unlocking an app. Making things stricter never does. A friend can set it for you. If it's forgotten, it can be reset after a 24-hour wait.")
        }
        .onChange(of: pin) { _, _ in problem = nil }
        .onChange(of: confirmation) { _, _ in problem = nil }
    }

    private func save() {
        guard SettingsPin.isValid(pin) else {
            problem = "Use 4 to 6 digits."
            return
        }
        guard pin == confirmation else {
            problem = "The PINs don't match."
            return
        }
        model.setPin(pin)
        pin = ""
        confirmation = ""
        done()
    }
}

/// Asks for the PIN before a loosening change goes through.
struct PinPromptView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let prompt: PinPrompt
    @State private var pin = ""
    @State private var message: String?
    @State private var confirmReset = false
    @FocusState private var focused: Bool

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    SecureField("PIN", text: $pin)
                        .keyboardType(.numberPad)
                        .focused($focused)
                        .onSubmit(submit)
                    Button("Unlock", action: submit)
                        .disabled(pin.isEmpty)
                    if let message {
                        Text(message).font(.footnote).foregroundStyle(.red)
                    }
                } footer: {
                    Text(prompt.reason)
                }

                Section {
                    if let date = model.settingsPin?.resetDate {
                        Text("The PIN will be removed \(date.formatted(.relative(presentation: .named))). Entering it before then cancels the reset.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    } else {
                        Button("Forgot PIN?") { confirmReset = true }
                    }
                }
            }
            .navigationTitle("Enter settings PIN")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        model.pinPrompt = nil
                        dismiss()
                    }
                }
            }
            .confirmationDialog("Reset the PIN?", isPresented: $confirmReset, titleVisibility: .visible) {
                Button("Remove PIN in 24 hours", role: .destructive) { model.requestPinReset() }
            } message: {
                Text("The PIN will be removed after a 24-hour wait. Until then, everything stays as it is.")
            }
            .onAppear { focused = true }
        }
    }

    private func submit() {
        switch model.enterPin(pin) {
        case .correct:
            dismiss()
        case .wrong(let left):
            message = left == 1 ? "Wrong PIN. 1 try left before a pause." : "Wrong PIN. \(left) tries left before a pause."
        case .paused(let until):
            message = "Too many tries. Try again \(until.formatted(.relative(presentation: .named)))."
        }
        pin = ""
    }
}
