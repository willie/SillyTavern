import SwiftUI

// MARK: - Settings View

struct SettingsView: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        TabView {
            APISettingsTab()
                .environment(appState)
                .tabItem { Label("API", systemImage: "key") }

            ModelSettingsTab()
                .environment(appState)
                .tabItem { Label("Model", systemImage: "cpu") }

            GenerationSettingsTab()
                .environment(appState)
                .tabItem { Label("Generation", systemImage: "slider.horizontal.3") }

            PersonaSettingsTab()
                .environment(appState)
                .tabItem { Label("Persona", systemImage: "person") }

            PromptsSettingsTab()
                .environment(appState)
                .tabItem { Label("Prompts", systemImage: "text.bubble") }
        }
        .frame(minWidth: 500, minHeight: 400)
    }
}

// MARK: - API Settings Tab

struct APISettingsTab: View {
    @Environment(AppState.self) private var appState
    @AppStorage("settings.provider") private var provider = "openrouter"
    @AppStorage("settings.apiKey") private var apiKey = ""
    @AppStorage("settings.baseURL") private var baseURL = ""
    @State private var showingModelPicker = false

    var body: some View {
        Form {
            Section("Provider") {
                Picker("API Provider", selection: $provider) {
                    Text("OpenRouter").tag("openrouter")
                    Text("OpenAI").tag("openai")
                    Text("Claude").tag("claude")
                    Text("Custom").tag("custom")
                }
                .pickerStyle(.segmented)
            }

            Section("Authentication") {
                SecureField("API Key", text: $apiKey)
                    .textContentType(.password)

                if provider == "custom" {
                    TextField("Base URL", text: $baseURL)
                        .textContentType(.URL)
                }

                connectionStatus
            }

            if provider == "openrouter" {
                Section("Model Selection") {
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Current Model")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Text(appState.settings.model.isEmpty ? "None selected" : appState.settings.model)
                                .font(.body)
                        }
                        Spacer()
                        Button("Browse Models") {
                            showingModelPicker = true
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(apiKey.isEmpty)
                    }
                }
            }
        }
        .formStyle(.grouped)
        .onChange(of: provider) { _, newValue in
            appState.settings.selectedProvider = newValue
        }
        .onChange(of: apiKey) { _, newValue in
            appState.settings.apiKey = newValue
        }
        .onChange(of: baseURL) { _, newValue in
            appState.settings.baseURL = newValue
        }
        .onAppear {
            // Sync from AppState on appear
            provider = appState.settings.selectedProvider
            apiKey = appState.settings.apiKey
            baseURL = appState.settings.baseURL
        }
        .sheet(isPresented: $showingModelPicker) {
            OpenRouterModelPicker()
                .environment(appState)
        }
    }

    @ViewBuilder
    private var connectionStatus: some View {
        if apiKey.isEmpty {
            Label("Enter your API key", systemImage: "key")
                .foregroundStyle(.secondary)
        } else {
            Label("Ready", systemImage: "checkmark.circle.fill")
                .foregroundStyle(.green)
        }
    }
}

// MARK: - Model Settings Tab

struct ModelSettingsTab: View {
    @Environment(AppState.self) private var appState
    @AppStorage("settings.model") private var model = "openai/gpt-4o"
    @AppStorage("settings.maxContextTokens") private var maxContextTokens = 8192
    @AppStorage("settings.maxResponseTokens") private var maxResponseTokens = 1024

    var body: some View {
        Form {
            Section("Model") {
                TextField("Model ID", text: $model)
                    .textFieldStyle(.roundedBorder)

                Text("For OpenRouter, use format: provider/model-name")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Context") {
                Stepper("Max Context: \(TokenCounter.format(maxContextTokens))",
                        value: $maxContextTokens,
                        in: 1024...200000,
                        step: 1024)

                Stepper("Max Response: \(TokenCounter.format(maxResponseTokens))",
                        value: $maxResponseTokens,
                        in: 64...16384,
                        step: 64)
            }
        }
        .formStyle(.grouped)
        .onChange(of: model) { _, newValue in
            appState.settings.model = newValue
        }
        .onChange(of: maxContextTokens) { _, newValue in
            appState.settings.maxContextTokens = newValue
        }
        .onChange(of: maxResponseTokens) { _, newValue in
            appState.settings.maxResponseTokens = newValue
        }
        .onAppear {
            model = appState.settings.model
            maxContextTokens = appState.settings.maxContextTokens
            maxResponseTokens = appState.settings.maxResponseTokens
        }
    }
}

// MARK: - Generation Settings Tab

struct GenerationSettingsTab: View {
    @Environment(AppState.self) private var appState
    @AppStorage("settings.temperature") private var temperature = 0.7
    @AppStorage("settings.topP") private var topP = 1.0
    @AppStorage("settings.frequencyPenalty") private var frequencyPenalty = 0.0
    @AppStorage("settings.presencePenalty") private var presencePenalty = 0.0

    var body: some View {
        Form {
            Section("Sampling") {
                VStack(alignment: .leading) {
                    HStack {
                        Text("Temperature")
                        Spacer()
                        Text(String(format: "%.2f", temperature))
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    }
                    Slider(value: $temperature, in: 0...2, step: 0.05)
                }

                VStack(alignment: .leading) {
                    HStack {
                        Text("Top P")
                        Spacer()
                        Text(String(format: "%.2f", topP))
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    }
                    Slider(value: $topP, in: 0...1, step: 0.05)
                }
            }

            Section("Penalties") {
                VStack(alignment: .leading) {
                    HStack {
                        Text("Frequency Penalty")
                        Spacer()
                        Text(String(format: "%.2f", frequencyPenalty))
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    }
                    Slider(value: $frequencyPenalty, in: 0...2, step: 0.05)
                }

                VStack(alignment: .leading) {
                    HStack {
                        Text("Presence Penalty")
                        Spacer()
                        Text(String(format: "%.2f", presencePenalty))
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    }
                    Slider(value: $presencePenalty, in: 0...2, step: 0.05)
                }
            }
        }
        .formStyle(.grouped)
        .onChange(of: temperature) { _, newValue in
            appState.settings.temperature = newValue
        }
        .onChange(of: topP) { _, newValue in
            appState.settings.topP = newValue
        }
        .onChange(of: frequencyPenalty) { _, newValue in
            appState.settings.frequencyPenalty = newValue
        }
        .onChange(of: presencePenalty) { _, newValue in
            appState.settings.presencePenalty = newValue
        }
        .onAppear {
            temperature = appState.settings.temperature
            topP = appState.settings.topP
            frequencyPenalty = appState.settings.frequencyPenalty
            presencePenalty = appState.settings.presencePenalty
        }
    }
}

// MARK: - Persona Settings Tab

struct PersonaSettingsTab: View {
    @Environment(AppState.self) private var appState
    @AppStorage("settings.personaName") private var personaName = "User"
    @AppStorage("settings.personaDescription") private var personaDescription = ""
    @AppStorage("settings.hideNSFWImages") private var hideNSFWImages = true

    var body: some View {
        Form {
            Section("Your Persona") {
                TextField("Name", text: $personaName)

                VStack(alignment: .leading, spacing: 8) {
                    Text("Description")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    TextEditor(text: $personaDescription)
                        .frame(minHeight: 100)
                        .font(.body)
                }
            }

            Section("Content") {
                Toggle("Hide NSFW Character Images", isOn: $hideNSFWImages)
            }
        }
        .formStyle(.grouped)
        .onChange(of: personaName) { _, newValue in
            appState.settings.personaName = newValue
        }
        .onChange(of: personaDescription) { _, newValue in
            appState.settings.personaDescription = newValue
        }
        .onAppear {
            personaName = appState.settings.personaName
            personaDescription = appState.settings.personaDescription
        }
    }
}

// MARK: - Prompts Settings Tab

struct PromptsSettingsTab: View {
    @Environment(AppState.self) private var appState
    @AppStorage("settings.mainPrompt") private var mainPrompt = "Write {{char}}'s next reply in a fictional chat between {{char}} and {{user}}."
    @AppStorage("settings.jailbreakPrompt") private var jailbreakPrompt = ""
    @AppStorage("settings.authorsNote") private var authorsNote = ""
    @AppStorage("settings.authorsNoteDepth") private var authorsNoteDepth = 4

    var body: some View {
        Form {
            Section("System Prompt") {
                TextEditor(text: $mainPrompt)
                    .frame(minHeight: 100)
                    .font(.body.monospaced())

                Text("Use {{char}} for character name, {{user}} for your name")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Jailbreak Prompt") {
                TextEditor(text: $jailbreakPrompt)
                    .frame(minHeight: 80)
                    .font(.body.monospaced())
            }

            Section("Author's Note") {
                TextEditor(text: $authorsNote)
                    .frame(minHeight: 80)
                    .font(.body.monospaced())

                Stepper("Injection Depth: \(authorsNoteDepth)",
                        value: $authorsNoteDepth,
                        in: 0...20)
            }
        }
        .formStyle(.grouped)
        .onChange(of: mainPrompt) { _, newValue in
            appState.settings.mainPrompt = newValue
        }
        .onChange(of: jailbreakPrompt) { _, newValue in
            appState.settings.jailbreakPrompt = newValue
        }
        .onChange(of: authorsNote) { _, newValue in
            appState.settings.authorsNote = newValue
        }
        .onChange(of: authorsNoteDepth) { _, newValue in
            appState.settings.authorsNoteDepth = newValue
        }
        .onAppear {
            mainPrompt = appState.settings.mainPrompt
            jailbreakPrompt = appState.settings.jailbreakPrompt
            authorsNote = appState.settings.authorsNote
            authorsNoteDepth = appState.settings.authorsNoteDepth
        }
    }
}

// MARK: - Preview

#Preview {
    SettingsView()
        .environment(AppState())
}
