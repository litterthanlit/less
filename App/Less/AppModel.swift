import Combine
import Foundation

final class AppModel: ObservableObject {
  @Published private(set) var ledger: Ledger

  private let defaults: UserDefaults

  init(defaults: UserDefaults = .standard) {
    self.defaults = defaults
    ledger = Ledger.load(from: defaults)
  }

  func snapshot(now: Date) -> Snapshot {
    LedgerMutations.snapshot(ledger: ledger, now: now, calendar: .current)
  }

  func toggle(_ kind: Kind) {
    ledger = LedgerMutations.toggle(kind, on: ledger, now: Date())
    ledger.save(to: defaults)
  }

  var createButtonTitle: String {
    if ledger.run?.kind == .create {
      return "Stop Create"
    }
    return "Start Create"
  }

  var consumeButtonTitle: String {
    if ledger.run?.kind == .consume {
      return "Stop Consume"
    }
    return "Start Consume"
  }
}
