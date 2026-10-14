import AVFoundation
import Foundation

final class GrowableStereoRecorder {

    private let sampleRate: Double = 16_000
    private let maxFrames: Int
    private let lock = NSLock()
    private var micTrack: [Float] = []
    private var systemTrack: [Float] = []
    private var epochSeconds: TimeInterval?
    private var lastSystemAudioAt: Date?
    private var paused = false

    init(maxSeconds: Int = 7_200) {
        maxFrames = Int(Double(maxSeconds) * sampleRate)
    }

    func begin(epochSeconds: TimeInterval) {
        lock.lock()
        defer { lock.unlock() }
        self.epochSeconds = epochSeconds
        micTrack.removeAll(keepingCapacity: true)
        systemTrack.removeAll(keepingCapacity: true)
    }

    var recordedSeconds: Double {
        lock.lock()
        defer { lock.unlock() }
        return Double(max(micTrack.count, systemTrack.count)) / sampleRate
    }

    var isPaused: Bool {
        lock.lock()
        defer { lock.unlock() }
        return paused
    }

    func setPaused(_ value: Bool) {
        lock.lock()
        paused = value
        if !value { lastSystemAudioAt = Date() }
        lock.unlock()
    }

    func resetSilenceClock() {
        lock.lock()
        lastSystemAudioAt = Date()
        lock.unlock()
    }

    func addMic(_ buffer: AVAudioPCMBuffer, atHostSeconds seconds: TimeInterval) {
        guard !isPaused else { return }
        place(buffer, at: seconds, into: &micTrack)
    }

    func addSystem(_ buffer: AVAudioPCMBuffer, atHostSeconds seconds: TimeInterval) {
        guard !isPaused else { return }
        if let data = buffer.floatChannelData?[0] {
            let samples = UnsafeBufferPointer(start: data, count: Int(buffer.frameLength))
            if samples.contains(where: { abs($0) > 0.01 }) {
                lock.lock()
                lastSystemAudioAt = Date()
                lock.unlock()
            }
        }
        place(buffer, at: seconds, into: &systemTrack)
    }

    var secondsSinceSystemAudio: TimeInterval? {
        lock.lock()
        defer { lock.unlock() }
        guard let lastSystemAudioAt else { return nil }
        return Date().timeIntervalSince(lastSystemAudioAt)
    }

    func newSamples(micCursor: Int, systemCursor: Int) -> (mic: [Float], micCursor: Int, system: [Float], systemCursor: Int) {
        lock.lock()
        defer { lock.unlock() }
        let mic = micCursor < micTrack.count ? Array(micTrack[micCursor...]) : []
        let system = systemCursor < systemTrack.count ? Array(systemTrack[systemCursor...]) : []
        return (mic, micTrack.count, system, systemTrack.count)
    }

    private func place(_ buffer: AVAudioPCMBuffer, at seconds: TimeInterval, into track: inout [Float]) {
        guard let data = buffer.floatChannelData?[0] else { return }
        lock.lock()
        defer { lock.unlock() }
        guard let epoch = epochSeconds else { return }
        let start = Int(((seconds - epoch) * sampleRate).rounded())
        let frameCount = Int(buffer.frameLength)
        let end = min(start + frameCount, maxFrames)
        guard end > 0, start < maxFrames else { return }
        if end > track.count {
            track.append(contentsOf: repeatElement(0, count: end - track.count))
        }
        for index in max(start, 0)..<end {
            track[index] = data[index - start]
        }
    }

    func write(to url: URL) throws -> (micPeak: Float, systemPeak: Float, seconds: Double) {
        lock.lock()
        defer { lock.unlock() }

        let frames = max(micTrack.count, systemTrack.count)
        guard frames > 0 else {
            throw StereoWavRecorderError.bufferAllocation
        }
        if micTrack.count < frames { micTrack.append(contentsOf: repeatElement(0, count: frames - micTrack.count)) }
        if systemTrack.count < frames { systemTrack.append(contentsOf: repeatElement(0, count: frames - systemTrack.count)) }

        let settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVSampleRateKey: sampleRate,
            AVNumberOfChannelsKey: 2,
            AVLinearPCMBitDepthKey: 16,
            AVLinearPCMIsFloatKey: false,
            AVLinearPCMIsBigEndianKey: false,
            AVLinearPCMIsNonInterleaved: false
        ]
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let file = try AVAudioFile(forWriting: url, settings: settings)

        guard let format = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: sampleRate, channels: 2, interleaved: false),
              let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(frames)),
              let channels = buffer.floatChannelData else {
            throw StereoWavRecorderError.bufferAllocation
        }
        buffer.frameLength = AVAudioFrameCount(frames)
        micTrack.withUnsafeBufferPointer { channels[0].update(from: $0.baseAddress!, count: frames) }
        systemTrack.withUnsafeBufferPointer { channels[1].update(from: $0.baseAddress!, count: frames) }
        try file.write(from: buffer)

        let micPeak = micTrack.reduce(Float(0)) { max($0, abs($1)) }
        let systemPeak = systemTrack.reduce(Float(0)) { max($0, abs($1)) }
        return (micPeak, systemPeak, Double(frames) / sampleRate)
    }
}
