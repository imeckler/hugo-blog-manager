import Foundation
import SwiftUI

@MainActor
final class PostStore: ObservableObject {
    @Published var posts: [Post] = []
    @Published var loadError: String?

    private static let markdownExtensions: Set<String> = ["md", "markdown"]
    private static let indexNames: [String] = ["index.md", "index.markdown", "_index.md", "_index.markdown"]

    func reload(repoPath: String) {
        loadError = nil
        guard !repoPath.isEmpty else {
            posts = []
            loadError = "Set the repo path in Preferences."
            return
        }
        let postsDir = URL(fileURLWithPath: repoPath).appendingPathComponent("content/posts", isDirectory: true)
        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: postsDir.path, isDirectory: &isDir), isDir.boolValue else {
            posts = []
            loadError = "content/posts not found at \(postsDir.path)"
            return
        }
        do {
            let contents = try FileManager.default.contentsOfDirectory(
                at: postsDir,
                includingPropertiesForKeys: [.isDirectoryKey],
                options: [.skipsHiddenFiles]
            )
            let loaded: [Post] = contents.compactMap { url in
                let values = try? url.resourceValues(forKeys: [.isDirectoryKey])
                if values?.isDirectory == true {
                    // Page bundle: look for index.md / _index.md inside
                    for name in Self.indexNames {
                        let candidate = url.appendingPathComponent(name)
                        if FileManager.default.fileExists(atPath: candidate.path) {
                            return Self.load(fileURL: candidate, bundleURL: url)
                        }
                    }
                    return nil
                }
                let ext = url.pathExtension.lowercased()
                guard Self.markdownExtensions.contains(ext) else { return nil }
                return Self.load(fileURL: url, bundleURL: url)
            }
            posts = loaded.sorted { (a, b) in
                switch (a.date, b.date) {
                case let (x?, y?): return x > y
                case (nil, _?): return false
                case (_?, nil): return true
                default: return a.title.localizedCaseInsensitiveCompare(b.title) == .orderedAscending
                }
            }
            if posts.isEmpty {
                loadError = "No posts found under \(postsDir.path)"
            }
        } catch {
            posts = []
            loadError = error.localizedDescription
        }
    }

    private static func load(fileURL: URL, bundleURL: URL) -> Post? {
        guard let data = try? Data(contentsOf: fileURL),
              let text = String(data: data, encoding: .utf8) else {
            return nil
        }
        let fm = Frontmatter.parse(text)
        let title = fm["title"] ?? bundleURL.deletingPathExtension().lastPathComponent
        let author = fm["author"]
        let rawDate = fm["date"]
        let date = rawDate.flatMap { Frontmatter.parseDate($0) }
        return Post(id: fileURL, title: title, date: date, author: author, rawDate: rawDate, bundleURL: bundleURL)
    }
}
