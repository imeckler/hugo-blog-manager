import Foundation
import SwiftUI

@MainActor
final class HugoService: ObservableObject {
    enum State: Equatable {
        case idle
        case starting
        case running(url: String)
        case failed(String)
    }

    @Published private(set) var state: State = .idle
    @Published private(set) var logTail: String = ""

    private var process: Process?
    private var stdoutHandle: FileHandle?
    private var stderrHandle: FileHandle?

    var isRunning: Bool {
        switch state {
        case .starting, .running: return true
        default: return false
        }
    }

    func start(hugoPath: String, repo: URL) {
        stop()
        state = .starting
        logTail = ""

        let proc = Process()
        proc.currentDirectoryURL = repo
        proc.executableURL = URL(fileURLWithPath: hugoPath)
        proc.arguments = ["serve", "--buildDrafts", "--navigateToChanged"]

        let out = Pipe(), err = Pipe()
        proc.standardOutput = out
        proc.standardError = err
        stdoutHandle = out.fileHandleForReading
        stderrHandle = err.fileHandleForReading

        let urlRegex = try? NSRegularExpression(
            pattern: #"(https?://(?:localhost|127\.0\.0\.1)(?::\d+)?/?)"#
        )

        let onChunk: @Sendable (FileHandle) -> Void = { [weak self] handle in
            let data = handle.availableData
            if data.isEmpty { return }
            guard let chunk = String(data: data, encoding: .utf8) else { return }
            DispatchQueue.main.async {
                guard let self else { return }
                self.logTail = String((self.logTail + chunk).suffix(4000))
                if case .running = self.state { return }
                if let regex = urlRegex {
                    let ns = chunk as NSString
                    if let m = regex.firstMatch(in: chunk, range: NSRange(location: 0, length: ns.length)) {
                        let url = ns.substring(with: m.range(at: 1))
                        self.state = .running(url: url)
                    }
                }
            }
        }

        stdoutHandle?.readabilityHandler = onChunk
        stderrHandle?.readabilityHandler = onChunk

        proc.terminationHandler = { [weak self] p in
            DispatchQueue.main.async {
                guard let self else { return }
                self.stdoutHandle?.readabilityHandler = nil
                self.stderrHandle?.readabilityHandler = nil
                self.stdoutHandle = nil
                self.stderrHandle = nil
                self.process = nil
                if case .running = self.state {
                    self.state = .idle
                } else if p.terminationStatus != 0 {
                    self.state = .failed("hugo exited with status \(p.terminationStatus). \(self.logTail.suffix(500))")
                } else {
                    self.state = .idle
                }
            }
        }

        do {
            try proc.run()
            self.process = proc
        } catch {
            state = .failed("Failed to launch hugo at \(hugoPath): \(error.localizedDescription)")
        }
    }

    func stop() {
        guard let proc = process else {
            state = .idle
            return
        }
        proc.terminate()
        // give hugo a moment to exit gracefully; terminationHandler clears state
        DispatchQueue.global().asyncAfter(deadline: .now() + 2) { [weak proc] in
            if let p = proc, p.isRunning { p.interrupt() }
        }
    }
}
