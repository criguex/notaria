import Foundation

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

    static var url: URL {
        WhisperModelStore.modelsDirectory.appendingPathComponent(fileName)
    }

    static var isAvailable: Bool {
        FileManager.default.fileExists(atPath: url.path)
    }
}

// Ver vault aria-obsidian, ADR-06: la inferencia real (whisper.cpp con VAD nativo
// vs ONNX Runtime) queda pendiente de validar en máquina con red/audio real.
// SileroVAD ya resuelve descubrimiento del modelo y cae a EnergyVAD mientras tanto,
// así ChunkedTranscriber no cambia el día que se aterrice el runtime.
struct SileroVAD: VoiceActivityDetector {
    var options: ChunkingOptions = .default
    private var fallback: EnergyVAD { EnergyVAD(options: options) }

    func voicedRegions(in samples: [Float], sampleRate: Double) -> [Range<Int>] {
        fallback.voicedRegions(in: samples, sampleRate: sampleRate)
    }
}

enum VADFactory {
    static func backendName(modelAvailable: Bool = SileroModel.isAvailable) -> String {
        modelAvailable ? "silero" : "energy"
    }

    static func preferred(options: ChunkingOptions = .default) -> VoiceActivityDetector {
        SileroModel.isAvailable ? SileroVAD(options: options) : EnergyVAD(options: options)
    }
}
