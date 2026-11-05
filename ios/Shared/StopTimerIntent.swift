import ActivityKit
import AppIntents

/// The Stop button on the Live Activity. Because this is a LiveActivityIntent,
/// iOS runs `perform()` in the app's process (launching it in the background if
/// needed), even though the button lives in the widget extension.
struct StopTimerIntent: LiveActivityIntent {
    static var title: LocalizedStringResource = "Stop Timer"
    static var description = IntentDescription("Stops the running activity timer.")

    func perform() async throws -> some IntentResult {
        // End the Live Activity right away so the UI responds even before the
        // Firestore write happens.
        for activity in Activity<TimerActivityAttributes>.activities {
            await activity.end(nil, dismissalPolicy: .immediate)
        }
        #if MAIN_APP
        await TimerActions.stopAllRunning()
        #endif
        return .result()
    }
}
