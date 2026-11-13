import SwiftUI

/// Edit groups and activities, and sign out.
struct SettingsView: View {
    let timers: TimersStore
    let onSignOut: () -> Void

    @State private var editingType: EditingType?
    @State private var addingGroup = false
    @State private var editingGroup: ActivityGroup?
    @State private var groupName = ""
    @State private var deletingGroup: ActivityGroup?
    @State private var deletingType: ActivityType?
    @State private var confirmingSignOut = false

    /// The activity editor sheet's subject: an existing type or a new one.
    private struct EditingType: Identifiable {
        let type: ActivityType?
        var id: String { type?.id ?? "new" }
    }

    init(timers: TimersStore, onSignOut: @escaping () -> Void) {
        self.timers = timers
        self.onSignOut = onSignOut
    }

    var body: some View {
        List {
            ForEach(timers.typeSections) { section in
                Section {
                    activityRows(section)
                } header: {
                    Text(section.group?.name ?? "No Group")
                }
            }
            Section {
                Button {
                    editingType = EditingType(type: nil)
                } label: {
                    Label("Add Activity", systemImage: "plus")
                }
            } footer: {
                Text("Tap an activity to rename it, change its group or icon. Use Edit to reorder or delete.")
            }

            Section {
                ForEach(timers.groups) { group in
                    Button {
                        editingGroup = group
                    } label: {
                        HStack {
                            Text(group.name).foregroundStyle(.primary)
                            if !group.showOnWidget {
                                Image(systemName: "eye.slash")
                                    .foregroundStyle(.secondary)
                                    .imageScale(.small)
                                    .accessibilityLabel("Hidden from widget")
                            }
                            Spacer()
                            Text(memberCount(group))
                                .foregroundStyle(.secondary)
                        }
                    }
                    .tint(.primary)
                }
                .onMove { from, to in
                    var ids = timers.groups.map(\.id)
                    ids.move(fromOffsets: from, toOffset: to)
                    CatalogActions.reorder("groups", ids: ids, uid: timers.uid)
                }
                .onDelete { offsets in
                    deletingGroup = offsets.first.map { timers.groups[$0] }
                }
                Button {
                    groupName = ""
                    addingGroup = true
                } label: {
                    Label("Add Group", systemImage: "plus")
                }
            } header: {
                Text("Groups")
            } footer: {
                Text("Groups organize the Timers screen. The Lock Screen widget shows a total for each group that has it turned on.")
            }

            Section {
                Button("Sign Out", role: .destructive) { confirmingSignOut = true }
            }
        }
        .navigationTitle("Settings")
        .toolbar { EditButton() }
        .sheet(item: $editingType) { editing in
            NavigationStack {
                ActivityEditor(type: editing.type, timers: timers)
            }
        }
        .alert("New Group", isPresented: $addingGroup) {
            TextField("Name", text: $groupName)
            Button("Add") {
                let name = groupName.trimmingCharacters(in: .whitespaces)
                guard !name.isEmpty else { return }
                let order = (timers.groups.map(\.sortOrder).max() ?? -1) + 1
                CatalogActions.addGroup(name: name, sortOrder: order, uid: timers.uid)
            }
            Button("Cancel", role: .cancel) {}
        }
        .sheet(item: $editingGroup) { group in
            NavigationStack {
                GroupEditor(group: group, uid: timers.uid)
            }
            .presentationDetents([.medium])
        }
        .confirmationDialog(
            "Delete \u{201C}\(deletingGroup?.name ?? "")\u{201D}?",
            isPresented: isPresent($deletingGroup), titleVisibility: .visible, presenting: deletingGroup
        ) { group in
            Button("Delete Group", role: .destructive) {
                let members = timers.types.filter { $0.groupId == group.id }.map(\.id)
                CatalogActions.deleteGroup(group.id, memberIds: members, uid: timers.uid)
            }
        } message: { _ in
            Text("Its activities are kept and move to No Group.")
        }
        .confirmationDialog(
            "Delete \u{201C}\(deletingType?.name ?? "")\u{201D}?",
            isPresented: isPresent($deletingType), titleVisibility: .visible, presenting: deletingType
        ) { type in
            Button("Delete Activity", role: .destructive) {
                CatalogActions.deleteType(type.id, uid: timers.uid)
            }
        } message: { _ in
            Text("Its recorded sessions are kept but will show as \u{201C}Unknown activity\u{201D} and no longer appear in stats.")
        }
        .confirmationDialog("Sign out?", isPresented: $confirmingSignOut, titleVisibility: .visible) {
            Button("Sign Out", role: .destructive, action: onSignOut)
        }
        .task(id: timers.loaded) {
            // Debug: -debugEditActivity <typeId|new>, once activities have loaded.
            if timers.loaded, let id = DebugLaunch.editActivity, editingType == nil {
                editingType = EditingType(type: timers.types.first { $0.id == id })
            }
            if timers.loaded, let id = DebugLaunch.editGroup {
                editingGroup = timers.groups.first { $0.id == id }
            }
        }
    }

    private func activityRows(_ section: TypeSection) -> some View {
        ForEach(section.types) { type in
            Button {
                editingType = EditingType(type: type)
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: resolvedSymbolName(type.icon))
                        .foregroundStyle(Color.accentColor)
                        .frame(width: 28)
                    Text(type.name)
                        .foregroundStyle(.primary)
                }
            }
            .tint(.primary)
        }
        .onMove { from, to in
            var ids = section.types.map(\.id)
            ids.move(fromOffsets: from, toOffset: to)
            CatalogActions.reorder("activityTypes", ids: ids, uid: timers.uid)
        }
        .onDelete { offsets in
            deletingType = offsets.first.map { section.types[$0] }
        }
    }

    private func memberCount(_ group: ActivityGroup) -> String {
        let n = timers.types.filter { $0.groupId == group.id }.count
        return n == 1 ? "1 activity" : "\(n) activities"
    }
}

/// A Bool binding that's true while `item` is non-nil; setting false clears it.
private func isPresent<T>(_ item: Binding<T?>) -> Binding<Bool> {
    Binding(get: { item.wrappedValue != nil }, set: { if !$0 { item.wrappedValue = nil } })
}

/// Rename a group and choose whether the Lock Screen widget shows it.
struct GroupEditor: View {
    let group: ActivityGroup
    let uid: String

    @Environment(\.dismiss) private var dismiss
    @State private var name: String
    @State private var showOnWidget: Bool

    init(group: ActivityGroup, uid: String) {
        self.group = group
        self.uid = uid
        _name = State(initialValue: group.name)
        _showOnWidget = State(initialValue: group.showOnWidget)
    }

    private var trimmedName: String { name.trimmingCharacters(in: .whitespaces) }

    var body: some View {
        Form {
            Section {
                TextField("Name", text: $name)
            }
            Section {
                Toggle("Show on Lock Screen widget", isOn: $showOnWidget)
            } footer: {
                Text("The widget shows today's total for each group with this on.")
            }
        }
        .navigationTitle("Edit Group")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") { dismiss() }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("Save") {
                    CatalogActions.updateGroup(group.id, name: trimmedName, showOnWidget: showOnWidget, uid: uid)
                    dismiss()
                }
                .disabled(trimmedName.isEmpty)
            }
        }
    }
}

/// Create or edit an activity: name, group, and SF Symbol icon.
struct ActivityEditor: View {
    let type: ActivityType?
    let timers: TimersStore

    @Environment(\.dismiss) private var dismiss
    @State private var name: String
    @State private var groupId: String?
    @State private var icon: String

    init(type: ActivityType?, timers: TimersStore) {
        self.type = type
        self.timers = timers
        _name = State(initialValue: type?.name ?? "")
        _groupId = State(initialValue: type?.groupId ?? timers.groups.first?.id)
        _icon = State(initialValue: type?.icon ?? "timer")
    }

    private var trimmedName: String { name.trimmingCharacters(in: .whitespaces) }
    private var iconIsValid: Bool { UIImage(systemName: icon) != nil }

    var body: some View {
        Form {
            Section {
                HStack(spacing: 12) {
                    Image(systemName: resolvedSymbolName(icon))
                        .font(.title)
                        .foregroundStyle(Color.accentColor)
                        .frame(width: 44, height: 44)
                    TextField("Name", text: $name)
                        .font(.title3)
                }
                Picker("Group", selection: $groupId) {
                    Text("No Group").tag(String?.none)
                    ForEach(timers.groups) { group in
                        Text(group.name).tag(Optional(group.id))
                    }
                }
            }

            Section {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 44), spacing: 8)], spacing: 8) {
                    ForEach(Self.suggestedIcons, id: \.self) { symbol in
                        Button {
                            icon = symbol
                        } label: {
                            Image(systemName: symbol)
                                .font(.title3)
                                .frame(width: 44, height: 44)
                                .foregroundStyle(icon == symbol ? Color.white : Color.primary)
                                .background(
                                    icon == symbol ? Color.accentColor : Color(.tertiarySystemFill),
                                    in: RoundedRectangle(cornerRadius: 10)
                                )
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(symbol)
                    }
                }
                .padding(.vertical, 4)
                TextField("SF Symbol name", text: $icon)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .font(.body.monospaced())
            } header: {
                Text("Icon")
            } footer: {
                if !iconIsValid {
                    Text("No SF Symbol named \u{201C}\(icon)\u{201D}. A timer icon will be shown instead.")
                        .foregroundStyle(.red)
                } else {
                    Text("Pick one above or type any SF Symbol name (see Apple's SF Symbols app).")
                }
            }
        }
        .navigationTitle(type == nil ? "New Activity" : "Edit Activity")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") { dismiss() }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("Save") { save() }
                    .disabled(trimmedName.isEmpty)
            }
        }
    }

    private func save() {
        // New activities, and ones moved to another group, go at the end of their group.
        let sortOrder: Int
        if let type, type.groupId == groupId {
            sortOrder = type.sortOrder
        } else {
            sortOrder = (timers.types.filter { $0.groupId == groupId }.map(\.sortOrder).max() ?? -1) + 1
        }
        let trimmedIcon = icon.trimmingCharacters(in: .whitespaces)
        CatalogActions.saveType(
            id: type?.id, name: trimmedName, groupId: groupId,
            icon: trimmedIcon.isEmpty ? nil : trimmedIcon,
            sortOrder: sortOrder, uid: timers.uid
        )
        dismiss()
    }

    static let suggestedIcons = [
        "timer", "briefcase.fill", "laptopcomputer", "book.fill", "pencil",
        "figure.run", "figure.walk", "figure.mind.and.body", "dumbbell.fill", "bicycle",
        "bed.double.fill", "fork.knife", "cup.and.saucer.fill", "cart.fill", "house.fill",
        "car.fill", "tram.fill", "music.note", "guitars.fill", "paintbrush.fill",
        "gamecontroller.fill", "tv.fill", "iphone", "bubble.left.and.bubble.right.fill", "phone.fill",
        "person.2.fill", "heart.fill", "leaf.fill", "sun.max.fill", "moon.fill",
        "star.fill", "flame.fill", "hammer.fill", "wrench.and.screwdriver.fill", "graduationcap.fill",
        "1.circle.fill", "2.circle.fill", "3.circle.fill", "4.circle.fill", "5.circle.fill",
    ]
}
