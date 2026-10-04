import Foundation
import XCTest
@testable import LessCore

final class TabLogTests: XCTestCase {
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
      .filter { $0.hasPrefix("\(TabLog.storageKey).backup.") }
      .sorted()
  }

  private func uuid(_ n: Int) -> UUID {
    UUID(uuidString: String(format: "00000000-0000-4000-8000-%012d", n))!
  }

  private func open(_ n: Int, _ at: Date, _ url: String? = nil, _ title: String? = nil) -> BridgeEvent {
    BridgeEvent(type: .open, id: uuid(n), at: at, url: url, title: title)
  }

  private func close(_ n: Int, _ at: Date, _ url: String? = nil, _ title: String? = nil) -> BridgeEvent {
    BridgeEvent(type: .close, id: uuid(n), at: at, url: url, title: title)
  }

  func testOpenThenCloseMakesOneClosedVisit() {
    let events = [
      open(1, utc(2026, 10, 4, 9), "https://x.com/home?s=1", "(2) Home / X"),
      close(1, utc(2026, 10, 4, 9, 6), "https://x.com/someone/status/9", "Someone on X: \"ok\" / X"),
    ]
    let result = TabLogMutations.apply(events, to: TabLog())
    let expected = Visit(
      id: uuid(1),
      openedAt: utc(2026, 10, 4, 9),
      closedAt: utc(2026, 10, 4, 9, 6),
      path: "/someone/status/9",
      title: "Someone on X: \"ok\""
    )
    XCTAssertEqual(result.log.visits, [expected])
    XCTAssertEqual(result.newlyClosed, [expected])
    XCTAssertEqual(expected.duration(now: utc(2026, 10, 4, 12)), 360)
  }

  func testReplayingTheSameEventsChangesNothing() {
    let events = [
      open(1, utc(2026, 10, 4, 9)),
      open(2, utc(2026, 10, 4, 9, 1)),
      close(1, utc(2026, 10, 4, 9, 5)),
    ]
    let once = TabLogMutations.apply(events, to: TabLog())
    let twice = TabLogMutations.apply(events, to: once.log)
    XCTAssertEqual(twice.log, once.log)
    XCTAssertEqual(twice.newlyClosed, [])
    XCTAssertEqual(once.log.visits.count, 2)
  }

  func testReplayKeepsTheRating() {
    let events = [open(1, utc(2026, 10, 4, 9)), close(1, utc(2026, 10, 4, 9, 5))]
    let applied = TabLogMutations.apply(events, to: TabLog()).log
    let rated = TabLogMutations.rate(uuid(1), .useful, on: applied)
    let replayed = TabLogMutations.apply(events, to: rated).log
    XCTAssertEqual(replayed.visits.first?.verdict, .useful)
  }

  func testCloseWithoutOpenStillCountsAndLaterOpenFixesStart() {
    let first = TabLogMutations.apply([close(1, utc(2026, 10, 4, 9, 5))], to: TabLog())
    XCTAssertEqual(first.log.visits.first?.openedAt, utc(2026, 10, 4, 9, 5))
    XCTAssertEqual(first.newlyClosed.map(\.id), [uuid(1)])

    let late = TabLogMutations.apply([open(1, utc(2026, 10, 4, 9), "https://x.com/home")], to: first.log)
    XCTAssertEqual(late.log.visits.first?.openedAt, utc(2026, 10, 4, 9))
    XCTAssertEqual(late.log.visits.first?.closedAt, utc(2026, 10, 4, 9, 5))
    XCTAssertEqual(late.log.visits.first?.path, "/home")
    XCTAssertEqual(late.newlyClosed, [])
  }

  func testCloseBeforeOpenTimeIsClampedToOpen() {
    let events = [open(1, utc(2026, 10, 4, 9)), close(1, utc(2026, 10, 4, 8))]
    let visit = TabLogMutations.apply(events, to: TabLog()).log.visits.first
    XCTAssertEqual(visit?.closedAt, utc(2026, 10, 4, 9))
    XCTAssertEqual(visit?.duration(now: utc(2026, 10, 4, 10)), 0)
  }

  func testCloseKeepsEarlierPathWhenItCarriesNone() {
    let events = [open(1, utc(2026, 10, 4, 9), "https://x.com/home", "Home / X"), close(1, utc(2026, 10, 4, 9, 1))]
    let visit = TabLogMutations.apply(events, to: TabLog()).log.visits.first
    XCTAssertEqual(visit?.path, "/home")
    XCTAssertEqual(visit?.title, "Home")
  }

  func testNonXURLsAreNeverStored() {
    let events = [open(1, utc(2026, 10, 4, 9), "https://bank.example/account?id=7")]
    XCTAssertNil(TabLogMutations.apply(events, to: TabLog()).log.visits.first?.path)
  }

  func testOpenVisitDurationRunsToNow() {
    let visit = Visit(id: uuid(1), openedAt: utc(2026, 10, 4, 9))
    XCTAssertEqual(visit.duration(now: utc(2026, 10, 4, 9, 2)), 120)
  }

  func testFormatStay() {
    XCTAssertEqual(TabLogMutations.formatStay(0), "<1 min")
    XCTAssertEqual(TabLogMutations.formatStay(59), "<1 min")
    XCTAssertEqual(TabLogMutations.formatStay(60), "1 min")
    XCTAssertEqual(TabLogMutations.formatStay(359), "5 min")
    XCTAssertEqual(TabLogMutations.formatStay(3600), "1 h")
    XCTAssertEqual(TabLogMutations.formatStay(3900), "1 h 5 min")
    XCTAssertEqual(TabLogMutations.formatStay(-5), "<1 min")
    XCTAssertEqual(TabLogMutations.formatStay(.infinity), "277777 h 46 min")
  }

  func testRateAndUnrate() {
    let log = TabLogMutations.apply([open(1, utc(2026, 10, 4, 9))], to: TabLog()).log
    let rated = TabLogMutations.rate(uuid(1), .notUseful, on: log)
    XCTAssertEqual(rated.visits.first?.verdict, .notUseful)
    XCTAssertEqual(TabLogMutations.rate(uuid(1), nil, on: rated), log)
    XCTAssertEqual(TabLogMutations.rate(uuid(9), .useful, on: log), log)
  }

  func testDayCountsVisitsOpenedTodayNewestFirst() {
    var log = TabLogMutations.apply(
      [
        open(1, utc(2026, 10, 3, 23, 50)),
        close(1, utc(2026, 10, 4, 0, 20)),
        open(2, utc(2026, 10, 4, 0, 0)),
        open(3, utc(2026, 10, 4, 9)),
        open(4, utc(2026, 10, 4, 21)),
        open(5, utc(2026, 10, 5, 0, 0)),
      ],
      to: TabLog()
    ).log
    log = TabLogMutations.rate(uuid(2), .useful, on: log)
    log = TabLogMutations.rate(uuid(3), .notUseful, on: log)

    let day = TabLogMutations.day(log: log, now: utc(2026, 10, 4, 22), calendar: calendar)
    XCTAssertEqual(day.visits.map(\.id), [uuid(4), uuid(3), uuid(2)])
    XCTAssertEqual(day.opened, 3)
    XCTAssertEqual(day.useful, 1)
    XCTAssertEqual(day.notUseful, 1)
    XCTAssertEqual(day.unrated, 1)
    XCTAssertEqual(day.countLine, "3 tabs")
    XCTAssertEqual(day.breakdownLine, "1 useful · 1 not · 1 to rate")
  }

  func testEmptyDayLines() {
    let day = TabLogMutations.day(log: TabLog(), now: utc(2026, 10, 4, 12), calendar: calendar)
    XCTAssertEqual(day.countLine, "0 tabs")
    XCTAssertEqual(day.breakdownLine, "none yet")
    XCTAssertEqual(TabDay(visits: [Visit(id: uuid(1), openedAt: utc(2026, 10, 4, 1))]).countLine, "1 tab")
  }

  func testSaveAndLoadRoundTrip() {
    let defaults = makeDefaults()
    var log = TabLogMutations.apply(
      [open(1, utc(2026, 10, 4, 9), "https://x.com/home", "Home / X"), close(1, utc(2026, 10, 4, 9, 4))],
      to: TabLog()
    ).log
    log = TabLogMutations.rate(uuid(1), .useful, on: log)
    log.save(to: defaults)
    XCTAssertEqual(TabLog.load(from: defaults), log)
    XCTAssertEqual(backupKeys(in: defaults), [])
  }

  func testLoadWithNothingStoredIsEmpty() {
    XCTAssertEqual(TabLog.load(from: makeDefaults()), TabLog())
  }

  func testLoadKeepsReadableVisitsAndBacksUpTheOriginal() {
    let defaults = makeDefaults()
    let json = #"""
      {"version":1,"visits":[
        {"id":"00000000-0000-4000-8000-000000000001","openedAt":800000000},
        {"id":"00000000-0000-4000-8000-000000000002","openedAt":800000060,"verdict":"meh"},
        {"id":"00000000-0000-4000-8000-000000000003","openedAt":800000120,"closedAt":800000180,"verdict":"useful"}
      ]}
      """#
    let data = Data(json.utf8)
    defaults.set(data, forKey: TabLog.storageKey)
    let now = Date(timeIntervalSince1970: 1_800_000_000)

    let log = TabLog.load(from: defaults, now: now)
    XCTAssertEqual(log.visits.map(\.id), [uuid(1), uuid(3)])
    XCTAssertEqual(log.visits.last?.verdict, .useful)
    XCTAssertEqual(backupKeys(in: defaults), ["app.less.tabs.backup.1800000000"])
    XCTAssertEqual(defaults.data(forKey: "app.less.tabs.backup.1800000000"), data)
  }

  func testUnreadableDataIsBackedUpAndNeverOverwritten() {
    let defaults = makeDefaults()
    let now = Date(timeIntervalSince1970: 1_800_000_000)
    defaults.set(Data("not json".utf8), forKey: TabLog.storageKey)
    XCTAssertEqual(TabLog.load(from: defaults, now: now), TabLog())
    XCTAssertEqual(TabLog.load(from: defaults, now: now), TabLog())
    XCTAssertEqual(
      backupKeys(in: defaults),
      ["app.less.tabs.backup.1800000000", "app.less.tabs.backup.1800000000-1"]
    )
  }

  func testIngestFromInboxFilesEndToEnd() throws {
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent("less-e2e-\(UUID().uuidString)")
    addTeardownBlock {
      try? FileManager.default.removeItem(at: dir)
    }
    let request = #"""
      {"v":1,"events":[
        {"type":"open","id":"00000000-0000-4000-8000-000000000001","at":1791100800000,"url":"https://x.com/home"},
        {"type":"close","id":"00000000-0000-4000-8000-000000000001","at":1791101100000,"url":"https://x.com/home"}
      ]}
      """#
    try Inbox.write(try Bridge.decodeRequest(Data(request.utf8)), to: dir, now: Date())

    let files = Inbox.pending(in: dir)
    let result = TabLogMutations.apply(Inbox.read(files), to: TabLog())
    XCTAssertEqual(result.log.visits.count, 1)
    XCTAssertEqual(result.log.visits.first?.duration(now: Date()), 300)
    XCTAssertEqual(result.newlyClosed.count, 1)
  }
}
