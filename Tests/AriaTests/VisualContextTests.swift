import AppKit
import CoreGraphics
import Vision
import XCTest
@testable import aria_capture

final class VisualContextTests: XCTestCase {

    // MARK: - Helpers (imágenes sintéticas dibujadas en código, nunca captura real)

    private static func makeSolidImage(gray: CGFloat, size: CGSize = CGSize(width: 320, height: 180)) -> CGImage {
        let width = Int(size.width)
        let height = Int(size.height)
        let colorSpace = CGColorSpaceCreateDeviceGray()
        let context = CGContext(
            data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
            space: colorSpace, bitmapInfo: CGImageAlphaInfo.none.rawValue
        )!
        context.setFillColor(gray: gray, alpha: 1)
        context.fill(CGRect(x: 0, y: 0, width: size.width, height: size.height))
        return context.makeImage()!
    }

    private static func makeTextImage(_ text: String, size: CGSize = CGSize(width: 600, height: 150), fontSize: CGFloat = 40) -> CGImage {
        let width = Int(size.width)
        let height = Int(size.height)
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let context = CGContext(
            data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
            space: colorSpace, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )!
        context.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: size.width, height: size.height))

        let nsContext = NSGraphicsContext(cgContext: context, flipped: false)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = nsContext
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.boldSystemFont(ofSize: fontSize),
            .foregroundColor: NSColor.black
        ]
        (text as NSString).draw(at: NSPoint(x: 20, y: size.height / 2 - fontSize / 2), withAttributes: attrs)
        NSGraphicsContext.restoreGraphicsState()

        return context.makeImage()!
    }

    // MARK: - LumaFingerprint

    func testFingerprintComputeUniformImage() {
        let width = 8, height = 8
        let pixels = [UInt8](repeating: 100, count: width * height)
        let fingerprint = LumaFingerprint.compute(grayscalePixels: pixels, width: width, height: height, columns: 2, rows: 2)
        XCTAssertEqual(fingerprint.samples, [100, 100, 100, 100])
    }

    func testFingerprintComputeDetectsRegionalDifference() {
        let width = 4, height = 4
        var pixels = [UInt8](repeating: 0, count: width * height)
        for y in 0..<height {
            for x in 2..<width {
                pixels[y * width + x] = 255
            }
        }
        let fingerprint = LumaFingerprint.compute(grayscalePixels: pixels, width: width, height: height, columns: 2, rows: 1)
        XCTAssertEqual(fingerprint.samples[0], 0)
        XCTAssertEqual(fingerprint.samples[1], 255)
    }

    func testFingerprintComputeHandlesDegenerateInputSafely() {
        let fingerprint = LumaFingerprint.compute(grayscalePixels: [], width: 0, height: 0, columns: 4, rows: 4)
        XCTAssertEqual(fingerprint.samples.count, 16)
        XCTAssertTrue(fingerprint.samples.allSatisfy { $0 == 0 })
    }

    // MARK: - VisualFingerprintDiff

    func testFingerprintDiffIdenticalIsUnchanged() {
        let fingerprint = LumaFingerprint(columns: 4, rows: 4, samples: Array(repeating: 100, count: 16))
        let diff = VisualFingerprintDiff.compare(fingerprint, fingerprint, changedRatioThreshold: 0.02)
        XCTAssertFalse(diff.changed)
        XCTAssertEqual(diff.changedSampleRatio, 0)
    }

    func testFingerprintDiffRespectsConfigurableThreshold() {
        let a = LumaFingerprint(columns: 4, rows: 4, samples: Array(repeating: 100, count: 16))
        var samples = a.samples
        samples[0] = 200 // 1 de 16 muestras cambia = 0.0625
        let b = LumaFingerprint(columns: 4, rows: 4, samples: samples)

        let diffLow = VisualFingerprintDiff.compare(a, b, changedRatioThreshold: 0.1)
        XCTAssertFalse(diffLow.changed)

        let diffHigh = VisualFingerprintDiff.compare(a, b, changedRatioThreshold: 0.05)
        XCTAssertTrue(diffHigh.changed)
    }

    func testFingerprintDiffMismatchedSizeAlwaysChanged() {
        let a = LumaFingerprint(columns: 2, rows: 2, samples: [1, 2, 3, 4])
        let b = LumaFingerprint(columns: 3, rows: 1, samples: [1, 2, 3])
        let diff = VisualFingerprintDiff.compare(a, b, changedRatioThreshold: 0.9)
        XCTAssertTrue(diff.changed)
    }

    // MARK: - VisualSamplingPolicy (piso de 30s)

    func testShouldCaptureFirstTimeAlwaysTrue() {
        XCTAssertTrue(VisualSamplingPolicy.shouldCapture(elapsedSinceLastCapture: nil, changed: false))
    }

    func testShouldCaptureWhenChangedRegardlessOfElapsed() {
        XCTAssertTrue(VisualSamplingPolicy.shouldCapture(elapsedSinceLastCapture: 1, changed: true))
    }

    func testShouldNotCaptureUnchangedBeforeFloor() {
        XCTAssertFalse(VisualSamplingPolicy.shouldCapture(elapsedSinceLastCapture: 10, changed: false, floorSeconds: 30))
    }

    func testShouldCaptureUnchangedAfterFloor() {
        XCTAssertTrue(VisualSamplingPolicy.shouldCapture(elapsedSinceLastCapture: 30, changed: false, floorSeconds: 30))
    }

    // MARK: - VisualAppExclusionPolicy

    func testDefaultExcludedAppsCoverRequiredCategories() {
        let defaults = VisualAppExclusionPolicy.defaultExcludedBundleIDs
        XCTAssertTrue(defaults.contains("com.apple.MobileSMS"))
        XCTAssertTrue(defaults.contains("com.apple.mail"))
        XCTAssertTrue(defaults.contains("net.whatsapp.WhatsApp"))
        XCTAssertTrue(defaults.contains("com.apple.keychainaccess"))
        XCTAssertTrue(defaults.contains { $0.lowercased().contains("1password") })
        XCTAssertTrue(defaults.contains { $0.lowercased().contains("bitwarden") })
    }

    func testIsExcludedCaseInsensitiveAndNilSafe() {
        let list = ["com.apple.mail"]
        XCTAssertTrue(VisualAppExclusionPolicy.isExcluded(bundleID: "COM.APPLE.MAIL", excludedList: list))
        XCTAssertFalse(VisualAppExclusionPolicy.isExcluded(bundleID: "com.apple.Safari", excludedList: list))
        XCTAssertFalse(VisualAppExclusionPolicy.isExcluded(bundleID: nil, excludedList: list))
    }

    func testParsedListTrimsAndDropsEmpty() {
        let parsed = VisualAppExclusionPolicy.parsedList(" com.a , , com.b ,com.c")
        XCTAssertEqual(parsed, ["com.a", "com.b", "com.c"])
    }

    // MARK: - VisualOCRQuality

    func testUsefulTextDiscardsEmptyOrTooShort() {
        XCTAssertNil(VisualOCRQuality.usefulText(from: []))
        XCTAssertNil(VisualOCRQuality.usefulText(from: ["", "  "]))
        XCTAssertNil(VisualOCRQuality.usefulText(from: ["Hi"]))
    }

    func testUsefulTextJoinsLinesAboveMinimum() {
        let text = VisualOCRQuality.usefulText(from: ["Sprint planning", "Q3 roadmap"])
        XCTAssertEqual(text, "Sprint planning\nQ3 roadmap")
    }

    // MARK: - VisualContextStorage (rutas, embeds, archivos)

    func testImageFileNameAndTimeLabelFormatting() {
        XCTAssertEqual(VisualContextStorage.imageFileName(index: 1), "01.jpg")
        XCTAssertEqual(VisualContextStorage.imageFileName(index: 12), "12.jpg")
        XCTAssertEqual(VisualContextStorage.timeLabel(elapsedSeconds: 65), "1:05")
        XCTAssertEqual(VisualContextStorage.timeLabel(elapsedSeconds: 0), "0:00")
    }

    func testCapturesDirectoryDerivesFromNoteStem() {
        let noteURL = URL(fileURLWithPath: "/vault/Reuniones/2026-10-14 - Standup.md")
        let (stem, dir) = VisualContextStorage.capturesDirectory(forNoteAt: noteURL)
        XCTAssertEqual(stem, "2026-10-14 - Standup")
        XCTAssertEqual(dir.path, "/vault/Reuniones/2026-10-14 - Standup/capturas")
    }

    func testEmbedLineAndSectionMarkdown() {
        let capture = VisualCaptureRecord(elapsedSeconds: 125, ocrText: "x", imageFileName: "01.jpg")
        let line = VisualContextStorage.embedLine(noteStem: "Standup", capture: capture)
        XCTAssertEqual(line, "![[Standup/capturas/01.jpg]] — 2:05")

        XCTAssertNil(VisualContextStorage.sectionMarkdown(noteStem: "Standup", captures: []))
        let section = VisualContextStorage.sectionMarkdown(noteStem: "Standup", captures: [capture])!
        XCTAssertTrue(section.contains("## Contexto visual"))
        XCTAssertTrue(section.contains(line))
    }

    func testWriteImagesAndAppendSectionOnDisk() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("aria-visual-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

        let noteURL = tempDir.appendingPathComponent("Standup.md")
        try "# Standup\n\nCuerpo.\n".write(to: noteURL, atomically: true, encoding: .utf8)

        let capturesDir = tempDir.appendingPathComponent("Standup").appendingPathComponent("capturas")
        let record = VisualCaptureRecord(elapsedSeconds: 10, ocrText: "hola", imageFileName: "01.jpg")

        try VisualContextStorage.writeImages([("01.jpg", "falso-jpeg".data(using: .utf8)!)], toDirectory: capturesDir)
        try VisualContextStorage.appendSection(noteStem: "Standup", captures: [record], toNoteAt: noteURL)

        XCTAssertTrue(FileManager.default.fileExists(atPath: capturesDir.appendingPathComponent("01.jpg").path))
        let content = try String(contentsOf: noteURL, encoding: .utf8)
        XCTAssertTrue(content.contains("## Contexto visual"))
        XCTAssertTrue(content.contains("Standup/capturas/01.jpg"))
    }

    func testWriteImagesNoOpWhenEmpty() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("aria-visual-empty-\(UUID().uuidString)", isDirectory: true)
        try VisualContextStorage.writeImages([], toDirectory: tempDir)
        XCTAssertFalse(FileManager.default.fileExists(atPath: tempDir.path))
    }

    // MARK: - VisualContextPrompt

    func testSummaryBlockNilWhenEmpty() {
        XCTAssertNil(VisualContextPrompt.summaryBlock(captures: []))
    }

    func testSummaryBlockOrdersByTimeAndTruncatesPerCapture() {
        let captures = [
            VisualCaptureRecord(elapsedSeconds: 120, ocrText: "segunda diapositiva", imageFileName: "02.jpg"),
            VisualCaptureRecord(elapsedSeconds: 10, ocrText: String(repeating: "x", count: 500), imageFileName: "01.jpg")
        ]
        let block = VisualContextPrompt.summaryBlock(captures: captures, maxCharsPerCapture: 20)!
        let lines = block.split(separator: "\n")
        XCTAssertEqual(lines.count, 2)
        XCTAssertTrue(lines[0].hasPrefix("[0:10]"))
        XCTAssertTrue(lines[1].hasPrefix("[2:00]"))
    }

    func testSummaryBlockRespectsTotalBudget() {
        let captures = (0..<100).map {
            VisualCaptureRecord(elapsedSeconds: Double($0), ocrText: String(repeating: "a", count: 100), imageFileName: "x")
        }
        let block = VisualContextPrompt.summaryBlock(captures: captures, maxCharsPerCapture: 100, maxTotalChars: 500)!
        XCTAssertLessThanOrEqual(block.count, 700)
        XCTAssertLessThan(block.split(separator: "\n").count, 100)
    }

    // MARK: - AriaConfig

    func testVisualContextConfigDefaults() {
        let config = AriaConfig()
        XCTAssertFalse(config.visualContextEnabled)
        XCTAssertTrue(config.excludedVisualContextBundleIDs.contains("com.apple.mail"))
        XCTAssertEqual(config.visualContextChangeThreshold, 0.02, accuracy: 0.0001)
    }

    func testVisualContextConfigSetAndValidate() throws {
        var config = AriaConfig()
        try config.set(key: "visualContextEnabled", value: "true")
        XCTAssertTrue(config.visualContextEnabled)

        try config.set(key: "visualContextExcludedApps", value: "com.foo.bar, com.baz.qux")
        XCTAssertEqual(config.excludedVisualContextBundleIDs, ["com.foo.bar", "com.baz.qux"])

        try config.set(key: "visualContextChangeThreshold", value: "0.1")
        XCTAssertEqual(config.visualContextChangeThreshold, 0.1, accuracy: 0.0001)

        XCTAssertThrowsError(try config.set(key: "visualContextChangeThreshold", value: "0"))
        XCTAssertThrowsError(try config.set(key: "visualContextChangeThreshold", value: "1.5"))
        XCTAssertThrowsError(try config.set(key: "visualContextEnabled", value: "quizás"))
    }

    // MARK: - MeetingEnhancer: inyección del contexto visual

    func testComposeUserMessageIncludesVisualContextWhenPresent() {
        let withContext = MeetingEnhancer.composeUserMessage(
            transcript: "[00:00] Yo: hola", notes: "", date: Date(), durationSeconds: 60,
            visualContext: "[1:00] Diapositiva: Roadmap Q3"
        )
        XCTAssertTrue(withContext.contains("## Contexto visual (OCR local, por hora)"))
        XCTAssertTrue(withContext.contains("Roadmap Q3"))

        let withoutContext = MeetingEnhancer.composeUserMessage(
            transcript: "[00:00] Yo: hola", notes: "", date: Date(), durationSeconds: 60
        )
        XCTAssertFalse(withoutContext.contains("Contexto visual"))
    }

    // MARK: - MeetingStore: tabla visual_captures

    func testMeetingStoreVisualCapturesRoundtripEncryptionAndDeletion() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("aria-visual-db-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let dbURL = tempDir.appendingPathComponent("test.db")
        let store = try MeetingStore(databaseURL: dbURL)
        let meetingID = try store.saveMeeting(
            date: Date(), title: "Reunión con contexto visual", durationSeconds: 300,
            notePath: "/tmp/visual.md", wavPath: nil, segments: [], quickNotes: []
        )

        try store.insertVisualCaptures([
            (elapsedSeconds: 10, ocrText: "Diapositiva 1: metas confidenciales", imagePath: "/tmp/visual/capturas/01.jpg"),
            (elapsedSeconds: 70, ocrText: "Diapositiva 2: riesgos", imagePath: "/tmp/visual/capturas/02.jpg")
        ], meetingID: meetingID)

        let captures = try store.visualCaptures(meetingID: meetingID)
        XCTAssertEqual(captures.count, 2)
        XCTAssertEqual(captures[0].ocrText, "Diapositiva 1: metas confidenciales")
        XCTAssertEqual(captures[0].elapsedSeconds, 10, accuracy: 0.001)
        XCTAssertEqual(captures[1].imagePath, "/tmp/visual/capturas/02.jpg")

        let rawDB = try Data(contentsOf: dbURL)
        XCTAssertFalse(String(decoding: rawDB, as: UTF8.self).contains("metas confidenciales"))

        let deletedPaths = try store.deleteVisualCaptures(meetingID: meetingID)
        XCTAssertEqual(Set(deletedPaths), Set(["/tmp/visual/capturas/01.jpg", "/tmp/visual/capturas/02.jpg"]))
        XCTAssertEqual(try store.visualCaptures(meetingID: meetingID).count, 0)
    }

    func testInsertVisualCapturesNoOpWhenEmpty() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("aria-visual-db-empty-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let store = try MeetingStore(databaseURL: tempDir.appendingPathComponent("test.db"))
        let meetingID = try store.saveMeeting(
            date: Date(), title: "Sin contexto visual", durationSeconds: 60,
            notePath: "/tmp/sin.md", wavPath: nil, segments: [], quickNotes: []
        )
        try store.insertVisualCaptures([], meetingID: meetingID)
        XCTAssertEqual(try store.visualCaptures(meetingID: meetingID).count, 0)
    }

    // MARK: - OCR real sobre imágenes sintéticas (Vision, sin captura de pantalla)

    func testVisualContextOCRRecognizesDrawnText() throws {
        let image = Self.makeTextImage("HELLO WORLD")
        let lines = try VisualContextOCR.recognizedLines(in: image, languages: ["en-US"])
        let joined = lines.joined(separator: " ").uppercased()
        XCTAssertTrue(joined.contains("HELLO"), "OCR no reconoció 'HELLO' en: \(lines)")
    }

    func testVisualContextOCRBlankImageYieldsNoUsefulText() throws {
        let image = Self.makeSolidImage(gray: 1.0)
        let lines = try VisualContextOCR.recognizedLines(in: image)
        XCTAssertNil(VisualOCRQuality.usefulText(from: lines))
    }

    // MARK: - VisualContextCapture: utilidades de imagen (sobre imágenes sintéticas)

    func testGrayscalePixelsMatchesImageDimensions() {
        let image = Self.makeSolidImage(gray: 0.5, size: CGSize(width: 40, height: 20))
        let result = VisualContextCapture.grayscalePixels(from: image)
        XCTAssertEqual(result?.width, 40)
        XCTAssertEqual(result?.height, 20)
        XCTAssertEqual(result?.pixels.count, 800)
    }

    func testScaledDownscalesLargerImageAndKeepsSmallUnchanged() {
        let big = Self.makeSolidImage(gray: 0.3, size: CGSize(width: 3200, height: 1800))
        let scaled = VisualContextCapture.scaled(big, maxDimension: 1_600)
        XCTAssertEqual(scaled?.width, 1_600)
        XCTAssertEqual(scaled?.height, 900)

        let small = Self.makeSolidImage(gray: 0.3, size: CGSize(width: 100, height: 50))
        let unchanged = VisualContextCapture.scaled(small, maxDimension: 1_600)
        XCTAssertEqual(unchanged?.width, 100)
    }

    func testEndToEndFingerprintDiffOnSyntheticCGContextImages() {
        let blank = Self.makeTextImage("", size: CGSize(width: 400, height: 120))
        let withText = Self.makeTextImage("Diapositiva 2: riesgos", size: CGSize(width: 400, height: 120))

        guard let blankGray = VisualContextCapture.grayscalePixels(from: blank),
              let textGray = VisualContextCapture.grayscalePixels(from: withText) else {
            return XCTFail("no se pudo convertir a escala de grises")
        }

        let blankFingerprint = LumaFingerprint.compute(
            grayscalePixels: blankGray.pixels, width: blankGray.width, height: blankGray.height, columns: 16, rows: 9
        )
        let textFingerprint = LumaFingerprint.compute(
            grayscalePixels: textGray.pixels, width: textGray.width, height: textGray.height, columns: 16, rows: 9
        )

        let diffSameImage = VisualFingerprintDiff.compare(blankFingerprint, blankFingerprint, changedRatioThreshold: 0.02)
        XCTAssertFalse(diffSameImage.changed)

        let diffWithText = VisualFingerprintDiff.compare(blankFingerprint, textFingerprint, changedRatioThreshold: 0.02)
        XCTAssertTrue(diffWithText.changed, "dibujar texto debería disparar un cambio detectado por la huella")
    }

    func testJpegDataProducesNonEmptyBytes() {
        let image = Self.makeSolidImage(gray: 0.5, size: CGSize(width: 200, height: 100))
        let data = VisualContextCapture.jpegData(from: image, maxDimension: 1_600, quality: 0.6)
        XCTAssertNotNil(data)
        XCTAssertGreaterThan(data?.count ?? 0, 0)
    }
}
