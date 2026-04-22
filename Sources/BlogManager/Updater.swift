import SwiftUI
import AppKit

@MainActor
final class Updater: ObservableObject {
    enum State: Equatable {
        case idle
        case checking
        case upToDate(current: String)
        case available(UpdateInfo)
        case downloading
        case installing
        case error(String)
    }

    struct UpdateInfo: Equatable {
        let currentVersion: String
        let latestVersion: String
        let notes: String
        let downloadURL: URL
    }

    @Published var state: State = .idle
    @Published var showSheet: Bool = false

    /// GitHub repository that hosts the releases.
    static let owner = "imeckler"
    static let repo = "hugo-blog-manager"

    static var currentVersion: String {
        (Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String) ?? "0"
    }

    /// Kick off a check. If `showIfUpToDate`, the sheet is opened immediately so
    /// the user sees the "checking" spinner and then the result. For silent
    /// background checks, pass false — the sheet only opens if an update is
    /// available or an error that deserves attention occurs.
    func checkForUpdates(showIfUpToDate: Bool) {
        switch state {
        case .checking, .downloading, .installing:
            if showIfUpToDate { showSheet = true }
            return
        default: break
        }
        state = .checking
        if showIfUpToDate { showSheet = true }
        Task { await performCheck(userInitiated: showIfUpToDate) }
    }

    private func performCheck(userInitiated: Bool) async {
        do {
            let release = try await fetchLatest()
            let current = Self.currentVersion
            if Self.isNewer(release.version, than: current) {
                state = .available(UpdateInfo(
                    currentVersion: current,
                    latestVersion: release.version,
                    notes: release.notes,
                    downloadURL: release.downloadURL
                ))
                showSheet = true
            } else {
                state = .upToDate(current: current)
                if !userInitiated { showSheet = false }
            }
        } catch {
            state = .error(error.localizedDescription)
            if !userInitiated { showSheet = false }
        }
    }

    func installAvailable() {
        guard case .available(let info) = state else { return }
        state = .downloading
        Task { await performDownloadAndInstall(info) }
    }

    func dismiss() {
        showSheet = false
        if case .installing = state { return } // don't clear during install
        state = .idle
    }

    // MARK: - GitHub fetch

    private struct Release {
        let version: String
        let notes: String
        let downloadURL: URL
    }

    private func fetchLatest() async throws -> Release {
        let url = URL(string: "https://api.github.com/repos/\(Self.owner)/\(Self.repo)/releases/latest")!
        var req = URLRequest(url: url)
        req.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        req.setValue("BlogManager/\(Self.currentVersion)", forHTTPHeaderField: "User-Agent")
        let (data, resp) = try await Self.dataTask(for: req)
        guard let http = resp as? HTTPURLResponse, http.statusCode == 200 else {
            let code = (resp as? HTTPURLResponse)?.statusCode ?? -1
            throw UpdaterError("GitHub returned HTTP \(code)")
        }
        let decoded = try JSONDecoder().decode(GHRelease.self, from: data)
        let asset = decoded.assets.first(where: { $0.name.hasSuffix("-macos.zip") })
            ?? decoded.assets.first(where: { $0.name.hasSuffix(".zip") })
        guard let asset else {
            throw UpdaterError("No .zip asset found in release \(decoded.tag_name)")
        }
        guard let downloadURL = URL(string: asset.browser_download_url) else {
            throw UpdaterError("Invalid download URL in release asset")
        }
        return Release(
            version: Self.normalizeVersion(decoded.tag_name),
            notes: decoded.body ?? "",
            downloadURL: downloadURL
        )
    }

    static func normalizeVersion(_ s: String) -> String {
        (s.hasPrefix("v") || s.hasPrefix("V")) ? String(s.dropFirst()) : s
    }

    static func isNewer(_ candidate: String, than current: String) -> Bool {
        compareVersions(normalizeVersion(candidate), normalizeVersion(current)) == .orderedDescending
    }

    private static func compareVersions(_ a: String, _ b: String) -> ComparisonResult {
        let ac = a.split(separator: ".").map { Int($0) ?? 0 }
        let bc = b.split(separator: ".").map { Int($0) ?? 0 }
        let n = max(ac.count, bc.count)
        for i in 0..<n {
            let av = i < ac.count ? ac[i] : 0
            let bv = i < bc.count ? bc[i] : 0
            if av < bv { return .orderedAscending }
            if av > bv { return .orderedDescending }
        }
        return .orderedSame
    }

    // MARK: - Download + install

    private func performDownloadAndInstall(_ info: UpdateInfo) async {
        do {
            // Verify we can actually write to the current app's parent dir before
            // downloading, so we fail early rather than mid-swap.
            let currentAppURL = Bundle.main.bundleURL
            guard currentAppURL.path.hasSuffix(".app") else {
                throw UpdaterError(
                    "Running from \(currentAppURL.path), which isn't a .app bundle. " +
                    "Auto-update only works on release builds."
                )
            }
            let parent = currentAppURL.deletingLastPathComponent().path
            if !FileManager.default.isWritableFile(atPath: parent) {
                throw UpdaterError(
                    "Can't write to \(parent). Move Blog Manager to ~/Applications " +
                    "and try again."
                )
            }

            let zipURL = try await downloadZip(from: info.downloadURL)
            state = .installing
            try await Task.detached(priority: .userInitiated) {
                try await Self.performSwap(zipURL: zipURL, destAppURL: currentAppURL)
            }.value
            // performSwap launches the detached helper that waits for us to exit.
            // Give it a beat to fork, then terminate.
            try? await Task.sleep(nanoseconds: 300_000_000)
            NSApp.terminate(nil)
        } catch {
            state = .error(error.localizedDescription)
        }
    }

    private func downloadZip(from url: URL) async throws -> URL {
        var req = URLRequest(url: url)
        req.setValue("BlogManager/\(Self.currentVersion)", forHTTPHeaderField: "User-Agent")
        let (stableURL, response) = try await Self.downloadTask(for: req)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw UpdaterError("Download failed: HTTP \(http.statusCode)")
        }
        return stableURL
    }

    /// macOS 11 doesn't have the async `URLSession.data(for:)` or `download(for:)`
    /// APIs, so wrap the completion-handler forms.
    private static func dataTask(for request: URLRequest) async throws -> (Data, URLResponse) {
        try await withCheckedThrowingContinuation { cont in
            let task = URLSession.shared.dataTask(with: request) { data, resp, err in
                if let err = err {
                    cont.resume(throwing: err)
                } else if let data = data, let resp = resp {
                    cont.resume(returning: (data, resp))
                } else {
                    cont.resume(throwing: UpdaterError("empty HTTP response"))
                }
            }
            task.resume()
        }
    }

    /// Runs a download and moves the temp file to a stable location inside the
    /// completion closure (URLSession deletes the original when the closure
    /// returns, so moving after resume would race).
    private static func downloadTask(for request: URLRequest) async throws -> (URL, URLResponse) {
        try await withCheckedThrowingContinuation { cont in
            let task = URLSession.shared.downloadTask(with: request) { tempURL, resp, err in
                if let err = err {
                    cont.resume(throwing: err)
                    return
                }
                guard let tempURL = tempURL, let resp = resp else {
                    cont.resume(throwing: UpdaterError("empty download response"))
                    return
                }
                let stable = FileManager.default.temporaryDirectory
                    .appendingPathComponent("BlogManagerUpdate-\(UUID().uuidString).zip")
                do {
                    try FileManager.default.moveItem(at: tempURL, to: stable)
                    cont.resume(returning: (stable, resp))
                } catch {
                    cont.resume(throwing: error)
                }
            }
            task.resume()
        }
    }

    private static func performSwap(zipURL: URL, destAppURL: URL) async throws {
        let fm = FileManager.default
        let work = fm.temporaryDirectory
            .appendingPathComponent("BlogManagerUpdate-\(UUID().uuidString)")
        try fm.createDirectory(at: work, withIntermediateDirectories: true)

        let unzip = runSync("/usr/bin/ditto", ["-x", "-k", zipURL.path, work.path])
        guard unzip.exit == 0 else {
            throw UpdaterError("Unzip failed: \(unzip.err.isEmpty ? unzip.out : unzip.err)")
        }

        let items = try fm.contentsOfDirectory(atPath: work.path)
        guard let appName = items.first(where: { $0.hasSuffix(".app") }) else {
            throw UpdaterError("No .app bundle found inside release zip")
        }
        let newAppURL = work.appendingPathComponent(appName)
        _ = runSync("/usr/bin/xattr", ["-dr", "com.apple.quarantine", newAppURL.path])

        let pid = ProcessInfo.processInfo.processIdentifier
        let scriptURL = work.appendingPathComponent("install.sh")
        let script = """
        #!/bin/sh
        # Wait (up to ~10s) for BlogManager (pid \(pid)) to exit.
        i=0
        while [ $i -lt 50 ] && kill -0 \(pid) 2>/dev/null; do
            sleep 0.2
            i=$((i+1))
        done
        sleep 0.3
        rm -rf \(shQuote(destAppURL.path))
        /usr/bin/ditto \(shQuote(newAppURL.path)) \(shQuote(destAppURL.path))
        /usr/bin/xattr -dr com.apple.quarantine \(shQuote(destAppURL.path)) 2>/dev/null
        /usr/bin/open \(shQuote(destAppURL.path))
        """
        try script.write(to: scriptURL, atomically: true, encoding: .utf8)
        try fm.setAttributes([.posixPermissions: 0o755], ofItemAtPath: scriptURL.path)

        // Fire-and-forget: the inner `&` detaches the real work from the sh we
        // run here, so when this app terminates the script continues as an orphan
        // under launchd.
        let launcher = Process()
        launcher.executableURL = URL(fileURLWithPath: "/bin/sh")
        launcher.arguments = [
            "-c",
            "\(shQuote(scriptURL.path)) </dev/null >/dev/null 2>&1 &",
        ]
        try launcher.run()
        launcher.waitUntilExit()
    }

    private struct RunResult { let exit: Int32; let out: String; let err: String }
    private static func runSync(_ exec: String, _ args: [String]) -> RunResult {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: exec)
        p.arguments = args
        let o = Pipe(), e = Pipe()
        p.standardOutput = o
        p.standardError = e
        do { try p.run() } catch {
            return RunResult(exit: -1, out: "", err: "launch failed: \(error)")
        }
        p.waitUntilExit()
        let out = String(data: o.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        let err = String(data: e.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        return RunResult(exit: p.terminationStatus, out: out, err: err)
    }
}

private func shQuote(_ s: String) -> String {
    if s.isEmpty { return "''" }
    return "'" + s.replacingOccurrences(of: "'", with: "'\\''") + "'"
}

struct UpdaterError: Error, LocalizedError {
    let message: String
    init(_ m: String) { self.message = m }
    var errorDescription: String? { message }
}

private struct GHRelease: Decodable {
    let tag_name: String
    let body: String?
    let assets: [GHAsset]
}

private struct GHAsset: Decodable {
    let name: String
    let browser_download_url: String
}

// MARK: - Sheet UI

struct UpdateSheetView: View {
    @EnvironmentObject var updater: Updater

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            header
            Divider()
            content
            Spacer(minLength: 0)
            HStack {
                Spacer()
                buttons
            }
        }
        .padding(20)
        .frame(width: 460, height: 320)
    }

    private var header: some View {
        HStack(spacing: 10) {
            Image(systemName: "arrow.down.circle")
                .font(.title)
                .foregroundColor(.accentColor)
            VStack(alignment: .leading, spacing: 2) {
                Text("Software Update")
                    .font(.headline)
                Text("Current version: \(Updater.currentVersion)")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
    }

    @ViewBuilder
    private var content: some View {
        switch updater.state {
        case .idle, .checking:
            HStack(spacing: 10) {
                ProgressView()
                Text("Checking for updates…")
            }
        case .upToDate(let current):
            Text("You're on the latest version (\(current)).")
        case .available(let info):
            VStack(alignment: .leading, spacing: 8) {
                Text("Version \(info.latestVersion) is available.")
                    .font(.body.weight(.semibold))
                if !info.notes.isEmpty {
                    SelectableText(text: info.notes)
                        .frame(maxHeight: 160)
                        .background(
                            RoundedRectangle(cornerRadius: 6)
                                .fill(Color(NSColor.textBackgroundColor))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 6)
                                .strokeBorder(Color.secondary.opacity(0.3))
                        )
                }
            }
        case .downloading:
            HStack(spacing: 10) {
                ProgressView()
                Text("Downloading update…")
            }
        case .installing:
            HStack(spacing: 10) {
                ProgressView()
                Text("Installing and relaunching…")
            }
        case .error(let msg):
            VStack(alignment: .leading, spacing: 6) {
                Label("Update failed", systemImage: "exclamationmark.triangle")
                    .foregroundColor(.red)
                SelectableText(text: msg, isMonospaced: true)
                    .frame(maxWidth: .infinity, minHeight: 60, maxHeight: 140)
            }
        }
    }

    @ViewBuilder
    private var buttons: some View {
        switch updater.state {
        case .idle, .checking, .downloading:
            Button("Cancel") { updater.dismiss() }
                .keyboardShortcut(.cancelAction)
        case .upToDate:
            Button("OK") { updater.dismiss() }
                .keyboardShortcut(.defaultAction)
        case .available:
            Button("Later") { updater.dismiss() }
                .keyboardShortcut(.cancelAction)
            Button("Install Update") { updater.installAvailable() }
                .keyboardShortcut(.defaultAction)
        case .installing:
            Text("Blog Manager will relaunch.")
                .font(.caption)
                .foregroundColor(.secondary)
        case .error:
            Button("Close") { updater.dismiss() }
                .keyboardShortcut(.defaultAction)
        }
    }
}
