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

    @ObservationIgnored private let uid: String
    @ObservationIgnored private let user: DocumentReference
    @ObservationIgnored private let liveActivity = LiveActivityController()
    /// Don't touch the Live Activity until both of these have loaded at least once,
    /// or we'd end it on launch before we know a session is running.
    @ObservationIgnored private var runningLoaded = false
    @ObservationIgnored private var listeners: [ListenerRegistration] = []
    @ObservationIgnored private var todayListener: ListenerRegistration?
    @ObservationIgnored private var pendingRunning = false
    @ObservationIgnored private var pendingToday = false

    private var sessions: CollectionReference { user.collection("sessions") }

    init(uid: String) {
        self.uid = uid
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
                    self?.syncLiveActivity()
                }
            },
            user.collection("activityTypes").addSnapshotListener { [weak self] snap, _ in
                guard let snap else { return }
                MainActor.assumeIsolated {
                    self?.types = snap.documents.compactMap(ActivityType.init)
                        .sorted { ($0.sortOrder, $0.name) < ($1.sortOrder, $1.name) }
                    self?.loaded = true
                    self?.syncLiveActivity()
                }
            },
            sessions.whereField("endedAt", isEqualTo: NSNull())
                .addSnapshotListener(includeMetadataChanges: true) { [weak self] snap, _ in
                    guard let snap else { return }
                    MainActor.assumeIsolated {
                        self?.running = snap.documents.compactMap(Session.init)
                        self?.pendingRunning = snap.metadata.hasPendingWrites
                        self?.updatePending()
                        self?.runningLoaded = true
                        self?.syncLiveActivity()
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
                    self?.syncLiveActivity()
                }
            }
    }

    private func updatePending() {
        hasPendingWrites = pendingRunning || pendingToday
    }

    // MARK: - Derived

    var runningSession: Session? { running.max { $0.startedAt < $1.startedAt } }

    /// Time spent on `typeId` today (local calendar day), as of `now`, optionally
    /// leaving out one session.
    func totalToday(_ typeId: String, now: Date, excluding excludedId: String? = nil) -> TimeInterval {
        let dayEnd = Calendar.current.date(byAdding: .day, value: 1, to: dayStart)!
        var seen = Set<String>()
        var total: TimeInterval = 0
        // A session moves from `running` to `endedToday` when stopped; dedupe by id
        // in case both listeners briefly hold it.
        for s in running + endedToday
        where s.activityTypeId == typeId && s.id != excludedId && seen.insert(s.id).inserted {
            total += s.duration(overlapping: dayStart, dayEnd, now: now)
        }
        return total
    }

    func name(ofType id: String) -> String {
        types.first { $0.id == id }?.name ?? "Unknown"
    }

    // MARK: - Actions

    /// Stops whatever is running and starts `typeId`.
    func start(_ typeId: String) {
        if running.count == 1, running[0].activityTypeId == typeId { return }
        TimerActions.switchTo(typeId, endingRunning: running.map(\.id), uid: uid)
    }

    func stop() {
        guard !running.isEmpty else { return }
        TimerActions.switchTo(nil, endingRunning: running.map(\.id), uid: uid)
    }

    // MARK: - Live Activity

    private func syncLiveActivity() {
        guard loaded, runningLoaded else { return }
        guard let session = runningSession,
              let type = types.first(where: { $0.id == session.activityTypeId }) else {
            liveActivity.sync(nil)
            return
        }
        // Time already logged today, not counting this session. The session's
        // today-portion starts at max(start, midnight), so counting up from
        // (that - prior) shows the full total.
        let prior = totalToday(type.id, now: .now, excluding: session.id)
        let todayCountingFrom = max(session.startedAt, dayStart).addingTimeInterval(-prior)
        liveActivity.sync(.init(
            sessionId: session.id,
            activityName: type.name,
            iconName: type.icon,
            groupName: type.groupId.flatMap { id in groups.first { $0.id == id }?.name },
            sessionStartedAt: session.startedAt,
            todayCountingFrom: todayCountingFrom
        ))
    }
}
