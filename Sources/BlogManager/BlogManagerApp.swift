import SwiftUI

@main
struct BlogManagerApp: App {
    @StateObject private var prefs = Preferences.shared
    @StateObject private var store = PostStore()
    @StateObject private var hugo = HugoService()

    var body: some Scene {
        WindowGroup("Blog Manager") {
            ContentView()
                .environmentObject(prefs)
                .environmentObject(store)
                .environmentObject(hugo)
                .frame(minWidth: 720, minHeight: 460)
                .onAppear { store.reload(repoPath: prefs.repoPath) }
        }
        .commands {
            CommandGroup(replacing: .newItem) {}
            CommandGroup(after: .appInfo) {
                Button("Reload Posts") { store.reload(repoPath: prefs.repoPath) }
                    .keyboardShortcut("r", modifiers: [.command])
            }
        }

        Settings {
            PreferencesView()
                .environmentObject(prefs)
                .environmentObject(store)
        }
    }
}
