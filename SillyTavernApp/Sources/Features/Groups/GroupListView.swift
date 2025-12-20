import SwiftUI

// MARK: - Group List View

struct GroupListView: View {
    @Environment(AppState.self) private var appState
    @State private var showingNewGroupSheet = false
    @State private var newGroupName = ""

    var filteredGroups: [CharacterGroup] {
        let groups = appState.groups.groups
        if appState.searchText.isEmpty {
            return groups
        }
        return groups.filter {
            $0.name.localizedCaseInsensitiveContains(appState.searchText) ||
            $0.members.contains { member in
                member.character?.name.localizedCaseInsensitiveContains(appState.searchText) ?? false
            }
        }
    }

    var body: some View {
        Group {
            if appState.groups.isLoading {
                ProgressView("Loading groups...")
            } else if filteredGroups.isEmpty {
                emptyState
            } else {
                groupList
            }
        }
        .navigationTitle("Groups")
        .toolbar {
            toolbarContent
        }
        .sheet(isPresented: $showingNewGroupSheet) {
            newGroupSheet
        }
    }

    // MARK: - Group List

    private var groupList: some View {
        List {
            ForEach(filteredGroups) { group in
                NavigationLink(value: group) {
                    GroupRowView(group: group)
                }
                .contextMenu {
                    groupContextMenu(for: group)
                }
            }
            .onDelete(perform: deleteGroups)
        }
        .listStyle(.plain)
    }

    // MARK: - Empty State

    private var emptyState: some View {
        ContentUnavailableView {
            Label("No Groups", systemImage: "person.3")
        } description: {
            if appState.searchText.isEmpty {
                Text("Create a group to chat with multiple characters")
            } else {
                Text("No groups match '\(appState.searchText)'")
            }
        } actions: {
            if appState.searchText.isEmpty {
                Button {
                    showingNewGroupSheet = true
                } label: {
                    Text("New Group")
                }
                .buttonStyle(.borderedProminent)
            }
        }
    }

    // MARK: - New Group Sheet

    private var newGroupSheet: some View {
        NavigationStack {
            Form {
                TextField("Group Name", text: $newGroupName)
            }
            .navigationTitle("New Group")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        newGroupName = ""
                        showingNewGroupSheet = false
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Create") {
                        createNewGroup()
                    }
                    .disabled(newGroupName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
        #if os(macOS)
        .frame(minWidth: 300, minHeight: 150)
        #endif
    }

    // MARK: - Toolbar

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .primaryAction) {
            Button {
                showingNewGroupSheet = true
            } label: {
                Label("New Group", systemImage: "plus")
            }
        }
    }

    // MARK: - Context Menu

    @ViewBuilder
    private func groupContextMenu(for group: CharacterGroup) -> some View {
        Button {
            // TODO: Duplicate group
        } label: {
            Label("Duplicate", systemImage: "doc.on.doc")
        }

        Divider()

        Button(role: .destructive) {
            appState.groups.remove(group)
        } label: {
            Label("Delete", systemImage: "trash")
        }
    }

    // MARK: - Actions

    private func deleteGroups(at offsets: IndexSet) {
        for index in offsets {
            let group = filteredGroups[index]
            appState.groups.remove(group)
        }
    }

    private func createNewGroup() {
        let group = CharacterGroup(name: newGroupName.trimmingCharacters(in: .whitespacesAndNewlines))
        appState.groups.add(group)
        newGroupName = ""
        showingNewGroupSheet = false
    }
}

// MARK: - Group Row View

struct GroupRowView: View {
    let group: CharacterGroup

    var enabledCount: Int {
        group.enabledMembers.count
    }

    var memberNames: String {
        let names = group.members.prefix(3).compactMap { $0.character?.name }
        if names.isEmpty {
            return "No members"
        }
        var result = names.joined(separator: ", ")
        if group.members.count > 3 {
            result += " +\(group.members.count - 3)"
        }
        return result
    }

    var body: some View {
        HStack(spacing: 12) {
            // Avatar stack
            avatarStack

            // Info
            VStack(alignment: .leading, spacing: 4) {
                Text(group.name.isEmpty ? "Untitled Group" : group.name)
                    .font(.headline)
                    .lineLimit(1)

                Text(memberNames)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)

                // Badges
                HStack(spacing: 6) {
                    Text(group.activationStrategy.title)
                        .font(.caption2)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.accentColor.opacity(0.15))
                        .foregroundColor(.accentColor)
                        .clipShape(Capsule())

                    if enabledCount < group.members.count {
                        Text("\(enabledCount)/\(group.members.count) active")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            Spacer()
        }
        .padding(.vertical, 4)
    }

    private var avatarStack: some View {
        ZStack {
            // Show up to 3 member avatars stacked
            ForEach(Array(group.members.prefix(3).enumerated()), id: \.element.id) { index, member in
                Circle()
                    .fill(Color.secondary.opacity(0.2))
                    .frame(width: 32, height: 32)
                    .overlay {
                        if let char = member.character {
                            Text(String(char.name.prefix(1)).uppercased())
                                .font(.caption)
                                .fontWeight(.medium)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .offset(x: CGFloat(index) * 12)
            }
        }
        .frame(width: 56, height: 40)
    }
}

// MARK: - Group Detail View

struct GroupDetailView: View {
    @Bindable var group: CharacterGroup
    @Environment(AppState.self) private var appState
    @State private var showingAddMember = false
    @State private var isEditing = false

    var body: some View {
        List {
            // Settings section
            settingsSection

            // Members section
            membersSection
        }
        .navigationTitle(group.name.isEmpty ? "Untitled Group" : group.name)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    isEditing.toggle()
                    if !isEditing {
                        saveGroup()
                    }
                } label: {
                    Text(isEditing ? "Done" : "Edit")
                }
            }

            if !isEditing {
                ToolbarItem(placement: .automatic) {
                    Button {
                        showingAddMember = true
                    } label: {
                        Label("Add Member", systemImage: "plus")
                    }
                }
            }
        }
        .sheet(isPresented: $showingAddMember) {
            AddMemberSheet(group: group)
        }
    }

    // MARK: - Settings Section

    private var settingsSection: some View {
        Section {
            if isEditing {
                TextField("Name", text: $group.name)
            }

            Picker("Activation", selection: $group.activationStrategy) {
                ForEach(ActivationStrategy.allCases, id: \.self) { strategy in
                    Text(strategy.title).tag(strategy)
                }
            }

            Picker("Generation Mode", selection: $group.generationMode) {
                ForEach(GenerationMode.allCases, id: \.self) { mode in
                    Text(mode.title).tag(mode)
                }
            }

            Toggle("Allow Self-Response", isOn: $group.allowSelfResponse)
        } header: {
            Text("Settings")
        } footer: {
            Text(group.activationStrategy.description)
        }
    }

    // MARK: - Members Section

    private var membersSection: some View {
        Section {
            if group.members.isEmpty {
                ContentUnavailableView {
                    Label("No Members", systemImage: "person.slash")
                } description: {
                    Text("Add characters to this group")
                }
            } else {
                ForEach(group.members) { member in
                    GroupMemberRow(
                        member: member,
                        group: group,
                        isEditing: isEditing
                    )
                }
                .onDelete(perform: deleteMembers)
                .onMove(perform: moveMembers)
            }
        } header: {
            HStack {
                Text("Members (\(group.members.count))")
                Spacer()
                if isEditing {
                    Button {
                        showingAddMember = true
                    } label: {
                        Label("Add", systemImage: "plus.circle")
                            .font(.caption)
                    }
                }
            }
        }
    }

    // MARK: - Actions

    private func deleteMembers(at offsets: IndexSet) {
        for index in offsets {
            group.removeMember(group.members[index])
        }
    }

    private func moveMembers(from source: IndexSet, to destination: Int) {
        group.members.move(fromOffsets: source, toOffset: destination)
    }

    private func saveGroup() {
        Task {
            await appState.groups.save(group)
        }
    }
}

// MARK: - Group Member Row

struct GroupMemberRow: View {
    let member: GroupMember
    let group: CharacterGroup
    let isEditing: Bool

    var isEnabled: Bool {
        !group.disabledMembers.contains(member.id)
    }

    var isFavorite: Bool {
        group.favoriteMembers.contains(member.id)
    }

    var body: some View {
        HStack(spacing: 12) {
            // Avatar
            Circle()
                .fill(isEnabled ? Color.green.opacity(0.2) : Color.secondary.opacity(0.2))
                .frame(width: 36, height: 36)
                .overlay {
                    if let char = member.character {
                        Text(String(char.name.prefix(1)).uppercased())
                            .font(.caption)
                            .fontWeight(.medium)
                            .foregroundStyle(isEnabled ? .green : .secondary)
                    }
                }

            // Info
            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    Text(member.character?.name ?? member.characterID)
                        .font(.headline)

                    if isFavorite {
                        Image(systemName: "star.fill")
                            .font(.caption)
                            .foregroundStyle(.yellow)
                    }
                }

                if let char = member.character, !char.description.isEmpty {
                    Text(char.description)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }

            Spacer()

            if !isEditing {
                // Toggle enabled
                Button {
                    group.toggleMember(member)
                } label: {
                    Image(systemName: isEnabled ? "eye" : "eye.slash")
                        .foregroundStyle(isEnabled ? .green : .secondary)
                }
                .buttonStyle(.plain)
            }
        }
        .opacity(isEnabled ? 1 : 0.6)
        .contextMenu {
            Button {
                group.toggleMember(member)
            } label: {
                Label(isEnabled ? "Disable" : "Enable", systemImage: isEnabled ? "eye.slash" : "eye")
            }

            Button {
                group.toggleFavorite(member)
            } label: {
                Label(isFavorite ? "Unfavorite" : "Favorite", systemImage: isFavorite ? "star.slash" : "star")
            }

            Divider()

            Button(role: .destructive) {
                group.removeMember(member)
            } label: {
                Label("Remove", systemImage: "trash")
            }
        }
    }
}

// MARK: - Add Member Sheet

struct AddMemberSheet: View {
    let group: CharacterGroup
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss
    @State private var searchText = ""

    var availableCharacters: [CharacterCard] {
        let existingIDs = Set(group.members.map { $0.characterID })
        return appState.characters.characters.filter { char in
            !existingIDs.contains(char.avatar) && !existingIDs.contains(char.name)
        }
    }

    var filteredCharacters: [CharacterCard] {
        if searchText.isEmpty {
            return availableCharacters
        }
        return availableCharacters.filter {
            $0.name.localizedCaseInsensitiveContains(searchText)
        }
    }

    var body: some View {
        NavigationStack {
            characterList
            .searchable(text: $searchText, prompt: "Search characters")
            .navigationTitle("Add Member")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
        #if os(macOS)
        .frame(minWidth: 400, minHeight: 500)
        #endif
    }

    private var characterList: some View {
        List {
            if filteredCharacters.isEmpty {
                emptyContent
            } else {
                ForEach(filteredCharacters) { character in
                    CharacterSelectionRow(character: character) {
                        addMember(character)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var emptyContent: some View {
        if availableCharacters.isEmpty {
            ContentUnavailableView("No Characters", systemImage: "person.slash", description: Text("All characters are already in this group"))
        } else {
            ContentUnavailableView("No Matches", systemImage: "magnifyingglass", description: Text("No characters match '\(searchText)'"))
        }
    }

    private func addMember(_ character: CharacterCard) {
        let member = GroupMember(characterID: character.avatar, character: character)
        group.addMember(member)
    }
}

struct CharacterSelectionRow: View {
    let character: CharacterCard
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Circle()
                    .fill(Color.secondary.opacity(0.2))
                    .frame(width: 40, height: 40)
                    .overlay {
                        Text(String(character.name.prefix(1)).uppercased())
                            .font(.headline)
                            .foregroundStyle(.secondary)
                    }

                VStack(alignment: .leading) {
                    Text(character.name)
                        .font(.headline)
                        .foregroundStyle(.primary)

                    if !character.description.isEmpty {
                        Text(character.description)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }

                Spacer()

                Image(systemName: "plus.circle")
                    .foregroundColor(.accentColor)
            }
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Preview

#Preview {
    NavigationStack {
        GroupListView()
            .environment(AppState())
    }
}
