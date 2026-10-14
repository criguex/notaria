import Foundation

public struct SlackExporter {
    public let title: String
    public let noteMarkdown: String
    public let date: Date
    public let webhookURL: URL

    public init(title: String, noteMarkdown: String, date: Date, webhookURL: URL) {
        self.title = title
        self.noteMarkdown = noteMarkdown
        self.date = date
        self.webhookURL = webhookURL
    }

    public func send() async throws {
        let dateStr = date.formatted(date: .abbreviated, time: .shortened)
        let payload: [String: Any] = [
            "text": title,
            "blocks": [
                [
                    "type": "header",
                    "text": [
                        "type": "plain_text",
                        "text": title,
                    ],
                ],
                [
                    "type": "section",
                    "text": [
                        "type": "mrkdwn",
                        "text": "📅 \(dateStr)\n\n\(noteMarkdown)",
                    ],
                ],
            ],
        ]

        let jsonData = try JSONSerialization.data(withJSONObject: payload)
        var request = URLRequest(url: webhookURL)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = jsonData

        let (_, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse, (200...299).contains(httpResponse.statusCode) else {
            throw SlackExportError.invalidResponse
        }
    }
}

public enum SlackExportError: Error {
    case invalidResponse
}
