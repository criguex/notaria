import AppKit
import Foundation

public struct ClipboardExporter {
    public let title: String
    public let noteMarkdown: String

    public init(title: String, noteMarkdown: String) {
        self.title = title
        self.noteMarkdown = noteMarkdown
    }

    public func copyAsMarkdown() throws {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(noteMarkdown, forType: .string)
    }

    public func copyAsRich() throws {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()

        let htmlString = markdownToHTML(noteMarkdown)
        if let rtf = htmlToRTF(htmlString) {
            pasteboard.setString(rtf, forType: .rtf)
        }
        pasteboard.setString(noteMarkdown, forType: .string)
    }

    private func markdownToHTML(_ markdown: String) -> String {
        let lines = markdown.split(separator: "\n", omittingEmptySubsequences: false)
        var html = "<html><body>"

        for line in lines {
            let trimmed = String(line).trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty {
                html += "<p></p>"
            } else if trimmed.hasPrefix("# ") {
                let text = String(trimmed.dropFirst(2))
                html += "<h1>\(escape(text))</h1>"
            } else if trimmed.hasPrefix("## ") {
                let text = String(trimmed.dropFirst(3))
                html += "<h2>\(escape(text))</h2>"
            } else if trimmed.hasPrefix("### ") {
                let text = String(trimmed.dropFirst(4))
                html += "<h3>\(escape(text))</h3>"
            } else if trimmed.hasPrefix("- ") {
                let text = String(trimmed.dropFirst(2))
                html += "<li>\(escape(text))</li>"
            } else {
                html += "<p>\(escape(trimmed))</p>"
            }
        }

        html += "</body></html>"
        return html
    }

    private func htmlToRTF(_ html: String) -> String? {
        let options: [NSAttributedString.DocumentReadingOptionKey: Any] = [
            .documentType: NSAttributedString.DocumentType.html,
            .characterEncoding: String.Encoding.utf8.rawValue,
        ]
        guard let data = html.data(using: .utf8),
              let attributed = try? NSAttributedString(data: data, options: options, documentAttributes: nil)
        else {
            return nil
        }

        let rtfData = attributed.rtf(from: NSRange(location: 0, length: attributed.length), documentAttributes: [:])
        return rtfData.flatMap { String(data: $0, encoding: .utf8) }
    }

    private func escape(_ text: String) -> String {
        text
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
    }
}
