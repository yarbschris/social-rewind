import Foundation
import Testing
@testable import RewindCore

/// rules/instagram.json from the repo root (the real, bundled pack).
private func instagramPackData() throws -> Data {
    let url = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent() // → Tests/RewindCoreTests
        .deletingLastPathComponent() // → Tests
        .deletingLastPathComponent() // → RewindCore
        .deletingLastPathComponent() // → Packages
        .deletingLastPathComponent() // → ios
        .deletingLastPathComponent() // → repo root
        .appendingPathComponent("rules/instagram.json")
    return try Data(contentsOf: url)
}

private func pack(revision: Int = 1, minEngine: Int = 1, platform: String = "instagram", schema: Int = 1) -> Data {
    Data("""
    {"schemaVersion":\(schema),"platform":"\(platform)","revision":\(revision),"minEngineVersion":\(minEngine),
     "startPath":"/","features":{
       "zeta":{"title":"Z","group":"content","default":true,"rules":{}},
       "alpha":{"title":"A","group":"ads","default":false,"rules":{"css":["a"]}},
       "soon":{"title":"S","group":"ads","default":true,"available":false,"rules":{}}
     },
     "modes":{"dmsOnly":{"title":"DMs","home":"/direct/inbox/","allowRoutes":["^/direct/"]}}}
    """.utf8)
}

@Suite struct RulePackTests {
    @Test func decodesBundledInstagramPack() throws {
        let loaded = try LoadedRulePack(data: try instagramPackData())
        #expect(loaded.pack.platform == "instagram")
        #expect(loaded.pack.schemaVersion == 1)
        #expect(loaded.pack.features["blockReels"]?.group == .content)
        #expect(loaded.pack.features["hideStoryAds"]?.isAvailable == false)
        #expect(loaded.pack.modes?["dmsOnly"]?.home == "/direct/inbox/")
        #expect(loaded.pack.modes?["savedOnly"]?.home == "/{username}/saved/")
        #expect(loaded.pack.minEngineVersion <= EngineInfo.version)
    }

    @Test func preservesDeclarationOrder() throws {
        let loaded = try LoadedRulePack(data: pack())
        #expect(loaded.featureOrder == ["zeta", "alpha", "soon"])
        #expect(loaded.features(in: .ads).map(\.id) == ["alpha", "soon"])
        #expect(loaded.modeOrder == ["dmsOnly"])

        let ig = try LoadedRulePack(data: try instagramPackData())
        #expect(ig.featureOrder.first == "blockReels")
        #expect(Set(ig.featureOrder) == Set(ig.pack.features.keys))
    }

    @Test func keyOrderHandlesEscapesAndNesting() {
        let json = Data(#"{"a":{"x\"y":[1,{"q":2}],"b":"}","c":null},"features":{"k2":1,"k1":{"k0":true}}}"#.utf8)
        #expect(JSONKeyOrder.keys(atPath: ["features"], in: json) == ["k2", "k1"])
        #expect(JSONKeyOrder.keys(atPath: ["a"], in: json) == ["x\"y", "b", "c"])
        #expect(JSONKeyOrder.keys(atPath: ["missing"], in: json) == nil)
    }
}

@Suite struct SettingsTests {
    @Test func defaultsComeFromPackAndRespectAvailability() throws {
        let p = try LoadedRulePack(data: pack()).pack
        let s = PlatformSettings.defaults(for: p)
        #expect(s.mode == "normal")
        #expect(s.features == ["zeta": true, "alpha": false, "soon": false])
    }

    @Test func effectiveFeaturesResolveMissingUnavailableAndStale() throws {
        let p = try LoadedRulePack(data: pack()).pack
        let s = PlatformSettings(features: ["alpha": true, "soon": true, "removedFeature": true])
        #expect(s.effectiveFeatures(for: p) == ["zeta": true, "alpha": true, "soon": false])
    }

    @Test func unknownModeFallsBackToNormal() throws {
        let p = try LoadedRulePack(data: pack()).pack
        #expect(PlatformSettings(mode: "dmsOnly").effectiveMode(for: p) == "dmsOnly")
        #expect(PlatformSettings(mode: "savedOnly").effectiveMode(for: p) == "normal")
    }

    @Test func reminderCadence() {
        let r = ReminderSettings(enabled: true, everyPosts: 30)
        #expect(!r.shouldRemind(afterPosts: 0))
        #expect(!r.shouldRemind(afterPosts: 29))
        #expect(r.shouldRemind(afterPosts: 30))
        #expect(r.shouldRemind(afterPosts: 60))
        #expect(!ReminderSettings(enabled: false).shouldRemind(afterPosts: 30))
        #expect(!ReminderSettings(everyPosts: 0).shouldRemind(afterPosts: 30))
    }
}

@Suite struct RulePackSelectorTests {
    let bundled = try! LoadedRulePack(data: pack(revision: 5))

    @Test func adoptsNewerValidPack() {
        let chosen = RulePackSelector.select(bundled: bundled, refreshed: pack(revision: 6), platform: .instagram)
        #expect(chosen.pack.revision == 6)
    }

    @Test func rejectsOlderOrEqual() {
        #expect(RulePackSelector.select(bundled: bundled, refreshed: pack(revision: 5), platform: .instagram).pack.revision == 5)
        #expect(RulePackSelector.select(bundled: bundled, refreshed: pack(revision: 2), platform: .instagram).pack.revision == 5)
        #expect(throws: RulePackSelector.RejectionReason.notNewer(revision: 5, current: 5)) {
            try RulePackSelector.accept(pack(revision: 5), over: bundled, platform: .instagram)
        }
    }

    @Test func rejectsInvalidPacks() {
        #expect(throws: RulePackSelector.RejectionReason.undecodable) {
            try RulePackSelector.accept(Data("not json".utf8), over: bundled, platform: .instagram)
        }
        #expect(throws: RulePackSelector.RejectionReason.wrongPlatform("reddit")) {
            try RulePackSelector.accept(pack(revision: 9, platform: "reddit"), over: bundled, platform: .instagram)
        }
        #expect(throws: RulePackSelector.RejectionReason.needsNewerEngine(99)) {
            try RulePackSelector.accept(pack(revision: 9, minEngine: 99), over: bundled, platform: .instagram)
        }
        #expect(throws: RulePackSelector.RejectionReason.unsupportedSchema(2)) {
            try RulePackSelector.accept(pack(revision: 9, schema: 2), over: bundled, platform: .instagram)
        }
        #expect(RulePackSelector.select(bundled: bundled, refreshed: nil, platform: .instagram) == bundled)
    }

    @Test func bundledInstagramPackPassesRefreshLimits() throws {
        _ = try RulePackSelector.validate(try instagramPackData(), platform: .instagram)
    }

    private func packWith(features: String = "{}", modes: String = "{}", startPath: String = "/", counter: String? = nil) -> Data {
        Data("""
        {"schemaVersion":1,"platform":"instagram","revision":9,"minEngineVersion":1,"startPath":"\(startPath)",
         "features":\(features),"modes":\(modes)\(counter.map { ",\"counter\":\($0)" } ?? "")}
        """.utf8)
    }

    @Test func rejectsOffOriginRedirectTargets() {
        for to in ["//evil.example/", "https://evil.example/", "/a\\\\b", "javascript:alert(1)", "/x?u=https://evil"] {
            let features = #"{"f":{"title":"F","group":"content","default":true,"rules":{"routes":[{"pattern":"^/","action":"redirect","to":"\#(to)"}]}}}"#
            #expect(throws: RulePackSelector.RejectionReason.self, "\(to)") {
                try RulePackSelector.validate(packWith(features: features), platform: .instagram)
            }
        }
        let modes = #"{"m":{"title":"M","home":"//evil.example/","allowRoutes":["^/"]}}"#
        #expect(throws: RulePackSelector.RejectionReason.unsafePath("//evil.example/")) {
            try RulePackSelector.validate(packWith(modes: modes), platform: .instagram)
        }
        let ok = #"{"f":{"title":"F","group":"content","default":true,"rules":{"routes":[{"pattern":"^/p/([^/]+)/c","action":"redirect","to":"/p/$1/"}]}}}"#
        #expect(throws: Never.self) { try RulePackSelector.validate(packWith(features: ok), platform: .instagram) }
    }

    @Test func rejectsOversizedPacks() {
        let selectors = (0..<501).map { "\"a\($0)\"" }.joined(separator: ",")
        let many = #"{"f":{"title":"F","group":"content","default":true,"rules":{"css":[\#(selectors)]}}}"#
        #expect(throws: RulePackSelector.RejectionReason.tooManySelectors(501)) {
            try RulePackSelector.validate(packWith(features: many), platform: .instagram)
        }

        let longRegex = String(repeating: "a", count: 301)
        let long = #"{"f":{"title":"F","group":"content","default":true,"rules":{"routes":[{"pattern":"\#(longRegex)","action":"block"}]}}}"#
        #expect(throws: RulePackSelector.RejectionReason.self) {
            try RulePackSelector.validate(packWith(features: long), platform: .instagram)
        }
        let longNet = #"{"f":{"title":"F","group":"ads","default":true,"rules":{"network":[{"url":"\#(longRegex)","removeWhere":{"path":"x","exists":true}}]}}}"#
        #expect(throws: RulePackSelector.RejectionReason.self) {
            try RulePackSelector.validate(packWith(features: longNet), platform: .instagram)
        }

        let longCounter = #"{"item":"article","key":{"selector":"a","attr":"href"},"routes":["\#(longRegex)"]}"#
        #expect(throws: RulePackSelector.RejectionReason.self) {
            try RulePackSelector.validate(packWith(counter: longCounter), platform: .instagram)
        }
        let okCounter = #"{"item":"article","key":{"selector":"a","attr":"href"},"routes":["^/p/([^/]+)/?$"]}"#
        #expect(throws: Never.self) { try RulePackSelector.validate(packWith(counter: okCounter), platform: .instagram) }

        let huge = Data(repeating: 0x20, count: RulePackSelector.maxPackBytes) + packWith()
        #expect(throws: RulePackSelector.RejectionReason.tooLarge(bytes: huge.count)) {
            try RulePackSelector.validate(huge, platform: .instagram)
        }
    }
}

@Suite struct HostPolicyTests {
    let policy = HostPolicy.for(.instagram)

    @Test func allowsPlatformHosts() {
        for s in ["https://www.instagram.com/", "https://instagram.com/direct/inbox/",
                  "https://scontent-lax3-1.cdninstagram.com/v/x.jpg", "https://static.cdninstagram.com/rsrc.php",
                  "https://video.xx.fbcdn.net/v.mp4"] {
            #expect(policy.decide(url: URL(string: s)!, isMainFrame: true, isUserInitiated: true) == .allow, "\(s)")
        }
    }

    @Test func externalLinksOpenOutsideOnlyWhenTapped() {
        let url = URL(string: "https://example.com/article")!
        #expect(policy.decide(url: url, isMainFrame: true, isUserInitiated: true) == .openExternally(url))
        #expect(policy.decide(url: url, isMainFrame: true, isUserInitiated: false) == .cancel)
        #expect(policy.decide(url: url, isMainFrame: false, isUserInitiated: true) == .cancel)
    }

    @Test func unwrapsLinkShim() {
        let shim = URL(string: "https://l.instagram.com/?u=https%3A%2F%2Fexample.com%2Fa&e=xyz")!
        #expect(policy.decide(url: shim, isMainFrame: true, isUserInitiated: true)
                == .openExternally(URL(string: "https://example.com/a")!))
        // A script-driven redirect through the shim must not open anything.
        #expect(policy.decide(url: shim, isMainFrame: true, isUserInitiated: false) == .cancel)
    }

    @Test func facebookOnlyForLogin() {
        #expect(policy.decide(url: URL(string: "https://www.facebook.com/login.php?x=1")!, isMainFrame: true, isUserInitiated: true) == .allow)
        #expect(policy.decide(url: URL(string: "https://www.facebook.com/v19.0/dialog/oauth")!, isMainFrame: true, isUserInitiated: false) == .allow)
        #expect(policy.decide(url: URL(string: "https://m.facebook.com/dialog/oauth?client_id=1")!, isMainFrame: true, isUserInitiated: true) == .allow)
        for s in ["https://www.facebook.com/", "https://www.facebook.com/videos/123", "https://www.facebook.com/v/abc",
                  "https://www.facebook.com/loginfoo", "https://www.facebook.com/someone/posts/1"] {
            let u = URL(string: s)!
            #expect(policy.decide(url: u, isMainFrame: true, isUserInitiated: true) == .openExternally(u), "\(s)")
            #expect(policy.decide(url: u, isMainFrame: false, isUserInitiated: false) == .cancel, "\(s)")
        }
    }

    @Test func blocksAppSchemesAndCleartext() {
        #expect(policy.decide(url: URL(string: "instagram://user?username=x")!, isMainFrame: true, isUserInitiated: true) == .cancel)
        #expect(policy.decide(url: URL(string: "http://www.instagram.com/")!, isMainFrame: true, isUserInitiated: true) == .cancel)
        #expect(policy.decide(url: URL(string: "https://evil-instagram.com/")!, isMainFrame: false, isUserInitiated: false) == .cancel)
        #expect(policy.decide(url: URL(string: "https://instagram.com.evil.net/")!, isMainFrame: false, isUserInitiated: false) == .cancel)
        let mail = URL(string: "mailto:a@b.c")!
        #expect(policy.decide(url: mail, isMainFrame: true, isUserInitiated: true) == .openExternally(mail))
        #expect(policy.decide(url: URL(string: "about:blank")!, isMainFrame: false, isUserInitiated: false) == .allow)
    }

    @Test func unavailablePlatformsAllowNothing() {
        #expect(HostPolicy.for(.tiktok).decide(url: URL(string: "https://www.tiktok.com/")!, isMainFrame: true, isUserInitiated: false) == .cancel)
    }
}

@Suite struct EngineConfigBuilderTests {
    private func config(_ loaded: LoadedRulePack, settings: PlatformSettings = PlatformSettings(),
                        username: String? = nil, debug: Bool = false) -> EngineConfig {
        EngineConfig(platform: .instagram, settings: settings, rules: loaded,
                     username: username, debug: debug, experimental: false)
    }

    @Test func wrapsBundleInClosureWithConfigConstant() throws {
        let loaded = try LoadedRulePack(data: try instagramPackData())
        let wrapped = try EngineConfigBuilder.wrap(bundleSource: "console.log(__SR_CONFIG__.platform);",
                                                   config: config(loaded))
        #expect(wrapped.hasPrefix("(function(){\"use strict\";const __SR_CONFIG__ = {"))
        #expect(wrapped.contains("};\nconsole.log(__SR_CONFIG__.platform);\n})();"))
        #expect(wrapped.hasSuffix("\n})();"))
        #expect(!wrapped.contains("window.__SOCIAL_REWIND_CONFIG__"))
    }

    @Test func configHasResolvedSettingsAndRules() throws {
        let loaded = try LoadedRulePack(data: try instagramPackData())
        let json = try EngineConfigBuilder.configJSON(config(
            loaded, settings: PlatformSettings(mode: "savedOnly", features: ["hideComments": true]),
            username: "some.user", debug: true))
        let obj = try #require(try JSONSerialization.jsonObject(with: Data(json.utf8)) as? [String: Any])
        #expect(obj["platform"] as? String == "instagram")
        // Engine stays inert off these hosts (e.g. Facebook login pages).
        let hosts = try #require(obj["hosts"] as? [String])
        #expect(hosts.contains("www.instagram.com"))
        #expect(!hosts.contains("www.facebook.com"))
        #expect(obj["username"] as? String == "some.user")
        #expect(obj["debug"] as? Bool == true)
        #expect(obj["experimental"] as? Bool == false)
        let settings = try #require(obj["settings"] as? [String: Any])
        #expect(settings["mode"] as? String == "savedOnly")
        let features = try #require(settings["features"] as? [String: Bool])
        #expect(features["hideComments"] == true)
        #expect(features["blockReels"] == true) // default filled in
        #expect(features["hideStoryAds"] == false) // unavailable
        let rules = try #require(obj["rules"] as? [String: Any])
        #expect(rules["revision"] as? Int == loaded.pack.revision)
        #expect((rules["features"] as? [String: Any])?["blockAds"] != nil)
    }

    @Test func escapesScriptBreakersAndDropsInvalidUsernames() throws {
        let loaded = try LoadedRulePack(data: pack())
        // Invalid usernames are never forwarded.
        let bad = try EngineConfigBuilder.configJSON(config(loaded, username: "</script><script>alert(1)</script>"))
        #expect(!bad.contains("username"))
        #expect(try EngineConfigBuilder.configJSON(config(loaded, username: "")).contains("username") == false)

        // Escaping still applies to everything else (e.g. rule text).
        let raw = Data(#"{"schemaVersion":1,"platform":"instagram","revision":1,"minEngineVersion":1,"startPath":"/","features":{"f":{"title":"</script>\u2028","group":"ads","default":true,"rules":{}}}}"#.utf8)
        let json = try EngineConfigBuilder.configJSON(config(try LoadedRulePack(data: raw)))
        #expect(!json.contains("<"))
        #expect(!json.contains("\u{2028}"))
        let obj = try #require(try JSONSerialization.jsonObject(with: Data(json.utf8)) as? [String: Any])
        let title = ((obj["rules"] as? [String: Any])?["features"] as? [String: [String: Any]])?["f"]?["title"] as? String
        #expect(title == "</script>\u{2028}")
    }

    @Test func updateScriptTargetsIsolatedGlobal() throws {
        let loaded = try LoadedRulePack(data: pack())
        let update = try EngineConfigBuilder.updateScript(settings: PlatformSettings(grayscale: true), rules: loaded.pack)
        #expect(update.hasPrefix("window.SocialRewind?.update({"))
        #expect(update.contains("\"grayscale\":true"))
    }

    @Test func usernameValidation() {
        #expect(Username.isValid("a.b_c9"))
        #expect(!Username.isValid(""))
        #expect(!Username.isValid("has space"))
        #expect(!Username.isValid("x/../y"))
        #expect(!Username.isValid(String(repeating: "a", count: 31)))
    }
}

@Suite struct RouteGuardTests {
    let ig = try! LoadedRulePack(data: try! instagramPackData()).pack

    private func guarded(_ mode: String = "normal", _ features: [String: Bool] = [:], username: String? = nil) -> RouteGuard {
        RouteGuard(pack: ig, settings: PlatformSettings(mode: mode, features: features), username: username)
    }

    @Test func normalModeBlocksOnlyBlockRulesOfEnabledFeatures() {
        let g = guarded()
        #expect(g.evaluate(path: "/") == .allow)
        #expect(g.evaluate(path: "/direct/inbox/") == .allow)
        // A single reel (e.g. one sent in DMs) may open; the engine hides the reels after it.
        #expect(g.evaluate(path: "/reel/abc/") == .allow)
        #expect(g.evaluate(path: "/someone/reel/abc/") == .allow)
        // "redirect" rules are the engine's job
        #expect(g.evaluate(path: "/reels/") == .allow)
        // hideComments has a "block" rule for the comments page
        #expect(g.evaluate(path: "/p/abc/comments/") == .allow)
        #expect(guarded("normal", ["hideComments": true]).evaluate(path: "/p/abc/comments/") == .navigate("/"))
        #expect(guarded("normal", ["blockExplore": true]).evaluate(path: "/explore/tags/cats/") == .navigate("/"))
    }

    @Test func alwaysAllowRoutesWin() {
        #expect(guarded("dmsOnly").evaluate(path: "/accounts/login/") == .allow)
        #expect(guarded("savedOnly").evaluate(path: "/challenge/123/") == .allow)
    }

    @Test func dmsOnly() {
        let g = guarded("dmsOnly")
        #expect(g.evaluate(path: "/direct/inbox/") == .allow)
        #expect(g.evaluate(path: "/direct/t/123/") == .allow)
        #expect(g.evaluate(path: "/") == .navigate("/direct/inbox/"))
        #expect(g.evaluate(path: "/explore/") == .navigate("/direct/inbox/"))
        // Posts and reels people send you open; their author's profile doesn't.
        #expect(g.evaluate(path: "/p/ABC/") == .allow)
        #expect(g.evaluate(path: "/reel/XYZ/") == .allow)
        #expect(g.evaluate(path: "/someone/") == .navigate("/direct/inbox/"))
    }

    @Test func savedOnlyWithAndWithoutUsername() {
        let g = guarded("savedOnly", username: "me.here")
        #expect(g.modeHome == "/me.here/saved/")
        #expect(g.evaluate(path: "/me.here/saved/") == .allow)
        #expect(g.evaluate(path: "/me.here/saved/all-posts/") == .allow)
        #expect(g.evaluate(path: "/p/C0de/") == .allow)
        #expect(g.evaluate(path: "/") == .navigate("/me.here/saved/"))
        #expect(g.evaluate(path: "/reel/x/") == .allow) // saved reels open too
        #expect(g.evaluate(path: "/someone/") == .navigate("/me.here/saved/"))

        let unknown = guarded("savedOnly")
        #expect(unknown.modeHome == nil)
        #expect(unknown.evaluate(path: "/") == .allow) // no loop while the username is unknown
        #expect(unknown.evaluate(path: "/explore/") == .navigate("/"))
        #expect(guarded("savedOnly", username: "bad/name").modeHome == nil)
    }

    @Test func pathHelpers() {
        #expect(RouteGuard.samePath("/a/", "/a"))
        #expect(RouteGuard.samePath("/", "/"))
        #expect(!RouteGuard.samePath("/a", "/b"))
        #expect(!RouteGuard.matches("([", "/x")) // invalid regex matches nothing
    }

    @Test func slidingWindowLimiter() {
        var limiter = SlidingWindowLimiter(limit: 3, window: 10)
        let t0 = Date(timeIntervalSince1970: 0)
        let results = [0, 1, 2, 3, 10.5].map { limiter.allow(at: t0.addingTimeInterval($0)) }
        #expect(results == [true, true, true, false, true]) // 4th over the limit; at 10.5s the first expired
        var perSecond = SlidingWindowLimiter(limit: 5, window: 1)
        #expect((0..<10).filter { _ in perSecond.allow(at: t0) }.count == 5)
    }
}

@Suite struct BridgeEventTests {
    @Test func decodesFoundationBodies() throws {
        #expect(try BridgeEvent(messageBody: ["type": "ready", "engineVersion": 1, "rulesRevision": 3])
                == .ready(engineVersion: 1, rulesRevision: 3))
        #expect(try BridgeEvent(messageBody: ["type": "postViewed", "key": "C0de", "sessionCount": 4])
                == .postViewed(key: "C0de", sessionCount: 4))
        #expect(try BridgeEvent(messageBody: ["type": "routeBlocked", "path": "/reels/", "reason": "blockReels", "redirectedTo": "/"])
                == .routeBlocked(path: "/reels/", reason: "blockReels", redirectedTo: "/"))
        #expect(try BridgeEvent(messageBody: ["type": "identity", "username": "me"]) == .identity(username: "me"))
        #expect(try BridgeEvent(messageBody: ["type": "somethingNew", "x": 1]) == .unknown(type: "somethingNew"))
    }

    @Test func decodesAndroidStrings() throws {
        #expect(try BridgeEvent(messageBody: #"{"type":"ruleHit","ruleId":"blockAds.dom[0]"}"#) == .ruleHit(ruleId: "blockAds.dom[0]"))
        #expect(try BridgeEvent(messageBody: #"{"type":"error","message":"boom"}"#) == .error(message: "boom"))
    }

    @Test func validatesUntrustedEvents() {
        #expect(BridgeEvent.identity(username: "good.user_1").validated() != nil)
        #expect(BridgeEvent.identity(username: "../../etc").validated() == nil)
        #expect(BridgeEvent.identity(username: String(repeating: "a", count: 31)).validated() == nil)
        #expect(BridgeEvent.identity(username: "").validated() == nil)
        #expect(BridgeEvent.postViewed(key: String(repeating: "k", count: 129), sessionCount: 1).validated() == nil)
        #expect(BridgeEvent.postViewed(key: "", sessionCount: 1).validated() == nil)
        #expect(BridgeEvent.postViewed(key: "C0de", sessionCount: 1).validated() == .postViewed(key: "C0de", sessionCount: 1))
        if case .error(let m) = BridgeEvent.error(message: String(repeating: "x", count: 10_000)).validated() {
            #expect(m.count == BridgeEvent.maxMessageLength)
        } else {
            Issue.record("error event dropped")
        }
    }

    @Test func rejectsGarbage() {
        #expect(throws: (any Error).self) { try BridgeEvent(messageBody: 42) }
        #expect(throws: (any Error).self) { try BridgeEvent(messageBody: ["type": "postViewed"]) }
    }
}

@Suite struct ViewStatsAndLinksTests {
    var calendar: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC")!
        return c
    }

    @Test func dedupesPerDay() {
        var stats = ViewStats()
        let day1 = Date(timeIntervalSince1970: 1_764_000_000)
        let day2 = day1.addingTimeInterval(86_400)
        let first = stats.record(platform: .instagram, key: "a", at: day1, calendar: calendar)
        let repeated = stats.record(platform: .instagram, key: "a", at: day1, calendar: calendar)
        let second = stats.record(platform: .instagram, key: "b", at: day1, calendar: calendar)
        #expect(first && !repeated && second)
        #expect(stats.count(platform: .instagram, on: day1, calendar: calendar) == 2)
        let nextDay = stats.record(platform: .instagram, key: "a", at: day2, calendar: calendar)
        #expect(nextDay)
        #expect(stats.count(platform: .instagram, on: day2, calendar: calendar) == 1)
        #expect(stats.count(platform: .instagram, on: day1, calendar: calendar) == 2)
        #expect(stats.days[ViewStats.dayKey(for: day1, calendar: calendar)]?.seenKeys.isEmpty == true)
    }

    @Test func prunesOldDaysAndRoundTrips() throws {
        var stats = ViewStats()
        let now = Date(timeIntervalSince1970: 1_764_000_000)
        stats.record(platform: .instagram, key: "old", at: now.addingTimeInterval(-40 * 86_400), calendar: calendar)
        stats.record(platform: .instagram, key: "new", at: now, calendar: calendar)
        stats.prune(keepingDays: 30, now: now, calendar: calendar)
        #expect(stats.days.count == 1)
        let decoded = try JSONDecoder().decode(ViewStats.self, from: JSONEncoder().encode(stats))
        #expect(decoded == stats)
    }

    @Test func deepLinks() {
        #expect(DeepLink(url: URL(string: "socialrewind://open/instagram")!) == .open(.instagram))
        #expect(DeepLink(url: URL(string: "socialrewind://open/Instagram")!) == .open(.instagram))
        #expect(DeepLink(url: URL(string: "socialrewind://open/myspace")!) == nil)
        #expect(DeepLink(url: URL(string: "https://open/instagram")!) == nil)
        #expect(DeepLink.open(.instagram).url.absoluteString == "socialrewind://open/instagram")
    }

    @Test func platformBasics() {
        #expect(Platform.instagram.isAvailable)
        #expect(!Platform.tiktok.isAvailable)
        #expect(Platform.instagram.startURL(startPath: "/direct/inbox/").absoluteString == "https://www.instagram.com/direct/inbox/")
        #expect(Set(Platform.allCases.map(\.websiteDataStoreID)).count == Platform.allCases.count)
    }
}
