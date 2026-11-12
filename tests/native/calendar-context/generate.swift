import Foundation

// Manual fixture generation only. Writes JSON to stdout for deliberate review.
// Compile with native/PlatformAdapters/CalendarContext.swift.
private struct Fixture: Codable {
    let source: String
    let cases: [Case]
}
private struct Case: Codable {
    let name: String
    let context: NativeEvaluationContext
}

@main struct GenerateCalendarFixtures {
    static func main() throws {
        let requests: [(String, String, String, [NativeCalendarDate])] = [
            ("UTC_epoch", "1970-01-01T00:00:00Z", "UTC", [.init(year: 1970, month: 1, day: 1)]),
            ("UTC_spring", "2026-03-08T12:00:00Z", "UTC", [.init(year: 2026, month: 3, day: 8)]),
            ("LA_spring", "2026-03-08T12:00:00Z", "America/Los_Angeles", [.init(year: 2026, month: 3, day: 8)]),
            ("LA_fall", "2026-11-01T12:00:00Z", "America/Los_Angeles", [.init(year: 2026, month: 11, day: 1)]),
            ("Lord_Howe_spring", "2026-10-04T12:00:00Z", "Australia/Lord_Howe", [.init(year: 2026, month: 10, day: 4)]),
            ("Apia_skipped", "2011-12-31T12:00:00Z", "Pacific/Apia", [.init(year: 2011, month: 12, day: 30)]),
        ]
        let cases = try requests.map { name, instant, zone, dates in
            Case(
                name: name,
                context: try NativeEvaluationContext.capture(
                    now: ISO8601DateFormatter().date(from: instant)!, timeZone: TimeZone(identifier: zone)!,
                    dates: dates))
        }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        #if arch(arm64)
        let architecture = "arm64"
        #else
        let architecture = "x86_64"
        #endif
        let data = try encoder.encode(
            Fixture(source: ProcessInfo.processInfo.operatingSystemVersionString + " \(architecture) Foundation Calendar", cases: cases)
        )
        FileHandle.standardOutput.write(data)
    }
}
