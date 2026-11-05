import FirebaseCore
import SwiftUI

@main
struct ActivityTimersApp: App {
    @State private var auth: AuthModel

    init() {
        // Firestore's offline cache is on by default on iOS: reads come from the
        // local cache and writes are queued (across app restarts) until online.
        FirebaseApp.configure()
        _auth = State(initialValue: AuthModel())
    }

    var body: some Scene {
        WindowGroup {
            if let uid = auth.uid {
                TimersView(uid: uid, onSignOut: auth.signOut)
                    .id(uid)
            } else {
                SignInView(auth: auth)
            }
        }
    }
}
