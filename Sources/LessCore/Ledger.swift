import Foundation

public enum Kind: String, Codable, Sendable, CaseIterable {
  case create
  case consume
}

public struct Session: Codable, Equatable, Sendable {
  public var kind: Kind
  public var start: Date
  public var end: Date

  public init(kind: Kind, start: Date, end: Date) {
    self.kind = kind
    self.start = start
    self.end = end
  }
}

public struct Run: Codable, Equatable, Sendable {
  public var kind: Kind
  public var start: Date

  public init(kind: Kind, start: Date) {
    self.kind = kind
    self.start = start
  }
}

public struct Ledger: Codable, Equatable, Sendable {
  public var sessions: [Session]
  public var run: Run?

  public init(sessions: [Session] = [], run: Run? = nil) {
    self.sessions = sessions
    self.run = run
  }
}

public struct Snapshot: Equatable, Sendable {
  public var create: TimeInterval
  public var consume: TimeInterval
  public var run: Run?

  public init(create: TimeInterval, consume: TimeInterval, run: Run?) {
    self.create = create
    self.consume = consume
    self.run = run
  }

  public var ratioLine: String {
    LedgerMutations.ratioLine(create: create, consume: consume)
  }
}

public enum LedgerMutations {
  public static func toggle(_ kind: Kind, on ledger: Ledger, now: Date) -> Ledger {
    var sessions = ledger.sessions
    if let run = ledger.run {
      sessions.append(closed(run, at: now))
      if run.kind == kind {
        return Ledger(sessions: sessions, run: nil)
      }
    }
    return Ledger(sessions: sessions, run: Run(kind: kind, start: now))
  }

  public static func stop(on ledger: Ledger, at now: Date) -> Ledger {
    guard let run = ledger.run else {
      return ledger
    }
    return Ledger(sessions: ledger.sessions + [closed(run, at: now)], run: nil)
  }

  public static func snapshot(ledger: Ledger, now: Date, calendar: Calendar) -> Snapshot {
    let dayStart = calendar.startOfDay(for: now)
    let dayEnd = calendar.date(byAdding: .day, value: 1, to: dayStart) ?? dayStart
    var create: TimeInterval = 0
    var consume: TimeInterval = 0

    func add(_ kind: Kind, from start: Date, to end: Date) {
      let seconds = overlap(start: start, end: end, dayStart: dayStart, dayEnd: dayEnd)
      switch kind {
      case .create:
        create += seconds
      case .consume:
        consume += seconds
      }
    }

    for session in ledger.sessions {
      add(session.kind, from: session.start, to: session.end)
    }
    if let run = ledger.run {
      add(run.kind, from: run.start, to: now)
    }

    return Snapshot(create: create, consume: consume, run: ledger.run)
  }

  public static func formatDuration(_ t: TimeInterval) -> String {
    let total = Int(max(0, t).rounded(.towardZero))
    let hours = total / 3600
    let minutes = (total % 3600) / 60
    let seconds = total % 60
    if hours >= 1 {
      return String(format: "%d:%02d:%02d", hours, minutes, seconds)
    }
    return String(format: "%d:%02d", minutes, seconds)
  }

  public static func ratioLine(create: TimeInterval, consume: TimeInterval) -> String {
    let createSeconds = wholeSeconds(create)
    let consumeSeconds = wholeSeconds(consume)
    if createSeconds == 0 && consumeSeconds == 0 {
      return "0 : 0"
    }
    if consumeSeconds == 0 {
      return "1 : 0"
    }
    if createSeconds == 0 {
      return "0 : 1"
    }
    if createSeconds >= consumeSeconds {
      return "\(ratioText(createSeconds, over: consumeSeconds)) : 1"
    }
    return "1 : \(ratioText(consumeSeconds, over: createSeconds))"
  }

  private static func closed(_ run: Run, at now: Date) -> Session {
    Session(kind: run.kind, start: run.start, end: max(run.start, now))
  }

  private static func overlap(
    start: Date,
    end: Date,
    dayStart: Date,
    dayEnd: Date
  ) -> TimeInterval {
    let lo = max(start, dayStart)
    let hi = min(end, dayEnd)
    return max(0, hi.timeIntervalSince(lo))
  }

  private static func wholeSeconds(_ t: TimeInterval) -> Int {
    guard t > 0 else {
      return 0
    }
    // keeps Int(_:) from trapping on absurd or infinite input
    return Int(min(t, 1e12))
  }

  private static func ratioText(_ larger: Int, over smaller: Int) -> String {
    let tenths = (larger * 20 + smaller) / (2 * smaller)
    if tenths >= 100 {
      return String((larger * 2 + smaller) / (2 * smaller))
    }
    return "\(tenths / 10).\(tenths % 10)"
  }
}

private struct Lossy<T: Decodable>: Decodable {
  let value: T?

  init(from decoder: Decoder) throws {
    value = try? T(from: decoder)
  }
}

extension Ledger {
  public static let storageKey = "app.less.ledger"

  private static let formatVersion = 1

  private enum CodingKeys: String, CodingKey {
    case version
    case sessions
    case run
  }

  private struct Stored: Decodable {
    let ledger: Ledger
    let droppedAny: Bool

    init(from decoder: Decoder) throws {
      let container = try decoder.container(keyedBy: Ledger.CodingKeys.self)
      let sessions = try container.decode([Lossy<Session>].self, forKey: .sessions)
      let run = try container.decodeIfPresent(Lossy<Run>.self, forKey: .run)
      let kept = sessions.compactMap(\.value)
      ledger = Ledger(sessions: kept, run: run?.value)
      droppedAny = kept.count != sessions.count || (run != nil && run?.value == nil)
    }
  }

  public init(from decoder: Decoder) throws {
    self = try Stored(from: decoder).ledger
  }

  public func encode(to encoder: Encoder) throws {
    var container = encoder.container(keyedBy: CodingKeys.self)
    try container.encode(Self.formatVersion, forKey: .version)
    try container.encode(sessions, forKey: .sessions)
    try container.encodeIfPresent(run, forKey: .run)
  }

  public static func load(from defaults: UserDefaults, now: Date = Date()) -> Ledger {
    guard let data = defaults.data(forKey: storageKey) else {
      return Ledger()
    }
    guard let stored = try? JSONDecoder().decode(Stored.self, from: data) else {
      backUp(data, in: defaults, now: now)
      return Ledger()
    }
    if stored.droppedAny {
      backUp(data, in: defaults, now: now)
    }
    return stored.ledger
  }

  public func save(to defaults: UserDefaults) {
    guard let data = try? JSONEncoder().encode(self) else {
      return
    }
    defaults.set(data, forKey: Self.storageKey)
  }

  private static func backUp(_ data: Data, in defaults: UserDefaults, now: Date) {
    let base = "\(storageKey).backup.\(Int(now.timeIntervalSince1970))"
    var key = base
    var suffix = 1
    while defaults.object(forKey: key) != nil {
      key = "\(base)-\(suffix)"
      suffix += 1
    }
    defaults.set(data, forKey: key)
  }
}
