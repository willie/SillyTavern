import SwiftUI
import UniformTypeIdentifiers

// MARK: - World Info List View

struct WorldInfoListView: View {
    @Environment(AppState.self) private var appState
    @State private var isImporting = false
    @State private var showingNewBookSheet = false
    @State private var newBookName = ""
    @State private var importError: Error?
    @State private var showingImportError = false

    var filteredBooks: [WorldInfoBook] {
        let books = appState.worldInfo.books
        if appState.searchText.isEmpty {
            return books
        }
        return books.filter {
            $0.name.localizedCaseInsensitiveContains(appState.searchText) ||
            $0.entries.contains { entry in
                entry.comment.localizedCaseInsensitiveContains(appState.searchText) ||
                entry.keys.contains { $0.localizedCaseInsensitiveContains(appState.searchText) }
            }
        }
    }

    var body: some View {
        Group {
            if appState.worldInfo.isLoading {
                ProgressView("Loading world info...")
            } else if filteredBooks.isEmpty {
                emptyState
            } else {
                bookList
            }
        }
        .navigationTitle("World Info")
        .toolbar {
            toolbarContent
        }
        .fileImporter(
            isPresented: $isImporting,
            allowedContentTypes: [.json],
            allowsMultipleSelection: true
        ) { result in
            handleImport(result)
        }
        .sheet(isPresented: $showingNewBookSheet) {
            newBookSheet
        }
        .alert("Import Error", isPresented: $showingImportError) {
            Button("OK") { }
        } message: {
            Text(importError?.localizedDescription ?? "Unknown error")
        }
        .alert("Error", isPresented: .init(
            get: { appState.worldInfo.error != nil },
            set: { if !$0 { appState.worldInfo.error = nil } }
        )) {
            Button("OK") { appState.worldInfo.error = nil }
        } message: {
            Text(appState.worldInfo.error?.localizedDescription ?? "Unknown error")
        }
    }

    // MARK: - Book List

    private var bookList: some View {
        List {
            ForEach(filteredBooks) { book in
                NavigationLink(value: book) {
                    WorldInfoBookRow(book: book)
                }
                .contextMenu {
                    bookContextMenu(for: book)
                }
            }
            .onDelete(perform: deleteBooks)
        }
        .listStyle(.plain)
    }

    // MARK: - Empty State

    private var emptyState: some View {
        ContentUnavailableView {
            Label("No Lorebooks", systemImage: "book")
        } description: {
            if appState.searchText.isEmpty {
                Text("Create a lorebook to add world context to your chats")
            } else {
                Text("No lorebooks match '\(appState.searchText)'")
            }
        } actions: {
            if appState.searchText.isEmpty {
                HStack {
                    Button {
                        showingNewBookSheet = true
                    } label: {
                        Text("New Lorebook")
                    }
                    .buttonStyle(.borderedProminent)

                    Button {
                        isImporting = true
                    } label: {
                        Text("Import")
                    }
                    .buttonStyle(.bordered)
                }
            }
        }
    }

    // MARK: - New Book Sheet

    private var newBookSheet: some View {
        NavigationStack {
            Form {
                TextField("Lorebook Name", text: $newBookName)
            }
            .navigationTitle("New Lorebook")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        newBookName = ""
                        showingNewBookSheet = false
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Create") {
                        createNewBook()
                    }
                    .disabled(newBookName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
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
            Menu {
                Button {
                    showingNewBookSheet = true
                } label: {
                    Label("New Lorebook", systemImage: "plus")
                }

                Button {
                    isImporting = true
                } label: {
                    Label("Import Lorebook", systemImage: "square.and.arrow.down")
                }
            } label: {
                Label("Add", systemImage: "plus")
            }
        }
    }

    // MARK: - Context Menu

    @ViewBuilder
    private func bookContextMenu(for book: WorldInfoBook) -> some View {
        Button {
            // TODO: Duplicate book
        } label: {
            Label("Duplicate", systemImage: "doc.on.doc")
        }

        Button {
            // TODO: Export book
        } label: {
            Label("Export", systemImage: "square.and.arrow.up")
        }

        Divider()

        Button(role: .destructive) {
            appState.worldInfo.remove(book)
        } label: {
            Label("Delete", systemImage: "trash")
        }
    }

    // MARK: - Actions

    private func deleteBooks(at offsets: IndexSet) {
        for index in offsets {
            let book = filteredBooks[index]
            appState.worldInfo.remove(book)
        }
    }

    private func createNewBook() {
        let book = WorldInfoBook()
        book.name = newBookName.trimmingCharacters(in: .whitespacesAndNewlines)
        appState.worldInfo.add(book)
        newBookName = ""
        showingNewBookSheet = false
    }

    private func handleImport(_ result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            Task {
                for url in urls {
                    do {
                        guard url.startAccessingSecurityScopedResource() else {
                            throw FileStoreError.fileNotFound
                        }
                        defer { url.stopAccessingSecurityScopedResource() }

                        _ = try await appState.worldInfo.importBook(from: url)
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

// MARK: - World Info Book Row

struct WorldInfoBookRow: View {
    let book: WorldInfoBook

    var enabledCount: Int {
        book.entries.filter { $0.enabled }.count
    }

    var body: some View {
        HStack(spacing: 12) {
            // Icon
            Image(systemName: "book.closed")
                .font(.title2)
                .foregroundStyle(.secondary)
                .frame(width: 40, height: 40)
                .background(Color.secondary.opacity(0.1))
                .clipShape(RoundedRectangle(cornerRadius: 8))

            // Info
            VStack(alignment: .leading, spacing: 4) {
                Text(book.name.isEmpty ? "Untitled Lorebook" : book.name)
                    .font(.headline)
                    .lineLimit(1)

                HStack(spacing: 8) {
                    Label("\(book.entries.count) entries", systemImage: "list.bullet")

                    if enabledCount < book.entries.count {
                        Text("(\(enabledCount) enabled)")
                            .foregroundStyle(.secondary)
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }

            Spacer()
        }
        .padding(.vertical, 4)
    }
}

// MARK: - World Info Book Detail View

struct WorldInfoBookDetailView: View {
    @Bindable var book: WorldInfoBook
    @Environment(AppState.self) private var appState
    @State private var searchText = ""
    @State private var showingNewEntrySheet = false
    @State private var selectedEntry: WorldInfoEntry?
    @State private var isEditing = false

    var filteredEntries: [WorldInfoEntry] {
        if searchText.isEmpty {
            return book.entries.sorted { $0.order < $1.order }
        }
        return book.entries.filter {
            $0.comment.localizedCaseInsensitiveContains(searchText) ||
            $0.keys.contains { $0.localizedCaseInsensitiveContains(searchText) } ||
            $0.content.localizedCaseInsensitiveContains(searchText)
        }.sorted { $0.order < $1.order }
    }

    var body: some View {
        List {
            // Book name header when editing
            if isEditing {
                Section("Book Name") {
                    TextField("Name", text: $book.name)
                }
            }

            // Entries
            Section {
                if filteredEntries.isEmpty {
                    ContentUnavailableView {
                        Label("No Entries", systemImage: "doc.text")
                    } description: {
                        if searchText.isEmpty {
                            Text("Add entries to define world context")
                        } else {
                            Text("No entries match '\(searchText)'")
                        }
                    }
                } else {
                    ForEach(filteredEntries) { entry in
                        Button {
                            selectedEntry = entry
                        } label: {
                            WorldInfoEntryRow(entry: entry)
                        }
                        .buttonStyle(.plain)
                        .contextMenu {
                            entryContextMenu(for: entry)
                        }
                    }
                    .onDelete(perform: deleteEntries)
                    .onMove(perform: moveEntries)
                }
            } header: {
                HStack {
                    Text("Entries (\(book.entries.count))")
                    Spacer()
                    if isEditing {
                        Button {
                            showingNewEntrySheet = true
                        } label: {
                            Label("Add", systemImage: "plus.circle")
                                .font(.caption)
                        }
                    }
                }
            }
        }
        .searchable(text: $searchText, prompt: "Search entries")
        .navigationTitle(book.name.isEmpty ? "Untitled Lorebook" : book.name)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    isEditing.toggle()
                    if !isEditing {
                        saveBook()
                    }
                } label: {
                    Text(isEditing ? "Done" : "Edit")
                }
            }

            if !isEditing {
                ToolbarItem(placement: .automatic) {
                    Button {
                        showingNewEntrySheet = true
                    } label: {
                        Label("Add Entry", systemImage: "plus")
                    }
                }
            }
        }
        .sheet(isPresented: $showingNewEntrySheet) {
            WorldInfoEntryEditor(entry: nil, book: book)
        }
        .sheet(item: $selectedEntry) { entry in
            WorldInfoEntryEditor(entry: entry, book: book)
        }
    }

    // MARK: - Context Menu

    @ViewBuilder
    private func entryContextMenu(for entry: WorldInfoEntry) -> some View {
        Button {
            entry.enabled.toggle()
        } label: {
            Label(entry.enabled ? "Disable" : "Enable", systemImage: entry.enabled ? "eye.slash" : "eye")
        }

        Button {
            duplicateEntry(entry)
        } label: {
            Label("Duplicate", systemImage: "doc.on.doc")
        }

        Divider()

        Button(role: .destructive) {
            book.entries.removeAll { $0.id == entry.id }
        } label: {
            Label("Delete", systemImage: "trash")
        }
    }

    // MARK: - Actions

    private func deleteEntries(at offsets: IndexSet) {
        let entriesToDelete = offsets.map { filteredEntries[$0] }
        for entry in entriesToDelete {
            book.entries.removeAll { $0.id == entry.id }
        }
    }

    private func moveEntries(from source: IndexSet, to destination: Int) {
        // Map filtered indices to actual book.entries indices
        let sortedEntries = book.entries.sorted { $0.order < $1.order }

        // Get the entries being moved from filtered view
        let movedEntries = source.map { filteredEntries[$0] }

        // Create new order based on the move operation
        var reorderedIDs = sortedEntries.map { $0.id }

        // Remove moved entries from their current positions
        for entry in movedEntries {
            reorderedIDs.removeAll { $0 == entry.id }
        }

        // Calculate insert position in the full list
        // The destination is in the filtered list, so we need to find the right spot
        let destinationInFull: Int
        if destination >= filteredEntries.count {
            destinationInFull = reorderedIDs.count
        } else if destination == 0 {
            destinationInFull = 0
        } else {
            let entryBeforeDestination = filteredEntries[destination - 1]
            if let idx = reorderedIDs.firstIndex(of: entryBeforeDestination.id) {
                destinationInFull = idx + 1
            } else {
                destinationInFull = reorderedIDs.count
            }
        }

        // Insert moved entries at the destination
        for entry in movedEntries.reversed() {
            reorderedIDs.insert(entry.id, at: destinationInFull)
        }

        // Update order values based on new positions
        for (index, entryID) in reorderedIDs.enumerated() {
            if let entry = book.entries.first(where: { $0.id == entryID }) {
                entry.order = index * 10
            }
        }

        // Save the book
        Task {
            await appState.worldInfo.save(book)
        }
    }

    private func duplicateEntry(_ entry: WorldInfoEntry) {
        let newEntry = WorldInfoEntry()
        newEntry.keys = entry.keys
        newEntry.secondary_keys = entry.secondary_keys
        newEntry.content = entry.content
        newEntry.comment = entry.comment + " (copy)"
        newEntry.enabled = entry.enabled
        newEntry.selective = entry.selective
        newEntry.constant = entry.constant
        newEntry.case_sensitive = entry.case_sensitive
        newEntry.match_whole_words = entry.match_whole_words
        newEntry.position = entry.position
        newEntry.depth = entry.depth
        newEntry.order = entry.order + 1
        newEntry.probability = entry.probability

        book.entries.append(newEntry)
    }

    private func saveBook() {
        Task {
            await appState.worldInfo.save(book)
        }
    }
}

// MARK: - World Info Entry Row

struct WorldInfoEntryRow: View {
    @Bindable var entry: WorldInfoEntry

    var body: some View {
        HStack(spacing: 12) {
            // Status indicator
            Circle()
                .fill(entry.enabled ? Color.green : Color.secondary)
                .frame(width: 8, height: 8)

            VStack(alignment: .leading, spacing: 4) {
                // Title/comment
                Text(entry.comment.isEmpty ? "Entry \(entry.uid)" : entry.comment)
                    .font(.headline)
                    .lineLimit(1)

                // Keys
                if !entry.keys.isEmpty {
                    Text(entry.keys.joined(separator: ", "))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                // Badges
                HStack(spacing: 6) {
                    if entry.constant {
                        EntryBadge(text: "Constant", color: .purple)
                    }
                    if entry.selective {
                        EntryBadge(text: "Selective", color: .orange)
                    }
                    if entry.probability < 100 {
                        EntryBadge(text: "\(entry.probability)%", color: .blue)
                    }
                }
            }

            Spacer()

            // Order indicator
            Text("#\(entry.order)")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)
        .opacity(entry.enabled ? 1 : 0.6)
    }
}

// MARK: - Entry Badge

struct EntryBadge: View {
    let text: String
    let color: Color

    var body: some View {
        Text(text)
            .font(.caption2)
            .fontWeight(.medium)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(color.opacity(0.15))
            .foregroundStyle(color)
            .clipShape(Capsule())
    }
}

// MARK: - Preview

#Preview {
    NavigationStack {
        WorldInfoListView()
            .environment(AppState())
    }
}
