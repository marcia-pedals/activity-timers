import ActivityKit
import Foundation

/// Keeps the (single) Live Activity matching the desired state: starts it when a
/// timer starts, updates it in place on switch, ends it on stop.
@MainActor
final class LiveActivityController {
    private typealias State = TimerActivityAttributes.ContentState

    private var queue: Task<Void, Never>?
    /// The session we last showed. Used so that if a Live Activity disappears for a
    /// session we already showed (you swiped it away, or it hit the 8-hour limit),
    /// we don't immediately re-create it on every data change. It's in-memory only,
    /// so relaunching the app brings it back.
    private var lastShownSessionId: String?

    /// Pass nil when nothing is running.
    func sync(_ desired: TimerActivityAttributes.ContentState?) {
        // Serialize: ActivityKit calls are async and must not interleave.
        let previous = queue
        queue = Task {
            await previous?.value
            await apply(desired)
        }
    }

    private func apply(_ desired: State?) async {
        let live = Activity<TimerActivityAttributes>.activities
            .filter { $0.activityState == .active || $0.activityState == .stale }

        guard let desired else {
            for activity in live { await activity.end(nil, dismissalPolicy: .immediate) }
            lastShownSessionId = nil
            return
        }

        if let current = live.first {
            for extra in live.dropFirst() { await extra.end(nil, dismissalPolicy: .immediate) }
            if current.content.state != desired {
                await current.update(ActivityContent(state: desired, staleDate: nil))
            }
            lastShownSessionId = desired.sessionId
            return
        }

        guard desired.sessionId != lastShownSessionId,
              ActivityAuthorizationInfo().areActivitiesEnabled else { return }
        do {
            // Only succeeds while the app is in the foreground, which is when you
            // tap Start. Otherwise it's retried on the next sync.
            _ = try Activity.request(
                attributes: TimerActivityAttributes(),
                content: ActivityContent(state: desired, staleDate: nil)
            )
            lastShownSessionId = desired.sessionId
        } catch {
            print("Live Activity request failed: \(error)")
        }
    }
}
