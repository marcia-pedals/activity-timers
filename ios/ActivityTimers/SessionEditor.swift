import FirebaseFirestore
import SwiftUI

/// Edits or deletes an existing session, or (with `session == nil`) adds a
/// finished one after the fact.
struct SessionEditor: View {
    let session: Session?
    let types: [ActivityType]
    /// Other sessions near this one, for the overlap warning.
    let others: [Session]
    let uid: String

    @Environment(\.dismiss) private var dismiss
    @State private var typeId: String
    @State private var start: Date
    @State private var end: Date
    @State private var confirmingDelete = false

    init(session: Session, types: [ActivityType], others: [Session], uid: String) {
        self.session = session
        self.types = types
        self.others = others
        self.uid = uid
        _typeId = State(initialValue: session.activityTypeId)
        _start = State(initialValue: session.startedAt)
        _end = State(initialValue: session.endedAt ?? .now)
    }

    /// New session on `day`: defaults to the last 30 minutes if `day` is today,
    /// otherwise noon–12:30.
    init(addingOn day: Date, types: [ActivityType], others: [Session], uid: String) {
        session = nil
        self.types = types
        self.others = others
        self.uid = uid
        let cal = Calendar.current
        let end = cal.isDateInToday(day)
            ? Date.now
            : cal.date(bySettingHour: 12, minute: 30, second: 0, of: day)!
        _typeId = State(initialValue: types.first?.id ?? "")
        _start = State(initialValue: end.addingTimeInterval(-30 * 60))
        _end = State(initialValue: end)
    }

    private var isNew: Bool { session == nil }
    private var isRunning: Bool { session != nil && session?.endedAt == nil }

    var body: some View {
        Form {
            Section {
                Picker("Activity", selection: $typeId) {
                    ForEach(types) { type in
                        Label(type.name, systemImage: resolvedSymbolName(type.icon))
                            .tag(type.id)
                    }
                }
            }

            Section {
                DatePicker("Start", selection: $start, in: ...Date.now)
                if isRunning {
                    LabeledContent("End", value: "Still running")
                } else {
                    DatePicker("End", selection: $end, in: ...Date.now)
                }
            } footer: {
                if let error {
                    Text(error).foregroundStyle(.red)
                } else if let overlap {
                    Text(overlap).foregroundStyle(.orange)
                } else if !isRunning {
                    Text("Duration \(formatDuration(end.timeIntervalSince(start)))")
                }
            }

            if !isNew {
                Section {
                    Button("Delete Session", role: .destructive) {
                        confirmingDelete = true
                    }
                }
            }
        }
        .navigationTitle(isNew ? "Add Session" : "Edit Session")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") { dismiss() }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button(isNew ? "Add" : "Save", action: save)
                    .disabled(error != nil || (!isNew && changes.isEmpty))
            }
        }
        .confirmationDialog("Delete this session?", isPresented: $confirmingDelete, titleVisibility: .visible) {
            Button("Delete Session", role: .destructive) {
                if let session { TimerActions.deleteSession(session.id, uid: uid) }
                dismiss()
            }
        }
    }

    /// Blocks saving.
    private var error: String? {
        if typeId.isEmpty { return "Choose an activity." }
        if start > .now { return "Start can't be in the future." }
        if !isRunning && end <= start { return "End must be after start." }
        return nil
    }

    /// Warns but allows saving: overlapping sessions get counted twice in totals.
    private var overlap: String? {
        let myEnd = isRunning ? Date.now : end
        let clash = others.first { other in
            let otherEnd = other.endedAt ?? .now
            return other.startedAt < myEnd && start < otherEnd
        }
        guard let clash else { return nil }
        let name = types.first { $0.id == clash.activityTypeId }?.name ?? "another session"
        return "Overlaps with \(name) at \(clash.startedAt.formatted(date: .omitted, time: .shortened)); the overlapping time will be counted twice."
    }

    private var changes: [String: Any] {
        guard let session else { return [:] }
        var fields: [String: Any] = [:]
        if typeId != session.activityTypeId { fields["activityTypeId"] = typeId }
        if start != session.startedAt { fields["startedAt"] = Timestamp(date: start) }
        if !isRunning, end != session.endedAt { fields["endedAt"] = Timestamp(date: end) }
        return fields
    }

    private func save() {
        if let session {
            TimerActions.updateSession(session.id, fields: changes, uid: uid)
        } else {
            TimerActions.addSession(typeId: typeId, start: start, end: end, uid: uid)
        }
        dismiss()
    }
}
