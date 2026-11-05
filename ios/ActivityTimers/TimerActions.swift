import FirebaseAuth
import FirebaseCore
import FirebaseFirestore
import Foundation

/// Session writes shared by the UI (TimersStore) and App Intents.
///
/// Writes are fire-and-forget: the local cache (and therefore the UI) updates
/// immediately, and Firestore syncs to the server whenever it can. Awaiting the
/// commit would hang while offline.
enum TimerActions {
    static func sessions(uid: String) -> CollectionReference {
        Firestore.firestore().collection("users").document(uid).collection("sessions")
    }

    /// Ends `runningIds` and, if `typeId` is given, starts a new session for it,
    /// all in one atomic batch at a single instant.
    static func switchTo(_ typeId: String?, endingRunning runningIds: [String], uid: String) {
        let sessions = sessions(uid: uid)
        let now = Timestamp(date: Date())
        let batch = sessions.firestore.batch()
        for id in runningIds {
            batch.updateData(["endedAt": now], forDocument: sessions.document(id))
        }
        if let typeId {
            batch.setData([
                "activityTypeId": typeId,
                "startedAt": now,
                "endedAt": NSNull(), // must be explicitly null so the "running" query matches
            ], forDocument: sessions.document())
        }
        batch.commit { error in
            if let error { print("session write failed: \(error)") }
        }
    }

    /// Stops all running sessions without needing a TimersStore (used by the Live
    /// Activity's Stop button, which may run with the app in the background).
    static func stopAllRunning() async {
        if FirebaseApp.app() == nil { FirebaseApp.configure() }
        guard let uid = Auth.auth().currentUser?.uid else { return }
        let running = sessions(uid: uid).whereField("endedAt", isEqualTo: NSNull())
        // The cache is authoritative for anything started on this device and is
        // instant offline; fall back to the server for sessions started elsewhere.
        var docs = (try? await running.getDocuments(source: .cache))?.documents ?? []
        if docs.isEmpty {
            docs = (try? await running.getDocuments())?.documents ?? []
        }
        guard !docs.isEmpty else { return }
        switchTo(nil, endingRunning: docs.map(\.documentID), uid: uid)
    }
}
