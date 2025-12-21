import SwiftUI

// MARK: - Character Detail View

struct CharacterDetailView: View {
    @Bindable var character: CharacterCard
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss
    @State private var isEditing = false
    @State private var avatarImage: Image?

    private var hideNSFWImages: Bool { appState.settings.hideNSFWImages }

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                // Header with avatar
                headerSection

                // Quick actions
                actionButtons

                // Saved chats for this character
                savedChatsSection

                Divider()

                // Character info sections
                if isEditing {
                    editingContent
                } else {
                    readOnlyContent
                }
            }
            .padding()
        }
        .navigationTitle(character.name)
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .toolbar {
            toolbarContent
        }
        .task {
            await loadAvatar()
        }
    }

    // MARK: - Header

    private var headerSection: some View {
        VStack(spacing: 12) {
            // Avatar
            avatarView
                .frame(width: 120, height: 120)

            // Name and creator
            VStack(spacing: 4) {
                if isEditing {
                    TextField("Name", text: $character.name)
                        .font(.title)
                        .multilineTextAlignment(.center)
                        .textFieldStyle(.roundedBorder)
                } else {
                    Text(character.name)
                        .font(.title)
                        .fontWeight(.bold)
                }

                if !character.creator.isEmpty || isEditing {
                    HStack {
                        Text("by")
                            .foregroundStyle(.secondary)
                        if isEditing {
                            TextField("Creator", text: $character.creator)
                                .textFieldStyle(.roundedBorder)
                        } else {
                            Text(character.creator)
                        }
                    }
                    .font(.subheadline)
                }

                if !character.character_version.isEmpty {
                    Text("v\(character.character_version)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            // Tags
            if !character.tags.isEmpty || isEditing {
                tagsSection
            }
        }
    }

    @ViewBuilder
    private var avatarView: some View {
        if character.isNSFW && hideNSFWImages {
            // Show placeholder for hidden NSFW images
            RoundedRectangle(cornerRadius: 16)
                .fill(Color.red.opacity(0.15))
                .overlay {
                    VStack(spacing: 8) {
                        Image(systemName: "eye.slash.fill")
                            .font(.system(size: 32))
                        Text("NSFW")
                            .font(.caption)
                            .fontWeight(.medium)
                    }
                    .foregroundStyle(.secondary)
                }
        } else if let image = avatarImage {
            image
                .resizable()
                .aspectRatio(contentMode: .fill)
                .clipShape(RoundedRectangle(cornerRadius: 16))
        } else {
            RoundedRectangle(cornerRadius: 16)
                .fill(Color.secondary.opacity(0.2))
                .overlay {
                    Text(String(character.name.prefix(1)).uppercased())
                        .font(.system(size: 48))
                        .foregroundStyle(.secondary)
                }
        }
    }

    private var tagsSection: some View {
        FlowLayout(spacing: 8) {
            ForEach(character.tags, id: \.self) { tag in
                TagView(tag: tag, isEditing: isEditing) {
                    character.tags.removeAll { $0 == tag }
                }
            }
            if isEditing {
                AddTagButton { newTag in
                    if !character.tags.contains(newTag) {
                        character.tags.append(newTag)
                    }
                }
            }
        }
    }

    // MARK: - Action Buttons

    private var actionButtons: some View {
        HStack(spacing: 16) {
            Button {
                appState.newChat(with: character)
            } label: {
                Label("Start Chat", systemImage: "bubble.left.fill")
            }
            .buttonStyle(.borderedProminent)

            Button {
                character.fav.toggle()
            } label: {
                Label(
                    character.fav ? "Unfavorite" : "Favorite",
                    systemImage: character.fav ? "star.fill" : "star"
                )
            }
            .buttonStyle(.bordered)
        }
    }

    // MARK: - Saved Chats

    private var savedChats: [ChatFile] {
        appState.chats.chats(for: character)
    }

    @ViewBuilder
    private var savedChatsSection: some View {
        if !savedChats.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                Text("Saved Chats")
                    .font(.headline)

                ForEach(savedChats) { chat in
                    Button {
                        appState.openChat(chat, for: character)
                    } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(chat.fileName)
                                    .fontWeight(.medium)
                                Text("\(chat.messages.count) messages")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            if let lastModified = chat.lastModified {
                                Text(lastModified, style: .relative)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Image(systemName: "chevron.right")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .padding(12)
                        .background(Color.secondary.opacity(0.1))
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                    }
                    .buttonStyle(.plain)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    // MARK: - Read-Only Content

    private var readOnlyContent: some View {
        VStack(alignment: .leading, spacing: 20) {
            if !character.description.isEmpty {
                infoSection("Description", content: character.description)
            }

            if !character.personality.isEmpty {
                infoSection("Personality", content: character.personality)
            }

            if !character.scenario.isEmpty {
                infoSection("Scenario", content: character.scenario)
            }

            if !character.first_mes.isEmpty {
                infoSection("First Message", content: character.first_mes)
            }

            if !character.mes_example.isEmpty {
                infoSection("Example Messages", content: character.mes_example)
            }

            if !character.creator_notes.isEmpty {
                infoSection("Creator Notes", content: character.creator_notes)
            }

            if !character.system_prompt.isEmpty {
                infoSection("System Prompt", content: character.system_prompt)
            }

            if !character.post_history_instructions.isEmpty {
                infoSection("Post-History Instructions", content: character.post_history_instructions)
            }

            // Alternate greetings
            if !character.alternate_greetings.isEmpty {
                alternateGreetingsSection
            }

            // Depth prompt
            if let depthPrompt = character.depth_prompt, !depthPrompt.prompt.isEmpty {
                depthPromptSection(depthPrompt)
            }

            // Embedded lorebook
            if let book = character.character_book {
                lorebookSection(book)
            }
        }
    }

    private func infoSection(_ title: String, content: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.headline)

            Text(content)
                .font(.body)
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var alternateGreetingsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Alternate Greetings (\(character.alternate_greetings.count))")
                .font(.headline)

            ForEach(Array(character.alternate_greetings.enumerated()), id: \.offset) { index, greeting in
                DisclosureGroup("Greeting \(index + 1)") {
                    Text(greeting)
                        .font(.body)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                        .padding(.top, 4)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func depthPromptSection(_ depthPrompt: DepthPrompt) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Depth Prompt")
                    .font(.headline)
                Text("(depth: \(depthPrompt.depth), role: \(depthPrompt.role))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Text(depthPrompt.prompt)
                .font(.body)
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func lorebookSection(_ book: WorldInfoBook) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Embedded Lorebook (\(book.entries.count) entries)")
                .font(.headline)

            ForEach(book.entries) { entry in
                DisclosureGroup {
                    VStack(alignment: .leading, spacing: 4) {
                        if !entry.keys.isEmpty {
                            Text("Keys: \(entry.keys.joined(separator: ", "))")
                                .font(.caption)
                        }
                        Text(entry.content)
                            .font(.body)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.top, 4)
                } label: {
                    HStack {
                        Text(entry.comment.isEmpty ? "Entry \(entry.uid)" : entry.comment)
                        if !entry.enabled {
                            Text("(disabled)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Editing Content

    private var editingContent: some View {
        VStack(alignment: .leading, spacing: 20) {
            editableSection("Description", text: $character.description)
            editableSection("Personality", text: $character.personality)
            editableSection("Scenario", text: $character.scenario)
            editableSection("First Message", text: $character.first_mes)
            editableSection("Example Messages", text: $character.mes_example)
            editableSection("Creator Notes", text: $character.creator_notes)
            editableSection("System Prompt", text: $character.system_prompt)
            editableSection("Post-History Instructions", text: $character.post_history_instructions)
        }
    }

    private func editableSection(_ title: String, text: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.headline)

            TextEditor(text: text)
                .frame(minHeight: 100)
                .padding(8)
                .background(Color.secondary.opacity(0.1))
                .clipShape(RoundedRectangle(cornerRadius: 8))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Toolbar

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .primaryAction) {
            Button {
                isEditing.toggle()
                if !isEditing {
                    // Save changes via the store
                    appState.characters.add(character)
                }
            } label: {
                Text(isEditing ? "Done" : "Edit")
            }
        }
    }

    // MARK: - Avatar Loading

    private func loadAvatar() async {
        guard let fileURL = character.fileURL,
              fileURL.pathExtension.lowercased() == "png" else { return }

        #if os(iOS)
        if let uiImage = UIImage(contentsOfFile: fileURL.path) {
            avatarImage = Image(uiImage: uiImage)
        }
        #elseif os(macOS)
        if let nsImage = NSImage(contentsOf: fileURL) {
            avatarImage = Image(nsImage: nsImage)
        }
        #endif
    }
}

// MARK: - Tag View

struct TagView: View {
    let tag: String
    let isEditing: Bool
    let onDelete: () -> Void

    var body: some View {
        HStack(spacing: 4) {
            Text(tag)
                .font(.caption)

            if isEditing {
                Button(action: onDelete) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.caption2)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(Color.accentColor.opacity(0.15))
        .clipShape(Capsule())
    }
}

// MARK: - Add Tag Button

struct AddTagButton: View {
    let onAdd: (String) -> Void
    @State private var isAdding = false
    @State private var newTag = ""

    var body: some View {
        if isAdding {
            HStack(spacing: 4) {
                TextField("Tag", text: $newTag)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 100)
                    .onSubmit {
                        addTag()
                    }

                Button {
                    addTag()
                } label: {
                    Image(systemName: "checkmark.circle.fill")
                }
                .buttonStyle(.plain)
                .disabled(newTag.isEmpty)

                Button {
                    isAdding = false
                    newTag = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                }
                .buttonStyle(.plain)
            }
        } else {
            Button {
                isAdding = true
            } label: {
                Label("Add Tag", systemImage: "plus.circle")
                    .font(.caption)
            }
            .buttonStyle(.bordered)
        }
    }

    private func addTag() {
        let trimmed = newTag.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty {
            onAdd(trimmed)
        }
        isAdding = false
        newTag = ""
    }
}

// MARK: - Flow Layout

struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let result = FlowResult(in: proposal.replacingUnspecifiedDimensions().width, subviews: subviews, spacing: spacing)
        return CGSize(width: proposal.replacingUnspecifiedDimensions().width, height: result.height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result = FlowResult(in: bounds.width, subviews: subviews, spacing: spacing)
        for (index, subview) in subviews.enumerated() {
            let point = result.positions[index]
            subview.place(at: CGPoint(x: bounds.minX + point.x, y: bounds.minY + point.y), proposal: .unspecified)
        }
    }

    struct FlowResult {
        var positions: [CGPoint] = []
        var height: CGFloat = 0

        init(in maxWidth: CGFloat, subviews: Subviews, spacing: CGFloat) {
            var x: CGFloat = 0
            var y: CGFloat = 0
            var rowHeight: CGFloat = 0

            for subview in subviews {
                let size = subview.sizeThatFits(.unspecified)
                if x + size.width > maxWidth && x > 0 {
                    x = 0
                    y += rowHeight + spacing
                    rowHeight = 0
                }
                positions.append(CGPoint(x: x, y: y))
                rowHeight = max(rowHeight, size.height)
                x += size.width + spacing
            }
            height = y + rowHeight
        }
    }
}

// MARK: - Preview

#Preview {
    NavigationStack {
        CharacterDetailView(character: CharacterCard())
            .environment(AppState())
    }
}
