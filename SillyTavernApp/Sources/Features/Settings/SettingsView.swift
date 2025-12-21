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
    @State private var showingModelPicker = false

    var body: some View {
        @Bindable var settings = appState.settings

        Form {
            Section("Provider") {
                Picker("API Provider", selection: $settings.selectedProvider) {
                    Text("OpenRouter").tag("openrouter")
                    Text("OpenAI").tag("openai")
                    Text("Claude").tag("claude")
                    Text("Custom").tag("custom")
                }
                .pickerStyle(.segmented)
            }

            Section("Authentication") {
                SecureField("API Key", text: $settings.apiKey)
                    .textContentType(.password)

                if settings.selectedProvider == "custom" {
                    TextField("Base URL", text: $settings.baseURL)
                        .textContentType(.URL)
                }

                connectionStatus
            }

            if settings.selectedProvider == "openrouter" {
                Section("Model Selection") {
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Current Model")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Text(settings.model.isEmpty ? "None selected" : settings.model)
                                .font(.body)
                        }
                        Spacer()
                        Button("Browse Models") {
                            showingModelPicker = true
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(settings.apiKey.isEmpty)
                    }
                }
            }
        }
        .formStyle(.grouped)
        .sheet(isPresented: $showingModelPicker) {
            OpenRouterModelPicker()
                .environment(appState)
        }
    }

    @ViewBuilder
    private var connectionStatus: some View {
        if appState.settings.apiKey.isEmpty {
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

    var body: some View {
        @Bindable var settings = appState.settings

        Form {
            Section("Model") {
                TextField("Model ID", text: $settings.model)
                    .textFieldStyle(.roundedBorder)

                Text("For OpenRouter, use format: provider/model-name")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Context") {
                Stepper("Max Context: \(TokenCounter.format(settings.maxContextTokens))",
                        value: $settings.maxContextTokens,
                        in: 1024...200000,
                        step: 1024)

                Stepper("Max Response: \(TokenCounter.format(settings.maxResponseTokens))",
                        value: $settings.maxResponseTokens,
                        in: 64...16384,
                        step: 64)
            }
        }
        .formStyle(.grouped)
    }
}

// MARK: - Generation Settings Tab

struct GenerationSettingsTab: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        @Bindable var settings = appState.settings

        Form {
            Section("Sampling") {
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
            }

            Section("Penalties") {
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
            }
        }
        .formStyle(.grouped)
    }
}

// MARK: - Persona Settings Tab

struct PersonaSettingsTab: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        @Bindable var settings = appState.settings

        Form {
            Section("Your Persona") {
                TextField("Name", text: $settings.personaName)

                VStack(alignment: .leading, spacing: 8) {
                    Text("Description")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    TextEditor(text: $settings.personaDescription)
                        .frame(minHeight: 100)
                        .font(.body)
                }
            }

            Section("Content") {
                Toggle("Hide NSFW Character Images", isOn: $settings.hideNSFWImages)
            }
        }
        .formStyle(.grouped)
    }
}

// MARK: - Prompts Settings Tab

struct PromptsSettingsTab: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        @Bindable var settings = appState.settings

        Form {
            Section("System Prompt") {
                TextEditor(text: $settings.mainPrompt)
                    .frame(minHeight: 100)
                    .font(.body.monospaced())

                Text("Use {{char}} for character name, {{user}} for your name")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Jailbreak Prompt") {
                TextEditor(text: $settings.jailbreakPrompt)
                    .frame(minHeight: 80)
                    .font(.body.monospaced())
            }

            Section("Author's Note") {
                TextEditor(text: $settings.authorsNote)
                    .frame(minHeight: 80)
                    .font(.body.monospaced())

                Stepper("Injection Depth: \(settings.authorsNoteDepth)",
                        value: $settings.authorsNoteDepth,
                        in: 0...20)
            }
        }
        .formStyle(.grouped)
    }
}

// MARK: - Preview

#Preview {
    SettingsView()
        .environment(AppState())
}
