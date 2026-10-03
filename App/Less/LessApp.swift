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
    if snap.run != nil {
      return "● \(snap.ratioLine)"
    }
    return snap.ratioLine
  }
}

private struct ExtraMenu: View {
  @EnvironmentObject private var model: AppModel
  @Environment(\.openWindow) private var openWindow

  var body: some View {
    let snap = model.snapshot(now: Date())
    Text(snap.ratioLine)
    Text("create \(LedgerMutations.formatDuration(snap.create))")
    Text("consume \(LedgerMutations.formatDuration(snap.consume))")
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
}
