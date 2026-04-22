import SwiftUI

@main
struct BlogManagerApp: App {
    @StateObject private var prefs = Preferences.shared
    @StateObject private var store = PostStore()
    @StateObject private var hugo = HugoService()
    @StateObject private var tutor = CLITutor()
    @StateObject private var updater = Updater()

    var body: some Scene {
        WindowGroup("Blog Manager") {
            ContentView()
                .environmentObject(prefs)
                .environmentObject(store)
                .environmentObject(hugo)
                .environmentObject(tutor)
                .environmentObject(updater)
                .frame(minWidth: 720, minHeight: 460)
                .onAppear {
                    store.reload(repoPath: prefs.repoPath)
                    // Silent check on launch (~2s delay to let UI settle);
                    // only surfaces a sheet if an update is available.
                    DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                        updater.checkForUpdates(showIfUpToDate: false)
                    }
                }
                .sheet(isPresented: $updater.showSheet) {
                    UpdateSheetView()
                        .environmentObject(updater)
                }
        }
        .commands {
            CommandGroup(replacing: .newItem) {}
            CommandGroup(after: .appInfo) {
                Button("Check for Updates…") {
                    updater.checkForUpdates(showIfUpToDate: true)
                }
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
