import FirebaseFirestore
import Foundation

// Firestore layout (all per-user, see firestore.rules):
//   users/{uid}/groups/{groupId}         name: string, sortOrder: int,
//                                        showOnWidget: bool (missing = true)
//   users/{uid}/activityTypes/{typeId}   name: string, groupId: string|null, sortOrder: int,
//                                        icon: string|null (SF Symbol name)
//   users/{uid}/sessions/{sessionId}     activityTypeId: string, startedAt: timestamp,
//                                        endedAt: timestamp|null (null = running)
//   users/{uid}/excludedDays/{yyyy-MM-dd}  (no fields needed) a day left out of stats
//                                        because it wasn't fully tracked
//
// Timestamps are always taken from the device clock (never serverTimestamp()) so
// that starting/stopping while offline records the right times.

struct ActivityGroup: Identifiable, Equatable {
    let id: String
    let name: String
    let sortOrder: Int
    /// Whether the Lock Screen widget lists this group's total.
    let showOnWidget: Bool

    init?(_ doc: QueryDocumentSnapshot) {
        let d = doc.data()
        guard let name = d["name"] as? String else { return nil }
        id = doc.documentID
        self.name = name
        sortOrder = d["sortOrder"] as? Int ?? 0
        showOnWidget = d["showOnWidget"] as? Bool ?? true
    }
}

struct ActivityType: Identifiable, Equatable {
    let id: String
    let name: String
    let groupId: String?
    let icon: String?
    let sortOrder: Int

    init?(_ doc: QueryDocumentSnapshot) {
        let d = doc.data()
        guard let name = d["name"] as? String else { return nil }
        id = doc.documentID
        self.name = name
        groupId = d["groupId"] as? String
        icon = d["icon"] as? String
        sortOrder = d["sortOrder"] as? Int ?? 0
    }
}

struct Session: Identifiable, Equatable {
    let id: String
    let activityTypeId: String
    let startedAt: Date
    let endedAt: Date?

    init?(_ doc: QueryDocumentSnapshot) {
        let d = doc.data()
        guard let typeId = d["activityTypeId"] as? String,
              let start = d["startedAt"] as? Timestamp else { return nil }
        id = doc.documentID
        activityTypeId = typeId
        startedAt = start.dateValue()
        endedAt = (d["endedAt"] as? Timestamp)?.dateValue()
    }

    /// Seconds of this session that fall inside [from, to), treating a running
    /// session as ending at `now`.
    func duration(overlapping from: Date, _ to: Date, now: Date) -> TimeInterval {
        let start = max(startedAt, from)
        let end = min(endedAt ?? now, to)
        return max(0, end.timeIntervalSince(start))
    }
}

/// "2026-11-12" for the local calendar day containing `date`. Used as the document
/// id for excluded days.
func dayKey(_ date: Date) -> String {
    let c = Calendar.current.dateComponents([.year, .month, .day], from: date)
    return String(format: "%04d-%02d-%02d", c.year!, c.month!, c.day!)
}
