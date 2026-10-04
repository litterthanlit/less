import Foundation

public enum BridgeEventType: String, Codable, Sendable {
  case open
  case close
}

// one tab landing on X (open) or leaving it (close), as the browser extension saw it
public struct BridgeEvent: Codable, Equatable, Sendable {
  public var type: BridgeEventType
  public var id: UUID
  public var at: Date
  public var url: String?
  public var title: String?

  public init(type: BridgeEventType, id: UUID, at: Date, url: String? = nil, title: String? = nil) {
    self.type = type
    self.id = id
    self.at = at
    self.url = url
    self.title = title
  }
}

public struct BridgeReply: Codable, Equatable, Sendable {
  public var ok: Bool
  public var accepted: Int
  public var error: String?

  public init(ok: Bool, accepted: Int, error: String? = nil) {
    self.ok = ok
    self.accepted = accepted
    self.error = error
  }
}

public enum Bridge {
  public static let hostName = "app.less.bridge"
  public static let protocolVersion = 1
  // Chrome caps host-bound messages far higher; the extension sends small batches
  public static let maxMessageBytes = 1 << 20
  public static let maxTitleLength = 200

  public static var encoder: JSONEncoder {
    let encoder = JSONEncoder()
    encoder.dateEncodingStrategy = .millisecondsSince1970
    encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
    return encoder
  }

  public static var decoder: JSONDecoder {
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .millisecondsSince1970
    return decoder
  }

  private struct Request: Decodable {
    let v: Int
    let events: [Lossy<BridgeEvent>]?
  }

  public enum RequestError: Error, Equatable {
    case unreadable
    case unsupportedVersion(Int)
  }

  // keeps every readable event so one bad entry never drops the batch
  public static func decodeRequest(_ data: Data) throws -> [BridgeEvent] {
    guard let request = try? decoder.decode(Request.self, from: data) else {
      throw RequestError.unreadable
    }
    guard request.v == protocolVersion else {
      throw RequestError.unsupportedVersion(request.v)
    }
    return (request.events ?? []).compactMap(\.value)
  }

  // native messaging frames each message with a 32-bit length in native (little-endian on Mac) order
  public static func frame(_ payload: Data) -> Data {
    var length = UInt32(payload.count).littleEndian
    var framed = Data(bytes: &length, count: 4)
    framed.append(payload)
    return framed
  }

  public static func length(fromHeader header: Data) -> Int? {
    let bytes = Array(header.prefix(4))
    guard bytes.count == 4 else {
      return nil
    }
    let value = UInt32(bytes[0])
      | UInt32(bytes[1]) << 8
      | UInt32(bytes[2]) << 16
      | UInt32(bytes[3]) << 24
    return Int(value)
  }

  public static func isXHost(_ host: String) -> Bool {
    let host = host.lowercased()
    return ["x.com", "twitter.com"].contains { host == $0 || host.hasSuffix(".\($0)") }
  }

  // the X path only: no query, no fragment, nothing from other sites
  public static func xPath(of urlString: String?) -> String? {
    guard
      let urlString,
      let components = URLComponents(string: urlString),
      let scheme = components.scheme?.lowercased(),
      scheme == "https" || scheme == "http",
      let host = components.host,
      isXHost(host)
    else {
      return nil
    }
    let path = components.path
    return path.isEmpty ? "/" : path
  }

  // "(3) Someone on X: "hello" / X" reads better as "Someone on X: "hello""
  public static func cleanTitle(_ title: String?) -> String? {
    guard var text = title?.trimmingCharacters(in: .whitespacesAndNewlines) else {
      return nil
    }
    if text.hasPrefix("("), let close = text.firstIndex(of: ")") {
      let inside = text[text.index(after: text.startIndex)..<close]
      if !inside.isEmpty, inside.allSatisfy(\.isNumber) {
        text = String(text[text.index(after: close)...]).trimmingCharacters(in: .whitespaces)
      }
    }
    for suffix in [" / X", " / Twitter"] where text.hasSuffix(suffix) {
      text = String(text.dropLast(suffix.count)).trimmingCharacters(in: .whitespaces)
    }
    if text.count > maxTitleLength {
      text = String(text.prefix(maxTitleLength - 1)) + "…"
    }
    return text.isEmpty ? nil : text
  }
}

// the helper drops one finished file per batch; the app reads and then removes them
public enum Inbox {
  public static let fileExtension = "jsonl"

  @discardableResult
  public static func write(
    _ events: [BridgeEvent],
    to directory: URL,
    now: Date,
    fileManager: FileManager = .default
  ) throws -> URL? {
    guard !events.isEmpty else {
      return nil
    }
    try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
    var data = Data()
    for event in events {
      data.append(try Bridge.encoder.encode(event))
      data.append(0x0A)
    }
    let name = "\(Int64(now.timeIntervalSince1970 * 1000))-\(UUID().uuidString)"
    let temp = directory.appendingPathComponent(".\(name).tmp")
    let final = directory.appendingPathComponent(name).appendingPathExtension(fileExtension)
    try data.write(to: temp)
    // a rename inside one directory is atomic, so the app never sees half a file
    try fileManager.moveItem(at: temp, to: final)
    return final
  }

  public static func pending(in directory: URL, fileManager: FileManager = .default) -> [URL] {
    let urls = (try? fileManager.contentsOfDirectory(
      at: directory,
      includingPropertiesForKeys: nil
    )) ?? []
    return urls
      .filter { $0.pathExtension == fileExtension && !$0.lastPathComponent.hasPrefix(".") }
      .sorted { $0.lastPathComponent < $1.lastPathComponent }
  }

  public static func parse(_ data: Data) -> [BridgeEvent] {
    let decoder = Bridge.decoder
    return data.split(separator: 0x0A).compactMap { line in
      try? decoder.decode(BridgeEvent.self, from: Data(line))
    }
  }

  public static func read(_ files: [URL]) -> [BridgeEvent] {
    files.flatMap { url in
      (try? Data(contentsOf: url)).map(parse) ?? []
    }
  }

  public static func remove(_ files: [URL], fileManager: FileManager = .default) {
    for url in files {
      try? fileManager.removeItem(at: url)
    }
  }
}
