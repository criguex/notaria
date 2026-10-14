import Foundation

enum RecordingPhase: Equatable {
    case recording
    case paused
    case awaitingStillThereConfirmation
    case stopped
}

struct RecordingSessionMachine: Equatable {

    static let defaultCountdownSeconds: TimeInterval = 30

    private(set) var phase: RecordingPhase = .recording
    private(set) var activeSeconds: TimeInterval = 0
    private(set) var pausedSeconds: TimeInterval = 0
    private(set) var countdownRemaining: TimeInterval = 0
    private let countdownSeconds: TimeInterval

    init(countdownSeconds: TimeInterval = RecordingSessionMachine.defaultCountdownSeconds) {
        self.countdownSeconds = countdownSeconds
    }

    var elapsedSeconds: TimeInterval { activeSeconds }
    var isRecording: Bool { phase == .recording }
    var isPaused: Bool { phase == .paused }
    var isAwaitingConfirmation: Bool { phase == .awaitingStillThereConfirmation }
    var isStopped: Bool { phase == .stopped }

    @discardableResult
    mutating func tick(_ delta: TimeInterval) -> RecordingPhase {
        guard delta > 0 else { return phase }
        switch phase {
        case .recording:
            activeSeconds += delta
        case .paused:
            pausedSeconds += delta
        case .awaitingStillThereConfirmation:
            countdownRemaining -= delta
            if countdownRemaining <= 0 {
                countdownRemaining = 0
                phase = .stopped
            }
        case .stopped:
            break
        }
        return phase
    }

    @discardableResult
    mutating func pause() -> Bool {
        guard phase == .recording else { return false }
        phase = .paused
        return true
    }

    @discardableResult
    mutating func resume() -> Bool {
        guard phase == .paused else { return false }
        phase = .recording
        return true
    }

    @discardableResult
    mutating func raiseStillThereWarning() -> Bool {
        guard phase == .recording else { return false }
        phase = .awaitingStillThereConfirmation
        countdownRemaining = countdownSeconds
        return true
    }

    @discardableResult
    mutating func keepRecording() -> Bool {
        guard phase == .awaitingStillThereConfirmation else { return false }
        phase = .recording
        countdownRemaining = 0
        return true
    }

    mutating func stop() {
        phase = .stopped
    }
}
