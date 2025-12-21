import SwiftUI

#if os(macOS)

/// Root view for macOS using NavigationSplitView
struct RootView_macOS: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        @Bindable var appState = appState

        NavigationSplitView {
            SidebarView()
        } detail: {
            NavigationStack(path: $appState.navigationPath) {
                // Aggregate view based on sidebar selection
                Group {
                    switch appState.sidebarSelection {
                    case .chats:
                        ChatListView()
                    case .characters:
                        CharacterListView()
                    case .groups:
                        GroupListView()
                    case .worldInfo:
                        WorldInfoListView()
                    case .settings:
                        SettingsView()
                    case .none:
                        ContentUnavailableView(
                            "Select an Item",
                            systemImage: "sidebar.left",
                            description: Text("Choose from the sidebar")
                        )
                    }
                }
                .navigationDestination(for: CharacterCard.self) { character in
                    CharacterDetailView(character: character)
                }
                .navigationDestination(for: ChatRoute.self) { route in
                    ChatDetailView_macOS(character: route.character)
                }
                .navigationDestination(for: WorldInfoBook.self) { book in
                    WorldInfoBookDetailView(book: book)
                }
                .navigationDestination(for: CharacterGroup.self) { group in
                    GroupDetailView(group: group)
                }
            }
        }
        .inspector(isPresented: $appState.isInspectorPresented) {
            InspectorView()
                .inspectorColumnWidth(min: 200, ideal: 300, max: 400)
        }
        .searchable(text: $appState.searchText)
    }
}

// MARK: - Sidebar

struct SidebarView: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        @Bindable var appState = appState

        List(selection: $appState.sidebarSelection) {
            Section("Library") {
                ForEach(SidebarItem.allCases) { item in
                    Label(item.title, systemImage: item.icon)
                        .tag(item)
                }
            }

            Section("Recent Chats") {
                // TODO: Show recent chats
                Text("No recent chats")
                    .foregroundStyle(.secondary)
            }
        }
        .navigationTitle("SillyTavern")
        .toolbar {
            ToolbarItem {
                Button {
                    appState.isInspectorPresented.toggle()
                } label: {
                    Label("Inspector", systemImage: "sidebar.right")
                }
                .keyboardShortcut("i", modifiers: [.command, .option])
            }
        }
    }
}

struct ChatListView: View {
    @Environment(AppState.self) private var appState

    /// Characters that have saved chats
    private var charactersWithChats: [CharacterCard] {
        appState.characters.characters.filter { character in
            !appState.chats.chats(for: character).isEmpty
        }
    }

    var body: some View {
        List {
            if charactersWithChats.isEmpty {
                ContentUnavailableView {
                    Label("No Chats", systemImage: "bubble.left.and.bubble.right")
                } description: {
                    Text("Start a chat with a character")
                }
            } else {
                ForEach(charactersWithChats) { character in
                    NavigationLink(value: ChatRoute(character: character)) {
                        CharacterRowView(character: character)
                    }
                }
            }
        }
        .navigationTitle("Chats")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Menu {
                    ForEach(appState.characters.characters) { character in
                        Button(character.name) {
                            appState.newChat(with: character)
                        }
                    }
                } label: {
                    Image(systemName: "plus")
                }
                .disabled(appState.characters.characters.isEmpty)
            }
        }
    }
}

// MARK: - Chat Detail View

struct ChatDetailView_macOS: View {
    let character: CharacterCard
    @Environment(AppState.self) private var appState
    @State private var editingMessage: ChatMessage?
    @State private var editText: String = ""

    var body: some View {
        VStack(spacing: 0) {
            // Messages
            messagesScrollView

            // Error banner
            if let error = appState.chatState.error {
                errorBanner(error)
            }

            Divider()

            // Input bar
            inputBar
        }
        .navigationTitle(character.name)
        .toolbar {
            toolbarContent
        }
        .sheet(item: $editingMessage) { message in
            MessageEditSheet(message: message, editText: $editText) {
                // Save changes
                message.mes = editText
                if let swipes = message.swipes, let swipeId = message.swipe_id, swipeId < swipes.count {
                    message.swipes?[swipeId] = editText
                }
                editingMessage = nil
                // Persist to disk
                Task {
                    await appState.saveActiveChat()
                }
            } onCancel: {
                editingMessage = nil
            }
            .onAppear {
                editText = message.displayedMessage
            }
        }
    }

    // MARK: - Messages

    private var messagesScrollView: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 12) {
                    ForEach(appState.chatState.messages) { message in
                        MessageBubble_macOS(
                            message: message,
                            onEdit: { msg in
                                editingMessage = msg
                            },
                            onDelete: { msg in
                                Task {
                                    if let index = appState.chatState.messages.firstIndex(where: { $0.id == msg.id }) {
                                        await appState.chatState.deleteMessage(at: index)
                                    }
                                }
                            },
                            onRegenerate: { msg in
                                Task {
                                    if let index = appState.chatState.messages.firstIndex(where: { $0.id == msg.id }) {
                                        await appState.chatState.regenerateFrom(index: index)
                                    }
                                }
                            }
                        )
                        .id(message.id)
                    }
                }
                .padding()
            }
            .onChange(of: appState.chatState.messages.count) {
                if let lastMessage = appState.chatState.messages.last {
                    withAnimation {
                        proxy.scrollTo(lastMessage.id, anchor: .bottom)
                    }
                }
            }
        }
    }

    // MARK: - Error Banner

    private func errorBanner(_ error: ChatError) -> some View {
        HStack {
            Image(systemName: "exclamationmark.triangle")
            Text(error.localizedDescription)
                .font(.caption)
            Spacer()
            Button("Dismiss") {
                appState.chatState.error = nil
            }
            .font(.caption)
            .buttonStyle(.plain)
        }
        .padding(8)
        .background(Color.red.opacity(0.1))
        .foregroundStyle(.red)
    }

    // MARK: - Input Bar

    private var inputBar: some View {
        HStack(spacing: 12) {
            @Bindable var chatState = appState.chatState
            TextField("Message...", text: $chatState.inputText, axis: .vertical)
                .textFieldStyle(.plain)
                .padding(8)
                .background(Color.secondary.opacity(0.1))
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .lineLimit(1...5)
                .disabled(appState.chatState.isGenerating)
                .onSubmit {
                    if !appState.chatState.inputText.isEmpty && !appState.chatState.isGenerating {
                        Task { await appState.chatState.send() }
                    }
                }

            Button {
                Task { await appState.chatState.send() }
            } label: {
                if appState.chatState.isGenerating {
                    ProgressView()
                        .scaleEffect(0.7)
                } else {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.title2)
                }
            }
            .buttonStyle(.plain)
            .disabled(appState.chatState.inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || appState.chatState.isGenerating)
            .keyboardShortcut(.return, modifiers: .command)
        }
        .padding()
    }

    // MARK: - Toolbar

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItemGroup {
            // Token count display
            Text("\(TokenCounter.format(appState.chatState.tokenCount)) / \(TokenCounter.format(appState.chatState.maxContextTokens))")
                .font(.caption)
                .foregroundStyle(.secondary)
                .monospacedDigit()

            Button {
                Task { await appState.chatState.regenerate() }
            } label: {
                Label("Regenerate", systemImage: "arrow.clockwise")
            }
            .disabled(appState.chatState.isGenerating || appState.chatState.messages.isEmpty)
            .keyboardShortcut("r", modifiers: .command)

            Button {
                Task { await appState.chatState.continueGeneration() }
            } label: {
                Label("Continue", systemImage: "arrow.right")
            }
            .disabled(appState.chatState.isGenerating || appState.chatState.messages.isEmpty || appState.chatState.messages.last?.is_user == true)
            .keyboardShortcut(.return, modifiers: [.command, .shift])
        }
    }
}

// MARK: - Inspector

struct InspectorView: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        if let character = appState.activeCharacter {
            Form {
                Section("Character") {
                    LabeledContent("Name", value: character.name)
                    if !character.creator.isEmpty {
                        LabeledContent("Creator", value: character.creator)
                    }
                }

                if !character.description.isEmpty {
                    Section("Description") {
                        Text(character.description)
                            .font(.caption)
                    }
                }

                Section("Stats") {
                    LabeledContent("Messages", value: "0")
                    LabeledContent("Tokens Used", value: "0")
                }
            }
            .formStyle(.grouped)
        } else {
            ContentUnavailableView(
                "No Selection",
                systemImage: "info.circle",
                description: Text("Select a chat to view details")
            )
        }
    }
}

// MARK: - Shared Components
// CharacterRowView is now in Features/Characters/CharacterListView.swift

struct MessageBubble_macOS: View {
    @Bindable var message: ChatMessage
    var onEdit: ((ChatMessage) -> Void)?
    var onDelete: ((ChatMessage) -> Void)?
    var onRegenerate: ((ChatMessage) -> Void)?

    var body: some View {
        HStack {
            if message.is_user { Spacer(minLength: 100) }

            VStack(alignment: message.is_user ? .trailing : .leading, spacing: 4) {
                // Character name and swipe controls
                if !message.is_user {
                    HStack(spacing: 8) {
                        Text(message.name)
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        // Swipe navigation
                        if message.hasSwipes {
                            HStack(spacing: 4) {
                                Button {
                                    message.previousSwipe()
                                } label: {
                                    Image(systemName: "chevron.left")
                                        .font(.caption2)
                                }
                                .buttonStyle(.plain)

                                Text("\((message.swipe_id ?? 0) + 1)/\(message.swipeCount)")
                                    .font(.caption2)
                                    .monospacedDigit()

                                Button {
                                    message.nextSwipe()
                                } label: {
                                    Image(systemName: "chevron.right")
                                        .font(.caption2)
                                }
                                .buttonStyle(.plain)
                            }
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.secondary.opacity(0.2))
                            .clipShape(Capsule())
                        }
                    }
                }

                // Message content
                Text(message.displayedMessage)
                    .padding(12)
                    .background(message.is_user ? Color.accentColor : Color.secondary.opacity(0.15))
                    .foregroundStyle(message.is_user ? .white : .primary)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .textSelection(.enabled)
                    .contextMenu {
                        Button {
                            onEdit?(message)
                        } label: {
                            Label("Edit", systemImage: "pencil")
                        }

                        Button {
                            onRegenerate?(message)
                        } label: {
                            Label("Regenerate from here", systemImage: "arrow.clockwise")
                        }

                        Divider()

                        Button(role: .destructive) {
                            onDelete?(message)
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }
                    }
            }

            if !message.is_user { Spacer(minLength: 100) }
        }
    }
}

// MARK: - Message Edit Sheet

struct MessageEditSheet: View {
    let message: ChatMessage
    @Binding var editText: String
    var onSave: () -> Void
    var onCancel: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            Text("Edit Message")
                .font(.headline)

            TextEditor(text: $editText)
                .frame(minHeight: 150)
                .padding(8)
                .background(Color.secondary.opacity(0.1))
                .clipShape(RoundedRectangle(cornerRadius: 8))

            HStack {
                Button("Cancel", role: .cancel) {
                    onCancel()
                }
                .keyboardShortcut(.escape)

                Spacer()

                Button("Save") {
                    onSave()
                }
                .keyboardShortcut(.return, modifiers: .command)
                .buttonStyle(.borderedProminent)
            }
        }
        .padding()
        .frame(width: 500, height: 300)
    }
}

#Preview {
    RootView_macOS()
        .environment(AppState())
        .frame(width: 1000, height: 600)
}
#endif
