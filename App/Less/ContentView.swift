import SwiftUI

struct ContentView: View {
  @EnvironmentObject private var model: AppModel

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
