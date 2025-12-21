import SwiftUI

#if os(iOS)
/// Root view for iOS using TabView navigation
struct RootView_iOS: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        @Bindable var appState = appState

        TabView(selection: $appState.selectedTab) {
            ChatsTab()
                .tabItem {
                    Label(Tab.chats.title, systemImage: Tab.chats.icon)
                }
                .tag(Tab.chats)

            CharactersTab()
                .tabItem {
                    Label(Tab.characters.title, systemImage: Tab.characters.icon)
                }
                .tag(Tab.characters)

            GroupsTab()
                .tabItem {
                    Label(Tab.groups.title, systemImage: Tab.groups.icon)
                }
                .tag(Tab.groups)

            WorldInfoTab()
                .tabItem {
                    Label(Tab.worldInfo.title, systemImage: Tab.worldInfo.icon)
                }
                .tag(Tab.worldInfo)

            SettingsTab()
                .tabItem {
                    Label(Tab.settings.title, systemImage: Tab.settings.icon)
                }
                .tag(Tab.settings)
        }
    }
}

// MARK: - Tab Views (Placeholders)

struct ChatsTab: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        NavigationStack {
            List {
                if appState.characters.characters.isEmpty {
                    ContentUnavailableView(
                        "No Chats",
                        systemImage: "bubble.left.and.bubble.right",
                        description: Text("Start a chat by selecting a character")
                    )
                } else {
                    ForEach(appState.characters.characters) { character in
                        NavigationLink(value: character) {
                            CharacterRow(character: character)
                        }
                    }
                }
            }
            .navigationTitle("Chats")
            .navigationDestination(for: CharacterCard.self) { character in
                ChatView(character: character)
            }
        }
    }
}

struct CharactersTab: View {
    var body: some View {
        NavigationStack {
            CharacterListView()
                .navigationDestination(for: CharacterCard.self) { character in
                    CharacterDetailView(character: character)
                }
        }
    }
}

struct GroupsTab: View {
    var body: some View {
        NavigationStack {
            GroupListView()
                .navigationDestination(for: CharacterGroup.self) { group in
                    GroupDetailView(group: group)
                }
        }
    }
}

struct WorldInfoTab: View {
    var body: some View {
        NavigationStack {
            WorldInfoListView()
                .navigationDestination(for: WorldInfoBook.self) { book in
                    WorldInfoBookDetailView(book: book)
                }
        }
    }
}

struct SettingsTab: View {
    var body: some View {
        NavigationStack {
            SettingsView()
        }
    }
}

// MARK: - Shared Components

struct CharacterRow: View {
    let character: CharacterCard

    var body: some View {
        HStack {
            // Placeholder avatar
            Circle()
                .fill(Color.secondary.opacity(0.2))
                .frame(width: 44, height: 44)
                .overlay {
                    Text(String(character.name.prefix(1)).uppercased())
                        .font(.headline)
                        .foregroundStyle(.secondary)
                }

            VStack(alignment: .leading) {
                Text(character.name)
                    .font(.headline)

                if !character.description.isEmpty {
                    Text(character.description)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
        }
    }
}

struct ChatView: View {
    let character: CharacterCard
    @Environment(AppState.self) private var appState
    @State private var scrollProxy: ScrollViewProxy?

    var body: some View {
        @Bindable var chatState = appState.chatState

        VStack(spacing: 0) {
            // Messages
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 12) {
                        ForEach(appState.chatState.messages) { message in
                            MessageBubble(
                                content: message.content,
                                isUser: message.role == .user,
                                characterName: message.role == .assistant ? character.name : nil
                            )
                            .id(message.id)
                        }

                        // Streaming indicator
                        if appState.chatState.isGenerating && !appState.chatState.streamingText.isEmpty {
                            HStack {
                                ProgressView()
                                    .scaleEffect(0.8)
                                Spacer()
                            }
                            .padding(.horizontal)
                        }
                    }
                    .padding()
                }
                .onAppear {
                    scrollProxy = proxy
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
                }
                .padding(8)
                .background(Color.red.opacity(0.1))
                .foregroundStyle(.red)
            }

            Divider()

            // Input bar
            HStack(spacing: 12) {
                TextField("Message...", text: $chatState.inputText, axis: .vertical)
                    .textFieldStyle(.roundedBorder)
                    .lineLimit(1...5)
                    .disabled(appState.chatState.isGenerating)

                Button {
                    Task {
                        await appState.chatState.send()
                    }
                } label: {
                    if appState.chatState.isGenerating {
                        ProgressView()
                    } else {
                        Image(systemName: "arrow.up.circle.fill")
                            .font(.title)
                    }
                }
                .disabled(appState.chatState.inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || appState.chatState.isGenerating)
            }
            .padding()
        }
        .navigationTitle(character.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                VStack(spacing: 0) {
                    Text(character.name)
                        .font(.headline)
                    Text("\(TokenCounter.format(appState.chatState.tokenCount)) / \(TokenCounter.format(appState.chatState.maxContextTokens)) tokens")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            ToolbarItemGroup(placement: .primaryAction) {
                Menu {
                    Button {
                        Task { await appState.chatState.regenerate() }
                    } label: {
                        Label("Regenerate", systemImage: "arrow.clockwise")
                    }
                    .disabled(appState.chatState.isGenerating || appState.chatState.messages.isEmpty)

                    Button {
                        Task { await appState.chatState.continueGeneration() }
                    } label: {
                        Label("Continue", systemImage: "arrow.right")
                    }
                    .disabled(appState.chatState.isGenerating || appState.chatState.messages.last?.role != .assistant)

                    Divider()

                    Button(role: .destructive) {
                        Task {
                            await appState.chatState.clearChat()
                        }
                    } label: {
                        Label("Clear Chat", systemImage: "trash")
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
            }
        }
        .onAppear {
            configureChatState()
        }
    }

    private func configureChatState() {
        // Configure chat state with character and provider
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
            // No provider configured - show first message only
            appState.chatState.character = character
            if !character.first_mes.isEmpty && appState.chatState.messages.isEmpty {
                appState.chatState.messages = [Message(role: .assistant, content: character.first_mes)]
            }
        }
    }
}

struct MessageBubble: View {
    let content: String
    let isUser: Bool
    let characterName: String?

    var body: some View {
        HStack {
            if isUser { Spacer() }

            VStack(alignment: isUser ? .trailing : .leading) {
                if let name = characterName, !isUser {
                    Text(name)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Text(content)
                    .padding()
                    .background(isUser ? Color.blue : Color.secondary.opacity(0.2))
                    .foregroundStyle(isUser ? .white : .primary)
                    .clipShape(RoundedRectangle(cornerRadius: 16))
            }

            if !isUser { Spacer() }
        }
    }
}

// CharacterDetailView is now in Features/Characters/CharacterDetailView.swift

#Preview {
    RootView_iOS()
        .environment(AppState())
}
#endif
