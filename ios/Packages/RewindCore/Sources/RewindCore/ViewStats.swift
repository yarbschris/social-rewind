import Foundation

/// On-device counts of posts viewed per day and platform. Never leaves the device.
public struct ViewStats: Codable, Sendable, Equatable {
    public struct Day: Codable, Sendable, Equatable {
        /// platform rawValue → unique posts viewed
        public var counts: [String: Int] = [:]
        /// platform rawValue → post keys seen (kept only for the most recent day)
        public var seenKeys: [String: Set<String>] = [:]
    }

    /// "yyyy-MM-dd" in the user's calendar → day
    public private(set) var days: [String: Day] = [:]

    public init() {}

    /// Records a post view. Returns `true` if this post hadn't been counted today.
    @discardableResult
    public mutating func record(platform: Platform, key: String, at date: Date = .now, calendar: Calendar = .current) -> Bool {
        let dayKey = Self.dayKey(for: date, calendar: calendar)
        // Only today's keys are needed for de-duplication.
        for other in days.keys where other != dayKey {
            days[other]?.seenKeys = [:]
        }
        var day = days[dayKey] ?? Day()
        let inserted = day.seenKeys[platform.rawValue, default: []].insert(key).inserted
        if inserted {
            day.counts[platform.rawValue, default: 0] += 1
        }
        days[dayKey] = day
        return inserted
    }

    public func count(platform: Platform, on date: Date = .now, calendar: Calendar = .current) -> Int {
        days[Self.dayKey(for: date, calendar: calendar)]?.counts[platform.rawValue] ?? 0
    }

    public func total(on date: Date = .now, calendar: Calendar = .current) -> Int {
        days[Self.dayKey(for: date, calendar: calendar)]?.counts.values.reduce(0, +) ?? 0
    }

    /// Drops days older than `keepingDays` before `now`.
    public mutating func prune(keepingDays: Int = 30, now: Date = .now, calendar: Calendar = .current) {
        guard let cutoff = calendar.date(byAdding: .day, value: -keepingDays, to: now) else { return }
        let cutoffKey = Self.dayKey(for: cutoff, calendar: calendar)
        days = days.filter { $0.key >= cutoffKey } // zero-padded keys sort chronologically
    }

    public static func dayKey(for date: Date, calendar: Calendar = .current) -> String {
        let c = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
    }
}
