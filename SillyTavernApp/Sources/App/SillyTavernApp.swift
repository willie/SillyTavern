import SwiftUI
#if os(macOS)
import AppKit
#endif

#if os(macOS)
class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        NSApp.windows.first?.makeKeyAndOrderFront(nil)
    }
}
#endif

@main
struct SillyTavernApp: App {
    #if os(macOS)
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    #endif
    @State private var appState = AppState()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(appState)
                .onGeometryChange(for: CGSize.self) { proxy in
                    proxy.size
                } action: { size in
                    appState.windowSize = size
                }
        }
        #if os(macOS)
        .commands {
            AppCommands(appState: appState)
        }
        #endif

        #if os(macOS)
        Settings {
            SettingsView_macOS()
                .environment(appState)
        }
        #endif
    }
}

// MARK: - Content View (Platform Router)

struct ContentView: View {
    var body: some View {
        #if os(iOS)
        RootView_iOS()
        #elseif os(macOS)
        RootView_macOS()
        #endif
    }
}

// MARK: - macOS Commands

#if os(macOS)
struct AppCommands: Commands {
    let appState: AppState

    var body: some Commands {
        CommandGroup(replacing: .newItem) {
            Button("New Chat") {
                if let character = appState.activeCharacter {
                    appState.newChat(with: character)
                }
            }
            .keyboardShortcut("n")
            .disabled(appState.activeCharacter == nil)

            Button("New Group") {
                let group = CharacterGroup(name: "New Group")
                appState.groups.add(group)
            }
            .keyboardShortcut("n", modifiers: [.command, .shift])

            Divider()

            Button("Import Character...") {
                // Import handled via file importer in CharacterListView
            }
            .keyboardShortcut("o")
        }

        CommandMenu("Chat") {
            Button("Send Message") {
                Task {
                    await appState.chatState.send()
                }
            }
            .keyboardShortcut(.return, modifiers: .command)
            .disabled(appState.chatState.isGenerating || appState.chatState.inputText.isEmpty)

            Button("Regenerate") {
                Task {
                    await appState.chatState.regenerate()
                }
            }
            .keyboardShortcut("r", modifiers: .command)
            .disabled(appState.chatState.isGenerating || appState.chatState.messages.isEmpty)

            Button("Continue") {
                Task {
                    await appState.chatState.continueGeneration()
                }
            }
            .keyboardShortcut(.return, modifiers: [.command, .shift])
            .disabled(appState.chatState.isGenerating)

            Divider()

            Button("Stop Generation") {
                // Would need cancellation support in ChatState
            }
            .keyboardShortcut(.escape, modifiers: [])
            .disabled(!appState.chatState.isGenerating)

            Divider()

            Button("Clear Chat") {
                appState.chatState.clearChat()
            }
            .disabled(appState.chatState.messages.isEmpty)
        }

        CommandMenu("Navigate") {
            Button("Chats") {
                appState.sidebarSelection = .chats
            }
            .keyboardShortcut("1", modifiers: .command)

            Button("Characters") {
                appState.sidebarSelection = .characters
            }
            .keyboardShortcut("2", modifiers: .command)

            Button("Groups") {
                appState.sidebarSelection = .groups
            }
            .keyboardShortcut("3", modifiers: .command)

            Button("World Info") {
                appState.sidebarSelection = .worldInfo
            }
            .keyboardShortcut("4", modifiers: .command)

            Button("Settings") {
                appState.sidebarSelection = .settings
            }
            .keyboardShortcut(",", modifiers: .command)
        }

        CommandGroup(after: .sidebar) {
            Button("Toggle Inspector") {
                appState.isInspectorPresented.toggle()
            }
            .keyboardShortcut("i", modifiers: [.command, .option])
        }
    }
}
#endif

// MARK: - macOS Settings Window

#if os(macOS)
struct SettingsView_macOS: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        TabView {
            APISettingsTab()
                .environment(appState)
                .tabItem {
                    Label("API", systemImage: "key")
                }

            ModelSettingsTab()
                .environment(appState)
                .tabItem {
                    Label("Model", systemImage: "cpu")
                }

            GenerationSettingsTab()
                .environment(appState)
                .tabItem {
                    Label("Generation", systemImage: "slider.horizontal.3")
                }
        }
        .frame(width: 500, height: 350)
    }
}

struct APISettingsTab: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        @Bindable var settings = appState.settings

        Form {
            Picker("Provider", selection: $settings.selectedProvider) {
                Text("OpenAI").tag("openai")
                Text("Claude").tag("claude")
                Text("OpenRouter").tag("openrouter")
                Text("Custom").tag("custom")
            }

            SecureField("API Key", text: $settings.apiKey)
                .textContentType(.password)

            if settings.selectedProvider == "custom" || settings.selectedProvider == "openrouter" {
                TextField("Base URL", text: $settings.baseURL)
            }

            LabeledContent("Status") {
                if settings.apiKey.isEmpty {
                    Text("No API Key")
                        .foregroundStyle(.secondary)
                } else {
                    Text("Ready")
                        .foregroundStyle(.green)
                }
            }
        }
        .formStyle(.grouped)
        .padding()
    }
}

struct ModelSettingsTab: View {
    @Environment(AppState.self) private var appState

    private var suggestedModels: [String] {
        switch appState.settings.selectedProvider {
        case "openai":
            return ["gpt-4o", "gpt-4o-mini", "gpt-4-turbo", "gpt-4", "gpt-3.5-turbo", "o1-preview", "o1-mini"]
        case "claude":
            return ["claude-sonnet-4-20250514", "claude-3-5-sonnet-20241022", "claude-3-5-haiku-20241022", "claude-3-opus-20240229"]
        case "openrouter":
            return ["openai/gpt-4o", "anthropic/claude-3.5-sonnet", "anthropic/claude-3-opus", "meta-llama/llama-3.1-405b-instruct"]
        default:
            return ["gpt-4o", "gpt-4", "gpt-3.5-turbo"]
        }
    }

    var body: some View {
        @Bindable var settings = appState.settings

        Form {
            Picker("Model", selection: $settings.model) {
                ForEach(suggestedModels, id: \.self) { model in
                    Text(model).tag(model)
                }
            }

            Stepper("Max Context: \(TokenCounter.format(settings.maxContextTokens))",
                    value: $settings.maxContextTokens,
                    in: 1024...200000,
                    step: 1024)

            Stepper("Max Response: \(TokenCounter.format(settings.maxResponseTokens))",
                    value: $settings.maxResponseTokens,
                    in: 64...16384,
                    step: 64)
        }
        .formStyle(.grouped)
        .padding()
    }
}

struct GenerationSettingsTab: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        @Bindable var settings = appState.settings

        Form {
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text("Temperature")
                    Spacer()
                    Text(String(format: "%.2f", settings.temperature))
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
                Slider(value: $settings.temperature, in: 0...2, step: 0.05)
            }

            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text("Top P")
                    Spacer()
                    Text(String(format: "%.2f", settings.topP))
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
                Slider(value: $settings.topP, in: 0...1, step: 0.05)
            }

            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text("Frequency Penalty")
                    Spacer()
                    Text(String(format: "%.2f", settings.frequencyPenalty))
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
                Slider(value: $settings.frequencyPenalty, in: 0...2, step: 0.05)
            }

            VStack(alignment: .leading, spacing: 4) {
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
        .formStyle(.grouped)
        .padding()
    }
}
#endif
