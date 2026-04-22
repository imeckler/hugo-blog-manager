import SwiftUI
import AppKit

struct PreferencesView: View {
    @EnvironmentObject var prefs: Preferences
    @EnvironmentObject var store: PostStore

    var body: some View {
        Form {
            Section(header: Text("Blog")) {
                HStack {
                    TextField("Repo path", text: $prefs.repoPath)
                        .textFieldStyle(RoundedBorderTextFieldStyle())
                    Button("Choose…") { pickRepo() }
                }
                if let dir = prefs.postsDirectory {
                    Text("Posts: \(dir.path)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }

            Section(header: Text("Editor")) {
                TextField("Editor app name", text: $prefs.editorApp)
                    .textFieldStyle(RoundedBorderTextFieldStyle())
                Text("Used with `open -a`. Default: MarkEdit.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Section(header: Text("Hugo")) {
                HStack {
                    TextField("Hugo binary", text: $prefs.hugoPath)
                        .textFieldStyle(RoundedBorderTextFieldStyle())
                    Button("Choose…") { pickHugo() }
                }
            }
        }
        .padding(20)
        .frame(width: 520)
    }

    private func pickRepo() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        if panel.runModal() == .OK, let url = panel.url {
            prefs.repoPath = url.path
            store.reload(repoPath: prefs.repoPath)
        }
    }

    private func pickHugo() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        if panel.runModal() == .OK, let url = panel.url {
            prefs.hugoPath = url.path
        }
    }
}
