import SwiftUI
import AppKit

struct ContentView: View {
    @EnvironmentObject var prefs: Preferences
    @EnvironmentObject var store: PostStore
    @EnvironmentObject var hugo: HugoService

    @State private var selection: Post.ID?
    @State private var commitMessage: String = "Publish blog posts"
    @State private var showCommitSheet = false
    @State private var publishResult: String?
    @State private var isPublishing = false

    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .none
        return f
    }()

    var body: some View {
        VStack(spacing: 0) {
            toolbar
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
            Divider()
            postList
            Divider()
            statusBar
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
        }
        .sheet(isPresented: $showCommitSheet) { commitSheet }
        .alert("Publish", isPresented: .constant(publishResult != nil), presenting: publishResult) { _ in
            Button("OK") { publishResult = nil }
        } message: { msg in
            Text(msg)
        }
    }

    private var toolbar: some View {
        HStack(spacing: 10) {
            Button {
                editSelected()
            } label: {
                Label("Edit", systemImage: "pencil")
            }
            .disabled(selection == nil)

            Button {
                togglePreview()
            } label: {
                if hugo.isRunning {
                    Label("Stop Preview", systemImage: "stop.circle")
                } else {
                    Label("Preview", systemImage: "eye")
                }
            }

            if case .running(let url) = hugo.state {
                Button {
                    if let u = URL(string: url) { NSWorkspace.shared.open(u) }
                } label: {
                    Text(url)
                        .underline()
                        .lineLimit(1)
                }
                .buttonStyle(.link)
            }

            Spacer()

            Button {
                commitMessage = defaultCommitMessage()
                showCommitSheet = true
            } label: {
                Label("Publish", systemImage: "square.and.arrow.up")
            }
            .disabled(prefs.repoURL == nil || isPublishing)

            Button {
                store.reload(repoPath: prefs.repoPath)
            } label: {
                Image(systemName: "arrow.clockwise")
            }
            .help("Reload posts")
        }
    }

    private var postList: some View {
        Group {
            if let err = store.loadError {
                VStack(spacing: 12) {
                    Text(err).foregroundStyle(.secondary)
                    Button("Open Preferences") {
                        NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if store.posts.isEmpty {
                Text("No posts found in content/posts.")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                Table(store.posts, selection: $selection) {
                    TableColumn("Date") { post in
                        Text(dateLabel(for: post))
                            .monospacedDigit()
                    }
                    .width(min: 100, ideal: 120, max: 160)
                    TableColumn("Title", value: \.title)
                    TableColumn("Author") { post in
                        Text(post.author ?? "")
                            .foregroundStyle(.secondary)
                    }
                    .width(min: 80, ideal: 140, max: 240)
                }
                .contextMenu(forSelectionType: Post.ID.self) { ids in
                    if ids.count == 1 {
                        Button("Edit") { edit(postID: ids.first!) }
                        Button("Reveal in Finder") { revealInFinder(postID: ids.first!) }
                    }
                } primaryAction: { ids in
                    if let id = ids.first { edit(postID: id) }
                }
            }
        }
    }

    private var statusBar: some View {
        HStack(spacing: 12) {
            Circle()
                .fill(statusColor)
                .frame(width: 8, height: 8)
            Text(statusText)
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
            Text("\(store.posts.count) post\(store.posts.count == 1 ? "" : "s")")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var commitSheet: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Publish Posts")
                .font(.headline)
            Text("This will `git add` modified posts in content/posts, commit, and push.")
                .font(.caption)
                .foregroundStyle(.secondary)
            TextField("Commit message", text: $commitMessage)
                .textFieldStyle(.roundedBorder)
            HStack {
                Spacer()
                Button("Cancel") { showCommitSheet = false }
                    .keyboardShortcut(.cancelAction)
                Button(isPublishing ? "Publishing…" : "Publish") {
                    runPublish()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(commitMessage.trimmingCharacters(in: .whitespaces).isEmpty || isPublishing)
            }
        }
        .padding(20)
        .frame(width: 460)
    }

    // MARK: - Helpers

    private func dateLabel(for post: Post) -> String {
        if let d = post.date { return Self.dateFormatter.string(from: d) }
        return post.rawDate ?? "—"
    }

    private var statusColor: Color {
        switch hugo.state {
        case .idle: return .gray
        case .starting: return .yellow
        case .running: return .green
        case .failed: return .red
        }
    }

    private var statusText: String {
        switch hugo.state {
        case .idle: return prefs.repoPath.isEmpty ? "No repo configured" : "Ready"
        case .starting: return "Starting hugo serve…"
        case .running(let url): return "Preview running at \(url)"
        case .failed(let msg): return "Hugo failed: \(msg)"
        }
    }

    private func editSelected() {
        guard let id = selection else { return }
        edit(postID: id)
    }

    private func edit(postID: URL) {
        guard let post = store.posts.first(where: { $0.id == postID }) else { return }
        let result = ShellRunner.run("/usr/bin/open", ["-a", prefs.editorApp, post.url.path])
        if !result.success {
            // Fallback: open with default app
            _ = ShellRunner.run("/usr/bin/open", [post.url.path])
        }
    }

    private func revealInFinder(postID: URL) {
        guard let post = store.posts.first(where: { $0.id == postID }) else { return }
        NSWorkspace.shared.activateFileViewerSelecting([post.url])
    }

    private func togglePreview() {
        if hugo.isRunning {
            hugo.stop()
        } else {
            guard let repo = prefs.repoURL else { return }
            hugo.start(hugoPath: prefs.hugoPath, repo: repo)
        }
    }

    private func defaultCommitMessage() -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        return "Publish posts \(f.string(from: Date()))"
    }

    private func runPublish() {
        guard let repo = prefs.repoURL else { return }
        isPublishing = true
        let message = commitMessage
        DispatchQueue.global(qos: .userInitiated).async {
            let result = GitService.publish(repo: repo, message: message)
            DispatchQueue.main.async {
                isPublishing = false
                showCommitSheet = false
                switch result {
                case .success(let outcome):
                    publishResult = outcome.message
                    store.reload(repoPath: prefs.repoPath)
                case .failure(let err):
                    publishResult = err.message
                }
            }
        }
    }
}
