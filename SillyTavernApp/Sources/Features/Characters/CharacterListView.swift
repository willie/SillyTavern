import SwiftUI
import UniformTypeIdentifiers

// MARK: - Character List View (Shared)

struct CharacterListView: View {
    @Environment(AppState.self) private var appState
    @State private var sortOrder: SortOrder = .name
    @State private var isImporting = false
    @State private var importError: Error?
    @State private var showingImportError = false

    enum SortOrder: String, CaseIterable {
        case name = "Name"
        case recent = "Recent"
        case creator = "Creator"
    }

    var filteredCharacters: [CharacterCard] {
        let characters = appState.characters.characters

        let filtered = appState.searchText.isEmpty ? characters : characters.filter {
            $0.name.localizedCaseInsensitiveContains(appState.searchText) ||
            $0.creator.localizedCaseInsensitiveContains(appState.searchText) ||
            $0.tags.contains { $0.localizedCaseInsensitiveContains(appState.searchText) }
        }

        switch sortOrder {
        case .name:
            return filtered.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        case .recent:
            return filtered.sorted { ($0.create_date ?? .distantPast) > ($1.create_date ?? .distantPast) }
        case .creator:
            return filtered.sorted { $0.creator.localizedCaseInsensitiveCompare($1.creator) == .orderedAscending }
        }
    }

    var body: some View {
        Group {
            if appState.characters.isLoading {
                ProgressView("Loading characters...")
            } else if filteredCharacters.isEmpty {
                emptyState
            } else {
                characterList
            }
        }
        .navigationTitle("Characters")
        .toolbar {
            toolbarContent
        }
        .fileImporter(
            isPresented: $isImporting,
            allowedContentTypes: [.png, .json],
            allowsMultipleSelection: true
        ) { result in
            handleImport(result)
        }
        .alert("Import Error", isPresented: $showingImportError) {
            Button("OK") { }
        } message: {
            Text(importError?.localizedDescription ?? "Unknown error")
        }
        .alert("Error", isPresented: .init(
            get: { appState.characters.error != nil },
            set: { if !$0 { appState.characters.error = nil } }
        )) {
            Button("OK") { appState.characters.error = nil }
        } message: {
            Text(appState.characters.error?.localizedDescription ?? "Unknown error")
        }
    }

    // MARK: - Character List

    private var characterList: some View {
        List {
            ForEach(filteredCharacters) { character in
                NavigationLink(value: character) {
                    CharacterRowView(character: character)
                }
                .contextMenu {
                    characterContextMenu(for: character)
                }
            }
            .onDelete(perform: deleteCharacters)
        }
        .listStyle(.plain)
    }

    // MARK: - Empty State

    private var emptyState: some View {
        ContentUnavailableView {
            Label("No Characters", systemImage: "person.2")
        } description: {
            if appState.searchText.isEmpty {
                Text("Import a character card to get started")
            } else {
                Text("No characters match '\(appState.searchText)'")
            }
        } actions: {
            if appState.searchText.isEmpty {
                Button {
                    isImporting = true
                } label: {
                    Text("Import Character")
                }
                .buttonStyle(.borderedProminent)
            }
        }
    }

    // MARK: - Toolbar

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .primaryAction) {
            Button {
                isImporting = true
            } label: {
                Label("Import", systemImage: "plus")
            }
        }

        ToolbarItem(placement: .automatic) {
            Menu {
                Button {
                    sortOrder = .name
                } label: {
                    Label("Name", systemImage: sortOrder == .name ? "checkmark" : "")
                }
                Button {
                    sortOrder = .recent
                } label: {
                    Label("Recent", systemImage: sortOrder == .recent ? "checkmark" : "")
                }
                Button {
                    sortOrder = .creator
                } label: {
                    Label("Creator", systemImage: sortOrder == .creator ? "checkmark" : "")
                }
            } label: {
                Label("Sort", systemImage: "arrow.up.arrow.down")
            }
        }
    }

    // MARK: - Context Menu

    @ViewBuilder
    private func characterContextMenu(for character: CharacterCard) -> some View {
        Button {
            appState.newChat(with: character)
        } label: {
            Label("Start Chat", systemImage: "bubble.left")
        }

        Divider()

        Button {
            // TODO: Duplicate character
        } label: {
            Label("Duplicate", systemImage: "doc.on.doc")
        }

        Button {
            // TODO: Export character
        } label: {
            Label("Export", systemImage: "square.and.arrow.up")
        }

        Divider()

        Button(role: .destructive) {
            appState.characters.remove(character)
        } label: {
            Label("Delete", systemImage: "trash")
        }
    }

    // MARK: - Actions

    private func deleteCharacters(at offsets: IndexSet) {
        for index in offsets {
            let character = filteredCharacters[index]
            appState.characters.remove(character)
        }
    }

    private func handleImport(_ result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            Task {
                for url in urls {
                    do {
                        // Start accessing security-scoped resource
                        guard url.startAccessingSecurityScopedResource() else {
                            throw FileStoreError.fileNotFound
                        }
                        defer { url.stopAccessingSecurityScopedResource() }

                        _ = try await appState.characters.importCharacter(from: url)
                    } catch {
                        importError = error
                        showingImportError = true
                    }
                }
            }
        case .failure(let error):
            importError = error
            showingImportError = true
        }
    }
}

// MARK: - Character Row View

struct CharacterRowView: View {
    let character: CharacterCard
    @Environment(AppState.self) private var appState
    @State private var avatarImage: Image?

    private var hideNSFWImages: Bool { appState.settings.hideNSFWImages }

    var body: some View {
        HStack(spacing: 12) {
            // Avatar
            avatarView
                .frame(width: 50, height: 50)

            // Info
            VStack(alignment: .leading, spacing: 4) {
                Text(character.name)
                    .font(.headline)
                    .lineLimit(1)

                if !character.creator.isEmpty {
                    Text("by \(character.creator)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                if !character.tags.isEmpty {
                    tagsList
                }
            }

            Spacer()

            // Favorite indicator
            if character.fav {
                Image(systemName: "star.fill")
                    .foregroundStyle(.yellow)
                    .font(.caption)
            }
        }
        .padding(.vertical, 4)
        .task {
            await loadAvatar()
        }
    }

    @ViewBuilder
    private var avatarView: some View {
        if character.isNSFW && hideNSFWImages {
            // Show placeholder for hidden NSFW images
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.red.opacity(0.15))
                .overlay {
                    Image(systemName: "eye.slash.fill")
                        .font(.title2)
                        .foregroundStyle(.secondary)
                }
        } else if let image = avatarImage {
            image
                .resizable()
                .aspectRatio(contentMode: .fill)
                .clipShape(RoundedRectangle(cornerRadius: 8))
        } else {
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.secondary.opacity(0.2))
                .overlay {
                    Text(String(character.name.prefix(1)).uppercased())
                        .font(.title2)
                        .foregroundStyle(.secondary)
                }
        }
    }

    private var tagsList: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 4) {
                ForEach(character.tags.prefix(3), id: \.self) { tag in
                    Text(tag)
                        .font(.caption2)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.secondary.opacity(0.15))
                        .clipShape(Capsule())
                }
                if character.tags.count > 3 {
                    Text("+\(character.tags.count - 3)")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private func loadAvatar() async {
        guard let fileURL = character.fileURL,
              fileURL.pathExtension.lowercased() == "png" else { return }

        // Load PNG as avatar thumbnail
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

// MARK: - Preview

#Preview {
    NavigationStack {
        CharacterListView()
            .environment(AppState())
    }
}
