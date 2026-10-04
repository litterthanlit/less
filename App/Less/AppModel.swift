import AppKit
import Combine
import Foundation

@MainActor
final class AppModel: ObservableObject {
  @Published private(set) var ledger: Ledger

  private let defaults: UserDefaults
  private var observers: [NSObjectProtocol] = []

  init(defaults: UserDefaults = .standard) {
    self.defaults = defaults
    ledger = Ledger.load(from: defaults)
    stopWhenTheMacLeaves()
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

  private func stopRunning() {
    guard ledger.run != nil else {
      return
    }
    ledger = LedgerMutations.stop(on: ledger, at: Date())
    ledger.save(to: defaults)
  }

  private func stopWhenTheMacLeaves() {
    let center = NSWorkspace.shared.notificationCenter
    let names = [
      NSWorkspace.willSleepNotification,
      NSWorkspace.willPowerOffNotification,
      NSWorkspace.sessionDidResignActiveNotification,
    ]
    observers = names.map { name in
      center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
        guard let self else {
          return
        }
        MainActor.assumeIsolated {
          self.stopRunning()
        }
      }
    }
  }
}
