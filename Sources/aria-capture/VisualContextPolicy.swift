import Foundation

struct LumaFingerprint: Equatable {
    let columns: Int
    let rows: Int
    let samples: [UInt8]

    static func compute(grayscalePixels pixels: [UInt8], width: Int, height: Int, columns: Int, rows: Int) -> LumaFingerprint {
        guard width > 0, height > 0, columns > 0, rows > 0, pixels.count >= width * height else {
            return LumaFingerprint(columns: columns, rows: rows, samples: Array(repeating: 0, count: max(columns * rows, 0)))
        }
        var samples = [UInt8](repeating: 0, count: columns * rows)
        let cellWidth = max(width / columns, 1)
        let cellHeight = max(height / rows, 1)
        for row in 0..<rows {
            let yStart = row * cellHeight
            let yEnd = row == rows - 1 ? height : min(yStart + cellHeight, height)
            guard yEnd > yStart else { continue }
            for col in 0..<columns {
                let xStart = col * cellWidth
                let xEnd = col == columns - 1 ? width : min(xStart + cellWidth, width)
                guard xEnd > xStart else { continue }
                var sum = 0
                var count = 0
                for y in yStart..<yEnd {
                    let rowBase = y * width
                    for x in xStart..<xEnd {
                        sum += Int(pixels[rowBase + x])
                        count += 1
                    }
                }
                samples[row * columns + col] = count > 0 ? UInt8(sum / count) : 0
            }
        }
        return LumaFingerprint(columns: columns, rows: rows, samples: samples)
    }
}

struct VisualFingerprintDiff {
    let meanLumaDiff: Double
    let changedSampleRatio: Double
    let changed: Bool

    static func compare(
        _ previous: LumaFingerprint,
        _ current: LumaFingerprint,
        perSampleChangeDelta: UInt8 = 4,
        changedRatioThreshold: Double
    ) -> VisualFingerprintDiff {
        guard previous.samples.count == current.samples.count, !previous.samples.isEmpty else {
            return VisualFingerprintDiff(meanLumaDiff: 1, changedSampleRatio: 1, changed: true)
        }
        var totalDiff = 0
        var changedCount = 0
        for index in 0..<previous.samples.count {
            let diff = abs(Int(previous.samples[index]) - Int(current.samples[index]))
            totalDiff += diff
            if diff >= Int(perSampleChangeDelta) { changedCount += 1 }
        }
        let meanDiff = Double(totalDiff) / Double(previous.samples.count) / 255.0
        let ratio = Double(changedCount) / Double(previous.samples.count)
        return VisualFingerprintDiff(meanLumaDiff: meanDiff, changedSampleRatio: ratio, changed: ratio >= changedRatioThreshold)
    }
}

enum VisualSamplingPolicy {
    /// Piso mínimo: si no hubo cambio, no se vuelve a capturar antes de este intervalo.
    static let floorSeconds: TimeInterval = 30

    static func shouldCapture(
        elapsedSinceLastCapture: TimeInterval?,
        changed: Bool,
        floorSeconds: TimeInterval = floorSeconds
    ) -> Bool {
        guard let elapsedSinceLastCapture else { return true }
        if changed { return true }
        return elapsedSinceLastCapture >= floorSeconds
    }
}

enum VisualAppExclusionPolicy {
    /// Bundle ids excluidos por defecto: gestores de contraseñas, mensajería y banca/correo.
    static let defaultExcludedBundleIDs: [String] = [
        "com.1password.1password",
        "com.agilebits.onepassword7",
        "com.bitwarden.desktop",
        "com.apple.keychainaccess",
        "com.apple.MobileSMS",
        "com.apple.mail",
        "net.whatsapp.WhatsApp"
    ]

    static func parsedList(_ raw: String) -> [String] {
        raw.split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }

    static func isExcluded(bundleID: String?, excludedList: [String]) -> Bool {
        guard let bundleID, !bundleID.isEmpty else { return false }
        return excludedList.contains { $0.caseInsensitiveCompare(bundleID) == .orderedSame }
    }
}

enum VisualOCRQuality {
    /// Descarta capturas sin texto útil (ruido de OCR, pantallas vacías, etc.).
    static func usefulText(from lines: [String], minimumCharacters: Int = 8) -> String? {
        let cleaned = lines
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        let joined = cleaned.joined(separator: "\n")
        return joined.count >= minimumCharacters ? joined : nil
    }
}

struct VisualCaptureRecord: Equatable {
    let elapsedSeconds: TimeInterval
    let ocrText: String
    let imageFileName: String
}

enum VisualContextStorage {

    static func imageFileName(index: Int) -> String {
        String(format: "%02d.jpg", index)
    }

    static func timeLabel(elapsedSeconds: TimeInterval) -> String {
        let total = max(Int(elapsedSeconds.rounded()), 0)
        return String(format: "%d:%02d", total / 60, total % 60)
    }

    static func capturesDirectory(forNoteAt noteURL: URL) -> (stem: String, directory: URL) {
        let stem = noteURL.deletingPathExtension().lastPathComponent
        let directory = noteURL.deletingLastPathComponent()
            .appendingPathComponent(stem, isDirectory: true)
            .appendingPathComponent("capturas", isDirectory: true)
        return (stem, directory)
    }

    static func embedLine(noteStem: String, capture: VisualCaptureRecord) -> String {
        "![[\(noteStem)/capturas/\(capture.imageFileName)]] — \(timeLabel(elapsedSeconds: capture.elapsedSeconds))"
    }

    static func sectionMarkdown(noteStem: String, captures: [VisualCaptureRecord]) -> String? {
        guard !captures.isEmpty else { return nil }
        let lines = captures.map { embedLine(noteStem: noteStem, capture: $0) }
        return "\n## Contexto visual\n" + lines.joined(separator: "\n") + "\n"
    }

    static func writeImages(_ images: [(fileName: String, data: Data)], toDirectory directory: URL) throws {
        guard !images.isEmpty else { return }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        for item in images {
            try item.data.write(to: directory.appendingPathComponent(item.fileName))
        }
    }

    static func appendSection(noteStem: String, captures: [VisualCaptureRecord], toNoteAt noteURL: URL) throws {
        guard let section = sectionMarkdown(noteStem: noteStem, captures: captures),
              let data = section.data(using: .utf8) else { return }
        guard let handle = FileHandle(forWritingAtPath: noteURL.path) else {
            throw CocoaError(.fileNoSuchFile)
        }
        defer { handle.closeFile() }
        handle.seekToEndOfFile()
        handle.write(data)
    }
}

enum VisualContextPrompt {
    /// Arma el bloque de contexto visual para el enhance, acotado en caracteres (proxy de tokens).
    static func summaryBlock(
        captures: [VisualCaptureRecord],
        maxCharsPerCapture: Int = 400,
        maxTotalChars: Int = 6_000
    ) -> String? {
        guard !captures.isEmpty else { return nil }
        var lines: [String] = []
        var total = 0
        for capture in captures.sorted(by: { $0.elapsedSeconds < $1.elapsedSeconds }) {
            let trimmedText = String(capture.ocrText.prefix(maxCharsPerCapture))
            let line = "[\(VisualContextStorage.timeLabel(elapsedSeconds: capture.elapsedSeconds))] \(trimmedText)"
            if total + line.count > maxTotalChars { break }
            lines.append(line)
            total += line.count
        }
        guard !lines.isEmpty else { return nil }
        return lines.joined(separator: "\n")
    }
}
