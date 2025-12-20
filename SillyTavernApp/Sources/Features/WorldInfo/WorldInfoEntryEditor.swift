import SwiftUI

// MARK: - World Info Entry Editor

struct WorldInfoEntryEditor: View {
    let entry: WorldInfoEntry?
    let book: WorldInfoBook
    @Environment(\.dismiss) private var dismiss

    // Entry state
    @State private var comment: String = ""
    @State private var keys: String = ""
    @State private var secondaryKeys: String = ""
    @State private var content: String = ""
    @State private var enabled: Bool = true

    // Matching settings
    @State private var selective: Bool = false
    @State private var constant: Bool = false
    @State private var caseSensitive: Bool = false
    @State private var matchWholeWords: Bool = false

    // Position settings
    @State private var position: Int = 0
    @State private var depth: Int = 4
    @State private var order: Int = 100

    // Probability
    @State private var probability: Int = 100

    // Timed effects
    @State private var sticky: Int = 0
    @State private var cooldown: Int = 0
    @State private var delay: Int = 0

    var isNewEntry: Bool { entry == nil }

    var body: some View {
        NavigationStack {
            Form {
                // Basic info
                basicSection

                // Content
                contentSection

                // Matching
                matchingSection

                // Position
                positionSection

                // Probability
                probabilitySection

                // Timed effects
                timedEffectsSection
            }
            .navigationTitle(isNewEntry ? "New Entry" : "Edit Entry")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(isNewEntry ? "Add" : "Save") {
                        saveEntry()
                    }
                    .disabled(keys.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !constant)
                }
            }
            .onAppear {
                loadEntry()
            }
        }
        #if os(macOS)
        .frame(minWidth: 500, minHeight: 600)
        #endif
    }

    // MARK: - Sections

    private var basicSection: some View {
        Section("Basic") {
            TextField("Title/Comment", text: $comment)
                .textFieldStyle(.roundedBorder)

            Toggle("Enabled", isOn: $enabled)
        }
    }

    private var contentSection: some View {
        Section {
            VStack(alignment: .leading, spacing: 8) {
                Text("Keys (comma-separated)")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                TextField("key1, key2, key3", text: $keys)
                    .textFieldStyle(.roundedBorder)
            }

            if selective {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Secondary Keys (comma-separated)")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    TextField("secondary1, secondary2", text: $secondaryKeys)
                        .textFieldStyle(.roundedBorder)
                }
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("Content")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                TextEditor(text: $content)
                    .frame(minHeight: 150)
                    .padding(4)
                    .background(Color.secondary.opacity(0.1))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
            }
        } header: {
            Text("Content")
        } footer: {
            Text("Content is injected into the prompt when keys are found in the chat.")
        }
    }

    private var matchingSection: some View {
        Section {
            Toggle("Constant", isOn: $constant)
            Toggle("Selective", isOn: $selective)
            Toggle("Case Sensitive", isOn: $caseSensitive)
            Toggle("Match Whole Words", isOn: $matchWholeWords)
        } header: {
            Text("Matching")
        } footer: {
            VStack(alignment: .leading, spacing: 4) {
                if constant {
                    Text("• Constant: Always included, no key matching needed")
                }
                if selective {
                    Text("• Selective: Requires both primary AND secondary key matches")
                }
            }
            .font(.caption)
        }
    }

    private var positionSection: some View {
        Section("Position") {
            Picker("Injection Position", selection: $position) {
                Text("Before Main").tag(0)
                Text("After Main").tag(1)
                Text("Before AN").tag(2)
                Text("After AN").tag(3)
                Text("At Depth").tag(4)
            }

            if position == 4 {
                Stepper("Depth: \(depth)", value: $depth, in: 0...100)
            }

            Stepper("Order: \(order)", value: $order, in: 0...1000, step: 10)
        }
    }

    private var probabilitySection: some View {
        Section {
            HStack {
                Text("Probability")
                Spacer()
                Text("\(probability)%")
                    .foregroundStyle(.secondary)
            }

            Slider(value: Binding(
                get: { Double(probability) },
                set: { probability = Int($0) }
            ), in: 0...100, step: 5)
        } header: {
            Text("Probability")
        } footer: {
            Text("Chance that this entry will be included when triggered.")
        }
    }

    private var timedEffectsSection: some View {
        Section {
            Stepper("Sticky: \(sticky) messages", value: $sticky, in: 0...100)
            Stepper("Cooldown: \(cooldown) messages", value: $cooldown, in: 0...100)
            Stepper("Delay: \(delay) messages", value: $delay, in: 0...100)
        } header: {
            Text("Timed Effects")
        } footer: {
            VStack(alignment: .leading, spacing: 4) {
                Text("• Sticky: Keep active for N messages after trigger")
                Text("• Cooldown: Wait N messages before re-triggering")
                Text("• Delay: Wait N messages before first trigger")
            }
            .font(.caption)
        }
    }

    // MARK: - Actions

    private func loadEntry() {
        guard let entry = entry else { return }

        comment = entry.comment
        keys = entry.keys.joined(separator: ", ")
        secondaryKeys = entry.secondary_keys.joined(separator: ", ")
        content = entry.content
        enabled = entry.enabled
        selective = entry.selective
        constant = entry.constant
        caseSensitive = entry.case_sensitive
        matchWholeWords = entry.match_whole_words
        position = entry.position
        depth = entry.depth
        order = entry.order
        probability = entry.probability
        sticky = entry.sticky
        cooldown = entry.cooldown
        delay = entry.delay
    }

    private func saveEntry() {
        let targetEntry: WorldInfoEntry
        if let existing = entry {
            targetEntry = existing
        } else {
            targetEntry = WorldInfoEntry()
            book.entries.append(targetEntry)
        }

        // Parse keys
        targetEntry.keys = keys
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }

        targetEntry.secondary_keys = secondaryKeys
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }

        targetEntry.comment = comment
        targetEntry.content = content
        targetEntry.enabled = enabled
        targetEntry.selective = selective
        targetEntry.constant = constant
        targetEntry.case_sensitive = caseSensitive
        targetEntry.match_whole_words = matchWholeWords
        targetEntry.position = position
        targetEntry.depth = depth
        targetEntry.order = order
        targetEntry.probability = probability
        targetEntry.sticky = sticky
        targetEntry.cooldown = cooldown
        targetEntry.delay = delay

        dismiss()
    }
}

// MARK: - Preview

#Preview {
    WorldInfoEntryEditor(entry: nil, book: WorldInfoBook())
}
