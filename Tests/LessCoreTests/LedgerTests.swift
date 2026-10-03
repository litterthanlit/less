import Foundation
import XCTest
@testable import LessCore

final class LedgerTests: XCTestCase {
  private var calendar: Calendar {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(secondsFromGMT: 0)!
    return calendar
  }

  private func utc(
    _ year: Int,
    _ month: Int,
    _ day: Int,
    _ hour: Int,
    _ minute: Int = 0,
    _ second: Int = 0
  ) -> Date {
    calendar.date(
      from: DateComponents(
        timeZone: TimeZone(secondsFromGMT: 0)!,
        year: year,
        month: month,
        day: day,
        hour: hour,
        minute: minute,
        second: second
      )
    )!
  }

  func testEmptyLedgerSnapshotAtNoonIsZeros() {
    let now = utc(2026, 9, 15, 12)
    let snap = LedgerMutations.snapshot(ledger: Ledger(), now: now, calendar: calendar)
    XCTAssertEqual(snap.create, 0)
    XCTAssertEqual(snap.consume, 0)
    XCTAssertEqual(snap.ratioLine, "0 : 0")
    XCTAssertNil(snap.run)
  }

  func testClosedTwoHourCreateSessionToday() {
    let ledger = Ledger(
      sessions: [
        Session(kind: .create, start: utc(2026, 9, 15, 10), end: utc(2026, 9, 15, 12))
      ]
    )
    let snap = LedgerMutations.snapshot(
      ledger: ledger,
      now: utc(2026, 9, 15, 12),
      calendar: calendar
    )
    XCTAssertEqual(snap.create, 7200)
    XCTAssertEqual(snap.consume, 0)
    XCTAssertEqual(snap.ratioLine, "1 : 0")
  }

  func testOneHourConsumeAndTwoHourCreateIsTwoToOne() {
    let ledger = Ledger(
      sessions: [
        Session(kind: .consume, start: utc(2026, 9, 15, 8), end: utc(2026, 9, 15, 9)),
        Session(kind: .create, start: utc(2026, 9, 15, 10), end: utc(2026, 9, 15, 12)),
      ]
    )
    let snap = LedgerMutations.snapshot(
      ledger: ledger,
      now: utc(2026, 9, 15, 12),
      calendar: calendar
    )
    XCTAssertEqual(snap.create, 7200)
    XCTAssertEqual(snap.consume, 3600)
    XCTAssertEqual(snap.ratioLine, "2.0 : 1")
  }

  func testToggleCreateStartsThenClosesWithExpectedDuration() {
    let t0 = utc(2026, 9, 15, 12)
    let tMid = utc(2026, 9, 15, 12, 10)
    let t1 = utc(2026, 9, 15, 12, 30)
    var ledger = Ledger()

    ledger = LedgerMutations.toggle(.create, on: ledger, now: t0)
    XCTAssertEqual(ledger.run, Run(kind: .create, start: t0))
    XCTAssertEqual(ledger.sessions, [])

    let running = LedgerMutations.snapshot(ledger: ledger, now: tMid, calendar: calendar)
    XCTAssertEqual(running.create, 600)
    XCTAssertEqual(running.consume, 0)
    XCTAssertEqual(running.run, Run(kind: .create, start: t0))

    ledger = LedgerMutations.toggle(.create, on: ledger, now: t1)
    XCTAssertNil(ledger.run)
    XCTAssertEqual(
      ledger.sessions,
      [Session(kind: .create, start: t0, end: t1)]
    )
    XCTAssertEqual(ledger.sessions[0].end.timeIntervalSince(ledger.sessions[0].start), 1800)

    let closed = LedgerMutations.snapshot(ledger: ledger, now: t1, calendar: calendar)
    XCTAssertEqual(closed.create, 1800)
    XCTAssertEqual(closed.consume, 0)
    XCTAssertEqual(closed.ratioLine, "1 : 0")
  }

  func testToggleConsumeWhileCreateIsRunningSwitchesKinds() {
    let t0 = utc(2026, 9, 15, 12)
    let t1 = utc(2026, 9, 15, 13)
    var ledger = Ledger()
    ledger = LedgerMutations.toggle(.create, on: ledger, now: t0)
    ledger = LedgerMutations.toggle(.consume, on: ledger, now: t1)
    XCTAssertEqual(
      ledger.sessions,
      [Session(kind: .create, start: t0, end: t1)]
    )
    XCTAssertEqual(ledger.run, Run(kind: .consume, start: t1))
    let snap = LedgerMutations.snapshot(ledger: ledger, now: utc(2026, 9, 15, 14), calendar: calendar)
    XCTAssertEqual(snap.create, 3600)
    XCTAssertEqual(snap.consume, 3600)
    XCTAssertEqual(snap.ratioLine, "1.0 : 1")
    XCTAssertEqual(snap.run?.kind, Kind.consume)
  }

  func testSessionCrossingMidnightCountsOnlyToday() {
    let ledger = Ledger(
      sessions: [
        Session(kind: .create, start: utc(2026, 9, 14, 23), end: utc(2026, 9, 15, 1))
      ]
    )
    let snap = LedgerMutations.snapshot(
      ledger: ledger,
      now: utc(2026, 9, 15, 12),
      calendar: calendar
    )
    XCTAssertEqual(snap.create, 3600)
    XCTAssertEqual(snap.consume, 0)
    XCTAssertEqual(snap.ratioLine, "1 : 0")
  }

  func testFormatDurationLiteralValues() {
    XCTAssertEqual(LedgerMutations.formatDuration(0), "0:00")
    XCTAssertEqual(LedgerMutations.formatDuration(63), "1:03")
    XCTAssertEqual(LedgerMutations.formatDuration(3723), "1:02:03")
    XCTAssertEqual(LedgerMutations.formatDuration(-1), "0:00")
  }

  func testRatioLineBothZero() {
    XCTAssertEqual(LedgerMutations.ratioLine(create: 0, consume: 0), "0 : 0")
  }

  func testRatioLineOnlyCreateOrOnlyConsume() {
    XCTAssertEqual(LedgerMutations.ratioLine(create: 90, consume: 0), "1 : 0")
    XCTAssertEqual(LedgerMutations.ratioLine(create: 0, consume: 90), "0 : 1")
  }

  func testRatioLineShowsSmallerSideAsOne() {
    XCTAssertEqual(LedgerMutations.ratioLine(create: 15127, consume: 3513), "4.3 : 1")
    XCTAssertEqual(LedgerMutations.ratioLine(create: 1501, consume: 6000), "1 : 4.0")
    XCTAssertEqual(LedgerMutations.ratioLine(create: 3600, consume: 3600), "1.0 : 1")
  }

  func testRatioLineIsReadableOneSecondOffARoundNumber() {
    XCTAssertEqual(LedgerMutations.ratioLine(create: 7200, consume: 3600), "2.0 : 1")
    XCTAssertEqual(LedgerMutations.ratioLine(create: 7201, consume: 3600), "2.0 : 1")
    let ledger = Ledger(
      sessions: [
        Session(kind: .consume, start: utc(2026, 9, 15, 8), end: utc(2026, 9, 15, 9)),
        Session(kind: .create, start: utc(2026, 9, 15, 10), end: utc(2026, 9, 15, 12, 0, 1)),
      ]
    )
    let snap = LedgerMutations.snapshot(
      ledger: ledger,
      now: utc(2026, 9, 15, 13),
      calendar: calendar
    )
    XCTAssertEqual(snap.create, 7201)
    XCTAssertEqual(snap.ratioLine, "2.0 : 1")
  }

  func testRatioLineRoundsToOneDecimal() {
    XCTAssertEqual(LedgerMutations.ratioLine(create: 1049, consume: 1000), "1.0 : 1")
    XCTAssertEqual(LedgerMutations.ratioLine(create: 1050, consume: 1000), "1.1 : 1")
    XCTAssertEqual(LedgerMutations.ratioLine(create: 1000, consume: 3000), "1 : 3.0")
    XCTAssertEqual(LedgerMutations.ratioLine(create: 1000, consume: 2999), "1 : 3.0")
    XCTAssertEqual(LedgerMutations.ratioLine(create: 1000, consume: 2951), "1 : 3.0")
    XCTAssertEqual(LedgerMutations.ratioLine(create: 1000, consume: 2949), "1 : 2.9")
  }

  func testRatioLineDropsTheDecimalOnceTheRoundedValueReachesTen() {
    XCTAssertEqual(LedgerMutations.ratioLine(create: 36000, consume: 1200), "30 : 1")
    XCTAssertEqual(LedgerMutations.ratioLine(create: 1200, consume: 36000), "1 : 30")
    XCTAssertEqual(LedgerMutations.ratioLine(create: 10000, consume: 1000), "10 : 1")
    XCTAssertEqual(LedgerMutations.ratioLine(create: 9996, consume: 1000), "10 : 1")
    XCTAssertEqual(LedgerMutations.ratioLine(create: 1000, consume: 9996), "1 : 10")
    XCTAssertEqual(LedgerMutations.ratioLine(create: 9949, consume: 1000), "9.9 : 1")
    XCTAssertEqual(LedgerMutations.ratioLine(create: 10460, consume: 1000), "10 : 1")
    XCTAssertEqual(LedgerMutations.ratioLine(create: 10500, consume: 1000), "11 : 1")
  }

  func testRatioLineUsesWholeTruncatedSeconds() {
    XCTAssertEqual(LedgerMutations.ratioLine(create: 0.9, consume: 0), "0 : 0")
    XCTAssertEqual(LedgerMutations.ratioLine(create: 0.9, consume: 5.9), "0 : 1")
    XCTAssertEqual(LedgerMutations.ratioLine(create: 2.9, consume: 2.1), "1.0 : 1")
    XCTAssertEqual(LedgerMutations.ratioLine(create: -5, consume: 10), "0 : 1")
  }

  func testRunningSessionFromYesterdayCountsOnlyToday() {
    let ledger = Ledger(run: Run(kind: .consume, start: utc(2026, 9, 14, 23)))
    let snap = LedgerMutations.snapshot(
      ledger: ledger,
      now: utc(2026, 9, 15, 1),
      calendar: calendar
    )
    XCTAssertEqual(snap.create, 0)
    XCTAssertEqual(snap.consume, 3600)
    XCTAssertEqual(snap.ratioLine, "0 : 1")
  }

  func testUserDefaultsRoundTripPreservesLedger() {
    let name = "app.less.tests.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: name)!
    defaults.removePersistentDomain(forName: name)
    let original = Ledger(
      sessions: [
        Session(kind: .create, start: utc(2026, 9, 15, 10), end: utc(2026, 9, 15, 12))
      ],
      run: Run(kind: .consume, start: utc(2026, 9, 15, 12))
    )
    original.save(to: defaults)
    XCTAssertEqual(Ledger.load(from: defaults), original)
    defaults.removePersistentDomain(forName: name)
  }

  func testCorruptUserDefaultsLoadsEmptyLedger() {
    let name = "app.less.tests.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: name)!
    defaults.removePersistentDomain(forName: name)
    defaults.set(Data("not-json".utf8), forKey: Ledger.storageKey)
    XCTAssertEqual(Ledger.load(from: defaults), Ledger())
    defaults.removePersistentDomain(forName: name)
  }

  func testNowBeforeStartCountsZeroAndDoesNotCrash() {
    let start = utc(2026, 9, 15, 12)
    let earlier = utc(2026, 9, 15, 11)
    let started = LedgerMutations.toggle(.create, on: Ledger(), now: start)
    let closed = LedgerMutations.toggle(.create, on: started, now: earlier)
    XCTAssertEqual(closed.sessions.count, 1)
    XCTAssertEqual(closed.sessions[0].start, start)
    XCTAssertEqual(closed.sessions[0].end, earlier)
    XCTAssertNil(closed.run)
    let snap = LedgerMutations.snapshot(ledger: closed, now: start, calendar: calendar)
    XCTAssertEqual(snap.create, 0)
    XCTAssertEqual(snap.consume, 0)
    XCTAssertEqual(snap.ratioLine, "0 : 0")
  }
}
