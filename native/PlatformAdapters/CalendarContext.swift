import Foundation

struct NativeCalendarDate: Codable, Hashable {
    let year: Int
    let month: Int
    let day: Int
}
struct NativeDayWindow: Codable, Equatable {
    let start_ms: Int64
    let end_ms: Int64
}
struct NativeCalendarDateWindow: Codable, Equatable {
    let date: NativeCalendarDate
    let window: NativeDayWindow?
}
enum NativeCalendarError: Error { case invalidClock, invalidTimeZone }

/// Immutable calendar facts for a supplied clock/timezone; no document access.
struct NativeEvaluationContext: Codable, Equatable {
    let now_ms: Int64
    let timezone_identifier: String
    let today: NativeDayWindow?
    let yesterday: NativeDayWindow?
    let dates: [NativeCalendarDateWindow]

    static func capture(now: Date, timeZone: TimeZone, dates: [NativeCalendarDate] = []) throws -> Self {
        guard let nowMS = milliseconds(now) else { throw NativeCalendarError.invalidClock }
        let identifier = timeZone.identifier
        guard let timeZone = TimeZone(identifier: identifier) else { throw NativeCalendarError.invalidTimeZone }
        let snappedNow = Date(timeIntervalSince1970: Double(nowMS) / 1000)
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = Locale(identifier: "en_US_POSIX")
        calendar.timeZone = timeZone
        let interval = calendar.dateInterval(of: .day, for: snappedNow)
        let previous = interval.flatMap { calendar.dateInterval(of: .day, for: $0.start.addingTimeInterval(-1)) }
        var seen = Set<NativeCalendarDate>()
        let requested = dates.filter { seen.insert($0).inserted }.map { date in
            NativeCalendarDateWindow(date: date, window: day(date, calendar: calendar))
        }
        return Self(
            now_ms: nowMS, timezone_identifier: identifier,
            today: interval.flatMap(window), yesterday: previous.flatMap(window), dates: requested)
    }
    private static func milliseconds(_ date: Date) -> Int64? {
        Int64(exactly: (date.timeIntervalSince1970 * 1000).rounded())
    }
    private static func window(_ interval: DateInterval) -> NativeDayWindow? {
        guard let start = milliseconds(interval.start), let end = milliseconds(interval.end), start < end else {
            return nil
        }
        return NativeDayWindow(start_ms: start, end_ms: end)
    }
    private static func day(_ date: NativeCalendarDate, calendar: Calendar) -> NativeDayWindow? {
        guard (1...9999).contains(date.year), (1...12).contains(date.month), (1...31).contains(date.day),
            let probe = calendar.date(from: DateComponents(year: date.year, month: date.month, day: date.day, hour: 12))
        else { return nil }
        let actual = calendar.dateComponents([.era, .year, .month, .day], from: probe)
        guard actual.era == 1, actual.year == date.year, actual.month == date.month, actual.day == date.day else {
            return nil
        }
        return calendar.dateInterval(of: .day, for: probe).flatMap(window)
    }
}
