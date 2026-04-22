import SwiftUI
import AppKit

struct ContentView: View {
    @EnvironmentObject var prefs: Preferences
    @EnvironmentObject var store: PostStore
    @EnvironmentObject var hugo: HugoService
    @EnvironmentObject var tutor: CLITutor

    @State private var selection: Post.ID?
    @State private var commitMessage: String = "Publish blog posts"
    @State private var showCommitSheet = false
    @State private var publishResult: String?
    @State private var isPublishing = false
    @State private var showNewPostSheet = false
    @State private var newPostTitle: String = ""
    @State private var newPostError: String?

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
            if tutor.isEnabled {
                Divider()
                tutorBar
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(Color(NSColor.underPageBackgroundColor))
            }
            Divider()
            postList
            Divider()
            statusBar
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
        }
        .sheet(isPresented: $showCommitSheet) { commitSheet }
        .sheet(isPresented: $showNewPostSheet) { newPostSheet }
        .alert(isPresented: Binding(
            get: { publishResult != nil },
            set: { if !$0 { publishResult = nil } }
        )) {
            Alert(
                title: Text("Publish"),
                message: Text(publishResult ?? ""),
                dismissButton: .default(Text("OK"))
            )
        }
        .background(newPostErrorAlert)
    }

    // macOS 11's `.alert` modifier only accepts one alert per view; stack a
    // second one via a hidden background view.
    private var newPostErrorAlert: some View {
        Color.clear.alert(isPresented: Binding(
            get: { newPostError != nil },
            set: { if !$0 { newPostError = nil } }
        )) {
            Alert(
                title: Text("Couldn't create post"),
                message: Text(newPostError ?? ""),
                dismissButton: .default(Text("OK"))
            )
        }
    }

    private var toolbar: some View {
        HStack(spacing: 10) {
            Button {
                newPostTitle = ""
                showNewPostSheet = true
            } label: {
                Label("New Post", systemImage: "square.and.pencil")
            }
            .disabled(prefs.postsDirectory == nil)
            .cliHint(title: "Create a new post and open it in the editor", command: newPostCommand())

            Button {
                editSelected()
            } label: {
                Label("Edit", systemImage: "pencil")
            }
            .keyboardShortcut(.return, modifiers: [.command])
            .disabled(selection == nil)
            .cliHint(title: "Edit selected post", command: editCommand())

            Button {
                togglePreview()
            } label: {
                if hugo.isRunning {
                    Label("Stop Preview", systemImage: "stop.circle")
                } else {
                    Label("Preview", systemImage: "eye")
                }
            }
            .cliHint(
                title: hugo.isRunning ? "Stop the Hugo preview server" : "Start the Hugo preview server",
                command: previewCommand()
            )

            if case .running(let url) = hugo.state {
                Button {
                    if let u = URL(string: url) { NSWorkspace.shared.open(u) }
                } label: {
                    Text(url)
                        .underline()
                        .lineLimit(1)
                }
                .buttonStyle(.link)
                .cliHint(title: "Open preview URL in browser", command: "open \(CLITutor.shellQuote(url))")
            }

            Spacer()

            Button {
                tutor.isEnabled.toggle()
            } label: {
                Label("CLI Tutor", systemImage: "terminal")
                    .foregroundColor(tutor.isEnabled ? .orange : .primary)
            }
            .help("Show the command-line equivalent for controls you hover")

            Button {
                commitMessage = defaultCommitMessage()
                showCommitSheet = true
            } label: {
                Label("Publish", systemImage: "square.and.arrow.up")
            }
            .disabled(prefs.repoURL == nil || isPublishing)
            .cliHint(title: "Publish: git add, commit, push", command: publishCommand())

            Button {
                store.reload(repoPath: prefs.repoPath)
            } label: {
                Image(systemName: "arrow.clockwise")
            }
            .help("Reload posts")
            .cliHint(title: "List posts on disk (app-internal reload)", command: reloadCommand())
        }
    }

    private var tutorBar: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "terminal")
                .foregroundColor(.orange)
                .padding(.top, 2)
            VStack(alignment: .leading, spacing: 4) {
                Text(tutor.currentTitle.isEmpty
                     ? "Hover any highlighted control to see the CLI equivalent."
                     : tutor.currentTitle)
                    .font(.caption)
                    .foregroundColor(.secondary)
                HStack(alignment: .top, spacing: 8) {
                    SelectableText(
                        text: tutor.currentCommand.isEmpty ? " " : tutor.currentCommand,
                        isMonospaced: true
                    )
                    .frame(minHeight: 40, maxHeight: 90)
                    .background(
                        RoundedRectangle(cornerRadius: 6)
                            .fill(Color(NSColor.textBackgroundColor))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .strokeBorder(Color.secondary.opacity(0.3))
                    )
                    Button {
                        let pb = NSPasteboard.general
                        pb.clearContents()
                        pb.setString(tutor.currentCommand, forType: .string)
                    } label: {
                        Label("Copy", systemImage: "doc.on.doc")
                    }
                    .disabled(tutor.currentCommand.isEmpty)
                }
            }
        }
    }

    private var postList: some View {
        Group {
            if let err = store.loadError {
                VStack(spacing: 12) {
                    Text(err).foregroundColor(.secondary)
                    Button("Open Preferences") {
                        NSApp.sendAction(
                            Selector(("showPreferencesWindow:")),
                            to: nil,
                            from: nil
                        )
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if store.posts.isEmpty {
                Text("No posts found in content/posts.")
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                postListContent
            }
        }
    }

    private var postListContent: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                Text("Date")
                    .frame(width: 120, alignment: .leading)
                Text("Title")
                    .frame(maxWidth: .infinity, alignment: .leading)
                Text("Author")
                    .frame(width: 180, alignment: .leading)
            }
            .font(.caption.weight(.semibold))
            .foregroundColor(.secondary)
            .padding(.horizontal, 12)
            .padding(.vertical, 4)
            Divider()
            List(selection: $selection) {
                ForEach(store.posts) { post in
                    HStack(spacing: 0) {
                        Text(dateLabel(for: post))
                            .font(.system(.body, design: .monospaced))
                            .frame(width: 120, alignment: .leading)
                            .foregroundColor(.secondary)
                        Text(post.title)
                            .lineLimit(1)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        Text(post.author ?? "")
                            .lineLimit(1)
                            .frame(width: 180, alignment: .leading)
                            .foregroundColor(.secondary)
                    }
                    .tag(post.id)
                    .contextMenu {
                        Button("Edit") { edit(postID: post.id) }
                        Button("Reveal in Finder") { revealInFinder(postID: post.id) }
                    }
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
                .foregroundColor(.secondary)
            Spacer()
            Text("\(store.posts.count) post\(store.posts.count == 1 ? "" : "s")")
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }

    private var newPostSheet: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("New Post")
                .font(.headline)
            Text("Creates \(previewNewPostPath(for: newPostTitle)) and opens it in \(prefs.editorApp).")
                .font(.caption)
                .foregroundColor(.secondary)
            TextField("Title", text: $newPostTitle, onCommit: { createNewPost() })
                .textFieldStyle(RoundedBorderTextFieldStyle())
            HStack {
                Spacer()
                Button("Cancel") { showNewPostSheet = false }
                    .keyboardShortcut(.cancelAction)
                Button("Create") { createNewPost() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(newPostTitle.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding(20)
        .frame(width: 460)
    }

    private var commitSheet: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Publish Posts")
                .font(.headline)
            Text("This will `git add` modified posts in content/posts, commit, and push.")
                .font(.caption)
                .foregroundColor(.secondary)
            TextField("Commit message", text: $commitMessage)
                .textFieldStyle(RoundedBorderTextFieldStyle())
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

    // MARK: - New post

    private static let isoDateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone.current
        f.dateFormat = "yyyy-MM-dd'T'HH:mm:ssXXX"
        return f
    }()

    private static let filenameDateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone.current
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    private func slugify(_ input: String) -> String {
        let folded = input.folding(options: .diacriticInsensitive, locale: .init(identifier: "en_US"))
            .lowercased()
        var out = ""
        var lastWasHyphen = false
        for ch in folded {
            if ch.isLetter || ch.isNumber {
                out.append(ch)
                lastWasHyphen = false
            } else if !lastWasHyphen {
                out.append("-")
                lastWasHyphen = true
            }
        }
        while out.hasPrefix("-") { out.removeFirst() }
        while out.hasSuffix("-") { out.removeLast() }
        return out.isEmpty ? "untitled" : out
    }

    private func newPostFilename(for title: String, on date: Date = Date()) -> String {
        "\(Self.filenameDateFormatter.string(from: date))-\(slugify(title)).markdown"
    }

    private func previewNewPostPath(for title: String) -> String {
        let name = newPostFilename(for: title.isEmpty ? "untitled" : title)
        return "content/posts/\(name)"
    }

    private func newPostFrontmatter(title: String, date: Date) -> String {
        // Match the existing YAML convention: ---\ntitle: "..."\ndate: ISO8601\n---\n\n
        let escapedTitle = title.replacingOccurrences(of: "\"", with: "\\\"")
        return """
        ---
        title: "\(escapedTitle)"
        date: \(Self.isoDateFormatter.string(from: date))
        ---


        """
    }

    private func createNewPost() {
        let trimmed = newPostTitle.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        guard let postsDir = prefs.postsDirectory else {
            newPostError = "Set the repo path in Preferences first."
            return
        }
        let now = Date()
        let filename = newPostFilename(for: trimmed, on: now)
        let fileURL = postsDir.appendingPathComponent(filename)

        if FileManager.default.fileExists(atPath: fileURL.path) {
            newPostError = "A file named \(filename) already exists."
            return
        }

        do {
            try FileManager.default.createDirectory(at: postsDir, withIntermediateDirectories: true)
            let body = newPostFrontmatter(title: trimmed, date: now)
            try body.write(to: fileURL, atomically: true, encoding: .utf8)
        } catch {
            newPostError = "Failed to write file: \(error.localizedDescription)"
            return
        }

        showNewPostSheet = false
        newPostTitle = ""
        store.reload(repoPath: prefs.repoPath)
        selection = fileURL

        let result = ShellRunner.run("/usr/bin/open", ["-a", prefs.editorApp, fileURL.path])
        if !result.success {
            _ = ShellRunner.run("/usr/bin/open", [fileURL.path])
        }
    }

    // MARK: - CLI hint commands

    private var repoPathForHint: String {
        prefs.repoPath.isEmpty ? "/path/to/blog" : prefs.repoPath
    }

    private func selectedPostPath() -> String? {
        guard let id = selection,
              let post = store.posts.first(where: { $0.id == id }) else { return nil }
        return post.url.path
    }

    private func newPostCommand() -> String {
        let title = newPostTitle.trimmingCharacters(in: .whitespaces)
        let displayTitle = title.isEmpty ? "My new post" : title
        let filename = newPostFilename(for: displayTitle)
        let relPath = "content/posts/\(filename)"
        let repo = CLITutor.shellQuote(repoPathForHint)
        let editor = CLITutor.shellQuote(prefs.editorApp)
        let absPath = CLITutor.shellQuote("\(repoPathForHint)/\(relPath)")
        let escapedTitle = displayTitle.replacingOccurrences(of: "\"", with: "\\\"")
        let dateStr = Self.isoDateFormatter.string(from: Date())
        return """
        cd \(repo)
        cat > \(CLITutor.shellQuote(relPath)) <<'EOF'
        ---
        title: "\(escapedTitle)"
        date: \(dateStr)
        ---

        EOF
        open -a \(editor) \(absPath)
        """
    }

    private func editCommand() -> String {
        let editor = CLITutor.shellQuote(prefs.editorApp)
        if let p = selectedPostPath() {
            return "open -a \(editor) \(CLITutor.shellQuote(p))"
        }
        let example = CLITutor.shellQuote("\(repoPathForHint)/content/posts/your-post.md")
        return "open -a \(editor) \(example)"
    }

    private func previewCommand() -> String {
        if hugo.isRunning {
            return "# Press Ctrl+C in the terminal running hugo serve\n# or:\npkill -f 'hugo serve'"
        }
        let repo = CLITutor.shellQuote(repoPathForHint)
        let hugo = CLITutor.shellQuote(prefs.hugoPath)
        return "cd \(repo) && \(hugo) serve --buildDrafts --navigateToChanged"
    }

    private func publishCommand() -> String {
        let repo = CLITutor.shellQuote(repoPathForHint)
        let msg = CLITutor.shellQuote(commitMessage.isEmpty ? defaultCommitMessage() : commitMessage)
        return """
        cd \(repo)
        git add -- content/posts
        git commit -m \(msg)
        git push
        """
    }

    private func reloadCommand() -> String {
        let posts = CLITutor.shellQuote("\(repoPathForHint)/content/posts")
        return "ls \(posts)"
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
