import AppKit
import CoreGraphics
import Foundation
import ScreenCaptureKit
import Vision

enum VisualContextOCR {
    static func recognizedLines(in image: CGImage, languages: [String] = ["es-ES", "en-US"]) throws -> [String] {
        let handler = VNImageRequestHandler(cgImage: image, options: [:])
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = true
        request.recognitionLanguages = languages
        try handler.perform([request])
        let observations = request.results ?? []
        return observations.compactMap { $0.topCandidates(1).first?.string }
    }
}

struct PendingVisualCapture {
    let elapsedSeconds: TimeInterval
    let ocrText: String
    let jpegData: Data
}

@MainActor
final class VisualContextCapture {

    private(set) var pendingCaptures: [PendingVisualCapture] = []

    private let pollInterval: TimeInterval
    private let excludedBundleIDs: [String]
    private let changedRatioThreshold: Double
    private let gridColumns = 16
    private let gridRows = 9

    private var pollTimer: Timer?
    private var lastFingerprint: LumaFingerprint?
    private var lastCaptureAt: Date?
    private var sessionStart = Date()
    private var paused = false
    private var ticking = false

    init(excludedBundleIDs: [String], changedRatioThreshold: Double, pollInterval: TimeInterval = 5) {
        self.excludedBundleIDs = excludedBundleIDs
        self.changedRatioThreshold = changedRatioThreshold
        self.pollInterval = pollInterval
    }

    func start(sessionStart: Date) {
        self.sessionStart = sessionStart
        pendingCaptures = []
        lastFingerprint = nil
        lastCaptureAt = nil
        paused = false
        pollTimer?.invalidate()
        pollTimer = Timer.scheduledTimer(withTimeInterval: pollInterval, repeats: true) { [weak self] _ in
            guard let self else { return }
            Task { @MainActor [weak self] in
                await self?.tick()
            }
        }
    }

    func stop() {
        pollTimer?.invalidate()
        pollTimer = nil
    }

    func setPaused(_ value: Bool) {
        paused = value
    }

    private func tick() async {
        guard !paused, !ticking else { return }
        guard !isFrontmostAppExcluded() else { return }
        ticking = true
        defer { ticking = false }

        guard let image = try? await captureScreen(),
              let grayscale = Self.grayscalePixels(from: image) else { return }

        let fingerprint = LumaFingerprint.compute(
            grayscalePixels: grayscale.pixels,
            width: grayscale.width,
            height: grayscale.height,
            columns: gridColumns,
            rows: gridRows
        )

        let changed: Bool
        if let lastFingerprint {
            changed = VisualFingerprintDiff.compare(
                lastFingerprint, fingerprint, changedRatioThreshold: changedRatioThreshold
            ).changed
        } else {
            changed = true
        }
        let elapsedSinceLast = lastCaptureAt.map { Date().timeIntervalSince($0) }
        lastFingerprint = fingerprint

        guard VisualSamplingPolicy.shouldCapture(elapsedSinceLastCapture: elapsedSinceLast, changed: changed) else {
            return
        }
        lastCaptureAt = Date()

        guard let lines = try? VisualContextOCR.recognizedLines(in: image),
              let usefulText = VisualOCRQuality.usefulText(from: lines) else { return }
        guard let jpeg = Self.jpegData(from: image, maxDimension: 1_600, quality: 0.6) else { return }

        pendingCaptures.append(PendingVisualCapture(
            elapsedSeconds: Date().timeIntervalSince(sessionStart),
            ocrText: usefulText,
            jpegData: jpeg
        ))
    }

    private func isFrontmostAppExcluded() -> Bool {
        let bundleID = NSWorkspace.shared.frontmostApplication?.bundleIdentifier
        return VisualAppExclusionPolicy.isExcluded(bundleID: bundleID, excludedList: excludedBundleIDs)
    }

    private func captureScreen() async throws -> CGImage {
        let content = try await SCShareableContent.current
        guard let display = content.displays.first else {
            throw SystemAudioCaptureError.noDisplay
        }
        let filter = SCContentFilter(display: display, excludingApplications: [], exceptingWindows: [])
        let configuration = SCStreamConfiguration()
        configuration.width = display.width
        configuration.height = display.height
        configuration.showsCursor = false
        return try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: configuration)
    }

    nonisolated static func grayscalePixels(from image: CGImage) -> (pixels: [UInt8], width: Int, height: Int)? {
        let width = image.width
        let height = image.height
        guard width > 0, height > 0 else { return nil }
        var pixels = [UInt8](repeating: 0, count: width * height)
        let colorSpace = CGColorSpaceCreateDeviceGray()
        guard let context = CGContext(
            data: &pixels,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.none.rawValue
        ) else { return nil }
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        return (pixels, width, height)
    }

    nonisolated static func scaled(_ image: CGImage, maxDimension: Int) -> CGImage? {
        let width = image.width
        let height = image.height
        let longest = max(width, height)
        guard longest > maxDimension else { return image }
        let scale = Double(maxDimension) / Double(longest)
        let newWidth = max(Int(Double(width) * scale), 1)
        let newHeight = max(Int(Double(height) * scale), 1)
        guard let colorSpace = image.colorSpace,
              let context = CGContext(
                data: nil,
                width: newWidth,
                height: newHeight,
                bitsPerComponent: image.bitsPerComponent,
                bytesPerRow: 0,
                space: colorSpace,
                bitmapInfo: image.bitmapInfo.rawValue
              ) else { return nil }
        context.interpolationQuality = .high
        context.draw(image, in: CGRect(x: 0, y: 0, width: newWidth, height: newHeight))
        return context.makeImage()
    }

    nonisolated static func jpegData(from image: CGImage, maxDimension: Int, quality: CGFloat) -> Data? {
        let target = scaled(image, maxDimension: maxDimension) ?? image
        let bitmap = NSBitmapImageRep(cgImage: target)
        return bitmap.representation(using: .jpeg, properties: [.compressionFactor: quality])
    }
}
