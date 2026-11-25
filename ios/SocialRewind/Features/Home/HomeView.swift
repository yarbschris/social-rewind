import FamilyControls
import RewindCore
import SwiftUI

struct HomeView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        NavigationStack {
            List {
                Section {
                    ForEach(Platform.allCases.filter(\.isAvailable)) { platform in
                        PlatformRow(platform: platform)
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
                ToolbarItem(placement: .topBarTrailing) {
                    NavigationLink { LockedAppsView() } label: { Image(systemName: "lock.shield") }
                        .accessibilityLabel("Locked apps")
                }
            }
            .fullScreenCover(item: $model.openPlatform) { platform in
                PlatformBrowserView(platform: platform)
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
                    Text(platform.displayName).font(.headline)
                    Text(summary).font(.caption).foregroundStyle(.secondary)
                }
            }
            Button("Open") { model.openPlatform = platform }
                .buttonStyle(.borderedProminent)
                .disabled(model.rulePack(for: platform) == nil)
        }
    }

    private var summary: String {
        let locked = model.lockedPlatforms.contains(platform) && model.selections[platform] != nil
        let mode = model.settings(for: platform).mode
        let modeTitle = model.rulePack(for: platform)?.pack.modes?[mode]?.title
        return [locked ? "App locked" : "App not locked", modeTitle].compactMap { $0 }.joined(separator: " · ")
    }
}

/// Re-pick or unlock the native apps after onboarding.
struct LockedAppsView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        List {
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
