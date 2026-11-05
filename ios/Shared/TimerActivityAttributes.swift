import ActivityKit
import Foundation

/// The Live Activity shown while a timer is running. All the data lives in
/// `ContentState` so switching activities can update the same Live Activity in place.
struct TimerActivityAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        /// The Firestore session this Live Activity currently represents.
        var sessionId: String
        var activityName: String
        /// SF Symbol name; may be nil or invalid (use `resolvedIconName`).
        var iconName: String?
        var groupName: String?
        var sessionStartedAt: Date
        /// A date chosen so that "time since this date" equals today's total for the
        /// activity: the time already logged today is folded in, so a plain counting-up
        /// timer shows the total without the app needing to update it.
        var todayCountingFrom: Date
    }
}

extension TimerActivityAttributes.ContentState {
    var resolvedIconName: String { resolvedSymbolName(iconName) }
}
