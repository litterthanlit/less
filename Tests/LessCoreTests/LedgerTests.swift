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

  private func makeDefaults() -> UserDefaults {
    let name = "app.less.tests.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: name)!
    defaults.removePersistentDomain(forName: name)
    addTeardownBlock {
      defaults.removePersistentDomain(forName: name)
    }
    return defaults
  }

  private func backupKeys(in defaults: UserDefaults) -> [String] {
    defaults.dictionaryRepresentation().keys
      .filter { $0.hasPrefix("\(Ledger.storageKey).backup.") }
      .sorted()
  }

  private let recoveredAt = Date(timeIntervalSince1970: 1_800_000_000)
  private let recoveredKey = "app.less.ledger.backup.1800000000"

  private func ref(_ seconds: TimeInterval) -> Date {
    Date(timeIntervalSinceReferenceDate: seconds)
  }

  private let partiallyBadJSON = #"""
    {"sessions":[
      {"kind":"create","start":800000000,"end":800003600},
      {"kind":"rest","start":800007200,"end":800010800},
      null,
      {"kind":"consume","start":800014400},
      {"kind":"consume","start":800018000,"end":800021600}
    ],"run":{"kind":"create","start":800025200}}
    """#

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
    XCTAssertEqual(backupKeys(in: defaults), [])
    defaults.removePersistentDomain(forName: name)
  }

  func testCorruptUserDefaultsLoadsEmptyLedger() {
    let name = "app.less.tests.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: name)!
    defaults.removePersistentDomain(forName: name)
    defaults.set(Data("not-json".utf8), forKey: Ledger.storageKey)
    XCTAssertEqual(Ledger.load(from: defaults), Ledger())
    XCTAssertEqual(backupKeys(in: defaults).count, 1)
    defaults.removePersistentDomain(forName: name)
  }

  func testPartiallyBadLedgerKeepsGoodSessionsAndWritesBackup() {
    let defaults = makeDefaults()
    let original = Data(partiallyBadJSON.utf8)
    defaults.set(original, forKey: Ledger.storageKey)

    let loaded = Ledger.load(from: defaults, now: recoveredAt)

    XCTAssertEqual(
      loaded,
      Ledger(
        sessions: [
          Session(kind: .create, start: ref(800_000_000), end: ref(800_003_600)),
          Session(kind: .consume, start: ref(800_018_000), end: ref(800_021_600)),
        ],
        run: Run(kind: .create, start: ref(800_025_200))
      )
    )
    XCTAssertEqual(backupKeys(in: defaults), [recoveredKey])
    XCTAssertEqual(defaults.data(forKey: recoveredKey), original)
  }

  func testUnreadableRunBecomesNilAndKeepsSessions() {
    let defaults = makeDefaults()
    let original = Data(
      #"{"sessions":[{"kind":"create","start":800000000,"end":800003600}],"run":{"kind":"nap","start":1}}"#
        .utf8
    )
    defaults.set(original, forKey: Ledger.storageKey)

    let loaded = Ledger.load(from: defaults, now: recoveredAt)

    XCTAssertEqual(
      loaded,
      Ledger(sessions: [Session(kind: .create, start: ref(800_000_000), end: ref(800_003_600))])
    )
    XCTAssertEqual(defaults.data(forKey: recoveredKey), original)
  }

  func testNullOrMissingRunIsNotADrop() {
    for json in [
      #"{"sessions":[],"run":null}"#,
      #"{"sessions":[]}"#,
    ] {
      let defaults = makeDefaults()
      defaults.set(Data(json.utf8), forKey: Ledger.storageKey)
      XCTAssertEqual(Ledger.load(from: defaults, now: recoveredAt), Ledger())
      XCTAssertEqual(backupKeys(in: defaults), [])
    }
  }

  func testFullyCorruptDataWritesBackupWithExactBytes() {
    let defaults = makeDefaults()
    let original = Data([0xFF, 0xFE, 0x00, 0x7B, 0x22]) + Data("not-json".utf8)
    defaults.set(original, forKey: Ledger.storageKey)

    XCTAssertEqual(Ledger.load(from: defaults, now: recoveredAt), Ledger())

    XCTAssertEqual(backupKeys(in: defaults), [recoveredKey])
    XCTAssertEqual(defaults.data(forKey: recoveredKey), original)
    XCTAssertEqual(defaults.data(forKey: Ledger.storageKey), original)
  }

  func testWrongShapeOfLedgerIsTreatedAsUnreadable() {
    for json in [#"{}"#, #"{"sessions":"nope"}"#, #"[]"#, #"{"sessions":{}}"#] {
      let defaults = makeDefaults()
      let original = Data(json.utf8)
      defaults.set(original, forKey: Ledger.storageKey)
      XCTAssertEqual(Ledger.load(from: defaults, now: recoveredAt), Ledger(), json)
      XCTAssertEqual(defaults.data(forKey: recoveredKey), original, json)
    }
  }

  func testMissingDataLoadsEmptyLedgerWithoutBackup() {
    let defaults = makeDefaults()
    XCTAssertEqual(Ledger.load(from: defaults, now: recoveredAt), Ledger())
    XCTAssertEqual(backupKeys(in: defaults), [])
  }

  func testSaveAfterRecoveryLeavesBackupIntact() {
    let defaults = makeDefaults()
    let original = Data(partiallyBadJSON.utf8)
    defaults.set(original, forKey: Ledger.storageKey)

    let recovered = Ledger.load(from: defaults, now: recoveredAt)
    LedgerMutations.toggle(.consume, on: recovered, now: recoveredAt).save(to: defaults)

    XCTAssertEqual(defaults.data(forKey: recoveredKey), original)
    XCTAssertNotEqual(defaults.data(forKey: Ledger.storageKey), original)

    let reloaded = Ledger.load(from: defaults, now: recoveredAt.addingTimeInterval(60))
    XCTAssertEqual(reloaded.sessions.count, 3)
    XCTAssertEqual(backupKeys(in: defaults), [recoveredKey])
  }

  func testTwoRecoveriesInTheSameSecondKeepTwoBackups() {
    let defaults = makeDefaults()
    let first = Data("not-json".utf8)
    let second = Data("[1,2,3]".utf8)

    defaults.set(first, forKey: Ledger.storageKey)
    _ = Ledger.load(from: defaults, now: recoveredAt)
    defaults.set(second, forKey: Ledger.storageKey)
    _ = Ledger.load(from: defaults, now: recoveredAt)

    XCTAssertEqual(backupKeys(in: defaults), [recoveredKey, "\(recoveredKey)-1"])
    XCTAssertEqual(defaults.data(forKey: recoveredKey), first)
    XCTAssertEqual(defaults.data(forKey: "\(recoveredKey)-1"), second)
  }

  func testRecoveriesInDifferentSecondsUseDifferentKeys() {
    let defaults = makeDefaults()
    let data = Data("not-json".utf8)
    let later = recoveredAt.addingTimeInterval(5)

    defaults.set(data, forKey: Ledger.storageKey)
    _ = Ledger.load(from: defaults, now: recoveredAt)
    _ = Ledger.load(from: defaults, now: later)

    XCTAssertEqual(
      backupKeys(in: defaults),
      [recoveredKey, "app.less.ledger.backup.1800000005"]
    )
  }

  func testLedgerWithoutVersionKeyStillDecodes() throws {
    let json =
      #"{"sessions":[{"kind":"create","start":800000000,"end":800003600}],"#
      + #""run":{"kind":"consume","start":800007200}}"#
    let expected = Ledger(
      sessions: [Session(kind: .create, start: ref(800_000_000), end: ref(800_003_600))],
      run: Run(kind: .consume, start: ref(800_007_200))
    )

    XCTAssertEqual(try JSONDecoder().decode(Ledger.self, from: Data(json.utf8)), expected)

    let defaults = makeDefaults()
    defaults.set(Data(json.utf8), forKey: Ledger.storageKey)
    XCTAssertEqual(Ledger.load(from: defaults, now: recoveredAt), expected)
    XCTAssertEqual(backupKeys(in: defaults), [])
  }

  func testSavedJSONCarriesVersionOne() throws {
    let defaults = makeDefaults()
    let ledger = Ledger(
      sessions: [Session(kind: .create, start: ref(800_000_000), end: ref(800_003_600))]
    )
    ledger.save(to: defaults)

    let data = try XCTUnwrap(defaults.data(forKey: Ledger.storageKey))
    let object = try XCTUnwrap(try JSONSerialization.jsonObject(with: data) as? [String: Any])
    XCTAssertEqual(object["version"] as? Int, 1)
    XCTAssertEqual((object["sessions"] as? [Any])?.count, 1)
    XCTAssertNil(object["run"])
    XCTAssertEqual(Ledger.load(from: defaults), ledger)
  }

  func testStopClosesTheRunAndAppendsTheSession() {
    let earlier = Session(kind: .consume, start: utc(2026, 9, 15, 8), end: utc(2026, 9, 15, 9))
    let ledger = Ledger(
      sessions: [earlier],
      run: Run(kind: .create, start: utc(2026, 9, 15, 10))
    )

    let stopped = LedgerMutations.stop(on: ledger, at: utc(2026, 9, 15, 11, 30))

    XCTAssertNil(stopped.run)
    XCTAssertEqual(
      stopped.sessions,
      [earlier, Session(kind: .create, start: utc(2026, 9, 15, 10), end: utc(2026, 9, 15, 11, 30))]
    )
    let snap = LedgerMutations.snapshot(
      ledger: stopped,
      now: utc(2026, 9, 15, 15),
      calendar: calendar
    )
    XCTAssertEqual(snap.create, 5400)
    XCTAssertEqual(snap.consume, 3600)
    XCTAssertNil(snap.run)
  }

  func testStopKeepsTheKindOfTheRun() {
    let ledger = Ledger(run: Run(kind: .consume, start: utc(2026, 9, 15, 10)))
    let stopped = LedgerMutations.stop(on: ledger, at: utc(2026, 9, 15, 10, 5))
    XCTAssertEqual(
      stopped.sessions,
      [Session(kind: .consume, start: utc(2026, 9, 15, 10), end: utc(2026, 9, 15, 10, 5))]
    )
  }

  func testStopWhenIdleChangesNothing() {
    let ledger = Ledger(
      sessions: [
        Session(kind: .create, start: utc(2026, 9, 15, 10), end: utc(2026, 9, 15, 12))
      ]
    )
    XCTAssertEqual(LedgerMutations.stop(on: ledger, at: utc(2026, 9, 15, 13)), ledger)
    XCTAssertEqual(LedgerMutations.stop(on: Ledger(), at: utc(2026, 9, 15, 13)), Ledger())
  }

  func testStopBeforeStartClampsToZeroLengthSession() {
    let start = utc(2026, 9, 15, 12)
    let ledger = Ledger(run: Run(kind: .create, start: start))
    let stopped = LedgerMutations.stop(on: ledger, at: utc(2026, 9, 15, 11))
    XCTAssertEqual(stopped.sessions, [Session(kind: .create, start: start, end: start)])
    XCTAssertNil(stopped.run)
  }

  func testToggleSwitchingKindsWithBackwardsClockClampsTheClosedSession() {
    let start = utc(2026, 9, 15, 12)
    let earlier = utc(2026, 9, 15, 11)
    let started = LedgerMutations.toggle(.create, on: Ledger(), now: start)
    let switched = LedgerMutations.toggle(.consume, on: started, now: earlier)
    XCTAssertEqual(switched.sessions, [Session(kind: .create, start: start, end: start)])
    XCTAssertEqual(switched.run, Run(kind: .consume, start: earlier))
  }

  func testNowBeforeStartCountsZeroAndDoesNotCrash() {
    let start = utc(2026, 9, 15, 12)
    let earlier = utc(2026, 9, 15, 11)
    let started = LedgerMutations.toggle(.create, on: Ledger(), now: start)
    let closed = LedgerMutations.toggle(.create, on: started, now: earlier)
    XCTAssertEqual(closed.sessions.count, 1)
    XCTAssertEqual(closed.sessions[0].start, start)
    XCTAssertEqual(closed.sessions[0].end, start)
    XCTAssertNil(closed.run)
    let snap = LedgerMutations.snapshot(ledger: closed, now: start, calendar: calendar)
    XCTAssertEqual(snap.create, 0)
    XCTAssertEqual(snap.consume, 0)
    XCTAssertEqual(snap.ratioLine, "0 : 0")
  }
}
