import FirebaseFirestore
import Foundation
import Observation

@MainActor
@Observable
final class TimersStore {
    private(set) var groups: [ActivityGroup] = []
    private(set) var types: [ActivityType] = []
    /// Sessions with endedAt == null. Normally 0 or 1.
    private(set) var running: [Session] = []
    /// Finished sessions that ended at or after the start of today.
    private(set) var endedToday: [Session] = []
    private(set) var dayStart = Calendar.current.startOfDay(for: .now)
    /// True while local session changes haven't reached the server yet (e.g. offline).
    private(set) var hasPendingWrites = false
    private(set) var loaded = false

    @ObservationIgnored private let user: DocumentReference
    @ObservationIgnored private var listeners: [ListenerRegistration] = []
    @ObservationIgnored private var todayListener: ListenerRegistration?
    @ObservationIgnored private var pendingRunning = false
    @ObservationIgnored private var pendingToday = false

    private var sessions: CollectionReference { user.collection("sessions") }

    init(uid: String) {
        user = Firestore.firestore().collection("users").document(uid)
    }

    // MARK: - Listening

    /// Attaches Firestore listeners and keeps them up to date (including across
    /// midnight) until the calling task is cancelled.
    func run() async {
        listeners = [
            user.collection("groups").addSnapshotListener { [weak self] snap, _ in
                guard let snap else { return }
                MainActor.assumeIsolated {
                    self?.groups = snap.documents.compactMap(ActivityGroup.init)
                        .sorted { ($0.sortOrder, $0.name) < ($1.sortOrder, $1.name) }
                }
            },
            user.collection("activityTypes").addSnapshotListener { [weak self] snap, _ in
                guard let snap else { return }
                MainActor.assumeIsolated {
                    self?.types = snap.documents.compactMap(ActivityType.init)
                        .sorted { ($0.sortOrder, $0.name) < ($1.sortOrder, $1.name) }
                    self?.loaded = true
                }
            },
            sessions.whereField("endedAt", isEqualTo: NSNull())
                .addSnapshotListener(includeMetadataChanges: true) { [weak self] snap, _ in
                    guard let snap else { return }
                    MainActor.assumeIsolated {
                        self?.running = snap.documents.compactMap(Session.init)
                        self?.pendingRunning = snap.metadata.hasPendingWrites
                        self?.updatePending()
                    }
                },
        ]
        listenToday()

        while !Task.isCancelled {
            try? await Task.sleep(for: .seconds(30))
            let today = Calendar.current.startOfDay(for: .now)
            if today != dayStart {
                dayStart = today
                listenToday()
            }
        }

        listeners.forEach { $0.remove() }
        todayListener?.remove()
        listeners = []
        todayListener = nil
    }

    private func listenToday() {
        todayListener?.remove()
        todayListener = sessions
            .whereField("endedAt", isGreaterThanOrEqualTo: Timestamp(date: dayStart))
            .addSnapshotListener(includeMetadataChanges: true) { [weak self] snap, _ in
                guard let snap else { return }
                MainActor.assumeIsolated {
                    self?.endedToday = snap.documents.compactMap(Session.init)
                    self?.pendingToday = snap.metadata.hasPendingWrites
                    self?.updatePending()
                }
            }
    }

    private func updatePending() {
        hasPendingWrites = pendingRunning || pendingToday
    }

    // MARK: - Derived

    var runningSession: Session? { running.max { $0.startedAt < $1.startedAt } }

    /// Time spent on `typeId` today (local calendar day), as of `now`.
    func totalToday(_ typeId: String, now: Date) -> TimeInterval {
        let dayEnd = Calendar.current.date(byAdding: .day, value: 1, to: dayStart)!
        var seen = Set<String>()
        var total: TimeInterval = 0
        // A session moves from `running` to `endedToday` when stopped; dedupe by id
        // in case both listeners briefly hold it.
        for s in running + endedToday where s.activityTypeId == typeId && seen.insert(s.id).inserted {
            total += s.duration(overlapping: dayStart, dayEnd, now: now)
        }
        return total
    }

    func name(ofType id: String) -> String {
        types.first { $0.id == id }?.name ?? "Unknown"
    }

    // MARK: - Actions
    //
    // Writes are fire-and-forget: the local cache (and therefore the UI) updates
    // immediately, and Firestore syncs to the server whenever it can. Awaiting the
    // commit would hang while offline.

    /// Stops whatever is running and starts `typeId`.
    func start(_ typeId: String) {
        if running.count == 1, running[0].activityTypeId == typeId { return }
        let now = Date()
        let batch = user.firestore.batch()
        for s in running {
            batch.updateData(["endedAt": Timestamp(date: now)], forDocument: sessions.document(s.id))
        }
        batch.setData([
            "activityTypeId": typeId,
            "startedAt": Timestamp(date: now),
            "endedAt": NSNull(), // must be explicitly null so the "running" query matches
        ], forDocument: sessions.document())
        batch.commit { error in
            if let error { print("start failed: \(error)") }
        }
    }

    func stop() {
        guard !running.isEmpty else { return }
        let now = Date()
        let batch = user.firestore.batch()
        for s in running {
            batch.updateData(["endedAt": Timestamp(date: now)], forDocument: sessions.document(s.id))
        }
        batch.commit { error in
            if let error { print("stop failed: \(error)") }
        }
    }
}
