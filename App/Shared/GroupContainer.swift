import Foundation
import Security

// the App Group both less and less-bridge are signed with; nil in unsigned builds
enum GroupContainer {
  private static let entitlement = "com.apple.security.application-groups"

  // entitlements are fixed at signing, so both are read once
  static let identifier: String? = {
    guard
      let task = SecTaskCreateFromSelf(nil),
      let groups = SecTaskCopyValueForEntitlement(task, entitlement as CFString, nil) as? [String]
    else {
      return nil
    }
    return groups.first
  }()

  static let inbox: URL? = {
    guard
      let identifier,
      let container = FileManager.default.containerURL(
        forSecurityApplicationGroupIdentifier: identifier
      )
    else {
      return nil
    }
    return container
      .appendingPathComponent("Library/Application Support/less/inbox", isDirectory: true)
  }()
}
