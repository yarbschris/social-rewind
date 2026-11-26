import Foundation
import Testing
@testable import RewindCore

private func lockPack() throws -> RulePack {
    try LoadedRulePack(data: Data("""
    {"schemaVersion":1,"platform":"instagram","revision":1,"minEngineVersion":1,"startPath":"/",
     "features":{
       "blockReels":{"title":"R","group":"content","default":true,"rules":{}},
       "hideStories":{"title":"S","group":"content","default":false,"rules":{}},
       "soon":{"title":"X","group":"ads","default":true,"available":false,"rules":{}}
     },
     "modes":{
       "dmsOnly":{"title":"DMs","home":"/direct/inbox/","allowRoutes":["^/direct/"]},
       "savedOnly":{"title":"Saved","home":"/{username}/saved/","allowRoutes":["^/[^/]+/saved/"]}
     }}
    """.utf8)).pack
}

@Suite struct LooseningTests {
    @Test func featuresOffLoosensOnDoesNot() throws {
        let pack = try lockPack()
        let base = PlatformSettings()
        var off = base
        off.features["blockReels"] = false
        var on = base
        on.features["hideStories"] = true
        #expect(Loosening.platformSettings(from: base, to: off, pack: pack))
        #expect(!Loosening.platformSettings(from: base, to: on, pack: pack))
        #expect(!Loosening.platformSettings(from: base, to: base, pack: pack))
    }

    @Test func unavailableFeaturesNeverCount() throws {
        let pack = try lockPack()
        var stale = PlatformSettings()
        stale.features["soon"] = true
        var cleared = stale
        cleared.features["soon"] = false
        #expect(!Loosening.platformSettings(from: stale, to: cleared, pack: pack))
    }

    @Test func leavingAModeLoosensEnteringDoesNot() throws {
        let pack = try lockPack()
        let normal = PlatformSettings()
        let dms = PlatformSettings(mode: "dmsOnly")
        let saved = PlatformSettings(mode: "savedOnly")
        #expect(!Loosening.platformSettings(from: normal, to: dms, pack: pack))
        #expect(Loosening.platformSettings(from: dms, to: normal, pack: pack))
        #expect(Loosening.platformSettings(from: dms, to: saved, pack: pack))
        // A mode the pack no longer has already behaves as normal.
        #expect(!Loosening.platformSettings(from: PlatformSettings(mode: "gone"), to: normal, pack: pack))
    }

    @Test func wellbeingSwitches() throws {
        let pack = try lockPack()
        let on = PlatformSettings(grayscale: true, postCounter: true)
        #expect(Loosening.platformSettings(from: on, to: PlatformSettings(grayscale: false, postCounter: true), pack: pack))
        #expect(Loosening.platformSettings(from: on, to: PlatformSettings(grayscale: true, postCounter: false), pack: pack))
        #expect(!Loosening.platformSettings(from: PlatformSettings(grayscale: false), to: on, pack: pack))
    }

    @Test func reminders() {
        let base = ReminderSettings(enabled: true, everyPosts: 30, everyMinutes: 15)
        #expect(Loosening.reminders(from: base, to: ReminderSettings(enabled: false, everyPosts: 30, everyMinutes: 15)))
        #expect(Loosening.reminders(from: base, to: ReminderSettings(enabled: true, everyPosts: 40, everyMinutes: 15)))
        #expect(Loosening.reminders(from: base, to: ReminderSettings(enabled: true, everyPosts: 30, everyMinutes: 0)))
        #expect(!Loosening.reminders(from: base, to: ReminderSettings(enabled: true, everyPosts: 20, everyMinutes: 10)))
        // Turning one on from "never" is stricter.
        #expect(!Loosening.reminders(from: ReminderSettings(enabled: true, everyPosts: 0, everyMinutes: 15),
                                     to: ReminderSettings(enabled: true, everyPosts: 50, everyMinutes: 15)))
        // While reminders are off, nothing about them loosens.
        let off = ReminderSettings(enabled: false, everyPosts: 30, everyMinutes: 15)
        #expect(!Loosening.reminders(from: off, to: ReminderSettings(enabled: false, everyPosts: 0, everyMinutes: 0)))
        #expect(!Loosening.reminders(from: off, to: base))
    }
}

@Suite struct SettingsPinTests {
    @Test func acceptsOnlyFourToSixDigits() {
        for ok in ["1234", "12345", "123456"] { #expect(SettingsPin(pin: ok) != nil, "\(ok)") }
        for bad in ["", "123", "1234567", "12a4", "١٢٣٤", " 1234"] { #expect(SettingsPin(pin: bad) == nil, "\(bad)") }
    }

    @Test func checksThePinWithoutStoringIt() throws {
        var pin = try #require(SettingsPin(pin: "2468"))
        #expect(pin.attempt("2468") == .correct)
        #expect(pin.attempt("1357") == .wrong(attemptsLeft: 4))
        let encoded = String(decoding: try JSONEncoder().encode(pin), as: UTF8.self)
        #expect(!encoded.contains("2468"))
    }

    @Test func saltsEachPin() throws {
        let a = try #require(SettingsPin(pin: "1111"))
        let b = try #require(SettingsPin(pin: "1111"))
        #expect(a != b)
    }

    @Test func pausesAfterTooManyWrongGuesses() throws {
        var pin = try #require(SettingsPin(pin: "2468"))
        let start = Date(timeIntervalSince1970: 1_000_000)
        for i in 1..<SettingsPin.attemptsBeforePause {
            #expect(pin.attempt("0000", now: start) == .wrong(attemptsLeft: SettingsPin.attemptsBeforePause - i))
        }
        let until = start.addingTimeInterval(SettingsPin.pauseDuration)
        #expect(pin.attempt("0000", now: start) == .paused(until: until))
        // Even the right PIN waits out the pause.
        #expect(pin.attempt("2468", now: start.addingTimeInterval(30)) == .paused(until: until))
        #expect(pin.attempt("2468", now: until) == .correct)
    }

    @Test func resetTakesADayAndTheRightPinCancelsIt() throws {
        var pin = try #require(SettingsPin(pin: "2468"))
        let start = Date(timeIntervalSince1970: 1_000_000)
        pin.requestReset(now: start)
        pin.requestReset(now: start.addingTimeInterval(3600)) // asking again doesn't restart the wait
        #expect(pin.resetDate == start.addingTimeInterval(SettingsPin.resetDelay))
        #expect(!pin.resetIsDue(now: start.addingTimeInterval(SettingsPin.resetDelay - 1)))
        #expect(pin.resetIsDue(now: start.addingTimeInterval(SettingsPin.resetDelay)))
        #expect(pin.attempt("2468", now: start) == .correct)
        #expect(pin.resetDate == nil)
    }
}
