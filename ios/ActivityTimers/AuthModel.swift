import FirebaseAuth
import Observation

/// Email/password auth. The signed-in user is persisted in the keychain, so the
/// app stays signed in (and works) when launched offline.
@MainActor
@Observable
final class AuthModel {
    private(set) var uid: String?
    @ObservationIgnored private var handle: AuthStateDidChangeListenerHandle?

    init() {
        uid = Auth.auth().currentUser?.uid
        handle = Auth.auth().addStateDidChangeListener { [weak self] _, user in
            MainActor.assumeIsolated { self?.uid = user?.uid }
        }
    }

    func signIn(email: String, password: String) async throws {
        try await Auth.auth().signIn(withEmail: email, password: password)
    }

    func signOut() {
        try? Auth.auth().signOut()
    }
}
