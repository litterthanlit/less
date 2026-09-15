import AppKit
import SwiftUI

@main
struct LessApp: App {
  @StateObject private var model = AppModel()

  var body: some Scene {
    WindowGroup("less", id: "main") {
      ContentView()
        .environmentObject(model)
        .frame(minWidth: 400, minHeight: 520)
    }
    .defaultSize(width: 480, height: 620)

    MenuBarExtra {
      ExtraMenu()
        .environmentObject(model)
    } label: {
      ExtraLabel()
        .environmentObject(model)
    }
  }
}

private struct ExtraLabel: View {
  @EnvironmentObject private var model: AppModel

  var body: some View {
    TimelineView(.periodic(from: .now, by: 1)) { context in
      let snap = model.snapshot(now: context.date)
      Text(title(snap))
    }
  }

  private func title(_ snap: Snapshot) -> String {
    let line = LedgerMutations.ratioLine(
      createPart: snap.createPart,
      consumePart: snap.consumePart
    )
    if snap.run != nil {
      return "● \(line)"
    }
    return line
  }
}

private struct ExtraMenu: View {
  @EnvironmentObject private var model: AppModel
  @Environment(\.openWindow) private var openWindow

  var body: some View {
    Text(ratioLine)
    Text("create \(createDuration)")
    Text("consume \(consumeDuration)")
    Divider()
    Button(model.createButtonTitle) {
      model.toggle(.create)
    }
    Button(model.consumeButtonTitle) {
      model.toggle(.consume)
    }
    Divider()
    Button("Open less") {
      NSApp.activate(ignoringOtherApps: true)
      openWindow(id: "main")
    }
  }

  private var snap: Snapshot {
    model.snapshot(now: Date())
  }

  private var ratioLine: String {
    LedgerMutations.ratioLine(createPart: snap.createPart, consumePart: snap.consumePart)
  }

  private var createDuration: String {
    LedgerMutations.formatDuration(snap.create)
  }

  private var consumeDuration: String {
    LedgerMutations.formatDuration(snap.consume)
  }
}
