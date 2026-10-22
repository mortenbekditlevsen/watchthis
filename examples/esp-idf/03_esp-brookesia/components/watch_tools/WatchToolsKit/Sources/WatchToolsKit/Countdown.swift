// The Timer app's countdown, and which timers it offers. Times in microseconds of a monotonic clock (see Stopwatch).

public struct Countdown: Equatable, Sendable {
    public enum State: Equatable, Sendable {
        case idle
        case running(endsAt: Int64)
        case paused(remaining: Int64)
        /// Time's up: the alarm sounds until stopped, or for `ringDuration`
        case ringing(since: Int64)
    }

    public private(set) var state: State = .idle
    /// The length of the current (or last) timer, seconds
    public private(set) var duration = 0

    public static let ringDuration: Int64 = 60_000_000

    public init() {}

    public mutating func start(seconds: Int, at now: Int64) {
        guard seconds > 0 else { return }
        duration = seconds
        state = .running(endsAt: now + Int64(seconds) * 1_000_000)
    }

    public mutating func pause(at now: Int64) {
        if case .running(let endsAt) = state {
            state = .paused(remaining: max(0, endsAt - now))
        }
    }

    public mutating func resume(at now: Int64) {
        if case .paused(let remaining) = state {
            state = .running(endsAt: now + remaining)
        }
    }

    /// Cancel a timer, or stop the alarm
    public mutating func cancel() {
        state = .idle
    }

    public func remaining(at now: Int64) -> Int64 {
        switch state {
        case .idle: Int64(duration) * 1_000_000
        case .running(let endsAt): max(0, endsAt - now)
        case .paused(let remaining): remaining
        case .ringing: 0
        }
    }

    /// 0 at the start ... 1 at the end
    public func progress(at now: Int64) -> Double {
        guard duration > 0 else { return 0 }
        return 1 - Double(remaining(at: now)) / Double(Int64(duration) * 1_000_000)
    }

    /// When the watch must be awake for this timer (to start ringing), or nil
    public var wakeAt: Int64? {
        if case .running(let endsAt) = state { return endsAt }
        return nil
    }

    public enum Event: Equatable, Sendable {
        case none
        /// Time's up: start the alarm
        case startRinging
        /// Rang long enough: stop the alarm
        case stopRinging
    }

    /// Call regularly (and on waking up)
    public mutating func tick(at now: Int64) -> Event {
        switch state {
        case .running(let endsAt) where now >= endsAt:
            state = .ringing(since: now)
            return .startRinging
        case .ringing(let since) where now - since >= Countdown.ringDuration:
            state = .idle
            return .stopRinging
        default:
            return .none
        }
    }
}

/// The timers the app offers: fixed presets, then the last few the user made (most recent first)
public struct TimerChoices: Equatable, Sendable {
    public static let presets = [2 * 60, 3 * 60, 5 * 60, 10 * 60]
    public static let maxRecent = 4
    public static let maxSeconds = 24 * 3600 - 1

    public private(set) var recent: [Int] = []

    public init(recent: [Int] = []) {
        for seconds in recent.reversed() { remember(seconds) }
    }

    public var all: [Int] { TimerChoices.presets + recent }

    /// A timer the user made: first in the recent list (once); presets aren't repeated there
    public mutating func remember(_ seconds: Int) {
        guard (1...TimerChoices.maxSeconds).contains(seconds), !TimerChoices.presets.contains(seconds) else { return }
        recent.removeAll { $0 == seconds }
        recent.insert(seconds, at: 0)
        if recent.count > TimerChoices.maxRecent { recent.removeLast(recent.count - TimerChoices.maxRecent) }
    }

    /// Stored as UInt32 little endian seconds, most recent first
    public var encoded: [UInt8] {
        recent.flatMap { s in (0..<4).map { UInt8(truncatingIfNeeded: s >> (8 * $0)) } }
    }

    public init(decoding bytes: [UInt8]) {
        var recent: [Int] = []
        var i = 0
        while i + 4 <= bytes.count {
            recent.append((0..<4).reduce(0) { $0 | Int(bytes[i + $1]) << (8 * $1) })
            i += 4
        }
        self.init(recent: recent)
    }
}
