import AVFoundation
import XCTest
@testable import aria_capture

final class PauseAutoStopTests: XCTestCase {

    // MARK: - RecordingSessionMachine: pausa/reanuda

    func testPauseStopsActiveTimeAndResumeContinuesIt() {
        var machine = RecordingSessionMachine()
        machine.tick(5)
        XCTAssertTrue(machine.pause())
        XCTAssertEqual(machine.phase, .paused)
        machine.tick(10)
        XCTAssertEqual(machine.elapsedSeconds, 5, accuracy: 0.001)
        XCTAssertEqual(machine.pausedSeconds, 10, accuracy: 0.001)

        XCTAssertTrue(machine.resume())
        XCTAssertEqual(machine.phase, .recording)
        machine.tick(3)
        XCTAssertEqual(machine.elapsedSeconds, 8, accuracy: 0.001)
        XCTAssertEqual(machine.pausedSeconds, 10, accuracy: 0.001)
    }

    func testPauseAndResumeGuardsAreIdempotent() {
        var machine = RecordingSessionMachine()
        XCTAssertFalse(machine.resume())
        XCTAssertTrue(machine.pause())
        XCTAssertFalse(machine.pause())
        XCTAssertTrue(machine.resume())
        XCTAssertFalse(machine.resume())
    }

    func testDurationExcludesMultiplePauseIntervals() {
        var machine = RecordingSessionMachine()
        machine.tick(20)
        machine.pause()
        machine.tick(15)
        machine.resume()
        machine.tick(25)
        machine.pause()
        machine.tick(8)
        machine.resume()
        machine.tick(10)

        XCTAssertEqual(machine.elapsedSeconds, 55, accuracy: 0.001)
        XCTAssertEqual(machine.pausedSeconds, 23, accuracy: 0.001)
    }

    // MARK: - RecordingSessionMachine: aviso "¿sigues ahí?" + cuenta atrás

    func testRaiseStillThereWarningOnlyFromRecording() {
        var machine = RecordingSessionMachine(countdownSeconds: 30)
        XCTAssertTrue(machine.raiseStillThereWarning())
        XCTAssertEqual(machine.phase, .awaitingStillThereConfirmation)
        XCTAssertEqual(machine.countdownRemaining, 30, accuracy: 0.001)

        var pausedMachine = RecordingSessionMachine()
        pausedMachine.pause()
        XCTAssertFalse(pausedMachine.raiseStillThereWarning())

        var stoppedMachine = RecordingSessionMachine()
        stoppedMachine.stop()
        XCTAssertFalse(stoppedMachine.raiseStillThereWarning())
    }

    func testCountdownTicksDownAndExpiresIntoStopped() {
        var machine = RecordingSessionMachine(countdownSeconds: 30)
        machine.raiseStillThereWarning()

        XCTAssertEqual(machine.tick(1), .awaitingStillThereConfirmation)
        XCTAssertEqual(machine.countdownRemaining, 29, accuracy: 0.001)

        for _ in 0..<28 {
            _ = machine.tick(1)
        }
        XCTAssertEqual(machine.phase, .awaitingStillThereConfirmation)
        XCTAssertEqual(machine.countdownRemaining, 1, accuracy: 0.001)

        XCTAssertEqual(machine.tick(1), .stopped)
        XCTAssertEqual(machine.countdownRemaining, 0)
        XCTAssertTrue(machine.isStopped)
    }

    func testCountdownCanOvershootInOneTickAndStillStops() {
        var machine = RecordingSessionMachine(countdownSeconds: 30)
        machine.raiseStillThereWarning()
        XCTAssertEqual(machine.tick(45), .stopped)
        XCTAssertEqual(machine.countdownRemaining, 0)
    }

    func testKeepRecordingDuringWarningResumesAndResetsCountdown() {
        var machine = RecordingSessionMachine(countdownSeconds: 30)
        machine.raiseStillThereWarning()
        _ = machine.tick(12)
        XCTAssertTrue(machine.keepRecording())
        XCTAssertEqual(machine.phase, .recording)
        XCTAssertEqual(machine.countdownRemaining, 0)

        machine.tick(4)
        XCTAssertEqual(machine.elapsedSeconds, 4, accuracy: 0.001)
    }

    func testKeepRecordingIsNoopOutsideWarningPhase() {
        var machine = RecordingSessionMachine()
        XCTAssertFalse(machine.keepRecording())
        machine.pause()
        XCTAssertFalse(machine.keepRecording())
    }

    func testStopForcesStoppedFromAnyPhase() {
        var recording = RecordingSessionMachine()
        recording.stop()
        XCTAssertTrue(recording.isStopped)

        var paused = RecordingSessionMachine()
        paused.pause()
        paused.stop()
        XCTAssertTrue(paused.isStopped)

        var awaiting = RecordingSessionMachine()
        awaiting.raiseStillThereWarning()
        awaiting.stop()
        XCTAssertTrue(awaiting.isStopped)
    }

    func testTickAfterStoppedIsNoop() {
        var machine = RecordingSessionMachine()
        machine.stop()
        XCTAssertEqual(machine.tick(10), .stopped)
        XCTAssertEqual(machine.elapsedSeconds, 0)
        XCTAssertEqual(machine.pausedSeconds, 0)
    }

    // MARK: - GrowableStereoRecorder: pausa no escribe audio

    private func toneBuffer(seconds: Int = 1) -> AVAudioPCMBuffer {
        let frames = AVAudioFrameCount(16_000 * seconds)
        let format = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 16_000, channels: 1, interleaved: false)!
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames)!
        buffer.frameLength = frames
        for index in 0..<Int(frames) {
            buffer.floatChannelData![0][index] = 0.5
        }
        return buffer
    }

    func testPausedRecorderDropsMicAndSystemSamples() {
        let recorder = GrowableStereoRecorder(maxSeconds: 10)
        recorder.begin(epochSeconds: 100)
        recorder.addMic(toneBuffer(), atHostSeconds: 100)
        recorder.addSystem(toneBuffer(), atHostSeconds: 100)
        XCTAssertEqual(recorder.recordedSeconds, 1, accuracy: 0.001)

        recorder.setPaused(true)
        XCTAssertTrue(recorder.isPaused)
        recorder.addMic(toneBuffer(), atHostSeconds: 101)
        recorder.addSystem(toneBuffer(), atHostSeconds: 101)
        XCTAssertEqual(recorder.recordedSeconds, 1, accuracy: 0.001)

        recorder.setPaused(false)
        XCTAssertFalse(recorder.isPaused)
        recorder.addMic(toneBuffer(), atHostSeconds: 102)
        recorder.addSystem(toneBuffer(), atHostSeconds: 102)
        XCTAssertEqual(recorder.recordedSeconds, 3, accuracy: 0.001)
    }

    func testResumeResetsSilenceClockToAvoidImmediateWarning() {
        let recorder = GrowableStereoRecorder(maxSeconds: 10)
        recorder.begin(epochSeconds: 100)
        recorder.addSystem(toneBuffer(), atHostSeconds: 100)
        XCTAssertNotNil(recorder.secondsSinceSystemAudio)

        recorder.setPaused(true)
        Thread.sleep(forTimeInterval: 0.05)
        recorder.setPaused(false)
        XCTAssertLessThan(recorder.secondsSinceSystemAudio ?? 999, 0.5)
    }

    func testResetSilenceClockRefreshesWithoutTogglingPause() {
        let recorder = GrowableStereoRecorder(maxSeconds: 10)
        recorder.begin(epochSeconds: 100)
        recorder.addSystem(toneBuffer(), atHostSeconds: 100)
        Thread.sleep(forTimeInterval: 0.05)
        recorder.resetSilenceClock()
        XCTAssertLessThan(recorder.secondsSinceSystemAudio ?? 999, 0.5)
        XCTAssertFalse(recorder.isPaused)
    }
}
