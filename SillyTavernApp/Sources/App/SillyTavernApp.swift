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
            SettingsView()
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
                appState.chatState.stopGeneration()
            }
            .keyboardShortcut(.escape, modifiers: [])
            .disabled(!appState.chatState.isGenerating)

            Divider()

            Button("Clear Chat") {
                Task {
                    await appState.chatState.clearChat()
                }
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

