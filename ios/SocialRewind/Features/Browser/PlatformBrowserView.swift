import RewindCore
import SwiftUI

/// Full-screen filtered browser for one platform.
struct PlatformBrowserView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    let platform: Platform
    @State private var browser: BrowserController
    /// Scripts fixed at web view creation; later changes go through `browser.apply`.
    @State private var initialScripts: InjectedScripts?

    init(platform: Platform) {
        self.platform = platform
        _browser = State(initialValue: BrowserController(platform: platform))
    }

    var body: some View {
        VStack(spacing: 0) {
            topBar
            Divider()
            content
        }
        .onAppear {
            if initialScripts == nil { initialScripts = model.injectedScripts(for: platform) }
            browser.reminderSettings = model.reminders
            browser.routeGuard = model.routeGuard(for: platform)
            browser.onEvent = { [model, platform] event in model.handle(event, from: platform) }
        }
        .onChange(of: model.settings(for: platform)) { old, new in
            // grayscale and postCounter are CSS/DOM-only and update live in the isolated world.
            // Anything else (mode, features → routes/network) needs a reload so the page-world
            // bundle gets the new closure config.
            var liveOnly = old
            liveOnly.grayscale = new.grayscale
            liveOnly.postCounter = new.postCounter
            reapply(reload: liveOnly != new)
        }
        .onChange(of: model.developer) { _, _ in
            // Debug overlay and experimental network filtering are baked into the config: reload.
            reapply(reload: true)
        }
        .onChange(of: model.username(for: platform)) { _, _ in
            // A newly learned or edited username resolves templated homes ("/{username}/saved/").
            reapply(reload: true)
        }
        .onChange(of: model.reminders) { _, new in browser.reminderSettings = new }
        .task {
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(60))
                if !Task.isCancelled { browser.minuteElapsed() }
            }
        }
        .sheet(item: $browser.reminder) { reminder in
            ReminderSheet(reminder: reminder, platform: platform) { dismiss() }
                .presentationDetents([.medium])
        }
    }

    private func reapply(reload: Bool) {
        browser.routeGuard = model.routeGuard(for: platform)
        guard let scripts = model.injectedScripts(for: platform) else { return }
        browser.apply(scripts, liveUpdate: reload ? nil : model.liveUpdateScript(for: platform), reload: reload)
    }

    @ViewBuilder private var content: some View {
        if let scripts = initialScripts, let pack = model.rulePack(for: platform) {
            ZStack {
                WebViewContainer(platform: platform,
                                 startURL: platform.startURL(startPath: model.routeGuard(for: platform)?.modeHome ?? pack.pack.startPath),
                                 scripts: scripts,
                                 controller: browser)
                // Fail closed: cover the page until the engine reports ready.
                if browser.filterState != .ready {
                    FilterStatusCover(state: browser.filterState, retry: browser.retry, close: { dismiss() })
                }
            }
            .overlay(alignment: .bottom) { blockedNotice }
        } else {
            ContentUnavailableView("Filters unavailable",
                                   systemImage: "exclamationmark.shield",
                                   description: Text("This build is missing its filter engine or rules, so \(platform.displayName) can't be opened safely."))
        }
    }

    private var topBar: some View {
        HStack(spacing: 12) {
            Button { dismiss() } label: {
                Image(systemName: "xmark").font(.body.weight(.semibold))
            }
            .accessibilityLabel("Close \(platform.displayName)")

            Text(platform.displayName).font(.headline)

            Spacer()

            if model.settings(for: platform).postCounter {
                Text("\(browser.sessionPosts) \(browser.sessionPosts == 1 ? "post" : "posts")")
                    .font(.subheadline.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .contentTransition(.numericText())
                    .accessibilityLabel("\(browser.sessionPosts) posts viewed this session")
            }
            // No settings button here on purpose: filters change from Home, outside the feed,
            // so they can't be loosened on impulse mid-scroll.
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(.bar)
    }

    @ViewBuilder private var blockedNotice: some View {
        if browser.lastBlockedPath != nil {
            Text("Blocked by your settings")
                .font(.footnote.weight(.medium))
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(.regularMaterial, in: Capsule())
                .padding(.bottom, 24)
                .transition(.opacity)
                .task {
                    try? await Task.sleep(for: .seconds(2))
                    withAnimation { browser.clearBlockedNotice() }
                }
        }
    }
}

struct FilterStatusCover: View {
    let state: BrowserController.FilterState
    let retry: () -> Void
    let close: () -> Void

    var body: some View {
        ZStack {
            Color(.systemBackground).ignoresSafeArea()
            switch state {
            case .loading:
                ProgressView("Applying your filters…")
            case .failed(let reason):
                ContentUnavailableView {
                    Label("Filters didn't load", systemImage: "exclamationmark.shield")
                } description: {
                    Text(reason)
                } actions: {
                    HStack {
                        Button("Close", action: close).buttonStyle(.bordered)
                        Button("Retry", action: retry).buttonStyle(.borderedProminent)
                    }
                }
            case .ready:
                EmptyView()
            }
        }
    }
}

struct ReminderSheet: View {
    @Environment(\.dismiss) private var dismissSheet
    let reminder: BrowserController.Reminder
    let platform: Platform
    let closePlatform: () -> Void

    var body: some View {
        VStack(spacing: 20) {
            Text(headline)
                .font(.title2.weight(.semibold))
                .multilineTextAlignment(.center)
            Text("Is this still how you want to spend your time?")
                .foregroundStyle(.secondary)
            VStack(spacing: 10) {
                Button {
                    dismissSheet()
                    closePlatform()
                } label: {
                    Text("Close \(platform.displayName)").frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                Button("Keep going") { dismissSheet() }
            }
        }
        .padding(24)
    }

    private var headline: String {
        let posts = "\(reminder.posts) \(reminder.posts == 1 ? "post" : "posts")"
        let minutes = "\(reminder.minutes) \(reminder.minutes == 1 ? "minute" : "minutes")"
        switch (reminder.posts > 0, reminder.minutes > 0) {
        case (true, true): return "You've seen \(posts) in \(minutes)."
        case (true, false): return "You've seen \(posts)."
        case (false, _): return "You've been here \(minutes)."
        }
    }
}
