import SwiftUI

struct TimersView: View {
    let onSignOut: () -> Void
    @State private var store: TimersStore
    @State private var path: [Screen] = []

    private enum Screen: Hashable {
        case stats, sessions
    }

    init(uid: String, onSignOut: @escaping () -> Void) {
        self.onSignOut = onSignOut
        _store = State(initialValue: TimersStore(uid: uid))
    }

    var body: some View {
        NavigationStack(path: $path) {
            TimelineView(.periodic(from: .now, by: 1)) { context in
                content(now: context.date)
            }
            .navigationTitle("Today")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    if store.hasPendingWrites {
                        Label("Not synced yet", systemImage: "icloud.slash")
                            .foregroundStyle(.secondary)
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    NavigationLink(value: Screen.stats) {
                        Label("Stats", systemImage: "chart.xyaxis.line")
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    NavigationLink(value: Screen.sessions) {
                        Label("Sessions", systemImage: "list.bullet.rectangle")
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button("Sign Out", role: .destructive, action: onSignOut)
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                }
            }
            .navigationDestination(for: Screen.self) { screen in
                switch screen {
                case .stats: StatsView(timers: store)
                case .sessions: SessionsView(timers: store)
                }
            }
        }
        .task { await store.run() }
        // Widget / Live Activity taps open activitytimers://timers: go back to the
        // main screen (popping a pushed screen also dismisses its sheets).
        .onOpenURL { url in
            if url.host == timersScreenURL.host { path = [] }
        }
    }

    @ViewBuilder
    private func content(now: Date) -> some View {
        if store.loaded && store.types.isEmpty {
            ContentUnavailableView(
                "No Activities",
                systemImage: "timer",
                description: Text("Add activity types to Firestore with scripts/seed.sh.")
            )
        } else {
            List {
                ForEach(sections, id: \.id) { section in
                    Section {
                        ForEach(section.types) { type in
                            row(type, now: now)
                        }
                    } header: {
                        if let title = section.title { Text(title) }
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
            .padding()
            .background(.bar)
        }
    }

    private struct ListSection {
        let id: String
        let title: String?
        let types: [ActivityType]
    }

    private var sections: [ListSection] {
        let groupIds = Set(store.groups.map(\.id))
        let ungrouped = store.types.filter { $0.groupId.map { !groupIds.contains($0) } ?? true }
        var result: [ListSection] = []
        if !ungrouped.isEmpty {
            result.append(ListSection(id: "", title: nil, types: ungrouped))
        }
        for group in store.groups {
            let types = store.types.filter { $0.groupId == group.id }
            if !types.isEmpty {
                result.append(ListSection(id: group.id, title: group.name, types: types))
            }
        }
        return result
    }
}

func formatDuration(_ interval: TimeInterval) -> String {
    let s = Int(interval)
    return String(format: "%d:%02d:%02d", s / 3600, s / 60 % 60, s % 60)
}
