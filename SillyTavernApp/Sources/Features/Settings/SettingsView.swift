import SwiftUI

// MARK: - Settings View (Shared)

struct SettingsView: View {
    @Environment(AppState.self) private var appState
    @State private var selectedSection: SettingsSection? = .api
    @State private var showingModelPicker = false

    var body: some View {
        @Bindable var settings = appState.settings

        #if os(macOS)
        NavigationSplitView {
            List(SettingsSection.allCases, selection: $selectedSection) { section in
                NavigationLink(value: section) {
                    Label(section.title, systemImage: section.icon)
                }
            }
            .navigationTitle("Settings")
        } detail: {
            if let section = selectedSection {
                settingsContent(for: section)
            } else {
                ContentUnavailableView("Select a Section", systemImage: "gear")
            }
        }
        .sheet(isPresented: $showingModelPicker) {
            OpenRouterModelPicker()
                .environment(appState)
        }
        #else
        Form {
            apiSection
            modelSection
            generationSection
            authorsNoteSection
            personaSection
            promptSection
            aboutSection
        }
        .navigationTitle("Settings")
        #endif
    }

    @ViewBuilder
    private func settingsContent(for section: SettingsSection) -> some View {
        Form {
            switch section {
            case .api:
                apiSection
            case .model:
                modelSection
            case .generation:
                generationSection
            case .authorsNote:
                authorsNoteSection
            case .persona:
                personaSection
            case .prompts:
                promptSection
            case .about:
                aboutSection
            }
        }
        .formStyle(.grouped)
        .navigationTitle(section.title)
    }

    // MARK: - API Section

    private var apiSection: some View {
        @Bindable var settings = appState.settings

        return Group {
            Section("API Provider") {
                Picker("Provider", selection: $settings.selectedProvider) {
                    Text("OpenAI").tag("openai")
                    Text("Claude").tag("claude")
                    Text("OpenRouter").tag("openrouter")
                    Text("Custom").tag("custom")
                }

                SecureField("API Key", text: $settings.apiKey)
                    .textContentType(.password)

                if settings.selectedProvider == "custom" {
                    TextField("Base URL", text: $settings.baseURL)
                        .textContentType(.URL)
                }
            }

            if settings.selectedProvider == "openrouter" {
                Section("OpenRouter Model") {
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(settings.model.isEmpty ? "No model selected" : settings.model)
                                .font(.body)
                        }
                        Spacer()
                        Button("Browse Models") {
                            showingModelPicker = true
                        }
                        .buttonStyle(.borderedProminent)
                    }
                }
            }
        }
    }

    // MARK: - Model Section

    private var modelSection: some View {
        @Bindable var settings = appState.settings

        return Section {
            if appState.settings.selectedProvider == "openrouter" {
                // OpenRouter model picker
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Model")
                            .foregroundStyle(.secondary)
                        Text(settings.model.isEmpty ? "Not selected" : settings.model)
                            .font(.headline)
                    }
                    Spacer()
                    Button("Browse") {
                        showingModelPicker = true
                    }
                    .buttonStyle(.bordered)
                }
                .sheet(isPresented: $showingModelPicker) {
                    OpenRouterModelPicker()
                        .environment(appState)
                }
            } else {
                // Standard picker for other providers
                Picker("Model", selection: $settings.model) {
                    ForEach(suggestedModels, id: \.self) { model in
                        Text(model).tag(model)
                    }
                }
                #if os(iOS)
                .pickerStyle(.navigationLink)
                #endif
            }

            Stepper("Max Context: \(TokenCounter.format(settings.maxContextTokens))",
                    value: $settings.maxContextTokens,
                    in: 1024...200000,
                    step: 1024)

            Stepper("Max Response: \(TokenCounter.format(settings.maxResponseTokens))",
                    value: $settings.maxResponseTokens,
                    in: 64...16384,
                    step: 64)
        } header: {
            Text("Model Settings")
        } footer: {
            if appState.settings.selectedProvider == "openrouter" {
                Text("Browse OpenRouter's catalog of 200+ models")
            } else {
                Text("Select a model or enter a custom model identifier")
            }
        }
    }

    private var suggestedModels: [String] {
        switch appState.settings.selectedProvider {
        case "openai":
            return [
                "gpt-4o",
                "gpt-4o-mini",
                "gpt-4-turbo",
                "gpt-4",
                "gpt-3.5-turbo",
                "o1-preview",
                "o1-mini"
            ]
        case "claude":
            return [
                "claude-sonnet-4-20250514",
                "claude-3-5-sonnet-20241022",
                "claude-3-5-haiku-20241022",
                "claude-3-opus-20240229",
                "claude-3-sonnet-20240229",
                "claude-3-haiku-20240307"
            ]
        case "openrouter":
            return [
                "openai/gpt-4o",
                "openai/gpt-4o-mini",
                "anthropic/claude-3.5-sonnet",
                "anthropic/claude-3-opus",
                "meta-llama/llama-3.1-405b-instruct",
                "meta-llama/llama-3.1-70b-instruct",
                "mistralai/mistral-large",
                "google/gemini-pro-1.5"
            ]
        default:
            return ["gpt-4o", "gpt-4", "gpt-3.5-turbo"]
        }
    }

    // MARK: - Generation Section

    private var generationSection: some View {
        @Bindable var settings = appState.settings

        return Section {
            VStack(alignment: .leading) {
                HStack {
                    Text("Temperature")
                    Spacer()
                    Text(String(format: "%.2f", settings.temperature))
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
                Slider(value: $settings.temperature, in: 0...2, step: 0.05)
            }

            VStack(alignment: .leading) {
                HStack {
                    Text("Top P")
                    Spacer()
                    Text(String(format: "%.2f", settings.topP))
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
                Slider(value: $settings.topP, in: 0...1, step: 0.05)
            }

            VStack(alignment: .leading) {
                HStack {
                    Text("Frequency Penalty")
                    Spacer()
                    Text(String(format: "%.2f", settings.frequencyPenalty))
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
                Slider(value: $settings.frequencyPenalty, in: 0...2, step: 0.05)
            }

            VStack(alignment: .leading) {
                HStack {
                    Text("Presence Penalty")
                    Spacer()
                    Text(String(format: "%.2f", settings.presencePenalty))
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
                Slider(value: $settings.presencePenalty, in: 0...2, step: 0.05)
            }
        } header: {
            Text("Generation Settings")
        } footer: {
            Text("Higher temperature = more creative, lower = more deterministic")
        }
    }

    // MARK: - Author's Note Section

    private var authorsNoteSection: some View {
        @Bindable var settings = appState.settings

        return Section {
            VStack(alignment: .leading, spacing: 8) {
                Text("Author's Note Content")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                TextEditor(text: $settings.authorsNote)
                    .frame(minHeight: 100)
                    .padding(4)
                    .background(Color.secondary.opacity(0.1))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
            }

            Stepper("Injection Depth: \(settings.authorsNoteDepth)",
                    value: $settings.authorsNoteDepth,
                    in: 0...100)

            Picker("Position", selection: $settings.authorsNotePosition) {
                Text("Before Character Defs").tag("beforeAN")
                Text("After Character Defs").tag("afterAN")
            }
        } header: {
            Text("Author's Note")
        } footer: {
            Text("Author's Note is injected into the prompt at the specified depth. Use it to guide the story or remind the AI of important details.")
        }
    }

    // MARK: - Persona Section

    private var personaSection: some View {
        @Bindable var settings = appState.settings

        return Section {
            TextField("Persona Name", text: $settings.personaName)

            VStack(alignment: .leading, spacing: 8) {
                Text("Persona Description")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                TextEditor(text: $settings.personaDescription)
                    .frame(minHeight: 80)
                    .padding(4)
                    .background(Color.secondary.opacity(0.1))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
            }
        } header: {
            Text("Persona")
        } footer: {
            Text("Your persona description is included in the prompt to help the AI understand who you are.")
        }
    }

    // MARK: - Prompt Section

    private var promptSection: some View {
        @Bindable var settings = appState.settings

        return Section {
            VStack(alignment: .leading, spacing: 8) {
                Text("Main System Prompt")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                TextEditor(text: $settings.mainPrompt)
                    .frame(minHeight: 100)
                    .padding(4)
                    .background(Color.secondary.opacity(0.1))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("Jailbreak/NSFW Prompt")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                TextEditor(text: $settings.jailbreakPrompt)
                    .frame(minHeight: 80)
                    .padding(4)
                    .background(Color.secondary.opacity(0.1))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
            }
        } header: {
            Text("Prompt Templates")
        } footer: {
            Text("Use {{char}} for character name and {{user}} for your persona name.")
        }
    }

    // MARK: - About Section

    private var aboutSection: some View {
        Section {
            LabeledContent("Version", value: "1.0.0")
            LabeledContent("Build", value: "1")

            Link("View on GitHub", destination: URL(string: "https://github.com/SillyTavern/SillyTavern")!)

            Button("Reset All Settings") {
                // TODO: Implement reset
            }
            .foregroundStyle(.red)
        } header: {
            Text("About")
        }
    }
}

// MARK: - Settings Section

enum SettingsSection: String, CaseIterable, Identifiable {
    case api
    case model
    case generation
    case authorsNote
    case persona
    case prompts
    case about

    var id: String { rawValue }

    var title: String {
        switch self {
        case .api: return "API Provider"
        case .model: return "Model"
        case .generation: return "Generation"
        case .authorsNote: return "Author's Note"
        case .persona: return "Persona"
        case .prompts: return "Prompts"
        case .about: return "About"
        }
    }

    var icon: String {
        switch self {
        case .api: return "key"
        case .model: return "cpu"
        case .generation: return "slider.horizontal.3"
        case .authorsNote: return "note.text"
        case .persona: return "person"
        case .prompts: return "text.bubble"
        case .about: return "info.circle"
        }
    }
}

// MARK: - Preview

#Preview {
    NavigationStack {
        SettingsView()
            .environment(AppState())
    }
}
