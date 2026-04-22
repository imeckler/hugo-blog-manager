import Foundation
import SwiftUI

final class Preferences: ObservableObject {
    static let shared = Preferences()

    private let defaults = UserDefaults.standard
    private enum Key {
        static let repoPath = "repoPath"
        static let editorApp = "editorApp"
        static let hugoPath = "hugoPath"
    }

    @Published var repoPath: String {
        didSet { defaults.set(repoPath, forKey: Key.repoPath) }
    }
    @Published var editorApp: String {
        didSet { defaults.set(editorApp, forKey: Key.editorApp) }
    }
    @Published var hugoPath: String {
        didSet { defaults.set(hugoPath, forKey: Key.hugoPath) }
    }

    private init() {
        self.repoPath = defaults.string(forKey: Key.repoPath) ?? ""
        self.editorApp = defaults.string(forKey: Key.editorApp) ?? "MarkEdit"
        self.hugoPath = defaults.string(forKey: Key.hugoPath) ?? Preferences.defaultHugoPath()
    }

    var postsDirectory: URL? {
        guard !repoPath.isEmpty else { return nil }
        return URL(fileURLWithPath: repoPath).appendingPathComponent("content/posts", isDirectory: true)
    }

    var repoURL: URL? {
        guard !repoPath.isEmpty else { return nil }
        return URL(fileURLWithPath: repoPath, isDirectory: true)
    }

    static func defaultHugoPath() -> String {
        for candidate in ["/opt/homebrew/bin/hugo", "/usr/local/bin/hugo", "/usr/bin/hugo"] {
            if FileManager.default.isExecutableFile(atPath: candidate) { return candidate }
        }
        return "hugo"
    }
}
