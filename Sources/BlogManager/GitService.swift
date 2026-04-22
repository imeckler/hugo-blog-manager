import Foundation

struct GitError: Error, LocalizedError {
    let message: String
    var errorDescription: String? { message }
}

enum GitService {
    struct Changes {
        /// Untracked or modified `.md` files inside content/posts, relative to repo root.
        let paths: [String]
        var isEmpty: Bool { paths.isEmpty }
    }

    struct PublishOutcome {
        let committed: Bool
        let pushed: Bool
        let message: String
    }

    static func pendingPosts(repo: URL) -> Result<Changes, GitError> {
        let status = ShellRunner.git(["status", "--porcelain", "--", "content/posts"], repo: repo)
        guard status.success else {
            return .failure(GitError(message: "git status failed: \(status.stderr.isEmpty ? status.stdout : status.stderr)"))
        }
        var paths: [String] = []
        for line in status.stdout.split(separator: "\n") {
            // porcelain format: "XY path" where XY is two-char status code
            let s = String(line)
            guard s.count > 3 else { continue }
            let pathPart = String(s.dropFirst(3))
            // Handle rename arrow "old -> new"
            let path: String
            if let arrow = pathPart.range(of: " -> ") {
                path = String(pathPart[arrow.upperBound...])
            } else {
                path = pathPart
            }
            let unquoted = path.hasPrefix("\"") && path.hasSuffix("\"")
                ? String(path.dropFirst().dropLast())
                : path
            if unquoted.hasSuffix(".md") {
                paths.append(unquoted)
            }
        }
        return .success(Changes(paths: paths))
    }

    static func publish(repo: URL, message: String) -> Result<PublishOutcome, GitError> {
        switch pendingPosts(repo: repo) {
        case .failure(let e):
            return .failure(e)
        case .success(let changes):
            guard !changes.isEmpty else {
                return .success(PublishOutcome(committed: false, pushed: false, message: "No post changes to publish."))
            }
            let add = ShellRunner.git(["add", "--"] + changes.paths, repo: repo)
            guard add.success else {
                return .failure(GitError(message: "git add failed: \(add.stderr)"))
            }
            let commit = ShellRunner.git(["commit", "-m", message], repo: repo)
            guard commit.success else {
                return .failure(GitError(message: "git commit failed: \(commit.stderr.isEmpty ? commit.stdout : commit.stderr)"))
            }
            let push = ShellRunner.git(["push"], repo: repo)
            guard push.success else {
                return .failure(GitError(message: "Committed locally, but git push failed: \(push.stderr.isEmpty ? push.stdout : push.stderr)"))
            }
            let summary = "Published \(changes.paths.count) post\(changes.paths.count == 1 ? "" : "s")."
            return .success(PublishOutcome(committed: true, pushed: true, message: summary))
        }
    }
}
