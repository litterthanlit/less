import Foundation

// Chrome starts this per message and talks length-prefixed JSON over stdin and stdout.
// Each batch lands in the shared inbox as one finished file for less to pick up.

let input = FileHandle.standardInput
let output = FileHandle.standardOutput

func readExactly(_ count: Int) -> Data? {
  var data = Data()
  while data.count < count {
    let chunk = input.readData(ofLength: count - data.count)
    if chunk.isEmpty {
      return nil
    }
    data.append(chunk)
  }
  return data
}

func reply(_ reply: BridgeReply) {
  guard let payload = try? Bridge.encoder.encode(reply) else {
    return
  }
  output.write(Bridge.frame(payload))
}

while let header = readExactly(4), let length = Bridge.length(fromHeader: header) {
  guard length <= Bridge.maxMessageBytes else {
    reply(BridgeReply(ok: false, accepted: 0, error: "message too large"))
    exit(1)
  }
  guard let body = readExactly(length) else {
    break
  }
  do {
    let events = try Bridge.decodeRequest(body)
    guard let inbox = GroupContainer.inbox else {
      reply(BridgeReply(ok: false, accepted: 0, error: "less is not signed with its App Group"))
      continue
    }
    try Inbox.write(events, to: inbox, now: Date())
    reply(BridgeReply(ok: true, accepted: events.count))
  } catch {
    reply(BridgeReply(ok: false, accepted: 0, error: String(describing: error)))
  }
}
