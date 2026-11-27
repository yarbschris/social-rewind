import RewindCore
import SwiftUI

/// Settings for one platform, generated from its rule pack.
struct PlatformSettingsView: View {
    @Environment(AppModel.self) private var model
    let platform: Platform
    @State private var showSignInHelp = false

    var body: some View {
        Group {
            if let loaded = model.rulePack(for: platform) {
                form(loaded)
            } else {
                ContentUnavailableView("No filter rules", systemImage: "exclamationmark.shield")
            }
        }
        .navigationTitle(platform.displayName)
        .sheet(isPresented: $showSignInHelp) {
            SignInHelpSheet(platform: platform)
        }
    }

    private func form(_ loaded: LoadedRulePack) -> some View {
        let pack = loaded.pack
        let settings = model.settings(for: platform)
        let effective = settings.effectiveFeatures(for: pack)
        let mode = settings.effectiveMode(for: pack)

        return Form {
            Section {
                Picker("Mode", selection: settingBinding(\.mode)) {
                    Text("Normal").tag(PlatformSettings.normalMode)
                    ForEach(loaded.modeOrder, id: \.self) { id in
                        Text(pack.modes?[id]?.title ?? id).tag(id)
                    }
                }
                .pickerStyle(.inline)
                .labelsHidden()
            } header: {
                Text("Mode")
            } footer: {
                if let description = pack.modes?[mode]?.description {
                    Text(description)
                }
            }

            if pack.modes?[mode]?.home.contains("{username}") == true {
                UsernameSection(platform: platform)
            }

            featureSection("Content", group: .content, loaded: loaded, effective: effective)
            featureSection("Ads & recommendations", group: .ads, loaded: loaded, effective: effective)

            Section("Wellbeing") {
                Toggle("Grayscale", isOn: settingBinding(\.grayscale))
                Toggle("Post counter", isOn: settingBinding(\.postCounter))
                ReminderControls()
            }

            if ShortcutPlatform(rawValue: platform.rawValue) != nil {
                HomeScreenShortcutSection(platform: platform)
            }

            Section {
                Button("Trouble signing in?") { showSignInHelp = true }
            } footer: {
                Text("If \(platform.displayName) wants you to approve the login in its app, Social Rewind can unlock it for a moment.")
            }

            RulesSection(revision: pack.revision)
        }
    }

    @ViewBuilder
    private func featureSection(_ title: String, group: RulePack.FeatureGroup,
                                loaded: LoadedRulePack, effective: [String: Bool]) -> some View {
        let features = loaded.features(in: group)
        if !features.isEmpty {
            Section(title) {
                ForEach(features, id: \.id) { feature in
                    if feature.def.isAvailable {
                        Toggle(isOn: Binding(
                            get: { effective[feature.id] ?? false },
                            set: { value in model.updateSettings(for: platform) { $0.features[feature.id] = value } }
                        )) {
                            FeatureLabel(def: feature.def)
                        }
                    } else {
                        LabeledContent {
                            Text("Coming soon").font(.caption).foregroundStyle(.secondary)
                        } label: {
                            FeatureLabel(def: feature.def)
                        }
                        .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    private func settingBinding<T>(_ keyPath: WritableKeyPath<PlatformSettings, T>) -> Binding<T> {
        Binding(
            get: { model.settings(for: platform)[keyPath: keyPath] },
            set: { value in model.updateSettings(for: platform) { $0[keyPath: keyPath] = value } }
        )
    }
}

/// Modes like "Saved posts only" land on "/{username}/saved/", so they need the account handle.
/// The engine can also learn it from the page, but the user can always set it here.
private struct UsernameSection: View {
    @Environment(AppModel.self) private var model
    let platform: Platform
    @State private var draft = ""
    @State private var invalid = false

    var body: some View {
        Section {
            TextField("username", text: $draft)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .textContentType(.username)
                .submitLabel(.done)
                .onSubmit(save)
            if invalid {
                Text("Use letters, numbers, periods and underscores (up to 30).")
                    .font(.footnote).foregroundStyle(.red)
            }
        } header: {
            Text("Your \(platform.displayName) username")
        } footer: {
            Text("Needed to open your saved posts. Stays on this iPhone.")
        }
        .onAppear { draft = model.username(for: platform) ?? "" }
        .onChange(of: draft) { _, _ in invalid = false }
        .onDisappear(perform: save)
    }

    private func save() {
        guard draft != (model.username(for: platform) ?? "") else { return }
        invalid = !model.setUsername(draft, for: platform)
    }
}

/// How to put "Open <platform> in Social Rewind" on the Home Screen. The app can't add the icon
/// itself: only the Shortcuts app can, so this explains the steps and opens a new shortcut there.
/// UNVERIFIED (roadmap 0.7): the labels below match what Shortcuts shows.
private struct HomeScreenShortcutSection: View {
    @Environment(\.openURL) private var openURL
    let platform: Platform

    /// Documented in Apple's Shortcuts User Guide ("Run a shortcut from a URL"): opens a new, empty shortcut.
    private static let newShortcutURL = URL(string: "shortcuts://create-shortcut")!

    var body: some View {
        Section {
            VStack(alignment: .leading, spacing: 6) {
                Text("1. Tap **New shortcut** below.")
                Text("2. Search for **Social Rewind** and add its **Open in Social Rewind** action. Check that it says \(platform.displayName).")
                Text("3. Open the menu under the shortcut's name at the top and choose **Add to Home Screen**. You can pick its name and icon there.")
            }
            .font(.subheadline)
            Button("New shortcut") { openURL(Self.newShortcutURL) }
        } header: {
            Text("Home Screen shortcut")
        } footer: {
            Text("Put \(platform.displayName) on your Home Screen so it opens here. You can also say “Open \(platform.displayName) in Social Rewind” to Siri, or use it with the Action button.")
        }
    }
}

private struct FeatureLabel: View {
    let def: RulePack.FeatureDef

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(def.title)
            if let description = def.description {
                Text(description).font(.caption).foregroundStyle(.secondary)
            }
        }
    }
}

private struct ReminderControls: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        Toggle("Scroll reminders", isOn: reminder(\.enabled))
        if model.reminders.enabled {
            Stepper(model.reminders.everyPosts == 0 ? "No post reminder" : "Every \(model.reminders.everyPosts) posts",
                    value: reminder(\.everyPosts), in: 0...500, step: 10)
            Stepper(model.reminders.everyMinutes == 0 ? "No time reminder" : "Every \(model.reminders.everyMinutes) minutes",
                    value: reminder(\.everyMinutes), in: 0...120, step: 5)
        }
    }

    /// Goes through `setReminders`, so making reminders less frequent asks for the PIN.
    private func reminder<T>(_ keyPath: WritableKeyPath<ReminderSettings, T>) -> Binding<T> {
        Binding(
            get: { model.reminders[keyPath: keyPath] },
            set: { value in
                var new = model.reminders
                new[keyPath: keyPath] = value
                model.setReminders(new)
            }
        )
    }
}

private struct RulesSection: View {
    @Environment(AppModel.self) private var model
    let revision: Int

    var body: some View {
        @Bindable var model = model
        Section {
            Toggle("Update filter rules automatically", isOn: $model.developer.autoUpdateRules)
            LabeledContent("Rules version", value: "r\(revision)")
            if model.developer.autoUpdateRules {
                Button("Check now") { Task { await model.refreshRulesIfNeeded(force: true) } }
                if let status = model.ruleRefreshStatus {
                    Text(status).font(.caption).foregroundStyle(.secondary)
                }
            }
        } header: {
            Text("Filter rules")
        } footer: {
            Text("When this is on, Social Rewind downloads updated filter rules from its public GitHub repository. Nothing about you is sent. Off by default.")
        }

        #if DEBUG
        Section("Developer") {
            Toggle("Show filter debug overlay", isOn: $model.developer.debugOverlay)
            Toggle("Experimental network filtering", isOn: $model.developer.experimentalNetworkFiltering)
        }
        #endif
    }
}
