import Foundation
import XCTest
@testable import LessCore

final class TabLimitTests: XCTestCase {
  private func makeDefaults() -> UserDefaults {
    let name = "app.less.tests.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: name)!
    defaults.removePersistentDomain(forName: name)
    addTeardownBlock {
      defaults.removePersistentDomain(forName: name)
    }
    return defaults
  }

  func testDefaultsToTenWhenNothingIsStored() {
    XCTAssertEqual(TabLimit.load(from: makeDefaults()), 10)
  }

  func testSaveAndLoadAChoice() {
    let defaults = makeDefaults()
    TabLimit.save(5, to: defaults)
    XCTAssertEqual(TabLimit.load(from: defaults), 5)
  }

  func testTurningItOffSticks() {
    let defaults = makeDefaults()
    TabLimit.save(nil, to: defaults)
    XCTAssertNil(TabLimit.load(from: defaults))
    XCTAssertEqual(defaults.object(forKey: TabLimit.storageKey) as? Int, 0)
  }

  func testNonsenseStoredValuesMeanOffOrDefault() {
    let defaults = makeDefaults()
    defaults.set(-4, forKey: TabLimit.storageKey)
    XCTAssertNil(TabLimit.load(from: defaults))
    defaults.set("ten", forKey: TabLimit.storageKey)
    XCTAssertEqual(TabLimit.load(from: defaults), 10)
    TabLimit.save(-3, to: defaults)
    XCTAssertNil(TabLimit.load(from: defaults))
  }

  func testOverOnlyAfterPassingTheLimit() {
    XCTAssertFalse(TabLimit.isOver(opened: 9, limit: 10))
    XCTAssertFalse(TabLimit.isOver(opened: 10, limit: 10))
    XCTAssertTrue(TabLimit.isOver(opened: 11, limit: 10))
    XCTAssertFalse(TabLimit.isOver(opened: 500, limit: nil))
  }

  func testCountLine() {
    XCTAssertEqual(TabLimit.countLine(opened: 0, limit: 10), "0 of 10 tabs")
    XCTAssertEqual(TabLimit.countLine(opened: 10, limit: 10), "10 of 10 tabs")
    XCTAssertEqual(TabLimit.countLine(opened: 12, limit: 10), "12 tabs · 2 over")
    XCTAssertEqual(TabLimit.countLine(opened: 1, limit: nil), "1 tab")
    XCTAssertEqual(TabLimit.countLine(opened: 7, limit: nil), "7 tabs")
  }

  func testMenuBarText() {
    XCTAssertNil(TabLimit.menuBarText(opened: 0, limit: 10))
    XCTAssertEqual(TabLimit.menuBarText(opened: 7, limit: 10), "X 7/10")
    XCTAssertEqual(TabLimit.menuBarText(opened: 12, limit: 10), "X 12/10")
    XCTAssertEqual(TabLimit.menuBarText(opened: 3, limit: nil), "X 3")
  }
}
