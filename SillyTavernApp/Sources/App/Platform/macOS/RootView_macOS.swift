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
                    ChatDetailView_macOS(character: route.character, chat: route.chat)
                }
                .navigationDestination(for: GroupChatRoute.self) { route in
                    GroupChatDetailView_macOS(group: route.group, chat: route.chat)
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

/// Represents either a character chat or a group chat for unified display
enum ChatItem: Identifiable {
    case character(chat: ChatFile, character: CharacterCard)
    case group(chat: ChatFile, group: CharacterGroup)

    var id: UUID { chat.id }

    var chat: ChatFile {
        switch self {
        case .character(let chat, _): return chat
        case .group(let chat, _): return chat
        }
    }

    var name: String {
        switch self {
        case .character(_, let character): return character.name
        case .group(_, let group): return group.name
        }
    }

    var isGroup: Bool {
        if case .group = self { return true }
        return false
    }
}

struct ChatListView: View {
    @Environment(AppState.self) private var appState

    /// All chats (character and group), sorted by most recent
    private var allChats: [ChatItem] {
        var items: [ChatItem] = []

        // Add character chats
        for character in appState.characters.characters {
            for chat in appState.chats.chats(for: character) {
                items.append(.character(chat: chat, character: character))
            }
        }

        // Add group chats
        for group in appState.groups.groups {
            for chat in appState.chats.chats(for: group) {
                items.append(.group(chat: chat, group: group))
            }
        }

        // Sort by most recent
        return items.sorted { ($0.chat.lastModified ?? .distantPast) > ($1.chat.lastModified ?? .distantPast) }
    }

    var body: some View {
        List {
            if allChats.isEmpty {
                ContentUnavailableView {
                    Label("No Chats", systemImage: "bubble.left.and.bubble.right")
                } description: {
                    Text("Start a chat with a character or group")
                }
            } else {
                ForEach(allChats) { item in
                    switch item {
                    case .character(let chat, let character):
                        NavigationLink(value: ChatRoute(character: character, chat: chat)) {
                            ChatRowView(chat: chat, character: character)
                        }
                    case .group(let chat, let group):
                        NavigationLink(value: GroupChatRoute(group: group, chat: chat)) {
                            GroupChatRowView(chat: chat, group: group)
                        }
                    }
                }
            }
        }
        .navigationTitle("Chats")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Menu {
                    Section("Characters") {
                        ForEach(appState.characters.characters) { character in
                            Button(character.name) {
                                appState.newChat(with: character)
                            }
                        }
                    }
                    Section("Groups") {
                        ForEach(appState.groups.groups) { group in
                            Button(group.name) {
                                appState.newGroupChat(with: group)
                            }
                            .disabled(group.enabledMembers.isEmpty)
                        }
                    }
                } label: {
                    Image(systemName: "plus")
                }
                .disabled(appState.characters.characters.isEmpty && appState.groups.groups.isEmpty)
            }
        }
        .alert("Error", isPresented: .init(
            get: { appState.chats.error != nil },
            set: { if !$0 { appState.chats.error = nil } }
        )) {
            Button("OK") { appState.chats.error = nil }
        } message: {
            Text(appState.chats.error?.localizedDescription ?? "Unknown error")
        }
    }
}

// MARK: - Chat Row View

struct ChatRowView: View {
    let chat: ChatFile
    let character: CharacterCard

    var body: some View {
        HStack(spacing: 12) {
            // Character initial
            Circle()
                .fill(Color.accentColor.opacity(0.2))
                .frame(width: 40, height: 40)
                .overlay {
                    Text(String(character.name.prefix(1)).uppercased())
                        .font(.headline)
                        .foregroundStyle(Color.accentColor)
                }

            // Chat info
            VStack(alignment: .leading, spacing: 4) {
                Text(character.name)
                    .font(.headline)
                    .lineLimit(1)

                HStack(spacing: 8) {
                    Text(chat.fileName)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)

                    Text("•")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Text("\(chat.messages.count) messages")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            // Last modified
            if let lastModified = chat.lastModified {
                Text(lastModified, style: .relative)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Group Chat Row View

struct GroupChatRowView: View {
    let chat: ChatFile
    let group: CharacterGroup

    var body: some View {
        HStack(spacing: 12) {
            // Group icon
            Circle()
                .fill(Color.purple.opacity(0.2))
                .frame(width: 40, height: 40)
                .overlay {
                    Image(systemName: "person.3")
                        .font(.caption)
                        .foregroundStyle(Color.purple)
                }

            // Chat info
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(group.name.isEmpty ? "Untitled Group" : group.name)
                        .font(.headline)
                        .lineLimit(1)

                    Text("Group")
                        .font(.caption2)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.purple.opacity(0.15))
                        .foregroundColor(.purple)
                        .clipShape(Capsule())
                }

                HStack(spacing: 8) {
                    Text(chat.fileName)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)

                    Text("•")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Text("\(chat.messages.count) messages")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            // Last modified
            if let lastModified = chat.lastModified {
                Text(lastModified, style: .relative)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Chat Detail View

struct ChatDetailView_macOS: View {
    let character: CharacterCard
    let chat: ChatFile?
    @Environment(AppState.self) private var appState
    @State private var editingMessage: ChatMessage?
    @State private var editText: String = ""
    @State private var isAtBottom: Bool = true

    /// Threshold for detecting "at bottom" scroll position
    private let scrollBottomThreshold: CGFloat = 50

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
        .task(id: chat?.fileURL) {
            // Configure the chat when the view appears or when chat changes
            // Use configureChat/createNewChat (not openChat/newChat) since we're already in the view
            if let chat = chat {
                // Only configure if not already showing this chat
                if appState.activeChatFile?.fileURL != chat.fileURL {
                    appState.configureChat(chat, for: character)
                }
            } else {
                // No specific chat - configure most recent or create new
                if let mostRecent = appState.chats.chats(for: character).first {
                    appState.configureChat(mostRecent, for: character)
                } else {
                    await appState.createNewChat(with: character)
                }
            }
        }
        .sheet(item: $editingMessage) { message in
            MessageEditSheet(message: message, editText: $editText) {
                // Save changes via ChatState for proper persistence
                if let index = appState.chatState.messages.firstIndex(where: { $0.id == message.id }) {
                    // Update the current swipe if swipes exist, otherwise update mes
                    if let swipes = message.swipes, let swipeId = message.swipe_id, swipeId < swipes.count {
                        message.swipes?[swipeId] = editText
                    }
                    Task {
                        await appState.chatState.editMessage(at: index, newContent: editText)
                    }
                }
                editingMessage = nil
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
                .padding(.bottom, 60)
            }
            .onScrollGeometryChange(for: Bool.self) { geometry in
                // Check if scrolled to bottom (within threshold)
                let atBottom = geometry.contentOffset.y + geometry.containerSize.height >= geometry.contentSize.height - scrollBottomThreshold
                return atBottom
            } action: { _, newValue in
                isAtBottom = newValue
            }
            .onChange(of: appState.chatState.messages.count) {
                // Only auto-scroll if user was already at bottom
                if isAtBottom, let lastMessage = appState.chatState.messages.last {
                    withAnimation {
                        proxy.scrollTo(lastMessage.id, anchor: .bottom)
                    }
                }
            }
            .onChange(of: appState.chatState.streamingText) {
                // Also scroll during streaming if at bottom
                if isAtBottom, let lastMessage = appState.chatState.messages.last {
                    proxy.scrollTo(lastMessage.id, anchor: .bottom)
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
            .accessibilityLabel(appState.chatState.isGenerating ? "Generating response" : "Send message")
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

// MARK: - Group Chat Detail View

struct GroupChatDetailView_macOS: View {
    let group: CharacterGroup
    let chat: ChatFile?
    @Environment(AppState.self) private var appState
    @State private var editingMessage: ChatMessage?
    @State private var editText: String = ""
    @State private var isAtBottom: Bool = true

    /// Threshold for detecting "at bottom" scroll position
    private let scrollBottomThreshold: CGFloat = 50

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
        .navigationTitle(group.name)
        .toolbar {
            toolbarContent
        }
        .task(id: chat?.fileURL) {
            // Configure the chat when the view appears or when chat changes
            // Use configureGroupChat/createNewGroupChat (not openGroupChat/newGroupChat) since we're already in the view
            if let chat = chat {
                // Only configure if not already showing this chat
                if appState.activeChatFile?.fileURL != chat.fileURL {
                    appState.configureGroupChat(chat, for: group)
                }
            } else {
                // No specific chat - configure most recent or create new
                if let mostRecent = appState.chats.chats(for: group).first {
                    appState.configureGroupChat(mostRecent, for: group)
                } else {
                    await appState.createNewGroupChat(with: group)
                }
            }
        }
        .sheet(item: $editingMessage) { message in
            MessageEditSheet(message: message, editText: $editText) {
                // Save changes via ChatState for proper persistence
                if let index = appState.chatState.messages.firstIndex(where: { $0.id == message.id }) {
                    // Update the current swipe if swipes exist, otherwise update mes
                    if let swipes = message.swipes, let swipeId = message.swipe_id, swipeId < swipes.count {
                        message.swipes?[swipeId] = editText
                    }
                    Task {
                        await appState.chatState.editMessage(at: index, newContent: editText)
                    }
                }
                editingMessage = nil
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
                .padding(.bottom, 60)
            }
            .onScrollGeometryChange(for: Bool.self) { geometry in
                // Check if scrolled to bottom (within threshold)
                let atBottom = geometry.contentOffset.y + geometry.containerSize.height >= geometry.contentSize.height - scrollBottomThreshold
                return atBottom
            } action: { _, newValue in
                isAtBottom = newValue
            }
            .onChange(of: appState.chatState.messages.count) {
                // Only auto-scroll if user was already at bottom
                if isAtBottom, let lastMessage = appState.chatState.messages.last {
                    withAnimation {
                        proxy.scrollTo(lastMessage.id, anchor: .bottom)
                    }
                }
            }
            .onChange(of: appState.chatState.streamingText) {
                // Also scroll during streaming if at bottom
                if isAtBottom, let lastMessage = appState.chatState.messages.last {
                    proxy.scrollTo(lastMessage.id, anchor: .bottom)
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
            .accessibilityLabel(appState.chatState.isGenerating ? "Generating response" : "Send message")
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

            // Current speaker display
            if let speaker = appState.chatState.currentSpeaker {
                Text("Next: \(speaker.name)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

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
                                .accessibilityLabel("Previous response")

                                Text("\((message.swipe_id ?? 0) + 1)/\(message.swipeCount)")
                                    .font(.caption2)
                                    .monospacedDigit()
                                    .accessibilityLabel("Response \((message.swipe_id ?? 0) + 1) of \(message.swipeCount)")

                                Button {
                                    message.nextSwipe()
                                } label: {
                                    Image(systemName: "chevron.right")
                                        .font(.caption2)
                                }
                                .buttonStyle(.plain)
                                .accessibilityLabel("Next response")
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
