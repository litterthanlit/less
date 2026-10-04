import AppKit
import SwiftUI

@main
struct LessApp: App {
  @StateObject private var model = AppModel()

  var body: some Scene {
    Window("less", id: "main") {
      ContentView()
        .environmentObject(model)
        .frame(minWidth: 400, minHeight: 640)
    }
    .defaultSize(width: 480, height: 720)

    Window("X today", id: "x-review") {
      TabReviewView()
        .environmentObject(model)
        .frame(minWidth: 380, minHeight: 420)
    }
    .defaultSize(width: 460, height: 600)

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
  @Environment(\.openWindow) private var openWindow

  var body: some View {
    TimelineView(.periodic(from: .now, by: 1)) { context in
      let snap = model.snapshot(now: context.date)
      Text(title(snap))
        .monospacedDigit()
    }
    // the menu bar label always exists, so it opens the review for notification taps
    .onChange(of: model.reviewRequests) {
      NSApp.activate()
      openWindow(id: "x-review")
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
    let day = model.tabDay(now: Date())
    Text(day.unrated > 0 ? "X tabs today: \(day.opened) · \(day.unrated) to rate" : "X tabs today: \(day.opened)")
    Button("Review X tabs…") {
      NSApp.activate()
      openWindow(id: "x-review")
    }
    Toggle(
      "Ask after each X tab",
      isOn: Binding(
        get: { model.askAfterEachTab },
        set: { model.askAfterEachTab = $0 }
      )
    )
    Divider()
    Button("Open less") {
      NSApp.activate()
      openWindow(id: "main")
    }
  }
}
