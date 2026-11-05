import Charts
import SwiftUI

/// Average time per day in each activity over time.
struct StatsView: View {
    let timers: TimersStore

    @State private var store: StatsStore
    @AppStorage("stats.range") private var range: StatsRange = .month
    @AppStorage("stats.granularity") private var granularity: StatsGranularity = .day
    /// Comma-separated activity type ids whose lines are hidden.
    @AppStorage("stats.hidden") private var hiddenRaw = ""
    @State private var selectedDate: Date?

    init(timers: TimersStore) {
        self.timers = timers
        _store = State(initialValue: StatsStore(uid: timers.uid))
    }

    var body: some View {
        let model = Model(
            sessions: store.sessions, types: timers.types,
            range: range, granularity: granularity, now: .now
        )
        List {
            Section {
                HStack(spacing: 8) {
                    Picker("Range", selection: $range) {
                        ForEach(StatsRange.allCases) { Text($0.rawValue).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    Menu {
                        Picker("Granularity", selection: $granularity) {
                            ForEach(StatsGranularity.allCases) { Text($0.rawValue).tag($0) }
                        }
                    } label: {
                        HStack(spacing: 2) {
                            Text(granularity.shortLabel)
                            Image(systemName: "chevron.up.chevron.down").imageScale(.small)
                        }
                        .padding(.horizontal, 8)
                        .foregroundStyle(.secondary)
                    }
                    .tint(.secondary)
                    .accessibilityLabel("Granularity: \(granularity.rawValue)")
                }
            }
            .listRowBackground(Color.clear)
            .listRowInsets(EdgeInsets(top: 4, leading: 0, bottom: 4, trailing: 0))

            Section {
                if !store.loaded {
                    ProgressView().frame(maxWidth: .infinity, minHeight: 260)
                } else {
                    chart(model)
                        .frame(height: 260)
                        .padding(.vertical, 8)
                }
            } header: {
                Text("Average per day")
            }

            Section {
                ForEach(timers.types) { type in
                    legendRow(type)
                }
            } header: {
                Text("Activities")
            }
        }
        .navigationTitle("Stats")
        .navigationBarTitleDisplayMode(.inline)
        .task(id: range) { await store.listen(range: range) }
    }

    // MARK: - Chart

    private func chart(_ model: Model) -> some View {
        let visible = model.points.filter { !hidden.contains($0.typeId) }
        let unit = granularity.component
        let selectedBucket = selectedDate.flatMap { model.bucket(containing: $0) }
        let showSymbols = model.bucketCount <= 31

        return Chart {
            ForEach(visible) { p in
                LineMark(
                    x: .value("Date", p.bucketStart, unit: unit),
                    y: .value("Hours per day", p.hoursPerDay),
                    series: .value("Activity", p.typeId)
                )
                .foregroundStyle(color(for: p.typeId))
                .lineStyle(StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))

                if showSymbols || model.bucketCount == 1 {
                    PointMark(
                        x: .value("Date", p.bucketStart, unit: unit),
                        y: .value("Hours per day", p.hoursPerDay)
                    )
                    .foregroundStyle(color(for: p.typeId))
                    .symbolSize(24)
                }
            }

            if let selectedBucket {
                RuleMark(x: .value("Selected", selectedBucket, unit: unit))
                    .foregroundStyle(Color.secondary.opacity(0.35))
                    .lineStyle(StrokeStyle(lineWidth: 1))
                    .annotation(
                        position: .top, spacing: 4,
                        // Keep the whole tooltip inside the chart's frame; otherwise it
                        // sits above the plot area and gets clipped.
                        overflowResolution: .init(x: .fit(to: .chart), y: .fit(to: .chart))
                    ) {
                        tooltip(model, bucket: selectedBucket)
                    }
            }
        }
        .chartXSelection(value: $selectedDate)
        .chartYAxis {
            AxisMarks(position: .leading) { value in
                AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5))
                    .foregroundStyle(Color.secondary.opacity(0.25))
                AxisValueLabel {
                    if let hours = value.as(Double.self) {
                        Text(formatHours(hours))
                    }
                }
            }
        }
        .chartXAxis {
            AxisMarks { _ in
                AxisValueLabel()
            }
        }
        .chartLegend(.hidden) // The activities list below is the legend.
    }

    private func tooltip(_ model: Model, bucket: Date) -> some View {
        let rows = timers.types
            .filter { !hidden.contains($0.id) }
            .map { ($0, model.value(typeId: $0.id, bucket: bucket)) }
            .sorted { $0.1 > $1.1 }
        return VStack(alignment: .leading, spacing: 4) {
            Text(bucketLabel(bucket))
                .font(.caption.weight(.semibold))
            ForEach(rows, id: \.0.id) { type, hours in
                HStack(spacing: 6) {
                    Circle().fill(color(for: type.id)).frame(width: 8, height: 8)
                    Text(type.name)
                    Spacer(minLength: 12)
                    Text(formatHoursMinutes(hours)).monospacedDigit()
                }
                .font(.caption)
            }
        }
        .padding(8)
        .frame(maxWidth: 220)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
    }

    private func bucketLabel(_ start: Date) -> String {
        switch granularity {
        case .day: start.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day())
        case .week: "Week of " + start.formatted(.dateTime.month(.abbreviated).day())
        case .month: start.formatted(.dateTime.month(.wide).year())
        }
    }

    // MARK: - Legend

    private func legendRow(_ type: ActivityType) -> some View {
        let isHidden = hidden.contains(type.id)
        return Button {
            toggle(type.id)
        } label: {
            HStack(spacing: 12) {
                // The icon wears the line's color, so it doubles as the legend swatch.
                // Hidden lines get a gray icon and dimmed name.
                Image(systemName: resolvedSymbolName(type.icon))
                    .foregroundStyle(isHidden ? Color.secondary.opacity(0.5) : color(for: type.id))
                    .font(.title3)
                    .frame(width: 28)
                Text(type.name)
                    .foregroundStyle(isHidden ? .secondary : .primary)
                Spacer()
            }
        }
        .accessibilityValue(isHidden ? "Hidden" : "Shown")
    }

    private var hidden: Set<String> {
        Set(hiddenRaw.split(separator: ",").map(String.init))
    }

    private func toggle(_ id: String) {
        var set = hidden
        if set.contains(id) { set.remove(id) } else { set.insert(id) }
        hiddenRaw = set.sorted().joined(separator: ",")
    }

    // MARK: - Colors

    /// Fixed categorical order by the activity's position in the list, so hiding a
    /// line never repaints the others. Validated for colorblind separation on iOS's
    /// light (#ffffff) and dark (#1c1c1e) backgrounds.
    private static let palette: [(light: UInt32, dark: UInt32)] = [
        (0x2A78D6, 0x3987E5), // blue
        (0xEB6834, 0xD95926), // orange
        (0x1BAF7A, 0x199E70), // aqua
        (0xEDA100, 0xC98500), // yellow
        (0xE87BA4, 0xD55181), // magenta
        (0x008300, 0x008300), // green
        (0x6250D6, 0x9085E9), // violet
        (0xE34948, 0xE66767), // red
    ]

    private func color(for typeId: String) -> Color {
        guard let index = timers.types.firstIndex(where: { $0.id == typeId }),
              index < Self.palette.count else { return .gray }
        let (light, dark) = Self.palette[index]
        return Color(UIColor { traits in
            UIColor(rgb: traits.userInterfaceStyle == .dark ? dark : light)
        })
    }
}

/// Everything derived from the sessions for the current controls.
private struct Model {
    let points: [StatsPoint]
    let bucketCount: Int
    private let bucketStarts: [Date]
    private let byKey: [String: Double]

    init(sessions: [Session], types: [ActivityType], range: StatsRange,
         granularity: StatsGranularity, now: Date) {
        let cal = Calendar.current
        let today = cal.startOfDay(for: now)
        let first = min(
            range.firstDay(today: today, earliest: sessions.map(\.startedAt).min()),
            today
        )
        let totals = StatsMath.dailyTotals(sessions, firstDay: first, lastDay: today, now: now)
        let buckets = StatsMath.buckets(firstDay: first, lastDay: today, granularity: granularity)
        points = StatsMath.points(totals: totals, typeIds: types.map(\.id), buckets: buckets)
        bucketCount = buckets.count
        bucketStarts = buckets.map(\.start)
        byKey = Dictionary(uniqueKeysWithValues: points.map { ($0.id, $0.hoursPerDay) })
    }

    /// The bucket a selected chart date falls into.
    func bucket(containing date: Date) -> Date? {
        bucketStarts.last { $0 <= date } ?? bucketStarts.first
    }

    func value(typeId: String, bucket: Date) -> Double {
        byKey["\(typeId)|\(bucket.timeIntervalSince1970)"] ?? 0
    }
}

private func formatHours(_ hours: Double) -> String {
    hours == hours.rounded() ? "\(Int(hours))h" : String(format: "%.1fh", hours)
}

/// "1h 05m" / "35m"
func formatHoursMinutes(_ hours: Double) -> String {
    let minutes = Int((hours * 60).rounded())
    return minutes >= 60 ? String(format: "%dh %02dm", minutes / 60, minutes % 60) : "\(minutes)m"
}

private extension UIColor {
    convenience init(rgb: UInt32) {
        self.init(
            red: CGFloat((rgb >> 16) & 0xFF) / 255,
            green: CGFloat((rgb >> 8) & 0xFF) / 255,
            blue: CGFloat(rgb & 0xFF) / 255,
            alpha: 1
        )
    }
}
