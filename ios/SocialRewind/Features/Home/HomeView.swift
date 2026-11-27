import FamilyControls
import RewindCore
import SwiftUI

struct HomeView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        NavigationStack {
            List {
                if model.hasActiveLocks && model.notificationsAllowed == false {
                    NotificationsOffSection()
                }

                Section {
                    ForEach(Platform.allCases.filter(\.isAvailable)) { platform in
                        PlatformRow(platform: platform)
                    }
                }

                Section {
                    NavigationLink { SettingsPinView() } label: {
                        LabeledContent("Settings PIN", value: model.settingsPin == nil ? "Off" : "On")
                    }
                }

                Section {
                    EmptyView()
                } footer: {
                    let later = Platform.allCases.filter { !$0.isAvailable }.map(\.displayName)
                    if !later.isEmpty {
                        Text("Coming later: \(later.formatted(.list(type: .and))).")
                    }
                }
            }
            .navigationTitle("Social Rewind")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    NavigationLink { StatsView() } label: { Image(systemName: "chart.bar") }
                        .accessibilityLabel("Today's stats")
                }
                if BuildFeatures.screenTime {
                    ToolbarItem(placement: .topBarTrailing) {
                        NavigationLink { LockedAppsView() } label: { Image(systemName: "lock.shield") }
                            .accessibilityLabel("Locked apps")
                    }
                }
            }
            .fullScreenCover(item: $model.openPlatform) { platform in
                PlatformBrowserView(session: model.browserSessions.session(for: platform))
                    .environment(model)
            }
        }
    }
}

private struct PlatformRow: View {
    @Environment(AppModel.self) private var model
    let platform: Platform

    var body: some View {
        HStack {
            NavigationLink {
                PlatformSettingsView(platform: platform)
            } label: {
                VStack(alignment: .leading, spacing: 2) {
                    Text(platform.displayName).font(.title3.weight(.semibold))
                    // An empty Text still takes a line and pushes the name off centre.
                    if !summary.isEmpty {
                        Text(summary).font(.subheadline).foregroundStyle(.secondary)
                    }
                }
                .padding(.vertical, 4)
            }
            Button("Open") { model.openPlatform = platform }
                .buttonStyle(.borderedProminent)
                .disabled(model.rulePack(for: platform) == nil)
        }
    }

    /// Lock state (when this build has Screen Time), then the mode, or in normal mode how many filters are on.
    private var summary: String {
        let locked = model.lockedPlatforms.contains(platform) && model.selections[platform] != nil
        let lockState = BuildFeatures.screenTime ? (locked ? "App locked" : "App not locked") : nil
        return [lockState, modeSummary].compactMap { $0 }.joined(separator: " · ")
    }

    private var modeSummary: String? {
        guard let pack = model.rulePack(for: platform)?.pack else { return nil }
        let settings = model.settings(for: platform)
        if let title = pack.modes?[settings.mode]?.title { return title }
        let available = pack.features.values.filter(\.isAvailable).count
        let on = settings.effectiveFeatures(for: pack).values.filter { $0 }.count
        return available > 0 ? "\(on) of \(available) filters on" : nil
    }
}

/// Without notifications, the shield's "Open in Social Rewind" button does nothing visible.
private struct NotificationsOffSection: View {
    var body: some View {
        Section {
            Label("Notifications are off", systemImage: "bell.slash")
                .font(.headline)
            Text("When you open a locked app, Social Rewind reaches you with a notification. Apple doesn't let the lock screen open apps directly. Without notifications, the lock screen's button can't bring you here.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Button("Turn on in Settings") {
                if let url = URL(string: UIApplication.openNotificationSettingsURLString) {
                    UIApplication.shared.open(url)
                }
            }
        }
    }
}

/// Re-pick or unlock the native apps after onboarding.
struct LockedAppsView: View {
    @Environment(AppModel.self) private var model
    @State private var screenTimeStatus = AuthorizationCenter.shared.authorizationStatus

    var body: some View {
        List {
            // Someone who finished onboarding on a build without Screen Time never granted it.
            if screenTimeStatus != .approved {
                Section {
                    Button("Allow Screen Time access") {
                        Task {
                            try? await AuthorizationCenter.shared.requestAuthorization(for: .individual)
                            screenTimeStatus = AuthorizationCenter.shared.authorizationStatus
                        }
                    }
                } footer: {
                    Text("Social Rewind needs Screen Time access to lock apps. Everything stays on your phone.")
                }
            }
            ForEach(Platform.allCases.filter(\.isAvailable)) { platform in
                let hasApp = !(model.selections[platform]?.applicationTokens.isEmpty ?? true)
                Section {
                    AppPickerRow(platform: platform)
                    // Locking does nothing until the app itself is picked, so don't show it as on.
                    Toggle("Lock the \(platform.displayName) app", isOn: Binding(
                        get: { hasApp && model.lockedPlatforms.contains(platform) },
                        set: { model.setLocked($0, for: platform) }))
                        .disabled(!hasApp)
                } header: {
                    Text(platform.displayName)
                } footer: {
                    if !hasApp {
                        Text("Select the \(platform.displayName) app first. Until then it isn't locked, and you can still open it as usual.")
                    }
                }
            }
        }
        .navigationTitle("Locked apps")
    }
}

/// Shows the picked app and lets the user re-pick it. Requires at least one app token.
struct AppPickerRow: View {
    @Environment(AppModel.self) private var model
    let platform: Platform
    @State private var showPicker = false
    @State private var draft = FamilyActivitySelection()
    @State private var problem: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let tokens = model.selections[platform]?.applicationTokens, !tokens.isEmpty {
                ForEach(Array(tokens), id: \.self) { token in
                    Label(token)
                }
            } else {
                Text("No app selected").foregroundStyle(.secondary)
            }
            Button(model.selections[platform] == nil ? "Select \(platform.displayName)" : "Change selection") {
                draft = model.selections[platform] ?? FamilyActivitySelection()
                showPicker = true
            }
            if let problem {
                Text(problem).font(.footnote).foregroundStyle(.red)
            }
        }
        .familyActivityPicker(isPresented: $showPicker, selection: $draft)
        .onChange(of: draft) { _, selection in
            problem = Self.problem(with: selection, platform: platform)
            if problem == nil { model.setSelection(selection, for: platform) }
        }
    }

    /// The shield uses app tokens only, so categories or websites alone would lock nothing.
    static func problem(with selection: FamilyActivitySelection, platform: Platform) -> String? {
        if selection.applicationTokens.isEmpty {
            return "Select the \(platform.displayName) app itself (not a category or website)."
        }
        if selection.applicationTokens.count > 1 {
            return "Select only the \(platform.displayName) app."
        }
        return nil
    }
}
