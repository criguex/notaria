import AVFoundation
import Foundation

enum StereoWavRecorderError: LocalizedError {
    case bufferAllocation

    var errorDescription: String? {
        switch self {
        case .bufferAllocation:
            return "No se pudo reservar el buffer estéreo para escribir el WAV."
        }
    }
}

final class StereoWavRecorder {

    private let sampleRate: Double
    private let capacity: Int
    private let lock = NSLock()
    private var micTrack: [Float]
    private var systemTrack: [Float]
    private var epochSeconds: TimeInterval?

    init(seconds: Int, sampleRate: Double = 16_000) {
        self.sampleRate = sampleRate
        self.capacity = Int(Double(seconds) * sampleRate)
        micTrack = [Float](repeating: 0, count: capacity)
        systemTrack = [Float](repeating: 0, count: capacity)
    }

    func begin(epochSeconds: TimeInterval) {
        lock.lock()
        defer { lock.unlock() }
        self.epochSeconds = epochSeconds
    }

    func addMic(_ buffer: AVAudioPCMBuffer, atHostSeconds seconds: TimeInterval) {
        place(buffer, at: seconds, into: &micTrack)
    }

    func addSystem(_ buffer: AVAudioPCMBuffer, atHostSeconds seconds: TimeInterval) {
        place(buffer, at: seconds, into: &systemTrack)
    }

    private func place(_ buffer: AVAudioPCMBuffer, at seconds: TimeInterval, into track: inout [Float]) {
        guard let data = buffer.floatChannelData?[0] else { return }
        lock.lock()
        defer { lock.unlock() }
        guard let epoch = epochSeconds else { return }
        let start = Int(((seconds - epoch) * sampleRate).rounded())
        let frameCount = Int(buffer.frameLength)
        let from = max(start, 0)
        let to = min(start + frameCount, capacity)
        guard to > from else { return }
        for index in from..<to {
            track[index] = data[index - start]
        }
    }

    func write(to url: URL) throws -> (micPeak: Float, systemPeak: Float, seconds: Double) {
        lock.lock()
        defer { lock.unlock() }

        let settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVSampleRateKey: sampleRate,
            AVNumberOfChannelsKey: 2,
            AVLinearPCMBitDepthKey: 16,
            AVLinearPCMIsFloatKey: false,
            AVLinearPCMIsBigEndianKey: false,
            AVLinearPCMIsNonInterleaved: false
        ]
        let file = try AVAudioFile(forWriting: url, settings: settings)

        guard let format = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: sampleRate, channels: 2, interleaved: false),
              let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(capacity)),
              let channels = buffer.floatChannelData else {
            throw StereoWavRecorderError.bufferAllocation
        }
        buffer.frameLength = AVAudioFrameCount(capacity)
        micTrack.withUnsafeBufferPointer { channels[0].update(from: $0.baseAddress!, count: capacity) }
        systemTrack.withUnsafeBufferPointer { channels[1].update(from: $0.baseAddress!, count: capacity) }
        try file.write(from: buffer)

        let micPeak = micTrack.reduce(Float(0)) { max($0, abs($1)) }
        let systemPeak = systemTrack.reduce(Float(0)) { max($0, abs($1)) }
        return (micPeak, systemPeak, Double(capacity) / sampleRate)
    }
}
