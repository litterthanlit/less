import Foundation
import XCTest
@testable import LessCore

final class BridgeTests: XCTestCase {
  private let id = UUID(uuidString: "6F1C2A3B-0000-4000-8000-000000000001")!

  private func makeDirectory() throws -> URL {
    let url = FileManager.default.temporaryDirectory
      .appendingPathComponent("less-inbox-\(UUID().uuidString)")
    addTeardownBlock {
      try? FileManager.default.removeItem(at: url)
    }
    return url
  }

  func testDecodesRequestFromTheExtension() throws {
    let json = #"""
      {"v":1,"events":[
        {"type":"open","id":"6f1c2a3b-0000-4000-8000-000000000001","at":1790000000123,
         "url":"https://x.com/home","title":"Home / X"}
      ]}
      """#
    let events = try Bridge.decodeRequest(Data(json.utf8))
    XCTAssertEqual(
      events,
      [
        BridgeEvent(
          type: .open,
          id: id,
          at: Date(timeIntervalSince1970: 1_790_000_000.123),
          url: "https://x.com/home",
          title: "Home"
        )
      ]
    )
  }

  func testRequestStripsQueriesTitlesAndOtherSites() throws {
    let json = #"""
      {"v":1,"events":[
        {"type":"open","id":"6f1c2a3b-0000-4000-8000-000000000001","at":1790000000000,
         "url":"https://mobile.twitter.com/someone/status/5?s=20#top","title":"(4) Post / X"},
        {"type":"close","id":"6f1c2a3b-0000-4000-8000-000000000001","at":1790000000000,
         "url":"https://mail.example/inbox?token=secret"}
      ]}
      """#
    let events = try Bridge.decodeRequest(Data(json.utf8))
    XCTAssertEqual(events.map(\.url), ["https://x.com/someone/status/5", nil])
    XCTAssertEqual(events.map(\.title), ["Post", nil])
  }

  func testRequestKeepsReadableEventsAndDropsBadOnes() throws {
    let json = #"""
      {"v":1,"events":[
        {"type":"open","id":"6f1c2a3b-0000-4000-8000-000000000001","at":1790000000000},
        {"type":"scroll","id":"6f1c2a3b-0000-4000-8000-000000000002","at":1790000000000},
        {"type":"close","id":"not-a-uuid","at":1790000000000},
        null,
        {"type":"close","id":"6f1c2a3b-0000-4000-8000-000000000001","at":1790000060000}
      ]}
      """#
    let events = try Bridge.decodeRequest(Data(json.utf8))
    XCTAssertEqual(events.map(\.type), [.open, .close])
  }

  func testPingWithoutEventsDecodesToNothing() throws {
    XCTAssertEqual(try Bridge.decodeRequest(Data(#"{"v":1}"#.utf8)), [])
    XCTAssertEqual(try Bridge.decodeRequest(Data(#"{"v":1,"events":[]}"#.utf8)), [])
  }

  func testRejectsGarbageAndOtherVersions() {
    XCTAssertThrowsError(try Bridge.decodeRequest(Data("nope".utf8))) { error in
      XCTAssertEqual(error as? Bridge.RequestError, .unreadable)
    }
    XCTAssertThrowsError(try Bridge.decodeRequest(Data(#"{"v":2,"events":[]}"#.utf8))) { error in
      XCTAssertEqual(error as? Bridge.RequestError, .unsupportedVersion(2))
    }
  }

  func testFrameRoundTripsLength() {
    let payload = Data(#"{"ok":true,"accepted":3}"#.utf8)
    let framed = Bridge.frame(payload)
    XCTAssertEqual(framed.count, payload.count + 4)
    XCTAssertEqual(Array(framed.prefix(4)), [UInt8(payload.count), 0, 0, 0])
    XCTAssertEqual(Bridge.length(fromHeader: framed), payload.count)
    XCTAssertEqual(framed.dropFirst(4), payload)
  }

  func testLengthReadsLittleEndianAndNeedsFourBytes() {
    XCTAssertEqual(Bridge.length(fromHeader: Data([0x00, 0x01, 0x00, 0x00])), 256)
    XCTAssertEqual(Bridge.length(fromHeader: Data([0xFF, 0xFF, 0xFF, 0xFF])), 4_294_967_295)
    XCTAssertNil(Bridge.length(fromHeader: Data([0x01, 0x00])))
  }

  func testRecognizesXHosts() {
    for host in ["x.com", "X.com", "mobile.x.com", "twitter.com", "www.twitter.com"] {
      XCTAssertTrue(Bridge.isXHost(host), host)
    }
    for host in ["notx.com", "x.co", "twitter.com.evil.io", "xcom", ""] {
      XCTAssertFalse(Bridge.isXHost(host), host)
    }
  }

  func testXPathDropsQueryFragmentAndOtherSites() {
    XCTAssertEqual(Bridge.xPath(of: "https://x.com/someone/status/1?s=20&t=abc#reply"), "/someone/status/1")
    XCTAssertEqual(Bridge.xPath(of: "https://x.com"), "/")
    XCTAssertEqual(Bridge.xPath(of: "http://twitter.com/home"), "/home")
    XCTAssertNil(Bridge.xPath(of: "https://example.com/x.com"))
    XCTAssertNil(Bridge.xPath(of: "chrome://newtab"))
    XCTAssertNil(Bridge.xPath(of: "javascript://x.com/%0aalert(1)"))
    XCTAssertNil(Bridge.xPath(of: nil))
  }

  func testCleanTitleStripsCounterAndSiteSuffix() {
    XCTAssertEqual(Bridge.cleanTitle("(3) Home / X"), "Home")
    XCTAssertEqual(Bridge.cleanTitle("Someone on X: \"hi\" / X"), "Someone on X: \"hi\"")
    XCTAssertEqual(Bridge.cleanTitle("(12) Explore / Twitter"), "Explore")
    XCTAssertEqual(Bridge.cleanTitle("(beta) notes"), "(beta) notes")
    XCTAssertNil(Bridge.cleanTitle("  "))
    XCTAssertNil(Bridge.cleanTitle(nil))
    let long = String(repeating: "a", count: 500)
    XCTAssertEqual(Bridge.cleanTitle(long)?.count, Bridge.maxTitleLength)
  }

  func testReplyEncodesForTheExtension() throws {
    let data = try Bridge.encoder.encode(BridgeReply(ok: true, accepted: 2))
    XCTAssertEqual(String(decoding: data, as: UTF8.self), #"{"accepted":2,"ok":true}"#)
  }

  func testInboxWritesFinishedFilesThatReadBack() throws {
    let dir = try makeDirectory()
    let events = [
      BridgeEvent(type: .open, id: id, at: Date(timeIntervalSince1970: 1_790_000_000), url: "https://x.com/home"),
      BridgeEvent(type: .close, id: id, at: Date(timeIntervalSince1970: 1_790_000_090)),
    ]
    let first = try Inbox.write(events, to: dir, now: Date(timeIntervalSince1970: 1_790_000_100))
    let second = try Inbox.write([events[1]], to: dir, now: Date(timeIntervalSince1970: 1_790_000_200))
    XCTAssertNil(try Inbox.write([], to: dir, now: Date()))

    let pending = Inbox.pending(in: dir)
    XCTAssertEqual(pending.map(\.lastPathComponent), [first, second].compactMap { $0?.lastPathComponent })
    XCTAssertEqual(Inbox.read(pending), events + [events[1]])

    let names = try FileManager.default.contentsOfDirectory(atPath: dir.path)
    XCTAssertFalse(names.contains { $0.hasSuffix(".tmp") })

    Inbox.remove(pending)
    XCTAssertEqual(Inbox.pending(in: dir), [])
  }

  func testInboxIgnoresTempFilesAndSkipsBadLines() throws {
    let dir = try makeDirectory()
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    try Data("{}\n".utf8).write(to: dir.appendingPathComponent(".half.tmp"))
    let good = #"{"type":"close","id":"6f1c2a3b-0000-4000-8000-000000000001","at":1790000000000}"#
    let body = "garbage\n\(good)\n{\"type\":\"open\"}\n"
    try Data(body.utf8).write(to: dir.appendingPathComponent("1-a.jsonl"))

    let pending = Inbox.pending(in: dir)
    XCTAssertEqual(pending.map(\.lastPathComponent), ["1-a.jsonl"])
    XCTAssertEqual(Inbox.read(pending).map(\.id), [id])
  }

  func testPendingInMissingDirectoryIsEmpty() throws {
    XCTAssertEqual(Inbox.pending(in: try makeDirectory()), [])
  }
}
