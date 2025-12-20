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
                    ChatDetailView_macOS(character: character)
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

    var body: some View {
        List {
            if appState.characters.characters.isEmpty {
                Text("No chats yet")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(appState.characters.characters) { character in
                    NavigationLink(value: character) {
                        CharacterRowView(character: character)
                    }
                }
            }
        }
        .navigationTitle("Chats")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    // TODO: New chat
                } label: {
                    Image(systemName: "plus")
                }
            }
        }
    }
}

// MARK: - Chat Detail View

struct ChatDetailView_macOS: View {
    let character: CharacterCard
    @Environment(AppState.self) private var appState

    private var chatState: ChatState { appState.chatState }

    var body: some View {
        VStack(spacing: 0) {
            // Messages
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 12) {
                        ForEach(appState.chatState.messages) { message in
                            MessageBubble_macOS(
                                content: message.content,
                                isUser: message.role == .user,
                                characterName: message.role == .assistant ? character.name : nil
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

            // Error banner
            if let error = appState.chatState.error {
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

            Divider()

            // Input bar
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
        .navigationTitle(character.name)
        .toolbar {
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
                .disabled(appState.chatState.isGenerating || appState.chatState.messages.last?.role != .assistant)
                .keyboardShortcut(.return, modifiers: [.command, .shift])
            }
        }
        .onAppear {
            configureChatState()
        }
    }

    private func configureChatState() {
        if let provider = appState.settings.createProvider() {
            appState.chatState.configure(
                character: character,
                provider: provider,
                settings: appState.settings.createPromptSettings(),
                worldInfo: appState.worldInfo.allEntries,
                extensionPrompts: appState.settings.createExtensionPrompts(),
                tokenizer: appState.settings.createTokenizer(),
                model: appState.settings.model,
                personaName: appState.settings.personaName,
                personaDescription: appState.settings.personaDescription
            )
        } else {
            appState.chatState.character = character
            if !character.first_mes.isEmpty && appState.chatState.messages.isEmpty {
                appState.chatState.messages = [Message(role: .assistant, content: character.first_mes)]
            }
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
    let content: String
    let isUser: Bool
    let characterName: String?

    var body: some View {
        HStack {
            if isUser { Spacer(minLength: 100) }

            VStack(alignment: isUser ? .trailing : .leading) {
                if let name = characterName, !isUser {
                    Text(name)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Text(content)
                    .padding(12)
                    .background(isUser ? Color.accentColor : Color.secondary.opacity(0.15))
                    .foregroundStyle(isUser ? .white : .primary)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .textSelection(.enabled)
            }

            if !isUser { Spacer(minLength: 100) }
        }
    }
}

#Preview {
    RootView_macOS()
        .environment(AppState())
        .frame(width: 1000, height: 600)
}
#endif
