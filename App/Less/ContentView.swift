import AppKit
import SwiftUI

struct ContentView: View {
  @EnvironmentObject private var model: AppModel
  @Environment(\.openWindow) private var openWindow

  var body: some View {
    TimelineView(.periodic(from: .now, by: 1)) { context in
      let snap = model.snapshot(now: context.date)
      ZStack {
        Color.black.ignoresSafeArea()
        VStack(spacing: 28) {
          Spacer()
          Text(snap.ratioLine)
            .font(.system(size: 96, weight: .ultraLight))
            .foregroundStyle(.white)
            .monospacedDigit()
            .minimumScaleFactor(0.4)
            .lineLimit(1)
          HStack(spacing: 36) {
            word("CREATE", own: snap.create, other: snap.consume)
            word("CONSUME", own: snap.consume, other: snap.create)
          }
          HStack(spacing: 56) {
            durationColumn(
              value: LedgerMutations.formatDuration(snap.create),
              label: "create"
            )
            durationColumn(
              value: LedgerMutations.formatDuration(snap.consume),
              label: "consume"
            )
          }
          HStack(spacing: 12) {
            kindButton("Create", kind: .create, active: snap.run?.kind == .create)
            kindButton("Consume", kind: .consume, active: snap.run?.kind == .consume)
          }
          .padding(.top, 8)
          Text(statusText(snap.run))
            .font(.system(size: 13, weight: .ultraLight))
            .foregroundStyle(Color.white.opacity(0.45))
            .padding(.top, 4)
          tabStrip(model.tabDay(now: context.date), limit: model.tabLimit)
            .padding(.top, 20)
          Spacer()
        }
        .padding(.horizontal, 36)
        .padding(.vertical, 24)
      }
    }
    .preferredColorScheme(.dark)
  }

  private func word(_ title: String, own: TimeInterval, other: TimeInterval) -> some View {
    let lead = own > other
    let even = own == other
    return Text(title)
      .font(.system(size: 13, weight: lead ? .semibold : .ultraLight))
      .tracking(3)
      .foregroundStyle(Color.white.opacity(lead ? 1 : (even ? 0.7 : 0.32)))
  }

  private func durationColumn(value: String, label: String) -> some View {
    VStack(spacing: 6) {
      Text(value)
        .font(.system(size: 20, weight: .light).monospacedDigit())
        .foregroundStyle(.white)
      Text(label)
        .font(.system(size: 11, weight: .ultraLight))
        .tracking(1.5)
        .foregroundStyle(Color.white.opacity(0.4))
    }
  }

  private func kindButton(_ title: String, kind: Kind, active: Bool) -> some View {
    Button {
      model.toggle(kind)
    } label: {
      Text(title)
        .font(.system(size: 16, weight: .regular))
        .frame(maxWidth: .infinity, minHeight: 52)
        .foregroundStyle(active ? Color.black : Color.white)
        .background(active ? Color.white : Color.clear)
        .overlay {
          Rectangle()
            .stroke(Color.white, lineWidth: 1)
        }
        .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
  }

  // today's X tabs sit under the ratio: present, but quieter than it
  private func tabStrip(_ day: TabDay, limit: Int?) -> some View {
    let over = TabLimit.isOver(opened: day.opened, limit: limit)
    let count = TabLimit.countLine(opened: day.opened, limit: limit)
    return VStack(spacing: 18) {
      Rectangle()
        .fill(Color.white.opacity(0.12))
        .frame(height: 1)
      HStack(alignment: .center, spacing: 16) {
        VStack(alignment: .leading, spacing: 6) {
          Text("X TODAY")
            .font(.system(size: 11, weight: .ultraLight))
            .tracking(1.5)
            .foregroundStyle(Color.white.opacity(0.4))
          // past the limit the count takes the same semibold a leading CREATE or CONSUME gets
          Text(count)
            .font(.system(size: 20, weight: over ? .semibold : .light).monospacedDigit())
            .foregroundStyle(.white)
          Text(tabHint(day))
            .font(.system(size: 13, weight: .ultraLight))
            .foregroundStyle(Color.white.opacity(0.45))
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("X today: \(count)\(over ? ", past your limit" : ""). \(tabHint(day))")
        Spacer(minLength: 0)
        Button {
          NSApp.activate()
          openWindow(id: "x-review")
        } label: {
          Text(day.unrated > 0 ? "Rate \(day.unrated)" : "Review")
            .font(.system(size: 14, weight: .regular))
            .frame(minWidth: 92, minHeight: 36)
            .padding(.horizontal, 6)
            .foregroundStyle(.white)
            .overlay {
              Rectangle()
                .stroke(Color.white.opacity(day.unrated > 0 ? 1 : 0.4), lineWidth: 1)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(day.unrated > 0 ? "Rate \(day.unrated) X tabs" : "Review X tabs")
      }
    }
  }

  private func tabHint(_ day: TabDay) -> String {
    if day.opened == 0 && !model.bridgeReady {
      return "sign less to connect the extension"
    }
    return day.breakdownLine
  }

  private func statusText(_ run: Run?) -> String {
    switch run?.kind {
    case .create:
      return "creating"
    case .consume:
      return "consuming"
    case nil:
      return "idle"
    }
  }
}
