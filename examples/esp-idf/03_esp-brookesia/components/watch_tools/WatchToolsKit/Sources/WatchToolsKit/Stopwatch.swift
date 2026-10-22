// Times are microseconds from a monotonic clock that keeps counting while the watch sleeps (esp_timer on the
// watch), passed in as `now` so the logic is plain and testable.

public struct Stopwatch: Equatable, Sendable {
    /// Time measured before the current run
    public private(set) var accumulated: Int64 = 0
    /// When the current run started; nil while stopped
    public private(set) var startedAt: Int64?

    public init() {}

    public var isRunning: Bool { startedAt != nil }

    public func elapsed(at now: Int64) -> Int64 {
        accumulated + (startedAt.map { max(0, now - $0) } ?? 0)
    }

    /// The second button reads "Nulstil" and works only when stopped with a measured time
    public var canReset: Bool { !isRunning && accumulated > 0 }

    /// The first button: Start when stopped, Stop when running
    public mutating func toggle(at now: Int64) {
        if let startedAt {
            accumulated += max(0, now - startedAt)
            self.startedAt = nil
        } else {
            startedAt = now
        }
    }

    public mutating func reset() {
        guard canReset else { return }
        accumulated = 0
    }
}

public enum TimeText {
    /// Stopwatch: "05:07,32" (minutes, seconds, hundredths; Danish decimal comma), "1:05:07" from an hour
    public static func stopwatch(_ us: Int64) -> String {
        let hundredths = Int(max(0, us) / 10_000)
        let seconds = hundredths / 100
        if seconds >= 3600 {
            return "\(seconds / 3600):" + two(seconds / 60 % 60) + ":" + two(seconds % 60)
        }
        return two(seconds / 60) + ":" + two(seconds % 60) + "," + two(hundredths % 100)
    }

    /// Countdown: "4:59", "1:04:59"; rounds up so it shows 0:00 only at the end
    public static func countdown(_ us: Int64) -> String {
        let seconds = Int((max(0, us) + 999_999) / 1_000_000)
        if seconds >= 3600 {
            return "\(seconds / 3600):" + two(seconds / 60 % 60) + ":" + two(seconds % 60)
        }
        return "\(seconds / 60):" + two(seconds % 60)
    }

    /// A timer button: "2 min", "1 t 30 min", "45 sek", "1 min 30 sek", "1 t 0 min 5 sek"
    public static func duration(seconds: Int) -> String {
        let h = seconds / 3600, m = seconds / 60 % 60, s = seconds % 60
        var parts: [String] = []
        if h > 0 { parts.append("\(h) t") }
        if m > 0 || (h > 0 && s > 0) { parts.append("\(m) min") }
        if s > 0 || parts.isEmpty { parts.append("\(s) sek") }
        return parts.joined(separator: " ")
    }

    static func two(_ v: Int) -> String {
        v < 10 ? "0\(v)" : "\(v)"
    }
}
