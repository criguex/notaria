import Foundation

/// Formato de una línea del log local de diagnóstico del detector de
/// llamadas/reuniones. Deliberadamente no incluye títulos de reunión ni
/// nombres de asistentes — solo timestamps, señales (booleanos, nombres
/// genéricos de app de llamadas) y la decisión tomada.
enum DetectorLogFormatter {

    static let timestampFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        formatter.timeZone = .current
        return formatter
    }()

    static func line(
        at date: Date,
        micInUse: Bool,
        callApps: [String],
        hasMeetingNow: Bool,
        meetingPromptExcluded: Bool,
        alwaysOn: Bool,
        isRecording: Bool,
        decision: String
    ) -> String {
        let apps = callApps.isEmpty ? "ninguna" : callApps.sorted().joined(separator: "+")
        return "\(timestampFormatter.string(from: date)) mic=\(micInUse) apps=\(apps) meetingNow=\(hasMeetingNow) meetingExcluded=\(meetingPromptExcluded) alwaysOn=\(alwaysOn) recording=\(isRecording) decision=\(decision)"
    }
}

/// Escribe el log de diagnóstico en ~/Library/Logs/NotarIA/detector.log,
/// con rotación simple cuando supera `maxBytes` (se mueve a detector.1.log,
/// sin acumular más de un archivo rotado).
final class DetectorLogWriter {

    static let shared = DetectorLogWriter()

    static var defaultURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Logs/NotarIA/detector.log")
    }

    private let url: URL
    private let maxBytes: UInt64
    private let queue = DispatchQueue(label: "aria.detectorlog")

    init(url: URL = DetectorLogWriter.defaultURL, maxBytes: UInt64 = 1_000_000) {
        self.url = url
        self.maxBytes = maxBytes
    }

    /// Espera a que termine cualquier escritura en curso — solo para tests
    /// (la cola es serial, así que un `sync` encolado detrás de los `append`
    /// pendientes garantiza que ya corrieron).
    func flush() {
        queue.sync {}
    }

    func append(_ line: String) {
        queue.async { [url, maxBytes] in
            Self.rotateIfNeeded(url: url, maxBytes: maxBytes)
            guard let data = (line + "\n").data(using: .utf8) else { return }
            if FileManager.default.fileExists(atPath: url.path) {
                guard let handle = try? FileHandle(forWritingTo: url) else { return }
                defer { try? handle.close() }
                handle.seekToEndOfFile()
                handle.write(data)
            } else {
                try? FileManager.default.createDirectory(
                    at: url.deletingLastPathComponent(),
                    withIntermediateDirectories: true
                )
                try? data.write(to: url)
            }
        }
    }

    private static func rotateIfNeeded(url: URL, maxBytes: UInt64) {
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: url.path),
              let size = attributes[.size] as? UInt64,
              size > maxBytes else { return }
        let rotated = url.deletingLastPathComponent()
            .appendingPathComponent(url.deletingPathExtension().lastPathComponent + ".1." + url.pathExtension)
        try? FileManager.default.removeItem(at: rotated)
        try? FileManager.default.moveItem(at: url, to: rotated)
    }
}
