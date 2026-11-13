import FirebaseFirestore
import Foundation

/// Writes for groups and activity types (the settings editor). Fire-and-forget,
/// like TimerActions, so editing works offline.
enum CatalogActions {
    private static func user(_ uid: String) -> DocumentReference {
        Firestore.firestore().collection("users").document(uid)
    }

    private static func done(_ what: String) -> (Error?) -> Void {
        { error in if let error { print("\(what) failed: \(error)") } }
    }

    // MARK: Groups

    static func addGroup(name: String, sortOrder: Int, uid: String) {
        user(uid).collection("groups").addDocument(
            data: ["name": name, "sortOrder": sortOrder], completion: done("add group"))
    }

    static func updateGroup(_ id: String, name: String, showOnWidget: Bool, uid: String) {
        user(uid).collection("groups").document(id)
            .updateData(["name": name, "showOnWidget": showOnWidget], completion: done("update group"))
    }

    /// Deletes a group; its activities become ungrouped.
    static func deleteGroup(_ id: String, memberIds: [String], uid: String) {
        let u = user(uid)
        let batch = u.firestore.batch()
        batch.deleteDocument(u.collection("groups").document(id))
        for typeId in memberIds {
            batch.updateData(["groupId": NSNull()], forDocument: u.collection("activityTypes").document(typeId))
        }
        batch.commit(completion: done("delete group"))
    }

    // MARK: Activity types

    /// Creates (id == nil) or updates an activity type.
    static func saveType(id: String?, name: String, groupId: String?, icon: String?,
                         sortOrder: Int, uid: String) {
        let data: [String: Any] = [
            "name": name,
            "groupId": groupId ?? NSNull(),
            "icon": icon ?? NSNull(),
            "sortOrder": sortOrder,
        ]
        let types = user(uid).collection("activityTypes")
        if let id {
            types.document(id).setData(data, merge: true, completion: done("save activity"))
        } else {
            types.addDocument(data: data, completion: done("add activity"))
        }
    }

    /// Deletes an activity type. Its sessions are kept.
    static func deleteType(_ id: String, uid: String) {
        user(uid).collection("activityTypes").document(id).delete(completion: done("delete activity"))
    }

    // MARK: Ordering

    /// Sets sortOrder = position for each id, in one batch.
    static func reorder(_ collection: String, ids: [String], uid: String) {
        let c = user(uid).collection(collection)
        let batch = c.firestore.batch()
        for (i, id) in ids.enumerated() {
            batch.updateData(["sortOrder": i], forDocument: c.document(id))
        }
        batch.commit(completion: done("reorder \(collection)"))
    }
}
