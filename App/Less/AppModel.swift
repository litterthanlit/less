import AppKit
import Combine
import Foundation

@MainActor
final class AppModel: ObservableObject {
  @Published private(set) var ledger: Ledger
  @Published private(set) var tabLog: TabLog
  // bumps whenever something outside a window, like a notification, asks for the review
  @Published private(set) var reviewRequests = 0

  private let defaults: UserDefaults
  private let prompt: TabPrompt
  private var observers: [NSObjectProtocol] = []
  private var inboxWatcher: DispatchSourceFileSystemObject?

  init(defaults: UserDefaults = .standard) {
    self.defaults = defaults
    ledger = Ledger.load(from: defaults)
    tabLog = TabLog.load(from: defaults)
    prompt = TabPrompt(defaults: defaults)
    stopWhenTheMacLeaves()
    prompt.onRate = { [weak self] id, verdict in
      self?.rate(id, verdict)
    }
    prompt.onReview = { [weak self] in
      self?.reviewRequests += 1
    }
    watchInbox()
    ingestInbox()
  }

  func snapshot(now: Date) -> Snapshot {
    LedgerMutations.snapshot(ledger: ledger, now: now, calendar: .current)
  }

  func toggle(_ kind: Kind) {
    ledger = LedgerMutations.toggle(kind, on: ledger, now: Date())
    ledger.save(to: defaults)
  }

  func tabDay(now: Date) -> TabDay {
    TabLogMutations.day(log: tabLog, now: now, calendar: .current)
  }

  func rate(_ id: UUID, _ verdict: Verdict?) {
    tabLog = TabLogMutations.rate(id, verdict, on: tabLog)
    tabLog.save(to: defaults)
  }

  // false in unsigned builds, where the browser bridge has nowhere to drop events
  var bridgeReady: Bool {
    GroupContainer.inbox != nil
  }

  var askAfterEachTab: Bool {
    get { prompt.enabled }
    set {
      objectWillChange.send()
      prompt.enabled = newValue
    }
  }

  func ingestInbox() {
    guard let inbox = GroupContainer.inbox else {
      return
    }
    let files = Inbox.pending(in: inbox)
    guard !files.isEmpty else {
      return
    }
    let result = TabLogMutations.apply(Inbox.read(files), to: tabLog)
    if result.log != tabLog {
      tabLog = result.log
      tabLog.save(to: defaults)
    }
    // removed only after the save, so a crash replays a batch instead of losing it
    Inbox.remove(files)
    prompt.ask(about: result.newlyClosed, now: Date())
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

  // the bridge renames each finished batch into the inbox, which writes the directory
  private func watchInbox() {
    guard let inbox = GroupContainer.inbox else {
      return
    }
    try? FileManager.default.createDirectory(at: inbox, withIntermediateDirectories: true)
    let fd = open(inbox.path, O_EVTONLY)
    guard fd >= 0 else {
      return
    }
    let source = DispatchSource.makeFileSystemObjectSource(
      fileDescriptor: fd,
      eventMask: .write,
      queue: .main
    )
    source.setEventHandler { [weak self] in
      MainActor.assumeIsolated {
        self?.ingestInbox()
      }
    }
    source.setCancelHandler {
      close(fd)
    }
    source.resume()
    inboxWatcher = source

    let active = NotificationCenter.default.addObserver(
      forName: NSApplication.didBecomeActiveNotification,
      object: nil,
      queue: .main
    ) { [weak self] _ in
      MainActor.assumeIsolated {
        self?.ingestInbox()
      }
    }
    observers.append(active)
  }
}
