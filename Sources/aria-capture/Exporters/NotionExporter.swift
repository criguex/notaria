import Foundation

public struct NotionExporter {
    public let title: String
    public let noteMarkdown: String
    public let date: Date
    public let token: String
    public let parentDatabaseID: String

    public init(title: String, noteMarkdown: String, date: Date, token: String, parentDatabaseID: String) {
        self.title = title
        self.noteMarkdown = noteMarkdown
        self.date = date
        self.token = token
        self.parentDatabaseID = parentDatabaseID
    }

    public func send() async throws {
        let blocks = try parseMarkdownToBlocks(noteMarkdown)

        let payload: [String: Any] = [
            "parent": [
                "database_id": parentDatabaseID,
            ],
            "properties": [
                "Name": [
                    "title": [
                        [
                            "text": [
                                "content": title,
                            ],
                        ],
                    ],
                ],
            ],
            "children": blocks,
        ]

        let jsonData = try JSONSerialization.data(withJSONObject: payload)
        var request = URLRequest(url: URL(string: "https://api.notion.com/v1/pages")!)
        request.httpMethod = "POST"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("2024-06-15", forHTTPHeaderField: "Notion-Version")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = jsonData

        let (_, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse, (200...299).contains(httpResponse.statusCode) else {
            throw NotionExportError.invalidResponse
        }
    }

    private func parseMarkdownToBlocks(_ markdown: String) throws -> [[String: Any]] {
        let lines = markdown.split(separator: "\n", omittingEmptySubsequences: false)
        var blocks: [[String: Any]] = []

        for line in lines {
            let trimmed = String(line).trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty {
                continue
            } else if trimmed.hasPrefix("# ") {
                let text = String(trimmed.dropFirst(2))
                blocks.append(headingBlock(text, level: 1))
            } else if trimmed.hasPrefix("## ") {
                let text = String(trimmed.dropFirst(3))
                blocks.append(headingBlock(text, level: 2))
            } else if trimmed.hasPrefix("### ") {
                let text = String(trimmed.dropFirst(4))
                blocks.append(headingBlock(text, level: 3))
            } else if trimmed.hasPrefix("- ") {
                let text = String(trimmed.dropFirst(2))
                blocks.append(bulletBlock(text))
            } else {
                blocks.append(paragraphBlock(trimmed))
            }
        }

        return blocks
    }

    private func paragraphBlock(_ text: String) -> [String: Any] {
        [
            "object": "block",
            "type": "paragraph",
            "paragraph": [
                "rich_text": [
                    [
                        "type": "text",
                        "text": [
                            "content": text,
                        ],
                    ],
                ],
            ],
        ]
    }

    private func headingBlock(_ text: String, level: Int) -> [String: Any] {
        let type: String
        switch level {
        case 1: type = "heading_1"
        case 2: type = "heading_2"
        case 3: type = "heading_3"
        default: type = "heading_3"
        }

        return [
            "object": "block",
            "type": type,
            type: [
                "rich_text": [
                    [
                        "type": "text",
                        "text": [
                            "content": text,
                        ],
                    ],
                ],
            ],
        ]
    }

    private func bulletBlock(_ text: String) -> [String: Any] {
        [
            "object": "block",
            "type": "bulleted_list_item",
            "bulleted_list_item": [
                "rich_text": [
                    [
                        "type": "text",
                        "text": [
                            "content": text,
                        ],
                    ],
                ],
            ],
        ]
    }
}

public enum NotionExportError: Error {
    case invalidResponse
}
