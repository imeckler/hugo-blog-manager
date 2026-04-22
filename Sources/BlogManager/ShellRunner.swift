import Foundation

enum ShellRunner {
    struct Result {
        let exitCode: Int32
        let stdout: String
        let stderr: String
        var success: Bool { exitCode == 0 }
    }

    /// Runs a command synchronously, waiting for completion. Uses the caller's
    /// PATH by shelling through `/bin/zsh -lc` so tools installed via Homebrew
    /// are found without the user configuring absolute paths.
    static func run(_ executable: String, _ args: [String], cwd: URL? = nil) -> Result {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = args
        if let cwd { process.currentDirectoryURL = cwd }
        let out = Pipe()
        let err = Pipe()
        process.standardOutput = out
        process.standardError = err
        do {
            try process.run()
        } catch {
            return Result(exitCode: -1, stdout: "", stderr: "launch failed: \(error)")
        }
        process.waitUntilExit()
        let stdout = String(data: out.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        let stderr = String(data: err.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        return Result(exitCode: process.terminationStatus, stdout: stdout, stderr: stderr)
    }

    static func git(_ args: [String], repo: URL) -> Result {
        run("/usr/bin/git", ["-C", repo.path] + args)
    }
}
