import SwiftUI

/// Lists the sessions recorded on one day; swipe to delete, tap to edit.
struct SessionsView: View {
    let timers: TimersStore

    @State private var store: SessionsStore
    @State private var day = Calendar.current.startOfDay(for: .now)
    @State private var editing: Session?
    @State private var adding = false

    init(timers: TimersStore) {
        self.timers = timers
        _store = State(initialValue: SessionsStore(uid: timers.uid))
    }

    private var isToday: Bool { Calendar.current.isDateInToday(day) }

    var body: some View {
        List {
            if store.loaded && store.sessions.isEmpty {
                ContentUnavailableView(
                    "No Sessions",
                    systemImage: "clock",
                    description: Text("Nothing was recorded on this day.")
                )
                .listRowBackground(Color.clear)
            }
            ForEach(store.sessions) { session in
                Button {
                    editing = session
                } label: {
                    SessionRow(session: session, type: activityType(for: session), day: day)
                }
                .tint(.primary)
            }
            .onDelete { offsets in
                for i in offsets {
                    TimerActions.deleteSession(store.sessions[i].id, uid: timers.uid)
                }
            }
        }
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Add Session", systemImage: "plus") { adding = true }
                    .disabled(timers.types.isEmpty)
            }
            ToolbarItemGroup(placement: .bottomBar) {
                Button("Previous Day", systemImage: "chevron.left") { shiftDay(-1) }
                Spacer()
                DatePicker("Day", selection: dayBinding, in: ...Date.now, displayedComponents: .date)
                    .labelsHidden()
                Spacer()
                Button("Next Day", systemImage: "chevron.right") { shiftDay(1) }
                    .disabled(isToday)
            }
        }
        .task(id: day) { await store.listen(day: day) }
        .sheet(isPresented: $adding) {
            NavigationStack {
                SessionEditor(addingOn: day, types: timers.types, others: store.sessions, uid: timers.uid)
            }
        }
        .sheet(item: $editing) { session in
            NavigationStack {
                SessionEditor(
                    session: session,
                    types: timers.types,
                    others: store.sessions.filter { $0.id != session.id },
                    uid: timers.uid
                )
            }
        }
    }

    private var title: String {
        if isToday { return "Today" }
        if Calendar.current.isDateInYesterday(day) { return "Yesterday" }
        return day.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day())
    }

    private var dayBinding: Binding<Date> {
        Binding(get: { day }, set: { day = Calendar.current.startOfDay(for: $0) })
    }

    private func shiftDay(_ delta: Int) {
        day = Calendar.current.date(byAdding: .day, value: delta, to: day)!
    }

    private func activityType(for session: Session) -> ActivityType? {
        timers.types.first { $0.id == session.activityTypeId }
    }
}

private struct SessionRow: View {
    let session: Session
    let type: ActivityType?
    let day: Date

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: resolvedSymbolName(type?.icon))
                .foregroundStyle(session.endedAt == nil ? Color.red : Color.accentColor)
                .frame(width: 28)
            VStack(alignment: .leading, spacing: 2) {
                Text(type?.name ?? "Unknown activity")
                Text(timeRange)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if session.endedAt == nil {
                TimelineView(.periodic(from: .now, by: 1)) { context in
                    Text(formatDuration(context.date.timeIntervalSince(session.startedAt)))
                }
                .monospacedDigit()
                .foregroundStyle(.red)
            } else {
                Text(formatDuration(session.endedAt!.timeIntervalSince(session.startedAt)))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 2)
    }

    private var timeRange: String {
        let start = label(session.startedAt)
        guard let end = session.endedAt else { return "\(start) – now" }
        return "\(start) – \(label(end))"
    }

    /// Time only, or with the date when it falls on a different day than shown.
    private func label(_ date: Date) -> String {
        Calendar.current.isDate(date, inSameDayAs: day)
            ? date.formatted(date: .omitted, time: .shortened)
            : date.formatted(.dateTime.month(.abbreviated).day().hour().minute())
    }
}
