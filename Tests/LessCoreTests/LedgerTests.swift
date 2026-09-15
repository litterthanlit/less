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
    XCTAssertEqual(snap.createPart, 0)
    XCTAssertEqual(snap.consumePart, 0)
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
    XCTAssertEqual(snap.createPart, 1)
    XCTAssertEqual(snap.consumePart, 0)
  }

  func testOneHourConsumeAndTwoHourCreatePartsTwoToOne() {
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
    XCTAssertEqual(snap.createPart, 2)
    XCTAssertEqual(snap.consumePart, 1)
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
    XCTAssertEqual(closed.createPart, 1)
    XCTAssertEqual(closed.consumePart, 0)
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
    XCTAssertEqual(snap.createPart, 1)
    XCTAssertEqual(snap.consumePart, 1)
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
    XCTAssertEqual(snap.createPart, 1)
    XCTAssertEqual(snap.consumePart, 0)
  }

  func testFormatDurationLiteralValues() {
    XCTAssertEqual(LedgerMutations.formatDuration(0), "0:00")
    XCTAssertEqual(LedgerMutations.formatDuration(63), "1:03")
    XCTAssertEqual(LedgerMutations.formatDuration(3723), "1:02:03")
    XCTAssertEqual(LedgerMutations.formatDuration(-1), "0:00")
  }

  func testRatioLineHasSpacesAroundColon() {
    XCTAssertEqual(LedgerMutations.ratioLine(createPart: 4, consumePart: 1), "4 : 1")
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
    XCTAssertEqual(snap.createPart, 0)
    XCTAssertEqual(snap.consumePart, 1)
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
    XCTAssertEqual(snap.createPart, 0)
    XCTAssertEqual(snap.consumePart, 0)
  }
}
