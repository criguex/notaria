import AppKit
import PDFKit

public struct PDFExporter {
    public let title: String
    public let noteMarkdown: String
    public let date: Date

    public init(title: String, noteMarkdown: String, date: Date) {
        self.title = title
        self.noteMarkdown = noteMarkdown
        self.date = date
    }

    public func exportToFile(at url: URL) throws {
        guard let attributed = markdownToAttributed(noteMarkdown) else {
            throw PDFExportError.conversionFailed
        }

        let pdfData = NSMutableData()
        let pdfBounds = CGRect(x: 0, y: 0, width: 612, height: 792)

        var mediaBox = pdfBounds
        guard let pdfContext = CGContext(consumer: CGDataConsumer(data: pdfData)!, mediaBox: &mediaBox, nil) else {
            throw PDFExportError.conversionFailed
        }

        let pageDict: CFDictionary? = nil
        pdfContext.beginPDFPage(pageDict)

        let graphicsContext = NSGraphicsContext(cgContext: pdfContext, flipped: false)
        let savedContext = NSGraphicsContext.current
        NSGraphicsContext.current = graphicsContext

        let dateStr = date.formatted(date: .complete, time: .shortened)
        let titleStr = (title as NSString).size(withAttributes: [.font: NSFont.boldSystemFont(ofSize: 24)])

        var yPos: CGFloat = 40
        let leftMargin: CGFloat = 40
        let pageWidth: CGFloat = 612 - 80
        let lineHeight: CGFloat = 20

        let titleAttr = NSAttributedString(string: title, attributes: [.font: NSFont.boldSystemFont(ofSize: 24)])
        titleAttr.draw(at: NSPoint(x: leftMargin, y: yPos))
        yPos += 30

        let dateAttr = NSAttributedString(string: dateStr, attributes: [.font: NSFont.systemFont(ofSize: 10), .foregroundColor: NSColor.gray])
        dateAttr.draw(at: NSPoint(x: leftMargin, y: yPos))
        yPos += 20

        let contentRect = CGRect(x: leftMargin, y: yPos, width: pageWidth, height: 700 - yPos)
        attributed.draw(in: contentRect)

        pdfContext.endPDFPage()
        pdfContext.closePDF()

        NSGraphicsContext.current = savedContext

        try pdfData.write(to: url)
    }

    private func markdownToAttributed(_ markdown: String) -> NSAttributedString? {
        let html = markdownToHTML(markdown)
        guard let data = html.data(using: .utf8) else { return nil }
        return try? NSAttributedString(
            data: data,
            options: [.documentType: NSAttributedString.DocumentType.html, .characterEncoding: String.Encoding.utf8.rawValue],
            documentAttributes: nil
        )
    }

    private func markdownToHTML(_ markdown: String) -> String {
        let lines = markdown.split(separator: "\n", omittingEmptySubsequences: false)
        var html = """
        <!DOCTYPE html>
        <html>
        <head>
            <meta charset="utf-8">
            <style>
                body { font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Helvetica, Arial, sans-serif; margin: 0; padding: 0; line-height: 1.6; }
                h1 { font-size: 24px; margin: 16px 0 8px 0; font-weight: bold; }
                h2 { font-size: 18px; margin: 12px 0 6px 0; font-weight: bold; }
                h3 { font-size: 16px; margin: 10px 0 4px 0; font-weight: bold; }
                p { margin: 4px 0; }
                li { margin: 2px 0 2px 20px; }
                blockquote { border-left: 4px solid #ddd; margin: 4px 0; padding-left: 12px; color: #555; }
            </style>
        </head>
        <body>
        """

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
            } else if trimmed.hasPrefix("> ") {
                let text = String(trimmed.dropFirst(2))
                html += "<blockquote>\(escape(text))</blockquote>"
            } else {
                html += "<p>\(escape(trimmed))</p>"
            }
        }

        html += "</body></html>"
        return html
    }

    private func escape(_ text: String) -> String {
        text
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
    }
}

private class WebViewForPDF: NSView {
    override var isFlipped: Bool { true }
}

public enum PDFExportError: Error {
    case conversionFailed
}
