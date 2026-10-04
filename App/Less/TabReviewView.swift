import SwiftUI

// today's X tabs, newest first, each one click away from an honest answer
struct TabReviewView: View {
  @EnvironmentObject private var model: AppModel

  var body: some View {
    TimelineView(.periodic(from: .now, by: 30)) { context in
      let day = model.tabDay(now: context.date)
      ZStack {
        Color.black.ignoresSafeArea()
        VStack(alignment: .leading, spacing: 0) {
          header(day, limit: model.tabLimit)
            .padding(.horizontal, 28)
            .padding(.top, 28)
            .padding(.bottom, 22)
          hairline
          if day.visits.isEmpty {
            emptyState
          } else {
            ScrollView {
              LazyVStack(spacing: 0) {
                ForEach(day.visits) { visit in
                  row(visit, now: context.date)
                  hairline
                }
              }
            }
          }
        }
      }
    }
    .preferredColorScheme(.dark)
  }

  private func header(_ day: TabDay, limit: Int?) -> some View {
    let over = TabLimit.isOver(opened: day.opened, limit: limit)
    let count = TabLimit.countLine(opened: day.opened, limit: limit)
    return VStack(alignment: .leading, spacing: 8) {
      Text("X TODAY")
        .font(.system(size: 11, weight: .ultraLight))
        .tracking(1.5)
        .foregroundStyle(Color.white.opacity(0.4))
      Text(count)
        .font(.system(size: 44, weight: over ? .regular : .ultraLight))
        .monospacedDigit()
        .foregroundStyle(.white)
      Text(day.breakdownLine)
        .font(.system(size: 13, weight: .ultraLight))
        .foregroundStyle(Color.white.opacity(0.45))
    }
    .accessibilityElement(children: .ignore)
    .accessibilityLabel("X today: \(count)\(over ? ", past your limit" : ""). \(day.breakdownLine)")
  }

  private var emptyState: some View {
    VStack(spacing: 8) {
      Spacer()
      Text("No X tabs yet today.")
        .font(.system(size: 16, weight: .light))
        .foregroundStyle(Color.white.opacity(0.7))
      Text(model.bridgeReady ? "Keep it that way." : "Sign less in Xcode, then connect the extension.")
        .font(.system(size: 13, weight: .ultraLight))
        .foregroundStyle(Color.white.opacity(0.45))
      Spacer()
    }
    .frame(maxWidth: .infinity)
  }

  private var hairline: some View {
    Rectangle()
      .fill(Color.white.opacity(0.12))
      .frame(height: 1)
  }

  private func row(_ visit: Visit, now: Date) -> some View {
    let rated = visit.verdict != nil
    let name = visit.title ?? visit.path ?? "x.com"
    let stay = TabLogMutations.formatStay(visit.duration(now: now))
    let still = visit.closedAt == nil ? " · open" : ""
    return HStack(alignment: .center, spacing: 16) {
      VStack(alignment: .leading, spacing: 5) {
        Text(name)
          .font(.system(size: 14, weight: .regular))
          .foregroundStyle(Color.white.opacity(rated ? 0.45 : 1))
          .lineLimit(2)
          .truncationMode(.tail)
        HStack(spacing: 0) {
          Text(visit.openedAt, format: .dateTime.hour().minute())
          Text(" · \(stay)\(still)")
        }
        .font(.system(size: 11, weight: .ultraLight).monospacedDigit())
        .foregroundStyle(Color.white.opacity(0.4))
      }
      .accessibilityElement(children: .ignore)
      .accessibilityLabel(rowLabel(visit, name: name, stay: stay))
      Spacer(minLength: 8)
      verdictControl(visit)
    }
    .padding(.horizontal, 28)
    .padding(.vertical, 14)
  }

  // two joined square segments; the chosen one inverts like an active Create button
  private func verdictControl(_ visit: Visit) -> some View {
    HStack(spacing: 0) {
      segment("Useful", spoken: "Useful", verdict: .useful, visit: visit)
      Rectangle()
        .fill(Color.white.opacity(0.4))
        .frame(width: 1)
      segment("Not", spoken: "Not useful", verdict: .notUseful, visit: visit)
    }
    .fixedSize()
    .overlay {
      Rectangle()
        .stroke(Color.white.opacity(visit.verdict == nil ? 1 : 0.4), lineWidth: 1)
    }
  }

  private func segment(_ title: String, spoken: String, verdict: Verdict, visit: Visit) -> some View {
    let selected = visit.verdict == verdict
    return Button {
      // choosing the same answer again clears it
      model.rate(visit.id, selected ? nil : verdict)
    } label: {
      Text(title)
        .font(.system(size: 13, weight: .regular))
        .frame(width: 64, height: 30)
        .foregroundStyle(selected ? Color.black : Color.white.opacity(visit.verdict == nil ? 1 : 0.45))
        .background(selected ? Color.white : Color.clear)
        .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
    .accessibilityLabel(spoken)
    .accessibilityAddTraits(selected ? .isSelected : [])
  }

  private func rowLabel(_ visit: Visit, name: String, stay: String) -> String {
    let time = visit.openedAt.formatted(date: .omitted, time: .shortened)
    let verdict: String
    switch visit.verdict {
    case .useful:
      verdict = "rated useful"
    case .notUseful:
      verdict = "rated not useful"
    case nil:
      verdict = "not rated"
    }
    let state = visit.closedAt == nil ? ", still open" : ""
    return "Opened \(time), \(stay)\(state), \(name), \(verdict)"
  }
}
