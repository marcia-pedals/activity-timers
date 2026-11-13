import SwiftUI

/// The main screen: start/stop buttons for each activity with today's totals.
struct TimersView: View {
    let store: TimersStore

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            content(now: context.date)
        }
        .navigationTitle("Today")
        .toolbar {
            if store.hasPendingWrites {
                ToolbarItem(placement: .topBarTrailing) {
                    Label("Not synced yet", systemImage: "icloud.slash")
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    @ViewBuilder
    private func content(now: Date) -> some View {
        if store.loaded && store.types.isEmpty {
            ContentUnavailableView(
                "No Activities",
                systemImage: "timer",
                description: Text("Add activities in Settings.")
            )
        } else {
            List {
                ForEach(store.typeSections) { section in
                    Section {
                        ForEach(section.types) { type in
                            row(type, now: now)
                        }
                    } header: {
                        if let group = section.group { Text(group.name) }
                    }
                }
            }
            .safeAreaInset(edge: .bottom) { stopBar(now: now) }
        }
    }

    private func row(_ type: ActivityType, now: Date) -> some View {
        let isRunning = store.running.contains { $0.activityTypeId == type.id }
        return Button {
            store.start(type.id)
        } label: {
            HStack {
                Image(systemName: resolvedSymbolName(type.icon))
                    .foregroundStyle(isRunning ? Color.red : Color.accentColor)
                    .symbolEffect(.pulse, isActive: isRunning)
                    .frame(width: 32)
                Text(type.name)
                    .foregroundStyle(.primary)
                    .fontWeight(isRunning ? .semibold : .regular)
                Spacer()
                Text(formatDuration(store.totalToday(type.id, now: now)))
                    .monospacedDigit()
                    .foregroundStyle(isRunning ? .primary : .secondary)
            }
            .font(.title3)
            .padding(.vertical, 6)
        }
    }

    @ViewBuilder
    private func stopBar(now: Date) -> some View {
        if let session = store.runningSession {
            Button(role: .destructive) {
                store.stop()
            } label: {
                HStack {
                    Image(systemName: "stop.fill")
                    Text("Stop \(store.name(ofType: session.activityTypeId))")
                    Spacer()
                    Text(formatDuration(now.timeIntervalSince(session.startedAt)))
                        .monospacedDigit()
                }
                .font(.headline)
                .padding(.vertical, 8)
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(.red)
            .padding(.horizontal)
            .padding(.bottom, 8)
        }
    }
}

func formatDuration(_ interval: TimeInterval) -> String {
    let s = Int(interval)
    return String(format: "%d:%02d:%02d", s / 3600, s / 60 % 60, s % 60)
}
