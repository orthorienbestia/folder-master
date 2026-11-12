import XCTest

final class CalendarContextTests: XCTestCase {
    private func date(_ text: String) -> Date { ISO8601DateFormatter().date(from: text)! }
    func testDSTDaysUseActualBoundariesAndPreviousCalendarDay() throws {
        let zone = try XCTUnwrap(TimeZone(identifier: "America/Los_Angeles"))
        let spring = try NativeEvaluationContext.capture(now: date("2026-03-08T12:00:00Z"), timeZone: zone)
        let fall = try NativeEvaluationContext.capture(now: date("2026-11-01T12:00:00Z"), timeZone: zone)
        XCTAssertEqual(try XCTUnwrap(spring.today).end_ms - XCTUnwrap(spring.today).start_ms, 23 * 3600_000)
        XCTAssertEqual(try XCTUnwrap(fall.today).end_ms - XCTUnwrap(fall.today).start_ms, 25 * 3600_000)
        XCTAssertEqual(spring.yesterday?.end_ms, spring.today?.start_ms)
        XCTAssertEqual(fall.yesterday?.end_ms, fall.today?.start_ms)
        let halfHour = try NativeEvaluationContext.capture(
            now: date("2026-10-04T12:00:00Z"), timeZone: XCTUnwrap(TimeZone(identifier: "Australia/Lord_Howe")))
        XCTAssertEqual(
            try XCTUnwrap(halfHour.today).end_ms - XCTUnwrap(halfHour.today).start_ms, 23 * 3600_000 + 30 * 60_000)
    }
    func testRequestedSkippedDayIsNotSilentlyNormalizedAndDuplicateRequestsCollapse() throws {
        let skipped = NativeCalendarDate(year: 2011, month: 12, day: 30)
        let context = try NativeEvaluationContext.capture(
            now: date("2011-12-31T12:00:00Z"), timeZone: XCTUnwrap(TimeZone(identifier: "Pacific/Apia")),
            dates: [skipped, skipped])
        XCTAssertEqual(context.dates.count, 1)
        XCTAssertNil(context.dates[0].window)
        XCTAssertEqual(context.dates[0].date, skipped)
    }
    func testClockQuantizationAndTimezoneAreCapturedBeforeDerivingToday() throws {
        let zone = try XCTUnwrap(TimeZone(secondsFromGMT: 0))
        let midnight = date("2026-01-02T00:00:00Z")
        let context = try NativeEvaluationContext.capture(now: midnight.addingTimeInterval(-0.0004), timeZone: zone)
        XCTAssertEqual(context.now_ms, Int64(midnight.timeIntervalSince1970 * 1000))
        XCTAssertEqual(context.today?.start_ms, context.now_ms)
        XCTAssertEqual(context.timezone_identifier, zone.identifier)
        XCTAssertThrowsError(
            try NativeEvaluationContext.capture(now: Date(timeIntervalSince1970: .infinity), timeZone: zone))
    }
    func testSharedNativeCalendarFixturesRemainIdentical() throws {
        struct Fixture: Decodable { let cases: [Case] }
        struct Case: Decodable {
            let name: String
            let context: NativeEvaluationContext
        }
        let url = try XCTUnwrap(Bundle(for: Self.self).url(forResource: "calendar-context", withExtension: "json"))
        let fixture = try JSONDecoder().decode(Fixture.self, from: Data(contentsOf: url))
        XCTAssertEqual(fixture.cases.count, 6)
        for item in fixture.cases {
            let expected = item.context
            let actual = try NativeEvaluationContext.capture(
                now: Date(timeIntervalSince1970: Double(expected.now_ms) / 1000),
                timeZone: XCTUnwrap(TimeZone(identifier: expected.timezone_identifier)),
                dates: expected.dates.map(\.date))
            XCTAssertEqual(actual, expected, item.name)
        }
    }
}
