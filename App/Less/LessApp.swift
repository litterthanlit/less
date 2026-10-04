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
      let opened = model.tabDay(now: context.date).opened
      if let x = TabLimit.menuBarText(opened: opened, limit: model.tabLimit) {
        let over = TabLimit.isOver(opened: opened, limit: model.tabLimit)
        Image(nsImage: MenuBarText.image([(title(snap), .regular), ("  \(x)", over ? .bold : .regular)]))
          .accessibilityLabel(
            "\(title(snap)). \(TabLimit.countLine(opened: opened, limit: model.tabLimit)) on X today"
          )
      } else {
        Text(title(snap))
          .monospacedDigit()
      }
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
    let count = TabLimit.countLine(opened: day.opened, limit: model.tabLimit)
    Text(day.unrated > 0 ? "X today: \(count) · \(day.unrated) to rate" : "X today: \(count)")
    Button("Review X tabs…") {
      NSApp.activate()
      openWindow(id: "x-review")
    }
    Picker(
      "Daily X limit",
      selection: Binding(
        get: { model.tabLimit ?? 0 },
        set: { model.tabLimit = $0 > 0 ? $0 : nil }
      )
    ) {
      Text("Off").tag(0)
      ForEach(TabLimit.choices, id: \.self) { limit in
        Text("\(limit) tabs").tag(limit)
      }
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

// SwiftUI drops font weight in menu bar labels, so the label is drawn as a template
// image; macOS still tints it for light and dark menu bars
private enum MenuBarText {
  static func image(_ parts: [(String, NSFont.Weight)]) -> NSImage {
    let text = NSMutableAttributedString()
    for (string, weight) in parts {
      text.append(
        NSAttributedString(
          string: string,
          attributes: [
            .font: NSFont.monospacedDigitSystemFont(ofSize: NSFont.systemFontSize, weight: weight),
            .foregroundColor: NSColor.black,
          ]
        )
      )
    }
    let drawn = NSAttributedString(attributedString: text)
    let size = drawn.size()
    let image = NSImage(
      size: NSSize(width: ceil(size.width), height: ceil(size.height)),
      flipped: false
    ) { _ in
      drawn.draw(at: .zero)
      return true
    }
    image.isTemplate = true
    return image
  }
}
