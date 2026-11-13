import SwiftUI
import WidgetKit

/// Lock Screen widget: today's time per group, rounded to the nearest minute.
struct TodayTotalsWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: TodaySnapshot.widgetKind, provider: TodayTotalsProvider()) { entry in
            TodayTotalsView(entry: entry)
                .containerBackground(.clear, for: .widget)
                .widgetURL(timersScreenURL)
        }
        .configurationDisplayName("Today's Totals")
        .description("Time spent today in each group.")
        .supportedFamilies([.accessoryRectangular, .accessoryInline])
    }
}

struct TodayTotalsEntry: TimelineEntry {
    let date: Date
    let snapshot: TodaySnapshot?
}

struct TodayTotalsProvider: TimelineProvider {
    func placeholder(in context: Context) -> TodayTotalsEntry {
        TodayTotalsEntry(date: .now, snapshot: .sample)
    }

    func getSnapshot(in context: Context, completion: @escaping (TodayTotalsEntry) -> Void) {
        completion(TodayTotalsEntry(date: .now, snapshot: TodaySnapshot.load() ?? .sample))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<TodayTotalsEntry>) -> Void) {
        let now = Date()
        let snapshot = TodaySnapshot.load()
        let midnight = Calendar.current.date(byAdding: .day, value: 1, to: Calendar.current.startOfDay(for: now))!
        var dates = [now]

        if let snapshot, let running = snapshot.runningGroupId {
            // The displayed (rounded) minutes change each time the running group's
            // total crosses N:30. Schedule an entry at each of those moments for the
            // next two hours, then ask for a new timeline.
            let total = snapshot.seconds(for: running, at: now)
            var next = now.addingTimeInterval(((total - 30) / 60).rounded(.down) * 60 + 90 - total)
            while next < now.addingTimeInterval(2 * 3600) {
                dates.append(next)
                next.addTimeInterval(60)
            }
            dates.append(midnight)
            dates = dates.filter { $0 <= midnight }.sorted()
            let entries = dates.map { TodayTotalsEntry(date: $0, snapshot: snapshot) }
            completion(Timeline(entries: entries, policy: .after(dates.last!)))
        } else {
            // Nothing running: totals only change at midnight (reset to 0) or when
            // the app writes a new snapshot and reloads the widget.
            dates.append(midnight)
            let entries = dates.map { TodayTotalsEntry(date: $0, snapshot: snapshot) }
            completion(Timeline(entries: entries, policy: .after(midnight)))
        }
    }
}

struct TodayTotalsView: View {
    let entry: TodayTotalsEntry
    @Environment(\.widgetFamily) private var family

    var body: some View {
        if let snapshot = entry.snapshot, !snapshot.groups.isEmpty {
            switch family {
            case .accessoryInline:
                Text(snapshot.groups.map { "\($0.name) \(time($0, snapshot))" }.joined(separator: " · "))
            default:
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(snapshot.groups.prefix(3)) { group in
                        HStack(spacing: 4) {
                            if group.id == snapshot.runningGroupId {
                                Image(systemName: "play.fill")
                                    .font(.caption2)
                            }
                            Text(group.name)
                                .fontWeight(group.id == snapshot.runningGroupId ? .semibold : .regular)
                                .lineLimit(1)
                            Spacer(minLength: 6)
                            Text(time(group, snapshot))
                                .monospacedDigit()
                                .fontWeight(.semibold)
                        }
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            }
        } else {
            Text(entry.snapshot == nil ? "Open GoodBadTime to start tracking" : "No groups shown. Choose some in Settings.")
                .font(.caption)
        }
    }

    private func time(_ group: TodaySnapshot.Group, _ snapshot: TodaySnapshot) -> String {
        formatRoundedMinutes(snapshot.seconds(for: group.id, at: entry.date))
    }
}

private extension TodaySnapshot {
    static let sample = TodaySnapshot(
        day: Calendar.current.startOfDay(for: .now),
        groups: [
            .init(id: "a", name: "Bad", finishedSeconds: 83.0 * 60),
            .init(id: "b", name: "Good", finishedSeconds: 45.0 * 60),
        ],
        runningGroupId: nil,
        runningStartedAt: nil
    )
}

#Preview(as: .accessoryRectangular) {
    TodayTotalsWidget()
} timeline: {
    TodayTotalsEntry(date: .now, snapshot: .sample)
}
