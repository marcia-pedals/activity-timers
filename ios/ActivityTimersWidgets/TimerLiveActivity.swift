import ActivityKit
import AppIntents
import SwiftUI
import WidgetKit

@main
struct ActivityTimersWidgets: WidgetBundle {
    var body: some Widget {
        TimerLiveActivity()
    }
}

/// Timers here use SwiftUI's self-updating date text, so they keep counting on the
/// Lock Screen and Dynamic Island without the app doing anything.
///
/// While the phone is locked, iOS hides seconds. `.timer` style then renders as
/// words ("3 minutes") which truncates, so the Lock Screen card uses `.relative`
/// style instead, which renders compactly ("3 min"; "3 min, 12 sec" when unlocked).
/// The Dynamic Island keeps `.timer` ("3:12").
struct TimerLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: TimerActivityAttributes.self) { context in
            LockScreenView(state: context.state)
                .padding()
        } dynamicIsland: { context in
            let state = context.state
            return DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    HStack(spacing: 8) {
                        ActivityIcon(state: state)
                            .font(.title2)
                        NameView(state: state)
                    }
                    .padding(.leading, 4)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    SessionTimer(state: state)
                        .font(.title2.weight(.semibold))
                        .padding(.trailing, 4)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    HStack {
                        TodayTotal(state: state)
                        Spacer()
                        StopButton()
                    }
                    .padding(.horizontal, 4)
                }
            } compactLeading: {
                ActivityIcon(state: state)
            } compactTrailing: {
                SessionTimer(state: state)
                    .font(.caption.weight(.semibold))
                    // Timer text otherwise claims all available width.
                    .frame(maxWidth: 56, alignment: .trailing)
            } minimal: {
                ActivityIcon(state: state)
            }
        }
    }
}

private struct LockScreenView: View {
    let state: TimerActivityAttributes.ContentState

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            ActivityIcon(state: state)
                .font(.title)
                .frame(width: 36)
            VStack(alignment: .leading, spacing: 4) {
                NameView(state: state)
                TodayTotal(state: state, style: .relative)
            }
            Spacer(minLength: 8)
            SessionTimer(state: state, style: .relative)
                .font(.title2.weight(.semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            StopButton()
        }
    }
}

private struct ActivityIcon: View {
    let state: TimerActivityAttributes.ContentState

    var body: some View {
        Image(systemName: state.resolvedIconName)
            .foregroundStyle(.tint)
    }
}

private struct NameView: View {
    let state: TimerActivityAttributes.ContentState

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let group = state.groupName {
                Text(group)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Text(state.activityName)
                .font(.headline)
                .lineLimit(1)
        }
    }
}

private struct SessionTimer: View {
    let state: TimerActivityAttributes.ContentState
    var style: Text.DateStyle = .timer

    var body: some View {
        Text(state.sessionStartedAt, style: style)
            .monospacedDigit()
            .multilineTextAlignment(.trailing)
    }
}

private struct TodayTotal: View {
    let state: TimerActivityAttributes.ContentState
    var style: Text.DateStyle = .timer

    var body: some View {
        HStack(spacing: 4) {
            Text("Today")
            Text(state.todayCountingFrom, style: style)
                .monospacedDigit()
        }
        .lineLimit(1)
        .font(.subheadline)
        .foregroundStyle(.secondary)
    }
}

private struct StopButton: View {
    var body: some View {
        Button(intent: StopTimerIntent()) {
            Image(systemName: "stop.fill")
                .font(.title3)
                .padding(4)
        }
        .buttonStyle(.borderedProminent)
        .buttonBorderShape(.circle)
        .tint(.red)
    }
}

#Preview("Lock Screen", as: .content, using: TimerActivityAttributes()) {
    TimerLiveActivity()
} contentStates: {
    TimerActivityAttributes.ContentState(
        sessionId: "preview",
        activityName: "Relaxing Yoga",
        iconName: "figure.mind.and.body",
        groupName: "Good",
        sessionStartedAt: .now.addingTimeInterval(-754),
        todayCountingFrom: .now.addingTimeInterval(-3_912)
    )
}
