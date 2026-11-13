import FirebaseFirestore
import Foundation
import Observation

enum StatsRange: String, CaseIterable, Identifiable {
    case week = "1W", month = "1M", threeMonths = "3M", year = "1Y", all = "All"
    var id: Self { self }

    /// First day included (start of day). `.all` starts at the earliest session.
    func firstDay(today: Date, earliest: Date?) -> Date {
        let cal = Calendar.current
        func back(_ c: Calendar.Component, _ n: Int) -> Date {
            // e.g. 1M on Nov 4 covers Oct 5 ... Nov 4.
            cal.date(byAdding: .day, value: 1, to: cal.date(byAdding: c, value: -n, to: today)!)!
        }
        switch self {
        case .week: return cal.date(byAdding: .day, value: -6, to: today)!
        case .month: return back(.month, 1)
        case .threeMonths: return back(.month, 3)
        case .year: return back(.year, 1)
        case .all: return earliest.map { cal.startOfDay(for: $0) } ?? today
        }
    }
}

enum StatsGranularity: String, CaseIterable, Identifiable {
    case day = "Daily", week = "Weekly", month = "Monthly"
    var id: Self { self }

    var shortLabel: String {
        switch self {
        case .day: "D"
        case .week: "W"
        case .month: "M"
        }
    }

    var component: Calendar.Component {
        switch self {
        case .day: .day
        case .week: .weekOfYear
        case .month: .month
        }
    }
}

/// One point on the chart: average hours per day for an activity in a bucket.
struct StatsPoint: Identifiable {
    let typeId: String
    let bucketStart: Date
    let hoursPerDay: Double
    var id: String { "\(typeId)|\(bucketStart.timeIntervalSince1970)" }
}

/// Loads the sessions needed for a stats range.
@MainActor
@Observable
final class StatsStore {
    private(set) var sessions: [Session] = []
    private(set) var loaded = false
    @ObservationIgnored private let uid: String

    init(uid: String) {
        self.uid = uid
    }

    func listen(range: StatsRange) async {
        let cal = Calendar.current
        let today = cal.startOfDay(for: .now)
        var query: Query = TimerActions.sessions(uid: uid)
        if range != .all {
            // A day earlier so sessions crossing into the first day are included.
            let since = cal.date(byAdding: .day, value: -1, to: range.firstDay(today: today, earliest: nil))!
            query = query.whereField("startedAt", isGreaterThanOrEqualTo: Timestamp(date: since))
        }
        loaded = false
        let listener = query.addSnapshotListener { [weak self] snap, _ in
            guard let snap else { return }
            MainActor.assumeIsolated {
                self?.sessions = snap.documents.compactMap(Session.init)
                self?.loaded = true
            }
        }
        while !Task.isCancelled {
            try? await Task.sleep(for: .seconds(3600))
        }
        listener.remove()
    }
}

enum StatsMath {
    /// Seconds per activity per calendar day, splitting sessions at midnight.
    /// Only days in [firstDay, lastDay] are counted.
    static func dailyTotals(
        _ sessions: [Session], firstDay: Date, lastDay: Date, now: Date
    ) -> [String: [Date: TimeInterval]] {
        let cal = Calendar.current
        let rangeEnd = cal.date(byAdding: .day, value: 1, to: lastDay)!
        var totals: [String: [Date: TimeInterval]] = [:]
        for s in sessions {
            var t = max(s.startedAt, firstDay)
            let end = min(s.endedAt ?? now, rangeEnd, now)
            while t < end {
                let day = cal.startOfDay(for: t)
                let next = cal.date(byAdding: .day, value: 1, to: day)!
                let segEnd = min(end, next)
                totals[s.activityTypeId, default: [:]][day, default: 0] += segEnd.timeIntervalSince(t)
                t = segEnd
            }
        }
        return totals
    }

    /// Buckets covering [firstDay, lastDay], each with the days it contains
    /// (clipped to the range, so partial first/last buckets average over fewer days).
    static func buckets(
        firstDay: Date, lastDay: Date, granularity: StatsGranularity
    ) -> [(start: Date, days: [Date])] {
        let cal = Calendar.current
        var result: [(Date, [Date])] = []
        var cursor = firstDay
        while cursor <= lastDay {
            let interval = cal.dateInterval(of: granularity.component, for: cursor)!
            var days: [Date] = []
            var d = cursor
            while d < interval.end && d <= lastDay {
                days.append(d)
                d = cal.date(byAdding: .day, value: 1, to: d)!
            }
            result.append((interval.start, days))
            cursor = d
        }
        return result
    }

    /// Average hours per day for each activity in each bucket, counting only the
    /// days that count: not marked excluded, and with at least one session (in any
    /// activity). Buckets with no such days get no points at all, so the daily
    /// chart skips those days and the weekly/monthly averages ignore them.
    static func points(
        totals: [String: [Date: TimeInterval]],
        typeIds: [String],
        buckets: [(start: Date, days: [Date])],
        excludedDays: Set<String>
    ) -> [StatsPoint] {
        let tracked = Set(totals.values.flatMap { $0.filter { $0.value > 0 }.keys })
        return buckets.flatMap { bucket -> [StatsPoint] in
            let days = bucket.days.filter { tracked.contains($0) && !excludedDays.contains(dayKey($0)) }
            guard !days.isEmpty else { return [] }
            return typeIds.map { typeId in
                let sum = days.reduce(0) { $0 + (totals[typeId]?[$1] ?? 0) }
                return StatsPoint(
                    typeId: typeId,
                    bucketStart: bucket.start,
                    hoursPerDay: sum / Double(days.count) / 3600
                )
            }
        }
    }
}
