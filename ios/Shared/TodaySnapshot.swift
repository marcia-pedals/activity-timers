import Foundation

/// Today's totals per group, written by the app into the shared App Group and
/// read by the Lock Screen widget (which can't query Firestore itself).
///
/// Finished time is stored as a number; the running session (if any) is stored as
/// a start time so the widget can keep counting without the app running.
struct TodaySnapshot: Codable, Equatable {
    struct Group: Codable, Equatable, Identifiable {
        var id: String
        var name: String
        /// Seconds of finished sessions on `day`.
        var finishedSeconds: Double
    }

    /// Start of the day the totals belong to.
    var day: Date
    var groups: [Group]
    var runningGroupId: String?
    var runningStartedAt: Date?

    static let appGroup = "group.io.github.marcia-pedals.ActivityTimers"
    static let widgetKind = "TodayTotals"
    /// Group id used for activity types that aren't in a group.
    static let otherGroupId = "_other"
    private static let key = "todaySnapshot"

    /// Total seconds for `groupId` as of `date`. Past midnight, finished totals
    /// reset and a running session counts only from midnight.
    func seconds(for groupId: String, at date: Date) -> Double {
        let cal = Calendar.current
        let dateDay = cal.startOfDay(for: date)
        let finished = dateDay == day ? (groups.first { $0.id == groupId }?.finishedSeconds ?? 0) : 0
        guard groupId == runningGroupId, let start = runningStartedAt else { return finished }
        return finished + max(0, date.timeIntervalSince(max(start, dateDay)))
    }

    /// The snapshot after stopping the running session at `date` (used by the Live
    /// Activity's Stop button, which runs without the app's data loaded).
    func stoppingRunning(at date: Date) -> TodaySnapshot {
        guard let runningGroupId else { return self }
        var copy = self
        let cal = Calendar.current
        let dateDay = cal.startOfDay(for: date)
        if dateDay != day {
            copy.day = dateDay
            for i in copy.groups.indices { copy.groups[i].finishedSeconds = 0 }
        }
        if let i = copy.groups.firstIndex(where: { $0.id == runningGroupId }) {
            copy.groups[i].finishedSeconds = seconds(for: runningGroupId, at: date)
        }
        copy.runningGroupId = nil
        copy.runningStartedAt = nil
        return copy
    }

    // MARK: - Storage

    private static var defaults: UserDefaults? { UserDefaults(suiteName: appGroup) }

    static func load() -> TodaySnapshot? {
        guard let data = defaults?.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(TodaySnapshot.self, from: data)
    }

    /// Saves and returns true if the stored snapshot changed.
    @discardableResult
    func save() -> Bool {
        guard Self.load() != self, let data = try? JSONEncoder().encode(self) else { return false }
        Self.defaults?.set(data, forKey: Self.key)
        return true
    }
}

/// "1h 23m" / "45m", rounded to the nearest minute.
func formatRoundedMinutes(_ seconds: Double) -> String {
    let minutes = Int((seconds / 60).rounded())
    return minutes >= 60 ? "\(minutes / 60)h \(String(format: "%02d", minutes % 60))m" : "\(minutes)m"
}

/// URL that widgets open to bring up the main timers screen.
let timersScreenURL = URL(string: "activitytimers://timers")!
