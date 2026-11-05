import FirebaseFirestore
import Foundation
import Observation

/// Sessions overlapping one calendar day, for the sessions editor.
@MainActor
@Observable
final class SessionsStore {
    /// Newest first.
    private(set) var sessions: [Session] = []
    private(set) var loaded = false

    @ObservationIgnored private let uid: String

    init(uid: String) {
        self.uid = uid
    }

    /// Listens to sessions overlapping `day` until the calling task is cancelled.
    func listen(day: Date) async {
        let cal = Calendar.current
        let dayStart = cal.startOfDay(for: day)
        let dayEnd = cal.date(byAdding: .day, value: 1, to: dayStart)!
        // Firestore can't express "overlaps this day" (it involves both startedAt and
        // endedAt), so fetch sessions that started up to a day earlier and filter
        // here. Sessions longer than 24h that began before that won't show.
        let lookback = cal.date(byAdding: .day, value: -1, to: dayStart)!

        loaded = false
        sessions = []
        let listener = TimerActions.sessions(uid: uid)
            .whereField("startedAt", isGreaterThanOrEqualTo: Timestamp(date: lookback))
            .whereField("startedAt", isLessThan: Timestamp(date: dayEnd))
            .order(by: "startedAt", descending: true)
            .addSnapshotListener { [weak self] snap, _ in
                guard let snap else { return }
                MainActor.assumeIsolated {
                    self?.sessions = snap.documents.compactMap(Session.init)
                        .filter { ($0.endedAt ?? .distantFuture) > dayStart }
                    self?.loaded = true
                }
            }

        while !Task.isCancelled {
            try? await Task.sleep(for: .seconds(3600))
        }
        listener.remove()
    }
}
