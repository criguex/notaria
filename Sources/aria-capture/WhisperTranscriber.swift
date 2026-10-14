import Foundation
import whisper

enum WhisperError: LocalizedError {
    case downloadFailed(String)
    case initFailed
    case transcriptionFailed(Int32)

    var errorDescription: String? {
        switch self {
        case .downloadFailed(let detail):
            return "Falló la descarga del modelo: \(detail)"
        case .initFailed:
            return "whisper.cpp no pudo inicializar el contexto con el modelo."
        case .transcriptionFailed(let code):
            return "whisper_full falló con código \(code)."
        }
    }
}

struct TranscriptSegment {
    let start: TimeInterval
    let end: TimeInterval
    let text: String
    var speaker: String = ""
}

enum WhisperModelStore {

    static var modelName: String { AriaConfig.load().whisperModel }
    static var modelFileName: String { "ggml-\(modelName).bin" }
    static var remoteURL: URL {
        URL(string: "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/\(modelFileName)")!
    }

    static var modelsDirectory: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Aria/models", isDirectory: true)
    }

    static var modelURL: URL {
        modelsDirectory.appendingPathComponent(modelFileName)
    }

    static func ensureModel() async throws -> URL {
        let fm = FileManager.default
        if fm.fileExists(atPath: modelURL.path) {
            return modelURL
        }
        try fm.createDirectory(at: modelsDirectory, withIntermediateDirectories: true)
        print("[whisper] Modelo \(modelName) no encontrado. Descargando \(modelFileName)…")
        let (tempURL, response) = try await URLSession.shared.download(from: remoteURL)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw WhisperError.downloadFailed("HTTP \((response as? HTTPURLResponse)?.statusCode ?? -1)")
        }
        try? fm.removeItem(at: modelURL)
        try fm.moveItem(at: tempURL, to: modelURL)
        let attributes = try? fm.attributesOfItem(atPath: modelURL.path)
        let sizeMB = ((attributes?[.size] as? Int64) ?? 0) >> 20
        print("[whisper] Descargado: \(modelURL.path) (\(sizeMB) MB)")
        return modelURL
    }
}

final class WhisperTranscriber {

    private let context: OpaquePointer

    init(modelPath: String) throws {
        var params = whisper_context_default_params()
        params.use_gpu = true
        guard let context = whisper_init_from_file_with_params(modelPath, params) else {
            throw WhisperError.initFailed
        }
        self.context = context
    }

    deinit {
        whisper_free(context)
    }

    func transcribe(samples: [Float], language: String = "es") throws -> [TranscriptSegment] {
        var params = whisper_full_default_params(WHISPER_SAMPLING_GREEDY)
        params.print_realtime = false
        params.print_progress = false
        params.print_timestamps = false
        params.print_special = false
        params.translate = false
        params.no_context = true
        params.suppress_blank = true
        params.suppress_non_speech_tokens = true
        params.n_threads = Int32(max(2, min(8, ProcessInfo.processInfo.activeProcessorCount - 2)))

        let padded = samples + [Float](repeating: 0, count: 16_000)
        let status = language.withCString { lang -> Int32 in
            params.language = lang
            return padded.withUnsafeBufferPointer { buffer in
                whisper_full(context, params, buffer.baseAddress, Int32(buffer.count))
            }
        }
        guard status == 0 else {
            throw WhisperError.transcriptionFailed(status)
        }

        return (0..<whisper_full_n_segments(context)).map { index in
            TranscriptSegment(
                start: Double(whisper_full_get_segment_t0(context, index)) / 100.0,
                end: Double(whisper_full_get_segment_t1(context, index)) / 100.0,
                text: String(cString: whisper_full_get_segment_text(context, index))
                    .trimmingCharacters(in: .whitespaces)
            )
        }
    }

    static var systemInfo: String {
        String(cString: whisper_print_system_info())
    }
}
