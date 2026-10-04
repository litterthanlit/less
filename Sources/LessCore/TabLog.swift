import Foundation

public enum Verdict: String, Codable, Sendable, CaseIterable {
  case useful
  case notUseful
}

// one X tab, from the moment it landed on X until it closed or left
public struct Visit: Codable, Equatable, Sendable, Identifiable {
  public var id: UUID
  public var openedAt: Date
  public var closedAt: Date?
  public var path: String?
  public var title: String?
  public var verdict: Verdict?

  public init(
    id: UUID,
    openedAt: Date,
    closedAt: Date? = nil,
    path: String? = nil,
    title: String? = nil,
    verdict: Verdict? = nil
  ) {
    self.id = id
    self.openedAt = openedAt
    self.closedAt = closedAt
    self.path = path
    self.title = title
    self.verdict = verdict
  }

  public func duration(now: Date) -> TimeInterval {
    max(0, (closedAt ?? now).timeIntervalSince(openedAt))
  }
}

public struct TabLog: Codable, Equatable, Sendable {
  public var visits: [Visit]

  public init(visits: [Visit] = []) {
    self.visits = visits
  }
}

public struct TabDay: Equatable, Sendable {
  // newest first
  public var visits: [Visit]

  public init(visits: [Visit]) {
    self.visits = visits
  }

  public var opened: Int { visits.count }
  public var useful: Int { visits.filter { $0.verdict == .useful }.count }
  public var notUseful: Int { visits.filter { $0.verdict == .notUseful }.count }
  public var unrated: Int { visits.filter { $0.verdict == nil }.count }

  public var countLine: String {
    Self.countLine(opened)
  }

  static func countLine(_ opened: Int) -> String {
    opened == 1 ? "1 tab" : "\(opened) tabs"
  }

  public var breakdownLine: String {
    if opened == 0 {
      return "none yet"
    }
    return "\(useful) useful · \(notUseful) not · \(unrated) to rate"
  }
}

public struct Ingest: Equatable, Sendable {
  public var log: TabLog
  // visits this batch closed for the first time, in event order
  public var newlyClosed: [Visit]

  public init(log: TabLog, newlyClosed: [Visit]) {
    self.log = log
    self.newlyClosed = newlyClosed
  }
}

public enum TabLogMutations {
  // safe to replay: the same events applied twice leave the log unchanged
  public static func apply(_ events: [BridgeEvent], to log: TabLog) -> Ingest {
    var visits = log.visits
    var index: [UUID: Int] = [:]
    for (i, visit) in visits.enumerated() {
      index[visit.id] = i
    }
    var closedIDs: [UUID] = []

    for event in events {
      let path = Bridge.xPath(of: event.url)
      let title = Bridge.cleanTitle(event.title)
      switch event.type {
      case .open:
        if let i = index[event.id] {
          // an open that arrives after its close still fixes the start
          visits[i].openedAt = min(visits[i].openedAt, event.at)
          if let closedAt = visits[i].closedAt {
            visits[i].closedAt = max(closedAt, visits[i].openedAt)
          }
          visits[i].path = visits[i].path ?? path
          visits[i].title = visits[i].title ?? title
        } else {
          index[event.id] = visits.count
          visits.append(Visit(id: event.id, openedAt: event.at, path: path, title: title))
        }
      case .close:
        if let i = index[event.id] {
          guard visits[i].closedAt == nil else {
            continue
          }
          visits[i].closedAt = max(visits[i].openedAt, event.at)
          visits[i].path = path ?? visits[i].path
          visits[i].title = title ?? visits[i].title
        } else {
          index[event.id] = visits.count
          visits.append(
            Visit(id: event.id, openedAt: event.at, closedAt: event.at, path: path, title: title)
          )
        }
        closedIDs.append(event.id)
      }
    }

    let newlyClosed = closedIDs.compactMap { id in index[id].map { visits[$0] } }
    return Ingest(log: TabLog(visits: visits), newlyClosed: newlyClosed)
  }

  public static func rate(_ id: UUID, _ verdict: Verdict?, on log: TabLog) -> TabLog {
    var log = log
    if let i = log.visits.firstIndex(where: { $0.id == id }) {
      log.visits[i].verdict = verdict
    }
    return log
  }

  // "<1 min", "6 min", "1 h 5 min": how long a tab stayed on X, at a glance
  public static func formatStay(_ t: TimeInterval) -> String {
    let minutes = Int(min(max(0, t), 1e9) / 60)
    if minutes < 1 {
      return "<1 min"
    }
    if minutes < 60 {
      return "\(minutes) min"
    }
    let rest = minutes % 60
    return rest == 0 ? "\(minutes / 60) h" : "\(minutes / 60) h \(rest) min"
  }

  // a visit belongs to the local day it was opened on
  public static func day(log: TabLog, now: Date, calendar: Calendar) -> TabDay {
    let dayStart = calendar.startOfDay(for: now)
    let dayEnd = calendar.date(byAdding: .day, value: 1, to: dayStart) ?? dayStart
    let visits = log.visits
      .filter { $0.openedAt >= dayStart && $0.openedAt < dayEnd }
      .sorted { $0.openedAt > $1.openedAt }
    return TabDay(visits: visits)
  }
}

extension TabLog {
  public static let storageKey = "app.less.tabs"

  private static let formatVersion = 1

  private enum CodingKeys: String, CodingKey {
    case version
    case visits
  }

  private struct Stored: Decodable {
    let log: TabLog
    let droppedAny: Bool

    init(from decoder: Decoder) throws {
      let container = try decoder.container(keyedBy: TabLog.CodingKeys.self)
      let visits = try container.decode([Lossy<Visit>].self, forKey: .visits)
      let kept = visits.compactMap(\.value)
      log = TabLog(visits: kept)
      droppedAny = kept.count != visits.count
    }
  }

  public init(from decoder: Decoder) throws {
    self = try Stored(from: decoder).log
  }

  public func encode(to encoder: Encoder) throws {
    var container = encoder.container(keyedBy: CodingKeys.self)
    try container.encode(Self.formatVersion, forKey: .version)
    try container.encode(visits, forKey: .visits)
  }

  public static func load(from defaults: UserDefaults, now: Date = Date()) -> TabLog {
    guard let data = defaults.data(forKey: storageKey) else {
      return TabLog()
    }
    guard let stored = try? JSONDecoder().decode(Stored.self, from: data) else {
      storeBackup(data, under: storageKey, in: defaults, now: now)
      return TabLog()
    }
    if stored.droppedAny {
      storeBackup(data, under: storageKey, in: defaults, now: now)
    }
    return stored.log
  }

  public func save(to defaults: UserDefaults) {
    guard let data = try? JSONEncoder().encode(self) else {
      return
    }
    defaults.set(data, forKey: Self.storageKey)
  }
}

// a daily budget for X tabs; nil means no limit
public enum TabLimit {
  public static let storageKey = "app.less.tabs.limit"
  public static let choices = [5, 10, 15, 20, 30]
  public static let defaultLimit = 10

  // nothing stored yet means the default; a stored 0 or less means the user turned it off
  public static func load(from defaults: UserDefaults) -> Int? {
    guard let stored = defaults.object(forKey: storageKey) as? Int else {
      return defaultLimit
    }
    return stored > 0 ? stored : nil
  }

  public static func save(_ limit: Int?, to defaults: UserDefaults) {
    defaults.set(max(0, limit ?? 0), forKey: storageKey)
  }

  // reaching the limit is fine; the next tab past it is the one that counts as over
  public static func isOver(opened: Int, limit: Int?) -> Bool {
    guard let limit else {
      return false
    }
    return opened > limit
  }

  // "7 of 10 tabs", then "12 tabs · 2 over" once past it
  public static func countLine(opened: Int, limit: Int?) -> String {
    guard let limit else {
      return TabDay.countLine(opened)
    }
    if opened > limit {
      return "\(TabDay.countLine(opened)) · \(opened - limit) over"
    }
    return "\(opened) of \(limit) tabs"
  }

  // the menu bar stays quiet until the first X tab of the day
  public static func menuBarText(opened: Int, limit: Int?) -> String? {
    guard opened > 0 else {
      return nil
    }
    guard let limit else {
      return "X \(opened)"
    }
    return "X \(opened)/\(limit)"
  }
}
