import CryptoKit
import Foundation

/// Which settings changes relax a restriction. With a settings PIN set, only these ask for it:
/// making things stricter never does.
public enum Loosening {
    /// Every feature is a restriction when on, so turning one off loosens. Leaving a mode such as
    /// "DMs only" loosens, including switching straight to another mode; entering one from normal
    /// mode doesn't. Turning off grayscale or the post counter loosens.
    public static func platformSettings(from old: PlatformSettings, to new: PlatformSettings, pack: RulePack) -> Bool {
        let oldMode = old.effectiveMode(for: pack)
        if oldMode != PlatformSettings.normalMode && new.effectiveMode(for: pack) != oldMode { return true }
        let before = old.effectiveFeatures(for: pack)
        let after = new.effectiveFeatures(for: pack)
        if before.contains(where: { $0.value && after[$0.key] != true }) { return true }
        if old.grayscale && !new.grayscale { return true }
        if old.postCounter && !new.postCounter { return true }
        return false
    }

    /// Turning reminders off, or making either reminder less frequent (a larger interval, or 0 = never).
    public static func reminders(from old: ReminderSettings, to new: ReminderSettings) -> Bool {
        guard old.enabled else { return false }
        if !new.enabled { return true }
        func lessOften(_ before: Int, _ after: Int) -> Bool { before > 0 && (after == 0 || after > before) }
        return lessOften(old.everyPosts, new.everyPosts) || lessOften(old.everyMinutes, new.everyMinutes)
    }
}

/// An optional PIN guarding changes that loosen restrictions. It adds friction rather than
/// security: anyone holding the phone can still delete the app.
public struct SettingsPin: Codable, Sendable, Equatable {
    public static let allowedLengths = 4...6
    /// How long "Forgot PIN" waits before removing the PIN.
    public static let resetDelay: TimeInterval = 24 * 60 * 60
    /// Wrong guesses allowed before entry pauses.
    public static let attemptsBeforePause = 5
    public static let pauseDuration: TimeInterval = 60
    /// How long a correct PIN keeps settings unlocked.
    public static let unlockDuration: TimeInterval = 5 * 60

    private var salt: Data
    private var hash: Data
    /// Digits in the PIN, so the keypad can show that many dots and submit when they're filled.
    /// nil for PINs saved before it was recorded; the keypad then shows an OK button.
    public private(set) var length: Int?
    /// Set by "Forgot PIN". The PIN is removed once `resetDelay` has passed.
    public private(set) var resetRequestedAt: Date?
    public private(set) var failedAttempts = 0
    public private(set) var pausedUntil: Date?

    /// nil unless `pin` is 4–6 digits.
    public init?(pin: String) {
        guard Self.isValid(pin) else { return nil }
        var bytes = [UInt8](repeating: 0, count: 16)
        var rng = SystemRandomNumberGenerator()
        for i in bytes.indices { bytes[i] = rng.next() }
        salt = Data(bytes)
        hash = Self.digest(pin, salt: salt)
        length = pin.count
    }

    public static func isValid(_ pin: String) -> Bool {
        allowedLengths.contains(pin.count) && pin.allSatisfy { ("0"..."9").contains($0) }
    }

    public enum Attempt: Equatable, Sendable {
        case correct
        case wrong(attemptsLeft: Int)
        case paused(until: Date)
    }

    /// Checks `pin`, counting wrong guesses and pausing entry after too many. A correct PIN also
    /// cancels a pending reset, since whoever asked for it evidently remembers it.
    public mutating func attempt(_ pin: String, now: Date = .now) -> Attempt {
        if let until = pausedUntil, until > now { return .paused(until: until) }
        pausedUntil = nil
        if Self.digest(pin, salt: salt) == hash {
            failedAttempts = 0
            resetRequestedAt = nil
            return .correct
        }
        failedAttempts += 1
        if failedAttempts >= Self.attemptsBeforePause {
            failedAttempts = 0
            let until = now.addingTimeInterval(Self.pauseDuration)
            pausedUntil = until
            return .paused(until: until)
        }
        return .wrong(attemptsLeft: Self.attemptsBeforePause - failedAttempts)
    }

    public mutating func requestReset(now: Date = .now) {
        if resetRequestedAt == nil { resetRequestedAt = now }
    }

    public mutating func cancelReset() { resetRequestedAt = nil }

    /// When a requested reset takes effect.
    public var resetDate: Date? { resetRequestedAt?.addingTimeInterval(Self.resetDelay) }

    public func resetIsDue(now: Date = .now) -> Bool {
        guard let date = resetDate else { return false }
        return date <= now
    }

    private static func digest(_ pin: String, salt: Data) -> Data {
        Data(SHA256.hash(data: salt + Data(pin.utf8)))
    }
}
