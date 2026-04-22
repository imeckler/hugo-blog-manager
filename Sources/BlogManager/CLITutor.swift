import SwiftUI
import AppKit

@MainActor
final class CLITutor: ObservableObject {
    @Published var isEnabled: Bool = false
    @Published var currentTitle: String = ""
    @Published var currentCommand: String = ""

    func setHint(title: String, command: String) {
        currentTitle = title
        currentCommand = command
    }

    /// Quote a string for safe use as a shell argument in a displayed command.
    /// Leaves plain identifier-ish strings untouched; single-quotes anything else.
    static func shellQuote(_ s: String) -> String {
        if s.isEmpty { return "''" }
        let safe = CharacterSet(charactersIn:
            "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-_./:=@%+,")
        if s.unicodeScalars.allSatisfy({ safe.contains($0) }) { return s }
        return "'" + s.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }
}

private struct CLIHintModifier: ViewModifier {
    @EnvironmentObject var tutor: CLITutor
    let title: String
    let command: () -> String

    func body(content: Content) -> some View {
        content
            .overlay(
                RoundedRectangle(cornerRadius: 5)
                    .strokeBorder(
                        Color.orange.opacity(0.7),
                        style: StrokeStyle(lineWidth: 1, dash: [3, 3])
                    )
                    .padding(-2)
                    .opacity(tutor.isEnabled ? 1 : 0)
                    .allowsHitTesting(false)
            )
            .onHover { hovering in
                guard tutor.isEnabled, hovering else { return }
                tutor.setHint(title: title, command: command())
            }
    }
}

extension View {
    /// Registers a CLI equivalent for this view. When CLI Tutor mode is on,
    /// hovering this view publishes the command to the tutor's hint bar.
    /// The `command` autoclosure is re-evaluated on each hover so it reflects
    /// current state (selection, repo path, etc.).
    func cliHint(title: String, command: @escaping @autoclosure () -> String) -> some View {
        modifier(CLIHintModifier(title: title, command: command))
    }
}
