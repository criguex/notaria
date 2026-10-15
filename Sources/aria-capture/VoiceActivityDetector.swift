import CryptoKit
import Foundation
import whisper

protocol VoiceActivityDetector {
    func voicedRegions(in samples: [Float], sampleRate: Double) -> [Range<Int>]
}

struct EnergyVAD: VoiceActivityDetector {
    var options: ChunkingOptions = .default

    func voicedRegions(in samples: [Float], sampleRate: Double) -> [Range<Int>] {
        ChunkedTranscriber.voicedRegions(in: samples, options: options, sampleRate: sampleRate)
    }
}

enum SileroModel {
    static let fileName = "ggml-silero-v5.1.2.bin"
    static let expectedSizeBytes: Int64 = 885_098
    static let expectedSHA256 = "29940d98d42b91fbd05ce489f3ecf7c72f0a42f027e4875919a28fb4c04ea2cf"

    static var remoteURL: URL {
        URL(string: "https://huggingface.co/ggml-org/whisper-vad/resolve/main/\(fileName)")!
    }

    static var url: URL {
        WhisperModelStore.modelsDirectory.appendingPathComponent(fileName)
    }

    static var isAvailable: Bool { isAvailable(at: url) }

    static func isAvailable(at modelURL: URL) -> Bool {
        FileManager.default.fileExists(atPath: modelURL.path)
    }

    @discardableResult
    static func ensureModel(destination: URL? = nil) async throws -> URL {
        let fm = FileManager.default
        let target = destination ?? url
        if fm.fileExists(atPath: target.path) {
            return target
        }
        try fm.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
        print("[vad] Modelo Silero no encontrado. Descargando \(fileName)…")
        let (tempURL, response) = try await URLSession.shared.download(from: remoteURL)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw WhisperError.downloadFailed("HTTP \((response as? HTTPURLResponse)?.statusCode ?? -1)")
        }

        let attributes = try fm.attributesOfItem(atPath: tempURL.path)
        let size = (attributes[.size] as? Int64) ?? -1
        guard size == expectedSizeBytes else {
            try? fm.removeItem(at: tempURL)
            throw WhisperError.downloadFailed("tamaño inesperado: \(size) bytes (esperado \(expectedSizeBytes))")
        }

        let sha = try sha256Hex(of: tempURL)
        guard sha == expectedSHA256 else {
            try? fm.removeItem(at: tempURL)
            throw WhisperError.downloadFailed("sha256 no coincide: \(sha) (esperado \(expectedSHA256))")
        }

        try? fm.removeItem(at: target)
        try fm.moveItem(at: tempURL, to: target)
        print("[vad] Descargado y verificado: \(target.path) (\(size) bytes, sha256 ok)")
        return target
    }

    private static func sha256Hex(of url: URL) throws -> String {
        let data = try Data(contentsOf: url)
        let digest = SHA256.hash(data: data)
        return digest.map { String(format: "%02x", $0) }.joined()
    }
}

final class SileroVAD: VoiceActivityDetector {
    private let context: OpaquePointer
    private let options: ChunkingOptions

    init?(modelPath: String, options: ChunkingOptions = .default) {
        guard FileManager.default.fileExists(atPath: modelPath) else { return nil }

        var params = whisper_vad_default_context_params()
        params.n_threads = Int32(max(1, min(4, ProcessInfo.processInfo.activeProcessorCount)))
        params.use_gpu = false

        guard let context = whisper_vad_init_from_file_with_params(modelPath, params) else {
            return nil
        }
        self.context = context
        self.options = options
    }

    deinit {
        whisper_vad_free(context)
    }

    func voicedRegions(in samples: [Float], sampleRate: Double) -> [Range<Int>] {
        guard sampleRate == 16_000, !samples.isEmpty else {
            return EnergyVAD(options: options).voicedRegions(in: samples, sampleRate: sampleRate)
        }

        var vadParams = whisper_vad_default_params()
        vadParams.threshold = 0.5
        vadParams.min_speech_duration_ms = Int32(options.minVoicedSeconds * 1000)
        vadParams.min_silence_duration_ms = Int32(options.vadMergeGapSeconds * 1000)
        vadParams.speech_pad_ms = Int32(options.vadPadSeconds * 1000)

        let segmentsPtr = samples.withUnsafeBufferPointer { buffer in
            whisper_vad_segments_from_samples(context, vadParams, buffer.baseAddress, Int32(buffer.count))
        }
        guard let segmentsPtr else {
            return EnergyVAD(options: options).voicedRegions(in: samples, sampleRate: sampleRate)
        }
        defer { whisper_vad_free_segments(segmentsPtr) }

        let count = Int(whisper_vad_segments_n_segments(segmentsPtr))
        guard count > 0 else { return [] }

        var regions: [Range<Int>] = []
        regions.reserveCapacity(count)
        for index in 0..<count {
            let t0 = Double(whisper_vad_segments_get_segment_t0(segmentsPtr, Int32(index))) / 100.0
            let t1 = Double(whisper_vad_segments_get_segment_t1(segmentsPtr, Int32(index))) / 100.0
            let start = max(0, Int(t0 * sampleRate))
            let end = min(samples.count, Int(t1 * sampleRate))
            guard end > start else { continue }
            regions.append(start..<end)
        }
        return regions
    }
}

enum VADFactory {
    static func backendName(modelAvailable: Bool = SileroModel.isAvailable) -> String {
        modelAvailable ? "silero" : "energy"
    }

    static func preferred(options: ChunkingOptions = .default, modelURL: URL = SileroModel.url) -> VoiceActivityDetector {
        guard SileroModel.isAvailable(at: modelURL),
              let silero = SileroVAD(modelPath: modelURL.path, options: options) else {
            return EnergyVAD(options: options)
        }
        return silero
    }
}
