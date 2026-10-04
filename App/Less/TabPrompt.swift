import AppKit
import UserNotifications

// read from the nonisolated delegate callbacks, so kept outside the main-actor class
private enum PromptKeys {
  static let category = "app.less.tab"
  static let usefulAction = "useful"
  static let notUsefulAction = "notUseful"
  static let visit = "visit"
}

// asks "was that X tab useful?" right after a tab closes, with the answer one click away
@MainActor
final class TabPrompt: NSObject, UNUserNotificationCenterDelegate {
  static let enabledKey = "app.less.tabs.ask"

  // a close older than this is history, not a moment worth interrupting
  private static let recent: TimeInterval = 10 * 60
  // more than this many at once becomes one "rate them in less" nudge
  private static let maxSingles = 2

  var onRate: (@MainActor (UUID, Verdict) -> Void)?
  var onReview: (@MainActor () -> Void)?

  private let defaults: UserDefaults

  init(defaults: UserDefaults) {
    self.defaults = defaults
    super.init()
    let center = UNUserNotificationCenter.current()
    center.setNotificationCategories([
      UNNotificationCategory(
        identifier: PromptKeys.category,
        actions: [
          UNNotificationAction(identifier: PromptKeys.usefulAction, title: "Useful"),
          UNNotificationAction(identifier: PromptKeys.notUsefulAction, title: "Not useful"),
        ],
        intentIdentifiers: []
      )
    ])
    center.delegate = self
  }

  var enabled: Bool {
    get { defaults.object(forKey: Self.enabledKey) as? Bool ?? true }
    set { defaults.set(newValue, forKey: Self.enabledKey) }
  }

  func ask(about visits: [Visit], now: Date) {
    guard enabled else {
      return
    }
    let fresh = visits.filter { visit in
      visit.verdict == nil && now.timeIntervalSince(visit.closedAt ?? now) < Self.recent
    }
    guard !fresh.isEmpty else {
      return
    }
    UNUserNotificationCenter.current().requestAuthorization(options: [.alert]) { granted, _ in
      guard granted else {
        return
      }
      Task { @MainActor in
        self.post(fresh, now: now)
      }
    }
  }

  private func post(_ visits: [Visit], now: Date) {
    let center = UNUserNotificationCenter.current()
    if visits.count > Self.maxSingles {
      let content = UNMutableNotificationContent()
      content.title = "\(visits.count) X tabs closed"
      content.body = "Were they useful? Rate them in less."
      center.add(UNNotificationRequest(identifier: "app.less.tabs.batch", content: content, trigger: nil))
      return
    }
    for visit in visits {
      let content = UNMutableNotificationContent()
      content.title = "Was that X tab useful?"
      let stay = TabLogMutations.formatStay(visit.duration(now: now))
      content.body = "\(visit.title ?? visit.path ?? "x.com") · \(stay)"
      content.categoryIdentifier = PromptKeys.category
      content.userInfo = [PromptKeys.visit: visit.id.uuidString]
      center.add(UNNotificationRequest(identifier: visit.id.uuidString, content: content, trigger: nil))
    }
  }

  nonisolated func userNotificationCenter(
    _ center: UNUserNotificationCenter,
    didReceive response: UNNotificationResponse,
    withCompletionHandler completionHandler: @escaping () -> Void
  ) {
    let action = response.actionIdentifier
    let visit = (response.notification.request.content.userInfo[PromptKeys.visit] as? String)
      .flatMap(UUID.init(uuidString:))
    Task { @MainActor in
      switch (action, visit) {
      case (PromptKeys.usefulAction, let id?):
        self.onRate?(id, .useful)
      case (PromptKeys.notUsefulAction, let id?):
        self.onRate?(id, .notUseful)
      case (UNNotificationDefaultActionIdentifier, _):
        NSApp.activate()
        self.onReview?()
      default:
        break
      }
    }
    completionHandler()
  }

  // still show the question while less is the frontmost app
  nonisolated func userNotificationCenter(
    _ center: UNUserNotificationCenter,
    willPresent notification: UNNotification,
    withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
  ) {
    completionHandler([.banner, .list])
  }
}
