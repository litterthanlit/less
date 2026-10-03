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
  public var createPart: Int
  public var consumePart: Int

  public init(
    create: TimeInterval,
    consume: TimeInterval,
    run: Run?,
    createPart: Int,
    consumePart: Int
  ) {
    self.create = create
    self.consume = consume
    self.run = run
    self.createPart = createPart
    self.consumePart = consumePart
  }
}

public enum LedgerMutations {
  public static func toggle(_ kind: Kind, on ledger: Ledger, now: Date) -> Ledger {
    var sessions = ledger.sessions
    if let run = ledger.run {
      sessions.append(Session(kind: run.kind, start: run.start, end: now))
      if run.kind == kind {
        return Ledger(sessions: sessions, run: nil)
      }
    }
    return Ledger(sessions: sessions, run: Run(kind: kind, start: now))
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

    let (createPart, consumePart) = ratioParts(create: create, consume: consume)
    return Snapshot(
      create: create,
      consume: consume,
      run: ledger.run,
      createPart: createPart,
      consumePart: consumePart
    )
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

  public static func ratioLine(createPart: Int, consumePart: Int) -> String {
    "\(createPart) : \(consumePart)"
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

  private static func ratioParts(create: TimeInterval, consume: TimeInterval) -> (Int, Int) {
    let createSeconds = Int(create.rounded(.towardZero))
    let consumeSeconds = Int(consume.rounded(.towardZero))
    if createSeconds == 0 && consumeSeconds == 0 {
      return (0, 0)
    }
    if createSeconds > 0 && consumeSeconds == 0 {
      return (1, 0)
    }
    if createSeconds == 0 && consumeSeconds > 0 {
      return (0, 1)
    }
    let g = gcd(createSeconds, consumeSeconds)
    return (createSeconds / g, consumeSeconds / g)
  }

  private static func gcd(_ a: Int, _ b: Int) -> Int {
    var a = abs(a)
    var b = abs(b)
    while b != 0 {
      let remainder = a % b
      a = b
      b = remainder
    }
    return max(a, 1)
  }
}

extension Ledger {
  public static let storageKey = "app.less.ledger"

  public static func load(from defaults: UserDefaults) -> Ledger {
    guard let data = defaults.data(forKey: storageKey),
      let decoded = try? JSONDecoder().decode(Ledger.self, from: data)
    else {
      return Ledger()
    }
    return decoded
  }

  public func save(to defaults: UserDefaults) {
    guard let data = try? JSONEncoder().encode(self) else {
      return
    }
    defaults.set(data, forKey: Self.storageKey)
  }
}
