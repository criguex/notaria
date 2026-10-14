import Foundation

final class LiveTranscriptionRunner {

    private let recorder: GrowableStereoRecorder
    private let feed: LiveTranscriptFeed
    private let intervalSeconds: Double
    private let windowSeconds: Double
    private let sampleRate: Double = 16_000

    private var timer: Timer?
    private var micCursor = 0
    private var systemCursor = 0
    private var transcriber: ChunkedTranscriber?
    private var isProcessing = false

    init(
        recorder: GrowableStereoRecorder,
        feed: LiveTranscriptFeed,
        intervalSeconds: Double = 15,
        windowSeconds: Double = 20
    ) {
        self.recorder = recorder
        self.feed = feed
        self.intervalSeconds = intervalSeconds
        self.windowSeconds = windowSeconds
    }

    func start() {
        stop()
        micCursor = 0
        systemCursor = 0
        feed.reset()
        scheduleTimer()
    }

    func pause() {
        timer?.invalidate()
        timer = nil
    }

    func resume() {
        guard timer == nil else { return }
        scheduleTimer()
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        isProcessing = false
    }

    private func scheduleTimer() {
        timer = Timer.scheduledTimer(withTimeInterval: intervalSeconds, repeats: true) { [weak self] _ in
            self?.tick()
        }
    }

    private func tick() {
        guard !isProcessing else { return }
        let window = recorder.newSamples(micCursor: micCursor, systemCursor: systemCursor)
        micCursor = window.micCursor
        systemCursor = window.systemCursor
        let maxWindowSamples = Int(windowSeconds * sampleRate)
        let micClip = Array(window.mic.suffix(maxWindowSamples))
        let systemClip = Array(window.system.suffix(maxWindowSamples))
        guard !micClip.isEmpty || !systemClip.isEmpty else { return }
        isProcessing = true
        Task {
            await self.process(micClip: micClip, systemClip: systemClip)
            await MainActor.run { self.isProcessing = false }
        }
    }

    private func process(micClip: [Float], systemClip: [Float]) async {
        guard let transcriber = await resolvedTranscriber() else { return }
        let language = AriaConfig.load().language
        if !micClip.isEmpty,
           let output = try? transcriber.transcribe(samples: micClip, language: language, speaker: LiveTranscriptFeed.youLabel) {
            feed.append(output.segments, speaker: LiveTranscriptFeed.youLabel)
        }
        if !systemClip.isEmpty,
           let output = try? transcriber.transcribe(samples: systemClip, language: language, speaker: LiveTranscriptFeed.themLabel) {
            feed.append(output.segments, speaker: LiveTranscriptFeed.themLabel)
        }
    }

    private func resolvedTranscriber() async -> ChunkedTranscriber? {
        if let transcriber { return transcriber }
        guard let modelURL = try? await WhisperModelStore.ensureModel(),
              let whisper = try? WhisperTranscriber(modelPath: modelURL.path) else { return nil }
        let chunked = ChunkedTranscriber(transcriber: whisper)
        transcriber = chunked
        return chunked
    }
}
