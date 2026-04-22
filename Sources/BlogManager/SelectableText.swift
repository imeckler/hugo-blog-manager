import SwiftUI
import AppKit

/// Read-only, selectable text that wraps an `NSTextView`. Works on macOS 11
/// (unlike `.textSelection(.enabled)`, which is macOS 12+).
struct SelectableText: NSViewRepresentable {
    let text: String
    var font: NSFont = .preferredFont(forTextStyle: .body)
    var isMonospaced: Bool = false

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSTextView.scrollableTextView()
        scrollView.drawsBackground = false
        scrollView.borderType = .noBorder
        scrollView.hasHorizontalScroller = false
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true

        if let tv = scrollView.documentView as? NSTextView {
            tv.isEditable = false
            tv.isSelectable = true
            tv.drawsBackground = false
            tv.textContainerInset = NSSize(width: 6, height: 6)
            tv.font = effectiveFont()
            tv.string = text
            tv.textContainer?.lineFragmentPadding = 0
        }
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let tv = scrollView.documentView as? NSTextView else { return }
        if tv.string != text { tv.string = text }
        let f = effectiveFont()
        if tv.font != f { tv.font = f }
    }

    private func effectiveFont() -> NSFont {
        isMonospaced
            ? .monospacedSystemFont(ofSize: NSFont.systemFontSize, weight: .regular)
            : font
    }
}
