import AVFoundation
import Darwin
import Foundation

final class CaptureStats {
    private let lock = NSLock()
    private var buffers = 0
    private var frames: AVAudioFramePosition = 0
    private var format: AVAudioFormat?
    private var peak: Float = 0

    func add(_ buffer: AVAudioPCMBuffer) {
        lock.lock()
        defer { lock.unlock() }
        buffers += 1
        frames += AVAudioFramePosition(buffer.frameLength)
        if format == nil { format = buffer.format }
        if let channels = buffer.floatChannelData {
            for channel in 0..<Int(buffer.format.channelCount) {
                let samples = UnsafeBufferPointer(start: channels[channel], count: Int(buffer.frameLength))
                for sample in samples where abs(sample) > peak {
                    peak = abs(sample)
                }
            }
        }
    }

    func snapshot() -> (buffers: Int, frames: AVAudioFramePosition, format: AVAudioFormat?, peak: Float) {
        lock.lock()
        defer { lock.unlock() }
        return (buffers, frames, format, peak)
    }
}

func report(_ stats: CaptureStats, source: String) -> Bool {
    let result = stats.snapshot()
    print("Buffers recibidos: \(result.buffers)")
    print("Frames totales: \(result.frames)")
    if let format = result.format {
        print("Formato real: \(Int(format.sampleRate)) Hz · \(format.channelCount) canal(es) · \(format.commonFormat == .pcmFormatFloat32 ? "float32" : "\(format.commonFormat)")")
        print(String(format: "Audio capturado: %.1f s · pico: %.4f", Double(result.frames) / format.sampleRate, result.peak))
    }
    guard result.buffers > 0 else {
        print("[fallo] No llegaron buffers de \(source).")
        return false
    }
    print("[ok] \(source) entrega AVAudioPCMBuffer.")
    return true
}

struct WavTranscription {
    let segments: [TranscriptSegment]
    let durationSeconds: Double
    let speakers: [String]
}

func transcribeWav(path: String) async throws -> WavTranscription {
    guard FileManager.default.fileExists(atPath: path) else {
        throw NSError(domain: "aria", code: 4, userInfo: [
            NSLocalizedDescriptionKey: "No existe el archivo: \(path)"
        ])
    }
    let file: AVAudioFile
    do {
        file = try AVAudioFile(forReading: URL(fileURLWithPath: path))
    } catch {
        throw NSError(domain: "aria", code: 5, userInfo: [
            NSLocalizedDescriptionKey: "No se pudo leer \(path) como audio (¿es un wav válido?)."
        ])
    }
    let format = file.processingFormat
    guard format.sampleRate == 16_000 else {
        throw NSError(domain: "aria", code: 1, userInfo: [
            NSLocalizedDescriptionKey: "El wav debe estar a 16 kHz (este es \(Int(format.sampleRate)) Hz)."
        ])
    }
    guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(file.length)) else {
        throw NSError(domain: "aria", code: 2, userInfo: [
            NSLocalizedDescriptionKey: "No se pudo reservar el buffer de lectura."
        ])
    }
    try file.read(into: buffer)
    guard let channels = buffer.floatChannelData else {
        throw NSError(domain: "aria", code: 3, userInfo: [
            NSLocalizedDescriptionKey: "El wav no expone datos float por canal."
        ])
    }
    let frameCount = Int(buffer.frameLength)
    let speakers = format.channelCount == 2 ? ["Yo", "Otros"] : ["Yo"]

    let modelURL = try await WhisperModelStore.ensureModel()
    let transcriber = try WhisperTranscriber(modelPath: modelURL.path)
    let chunked = ChunkedTranscriber(transcriber: transcriber)
    print("[vad] backend: \(VADFactory.backendName())")
    let language = AriaConfig.load().language
    if language != "es" {
        print("[whisper] Idioma: \(language)")
    }

    var perChannel: [[TranscriptSegment]] = []
    for (index, speaker) in speakers.enumerated() {
        let samples = Array(UnsafeBufferPointer(start: channels[index], count: frameCount))
        let output = try chunked.transcribe(samples: samples, language: language, speaker: speaker)
        let stats = output.stats
        print(String(format: "[whisper] Canal %@: %.1f s de voz de %.1f s · %d ventana(s) · %d segmento(s)",
                     speaker, stats.voicedSeconds, stats.totalSeconds, stats.windows, output.segments.count))
        perChannel.append(output.segments)
    }
    return WavTranscription(
        segments: ChunkedTranscriber.merged(perChannel),
        durationSeconds: Double(frameCount) / format.sampleRate,
        speakers: speakers
    )
}

func isMenubarRunning() -> Bool {
    let task = Process()
    task.executableURL = URL(fileURLWithPath: "/usr/bin/pgrep")
    task.arguments = ["-f", "aria-capture menubar"]
    let pipe = Pipe()
    task.standardOutput = pipe
    task.standardError = FileHandle.nullDevice
    do {
        try task.run()
    } catch {
        return false
    }
    task.waitUntilExit()
    let output = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
    return !output.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
}

// Empaquetado como .app: la raíz de un bundle firmado solo puede tener Contents/,
// así que los recursos (icono, shader Metal) se copian ahí (ver scripts/package-app.sh)
// en vez de los *.bundle sueltos que SwiftPM busca junto a Bundle.main.bundleURL.
// whisper.cpp (ggml-metal.m) soporta esta variable para encontrar ggml-metal.metal.
if let resourceURL = Bundle.main.resourceURL {
    setenv("GGML_METAL_PATH_RESOURCES", resourceURL.path, 1)
}

let arguments = CommandLine.arguments.dropFirst()
let mode = arguments.first ?? "menubar"

if mode != "mcp", mode != "--version", mode != "-v" {
    print("Aria capture — prototipo Fase 0")
}

switch mode {
case "--version", "-v":
    let info = Bundle.main.infoDictionary
    let version = (info?["CFBundleShortVersionString"] as? String) ?? "dev"
    let build = (info?["CFBundleVersion"] as? String) ?? ""
    print("NotarIA \(version)" + (build.isEmpty || build == version ? "" : " (\(build))"))
    exit(0)

case "system":
    let smokeSeconds = 5
    print("Smoke test de audio del sistema: \(smokeSeconds) s. Reproduce algo con sonido.")
    let capture = SystemAudioCapture()
    let stats = CaptureStats()
    capture.onBuffer = { buffer, _ in stats.add(buffer) }
    do {
        try await capture.start()
    } catch {
        print("[error] No se pudo iniciar la captura del sistema: \(error.localizedDescription)")
        print("Si es un tema de permisos: Ajustes › Privacidad y seguridad › Grabación de pantalla → habilita tu terminal y vuelve a correr.")
        exit(1)
    }
    try await Task.sleep(for: .seconds(smokeSeconds))
    await capture.stop()
    exit(report(stats, source: "SystemAudioCapture") ? 0 : 1)

case "mic":
    let smokeSeconds = 5
    print("Smoke test de micrófono: \(smokeSeconds) s. Habla o haz ruido.")
    let capture = MicCapture()
    let stats = CaptureStats()
    capture.onBuffer = { buffer, _ in stats.add(buffer) }
    do {
        try capture.start()
    } catch {
        print("[error] No se pudo iniciar la captura del micrófono: \(error.localizedDescription)")
        print("Si es un tema de permisos: Ajustes › Privacidad y seguridad › Micrófono → habilita tu terminal y vuelve a correr.")
        exit(1)
    }
    try await Task.sleep(for: .seconds(smokeSeconds))
    capture.stop()
    let ok = report(stats, source: "MicCapture")
    if ok, stats.snapshot().peak == 0 {
        print("[aviso] Pico en 0.0000: llegaron buffers pero en silencio absoluto. Probable permiso de Micrófono denegado.")
        exit(1)
    }
    exit(ok ? 0 : 1)

case "note":
    let store = NotesStore()
    let text = arguments.dropFirst().joined(separator: " ")
    if text.isEmpty {
        let notes = store.all()
        if notes.isEmpty {
            print("Sin notas. Agrega una con: aria-capture note <texto>")
        } else {
            print("Notas en \(store.fileURL.path):")
            for note in notes {
                print(note.timestamp.isEmpty ? "  - \(note.text)" : "  - [\(note.timestamp)] \(note.text)")
            }
        }
        exit(0)
    }
    do {
        try store.append(text)
        print("[ok] Nota guardada en \(store.fileURL.path)")
        exit(0)
    } catch {
        print("[error] No se pudo guardar la nota: \(error.localizedDescription)")
        exit(1)
    }

case "menubar":
    print("[menubar] Lanzando Aria en la barra de menú (⌃C aquí para cerrar)…")
    AriaMenuBarApp.main()

case "open":
    if isMenubarRunning() {
        DistributedNotificationCenter.default().postNotificationName(
            MainWindowBridge.openNotificationName, object: nil, userInfo: nil, deliverImmediately: true
        )
        print("[ok] Señal enviada a la Aria que ya está corriendo en la barra.")
        exit(0)
    }
    print("[aria] Aria no está corriendo todavía — lanzándola en la barra…")
    let menubarProcess = Process()
    menubarProcess.executableURL = URL(fileURLWithPath: CommandLine.arguments[0]).standardizedFileURL
    menubarProcess.arguments = ["menubar"]
    menubarProcess.standardInput = FileHandle.nullDevice
    do {
        try menubarProcess.run()
    } catch {
        print("[error] No se pudo lanzar aria-capture menubar: \(error.localizedDescription)")
        exit(1)
    }
    try await Task.sleep(for: .seconds(2))
    DistributedNotificationCenter.default().postNotificationName(
        MainWindowBridge.openNotificationName, object: nil, userInfo: nil, deliverImmediately: true
    )
    print("[ok] Aria lanzada y ventana solicitada.")
    exit(0)

case "writer-test":
    let scratch = FileManager.default.temporaryDirectory
        .appendingPathComponent("aria-writer-test-\(ProcessInfo.processInfo.processIdentifier)", isDirectory: true)
    let writer = ObsidianWriter(directory: scratch.appendingPathComponent("Reuniones", isDirectory: true))
    let note = MeetingNote(
        title: "Sync semanal: cierre de sprint / QA",
        date: Date(),
        participants: ["[[Ana GÃ³mez]]", "Otros"],
        durationSeconds: 1_845,
        body: "# Sync semanal\n\n## Resumen\nSe revisó el cierre del sprint y quedó pendiente la regresión.\n\n## Action items\n- [ ] Ejecutar regresión — Ana — viernes",
        transcript: "[00:00] Yo: ¿Cómo vamos con el informe?\n[00:05] Otros: Falta la regresión."
    )
    do {
        let first = try writer.write(note)
        let second = try writer.write(note)
        print("Escrito: \(first.lastPathComponent)")
        print("Colisión resuelta: \(second.lastPathComponent)")
        print("--- contenido ---")
        print(try String(contentsOf: first, encoding: .utf8))
        try FileManager.default.removeItem(at: scratch)
        exit(0)
    } catch {
        print("[error] \(error.localizedDescription)")
        exit(1)
    }

case "claude":
    let prompt = arguments.dropFirst().joined(separator: " ")
    guard !prompt.isEmpty else {
        print("Uso: aria-capture claude <texto de prueba>")
        exit(2)
    }
    do {
        guard let client = ClaudeCLIClient.preferredBackend() else {
            print("[error] Sin backend disponible: ni API key en Keychain ni CLI de Claude Code instalado.")
            print(KeychainStore.setupInstructions)
            exit(1)
        }
        print("[claude] Backend: \(client.backendName)…")
        let result = try await client.complete(
            system: "Eres Aria, asistente de notas de reuniones. Responde en español, breve.",
            userMessage: prompt,
            maxTokens: 16_000
        ) { chunk in
            print(chunk, terminator: "")
        }
        print("\n[claude] stop=\(result.stopReason)")
        exit(0)
    } catch {
        print("[error] \(error.localizedDescription)")
        exit(1)
    }

case "transcribe":
    let path = arguments.dropFirst().first ?? "out.wav"
    do {
        print("[whisper] Transcribiendo \(path)…")
        let result = try await transcribeWav(path: path)
        print("— Transcript:")
        print(TranscriptFormatter.render(result.segments))
        exit(0)
    } catch {
        print("[error] \(error.localizedDescription)")
        exit(1)
    }

case "enhance":
    var extra = Array(arguments.dropFirst())
    let offline = extra.contains("--offline")
    extra.removeAll { $0 == "--offline" }
    let polishFlag = extra.contains("--polish")
    extra.removeAll { $0 == "--polish" }
    var speakerMap: [String: String] = [:]
    if let flagIndex = extra.firstIndex(of: "--speakers") {
        guard extra.count > flagIndex + 1 else {
            print("Uso: aria-capture enhance [--offline] [--speakers \"Otros=Juan,Yo=Ana\"] [--template <nombre>] [archivo.wav]")
            exit(2)
        }
        do {
            speakerMap = try SpeakerMap.parse(extra[flagIndex + 1])
        } catch {
            print("[error] \(error.localizedDescription)")
            exit(2)
        }
        extra.removeSubrange(flagIndex...(flagIndex + 1))
    }
    var enhanceTemplate: Recipe?
    if let flagIndex = extra.firstIndex(of: "--template") {
        guard extra.count > flagIndex + 1 else {
            print("Uso: aria-capture enhance [--offline] [--speakers \"Otros=Juan,Yo=Ana\"] [--template <nombre>] [archivo.wav]")
            exit(2)
        }
        let templateStore = TemplateStore()
        _ = try? templateStore.ensureDefaults()
        guard let found = templateStore.template(named: extra[flagIndex + 1]) else {
            let names = templateStore.list().map(\.name).joined(separator: ", ")
            print("[error] No existe la plantilla '\(extra[flagIndex + 1])'. Disponibles: \(names)")
            print("        Crea la tuya: \(templateStore.directory.path)/<nombre>.md con el enfoque adentro.")
            exit(1)
        }
        if offline {
            print("[aviso] --template no aplica en modo offline (no hay enhance); se ignora.")
        }
        enhanceTemplate = found
        extra.removeSubrange(flagIndex...(flagIndex + 1))
    }
    if let unknown = extra.first(where: { $0.hasPrefix("--") }) {
        print("[error] Flag desconocido '\(unknown)'. Uso: aria-capture enhance [--offline] [--polish] [--speakers \"Otros=Juan\"] [--template <nombre>] [archivo.wav]")
        exit(2)
    }
    let path = extra.first { !$0.hasPrefix("--") } ?? "out.wav"
    do {
        let now = Date()
        let recordingEnd = (try? FileManager.default.attributesOfItem(atPath: path)[.modificationDate] as? Date) ?? now
        let claudeClient: EnhanceBackend?
        if offline {
            claudeClient = nil
        } else if let backend = ClaudeCLIClient.preferredBackend() {
            claudeClient = backend
        } else {
            print("[error] Sin backend disponible: ni API key en Keychain ni CLI de Claude Code instalado.")
            print(KeychainStore.setupInstructions)
            exit(1)
        }
        let result = try await transcribeWav(path: path)
        var segments = speakerMap.isEmpty ? result.segments : SpeakerMap.apply(speakerMap, to: result.segments)
        let speakers = speakerMap.isEmpty ? result.speakers : SpeakerMap.apply(speakerMap, to: result.speakers)
        if !speakerMap.isEmpty {
            print("[hablantes] Mapeo aplicado: \(speakerMap.map { "\($0.key)→\($0.value)" }.sorted().joined(separator: ", "))")
        }
        let rawNotes = NotesStore().rawMarkdown.trimmingCharacters(in: .whitespacesAndNewlines)
        let recordingStart = recordingEnd.addingTimeInterval(-result.durationSeconds)
        let calendarMeeting = MeetingCalendar.shared.meeting(overlapping: recordingStart, to: recordingEnd)
        if let meeting = calendarMeeting {
            print("[calendario] Reunión detectada: \(meeting.title)\(meeting.attendees.isEmpty ? "" : " · \(meeting.attendees.joined(separator: ", "))")")
        }
        let wantPolish = polishFlag || AriaConfig.load().transcriptPolish
        if wantPolish, offline {
            print("[aviso] --polish/transcriptPolish no aplica en modo offline (usa Claude); se ignora.")
        } else if wantPolish, let backend = claudeClient, !segments.isEmpty {
            do {
                print("[polish] Puliendo transcript (\(backend.backendName))…")
                segments = try await TranscriptPolisher.polish(
                    segments: segments,
                    calendarMeeting: calendarMeeting,
                    client: backend
                )
                print("[polish] Transcript pulido (\(segments.count) líneas, timestamps y hablantes intactos).")
            } catch {
                print("[aviso] Pulido falló: \(error.localizedDescription) Sigo con el transcript de whisper.")
            }
        }
        let transcript = TranscriptFormatter.render(segments)
        let participants = CalendarMeeting.participants(meeting: calendarMeeting, fallback: speakers)

        if offline {
            print("[enhance] Modo offline: transcript + notas crudas, sin IA.")
            let timeFormatter = DateFormatter()
            timeFormatter.dateFormat = "HH:mm"
            var body = ""
            if !rawNotes.isEmpty {
                body += "## Notas\n\(rawNotes)\n\n"
            }
            body += "## Transcript\n\(transcript.isEmpty ? "_(sin voz detectada)_" : transcript)"
            let note = MeetingNote(
                title: calendarMeeting?.title ?? "Reunion \(timeFormatter.string(from: now)) (sin enhance)",
                date: now,
                participants: participants,
                durationSeconds: result.durationSeconds,
                body: body,
                transcript: nil,
                companies: calendarMeeting?.companies ?? []
            )
            let url = try ObsidianWriter().write(note)
            do {
                try MeetingStore().saveMeeting(
                    date: now,
                    title: note.title,
                    durationSeconds: result.durationSeconds,
                    notePath: url.path,
                    wavPath: URL(fileURLWithPath: path).path,
                    segments: segments,
                    quickNotes: NotesStore().all()
                )
            } catch {
                print("[aviso] Historial no guardado: \(error.localizedDescription)")
            }
            try? NotesStore().clear()
            print("[ok] Nota guardada: \(url.path)")
            exit(0)
        }

        guard let claudeClient else { exit(1) }
        print("[enhance] Backend: \(claudeClient.backendName) (solo texto; el audio no sale del Mac)…")
        let enhancer = MeetingEnhancer(client: claudeClient, template: enhanceTemplate)
        let enhanced = try await enhancer.enhance(
            transcript: transcript,
            notes: rawNotes,
            date: now,
            durationSeconds: result.durationSeconds,
            calendarMeeting: calendarMeeting
        ) { chunk in
            print(chunk, terminator: "")
        }
        print("\n[claude] in=\(enhanced.inputTokens) tok · out=\(enhanced.outputTokens) tok")

        let note = MeetingNote(
            title: calendarMeeting?.title ?? enhanced.title,
            date: now,
            participants: participants,
            durationSeconds: result.durationSeconds,
            body: enhanced.markdown,
            transcript: transcript.isEmpty ? nil : transcript,
            companies: calendarMeeting?.companies ?? []
        )
        let url = try ObsidianWriter().write(note)
        do {
            let store = try MeetingStore()
            try store.saveMeeting(
                date: now,
                title: note.title,
                durationSeconds: result.durationSeconds,
                notePath: url.path,
                wavPath: URL(fileURLWithPath: path).path,
                segments: segments,
                quickNotes: NotesStore().all()
            )
        } catch {
            print("[aviso] Historial no guardado: \(error.localizedDescription)")
        }
        try? NotesStore().clear()
        print("[ok] Nota guardada: \(url.path)")
        exit(0)
    } catch {
        print("[error] \(error.localizedDescription)")
        if error is ClaudeError {
            print("[tip] Mientras tanto puedes guardar sin IA: aria-capture enhance --offline \(path)")
        }
        exit(1)
    }

case "chat":
    var chatArgs = Array(arguments.dropFirst())
    var meetingID: Int64?
    var chatLimit = 10
    while let flagIndex = chatArgs.firstIndex(where: { $0 == "--meeting" || $0 == "--last" }) {
        guard chatArgs.count > flagIndex + 1, let value = Int(chatArgs[flagIndex + 1]), value > 0 else {
            print("Uso: aria-capture chat [--meeting <id>] [--last <n>] <pregunta>")
            exit(2)
        }
        if chatArgs[flagIndex] == "--meeting" {
            meetingID = Int64(value)
        } else {
            chatLimit = value
        }
        chatArgs.removeSubrange(flagIndex...(flagIndex + 1))
    }
    if let unknown = chatArgs.first(where: { $0.hasPrefix("--") }) {
        print("[error] Flag desconocido '\(unknown)'. Uso: aria-capture chat [--meeting <id>] [--last <n>] <pregunta>")
        exit(2)
    }
    let question = chatArgs.joined(separator: " ").trimmingCharacters(in: .whitespaces)
    guard !question.isEmpty else {
        print("Uso: aria-capture chat [--meeting <id>] [--last <n>] <pregunta>")
        print("Ej.: aria-capture chat \"¿qué prometí esta semana?\"")
        exit(2)
    }
    do {
        let chatResult = try await MeetingChat.answer(question: question, meetingID: meetingID, limit: chatLimit) { chunk in
            print(chunk, terminator: "")
        }
        let omittedNote = chatResult.meetingsOmitted > 0 ? " (\(chatResult.meetingsOmitted) más fuera por tamaño)" : ""
        print("\n[chat] \(chatResult.backendName) · \(chatResult.meetingsIncluded) reunión(es) en contexto\(omittedNote) · in=\(chatResult.inputTokens) tok · out=\(chatResult.outputTokens) tok")
        exit(0)
    } catch {
        print("[error] \(error.localizedDescription)")
        exit(1)
    }

case "recipe":
    var recipeArgs = Array(arguments.dropFirst())
    var recipeMeetingID: Int64?
    var recipeLimit = 1
    while let flagIndex = recipeArgs.firstIndex(where: { $0 == "--meeting" || $0 == "--last" }) {
        guard recipeArgs.count > flagIndex + 1, let value = Int(recipeArgs[flagIndex + 1]), value > 0 else {
            print("Uso: aria-capture recipe [<nombre>] [--meeting <id>] [--last <n>]")
            exit(2)
        }
        if recipeArgs[flagIndex] == "--meeting" {
            recipeMeetingID = Int64(value)
        } else {
            recipeLimit = value
        }
        recipeArgs.removeSubrange(flagIndex...(flagIndex + 1))
    }
    let recipeStore = RecipeStore()
    do {
        let created = try recipeStore.ensureDefaults()
        if !created.isEmpty {
            print("[recipes] Creadas por defecto en \(recipeStore.directory.path): \(created.joined(separator: ", "))")
        }
    } catch {
        print("[error] No se pudo preparar \(recipeStore.directory.path): \(error.localizedDescription)")
        exit(1)
    }
    if let unknown = recipeArgs.first(where: { $0.hasPrefix("--") }) {
        print("[error] Flag desconocido '\(unknown)'. Uso: aria-capture recipe [<nombre>] [--meeting <id>] [--last <n>]")
        exit(2)
    }
    guard let recipeName = recipeArgs.first else {
        let recipes = recipeStore.list()
        print("Recipes en \(recipeStore.directory.path):")
        for recipe in recipes {
            let firstLine = recipe.prompt.split(separator: "\n").first.map(String.init) ?? ""
            print("  \(recipe.name) — \(firstLine)")
        }
        print("Uso: aria-capture recipe <nombre> [--meeting <id>] [--last <n>]  (por defecto: la última reunión)")
        exit(0)
    }
    guard let recipe = recipeStore.recipe(named: recipeName) else {
        let names = recipeStore.list().map(\.name).joined(separator: ", ")
        print("[error] No existe la recipe '\(recipeName)'. Disponibles: \(names)")
        print("        Crea la tuya: \(recipeStore.directory.path)/<nombre>.md con el prompt adentro.")
        exit(1)
    }
    do {
        let recipeResult = try await MeetingChat.applyRecipe(recipe, meetingID: recipeMeetingID, limit: recipeLimit) { chunk in
            print(chunk, terminator: "")
        }
        let omittedNote = recipeResult.meetingsOmitted > 0 ? " (\(recipeResult.meetingsOmitted) más fuera por tamaño)" : ""
        print("\n[recipe] \(recipe.name) · \(recipeResult.backendName) · \(recipeResult.meetingsIncluded) reunión(es)\(omittedNote)")
        exit(0)
    } catch {
        print("[error] \(error.localizedDescription)")
        exit(1)
    }

case "brief":
    var briefArgs = Array(arguments.dropFirst())
    var briefAttendees: [String] = []
    var briefTitle = ""
    while let flagIndex = briefArgs.firstIndex(where: { $0 == "--with" || $0 == "--title" }) {
        guard briefArgs.count > flagIndex + 1 else {
            print("Uso: aria-capture brief [--with \"Ana,Juan\"] [--title \"Sync semanal\"]")
            print("     Sin flags usa la reunión actual o la próxima del calendario (requiere: aria-capture calendar).")
            exit(2)
        }
        if briefArgs[flagIndex] == "--with" {
            briefAttendees = briefArgs[flagIndex + 1]
                .split(separator: ",")
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty }
            guard !briefAttendees.isEmpty else {
                print("[error] --with no trae nombres. Ej.: aria-capture brief --with \"Ana,Juan\"")
                exit(2)
            }
        } else {
            briefTitle = briefArgs[flagIndex + 1]
        }
        briefArgs.removeSubrange(flagIndex...(flagIndex + 1))
    }
    if let unknown = briefArgs.first(where: { $0.hasPrefix("--") }) {
        print("[error] Flag desconocido '\(unknown)'. Uso: aria-capture brief [--with \"Ana,Juan\"] [--title \"Sync\"]")
        exit(2)
    }
    if briefAttendees.isEmpty && briefTitle.isEmpty {
        guard MeetingCalendar.isAuthorized else {
            print("[error] Calendario: \(MeetingCalendar.statusDescription).")
            print("        O pasa los datos a mano: aria-capture brief --with \"Ana,Juan\" [--title \"Sync\"]")
            exit(1)
        }
        guard let meeting = MeetingCalendar.shared.currentMeeting() ?? MeetingCalendar.shared.nextMeeting() else {
            print("Sin reuniones en curso ni próximas (12 h) en el calendario.")
            exit(1)
        }
        briefAttendees = meeting.attendees
        briefTitle = meeting.title
        let hourFormatter = DateFormatter()
        hourFormatter.dateFormat = "HH:mm"
        print("[brief] Reunión: \(meeting.title) (\(hourFormatter.string(from: meeting.start)))\(meeting.attendees.isEmpty ? "" : " · \(meeting.attendees.joined(separator: ", "))")")
    }
    do {
        let briefResult = try await MeetingBrief.generate(attendees: briefAttendees, title: briefTitle) { chunk in
            print(chunk, terminator: "")
        }
        print("\n[brief] \(briefResult.backendName) · \(briefResult.meetingsIncluded) reunión(es) previas en contexto")
        exit(0)
    } catch {
        print("[error] \(error.localizedDescription)")
        exit(1)
    }

case "template":
    let templateStore = TemplateStore()
    do {
        let created = try templateStore.ensureDefaults()
        if !created.isEmpty {
            print("[plantillas] Creadas por defecto en \(templateStore.directory.path): \(created.joined(separator: ", "))")
        }
    } catch {
        print("[error] No se pudo preparar \(templateStore.directory.path): \(error.localizedDescription)")
        exit(1)
    }
    print("Plantillas en \(templateStore.directory.path):")
    for template in templateStore.list() {
        let firstLine = template.prompt.split(separator: "\n").first.map(String.init) ?? ""
        print("  \(template.name) — \(firstLine)")
    }
    print("Uso: aria-capture enhance --template <nombre> [archivo.wav]")
    exit(0)

case "ai":
    let aiArgs = Array(arguments.dropFirst())
    guard aiArgs.first == "test" else {
        print("Uso: aria-capture ai test")
        exit(2)
    }
    let aiConfig = AriaConfig.load()
    print("[ai] Proveedor configurado: \(aiConfig.aiProvider.rawValue) — \(aiConfig.aiProvider.label)")
    let aiResult = await AIProviderTester.test(config: aiConfig)
    print(aiResult.ok ? "[ok] \(aiResult.message)" : "[error] \(aiResult.message)")
    exit(aiResult.ok ? 0 : 1)

case "mcp":
    do {
        let server = try MCPServer()
        server.run()
        exit(0)
    } catch {
        FileHandle.standardError.write(Data("[error] \(error.localizedDescription)\n".utf8))
        exit(1)
    }

case "search":
    let searchQuery = arguments.dropFirst().joined(separator: " ").trimmingCharacters(in: .whitespaces)
    guard !searchQuery.isEmpty else {
        print("Uso: aria-capture search <palabras>")
        exit(2)
    }
    do {
        let hits = try MeetingSearch.search(searchQuery)
        if hits.isEmpty {
            print("Sin resultados para \"\(searchQuery)\".")
        } else {
            print("\(hits.count) resultado(s) para \"\(searchQuery)\":")
            for hit in hits {
                print("  " + MeetingSearch.line(for: hit))
            }
        }
        exit(0)
    } catch {
        print("[error] \(error.localizedDescription)")
        exit(1)
    }

case "config":
    var config = AriaConfig.load()
    let configArgs = Array(arguments.dropFirst())
    if configArgs.isEmpty {
        print(config.listing)
        exit(0)
    }
    guard configArgs.count == 2 else {
        print("Uso: aria-capture config [<clave> <valor>]")
        exit(2)
    }
    do {
        try config.set(key: configArgs[0], value: configArgs[1])
        try config.save()
        print("[ok] \(configArgs[0]) = \(config.displayValue(forKey: configArgs[0]) ?? configArgs[1])")
        exit(0)
    } catch {
        print("[error] \(error.localizedDescription)")
        exit(1)
    }

case "calls":
    let signal = CallDetector.currentSignal()
    print("Estado: \(signal.summary)")
    if signal.confirmedMeeting {
        print("[detector] Llamada en curso Y reunión en el calendario — grabando tendrás título y participantes reales.")
    } else if signal.probableCall {
        print("[detector] Probable llamada en curso — buen momento para grabar.")
    } else {
        print("[detector] Sin señales de llamada.")
    }
    exit(signal.probableCall ? 0 : 1)

case "calendar":
    if !MeetingCalendar.isAuthorized {
        print("[tcc] Calendario: \(MeetingCalendar.statusDescription) → pidiendo acceso completo (acepta el diálogo)…")
        do {
            let granted = try await MeetingCalendar.shared.requestAccess()
            print("[tcc] Calendario: \(granted ? "concedido" : "denegado")")
            guard granted else {
                print("      Habilita tu terminal en Ajustes › Privacidad y seguridad › Calendarios y vuelve a correr.")
                exit(1)
            }
        } catch {
            print("[error] Solicitando acceso al calendario: \(error.localizedDescription)")
            exit(1)
        }
    }
    let calendarNow = Date()
    let dayStart = Calendar.current.startOfDay(for: calendarNow)
    let dayEnd = Calendar.current.date(byAdding: .day, value: 1, to: dayStart) ?? calendarNow
    let todays = MeetingCalendar.shared.meetings(from: dayStart, to: dayEnd)
        .filter { !$0.isAllDay }
        .sorted { $0.start < $1.start }
    let current = MeetingCalendar.shared.currentMeeting(at: calendarNow)
    let visibleCalendars = MeetingCalendar.shared.calendarNames()
    if visibleCalendars.isEmpty {
        print("[aviso] EventKit no ve NINGÚN calendario. Añade tus cuentas en Ajustes del Sistema › Cuentas de Internet (Google/Exchange) con \"Calendarios\" activado.")
    } else {
        print("Calendarios visibles (\(visibleCalendars.count)):")
        for calendar in visibleCalendars {
            print("  \(calendar.source) › \(calendar.title)\(calendar.ignored ? " — IGNORADO (calendarIgnore)" : "")")
        }
    }
    if todays.isEmpty {
        print("Sin reuniones (con horario) en el calendario de hoy.")
    } else {
        let hourFormatter = DateFormatter()
        hourFormatter.dateFormat = "HH:mm"
        print("Reuniones de hoy:")
        for meeting in todays {
            let marker = meeting == current ? " ← AHORA" : ""
            let people = meeting.attendees.isEmpty ? "" : " · \(meeting.attendees.joined(separator: ", "))"
            let video = meeting.videoLink == nil ? "" : " 🎥"
            print("  \(hourFormatter.string(from: meeting.start))–\(hourFormatter.string(from: meeting.end)) \(meeting.title)\(video)\(people)\(marker)")
        }
    }
    exit(0)

case "history":
    do {
        let records = try MeetingStore().recentMeetings(limit: 15)
        if records.isEmpty {
            print("Sin reuniones en el historial todavía.")
        } else {
            let formatter = DateFormatter()
            formatter.dateFormat = "yyyy-MM-dd HH:mm"
            for record in records {
                let minutes = Int(record.durationSeconds) / 60
                let seconds = Int(record.durationSeconds) % 60
                let sourceTag = record.source == "aria" ? "" : " · [\(record.source)]"
                print("[\(record.id)] \(formatter.string(from: record.date)) · \(String(format: "%02d:%02d", minutes, seconds)) · \(record.title)\(sourceTag)")
                print("      nota: \(record.notePath)")
            }
        }
        exit(0)
    } catch {
        print("[error] \(error.localizedDescription)")
        exit(1)
    }

case "import-granola":
    guard let dirArg = arguments.dropFirst().first else {
        print("Uso: aria-capture import-granola <directorio-json>")
        exit(2)
    }
    let importDir = URL(fileURLWithPath: (dirArg as NSString).expandingTildeInPath, isDirectory: true)
    do {
        let result = try GranolaImporter.importDirectory(importDir)
        print("[ok] importadas=\(result.imported) actualizadas=\(result.updated) fallidas=\(result.failed.count)")
        for failure in result.failed {
            print("  [error] \(failure.file): \(failure.error)")
        }
        exit(result.failed.isEmpty ? 0 : 1)
    } catch {
        print("[error] \(error.localizedDescription)")
        exit(1)
    }

case "import":
    var importArgs = Array(arguments.dropFirst())
    var importSource: String?
    if let flagIndex = importArgs.firstIndex(of: "--source") {
        guard importArgs.count > flagIndex + 1 else {
            print("Uso: aria-capture import <ruta> [--source nombre]")
            exit(2)
        }
        importSource = importArgs[flagIndex + 1]
        importArgs.removeSubrange(flagIndex...(flagIndex + 1))
    }
    if let unknown = importArgs.first(where: { $0.hasPrefix("--") }) {
        print("[error] Flag desconocido '\(unknown)'. Uso: aria-capture import <ruta> [--source nombre]")
        exit(2)
    }
    guard let importPathArg = importArgs.first else {
        print("Uso: aria-capture import <ruta> [--source nombre]")
        print("     Formatos: .md/.txt (frontmatter opcional), .vtt/.srt, .json (ver docs/IMPORT-FORMAT.md)")
        exit(2)
    }
    let genericImportPath = URL(fileURLWithPath: (importPathArg as NSString).expandingTildeInPath)
    do {
        let result = try GenericImporter.importPath(genericImportPath, sourceOverride: importSource)
        print("[ok] importadas=\(result.imported) actualizadas=\(result.updated) fallidas=\(result.failed.count)")
        for failure in result.failed {
            print("  [error] \(failure.file): \(failure.error)")
        }
        exit(result.failed.isEmpty ? 0 : 1)
    } catch {
        print("[error] \(error.localizedDescription)")
        exit(1)
    }

case "model":
    let modelArgs = Array(arguments.dropFirst())
    if modelArgs.first == "vad" {
        do {
            let modelURL = try await SileroModel.ensureModel()
            print("[vad] Modelo Silero listo: \(modelURL.path)")
            exit(0)
        } catch {
            print("[error] \(error.localizedDescription)")
            exit(1)
        }
    }
    do {
        let modelURL = try await WhisperModelStore.ensureModel()
        print("[whisper] Modelo listo: \(modelURL.path)")
        let transcriber = try WhisperTranscriber(modelPath: modelURL.path)
        _ = transcriber
        print("[whisper] System info: \(WhisperTranscriber.systemInfo)")
        print("[ok] whisper.cpp inicializado con Metal.")
        exit(0)
    } catch {
        print("[error] \(error.localizedDescription)")
        exit(1)
    }

case "check":
    let ok = await Permissions.ensureAll()
    print(ok ? "[ok] Todos los permisos listos para grabar." : "[fallo] Faltan permisos; revisa arriba.")
    exit(ok ? 0 : 1)

case "wav":
    let seconds = arguments.dropFirst().first.flatMap(Int.init) ?? 60
    let outputURL = URL(fileURLWithPath: "out.wav")
    guard await Permissions.ensureAll() else { exit(1) }
    print("Grabando \(seconds) s → \(outputURL.path) (L=mic, R=sistema).")
    print("Habla al micrófono y deja algo sonando por los parlantes.")

    let recorder = StereoWavRecorder(seconds: seconds)
    let system = SystemAudioCapture()
    let mic = MicCapture()
    let systemStats = CaptureStats()
    let micStats = CaptureStats()
    system.onBuffer = { buffer, seconds in
        systemStats.add(buffer)
        recorder.addSystem(buffer, atHostSeconds: seconds)
    }
    system.onStopped = { error in
        print("[aviso] SCStream se detuvo solo: \(error?.localizedDescription ?? "sin error")")
    }
    mic.onBuffer = { buffer, seconds in
        micStats.add(buffer)
        recorder.addMic(buffer, atHostSeconds: seconds)
    }

    do {
        try await system.start()
    } catch {
        print("[error] Captura del sistema: \(error.localizedDescription)")
        exit(1)
    }
    do {
        try mic.start()
    } catch {
        await system.stop()
        print("[error] Captura del micrófono: \(error.localizedDescription)")
        exit(1)
    }
    recorder.begin(epochSeconds: AVAudioTime.seconds(forHostTime: mach_absolute_time()))
    let sleepGuard = SleepGuard()
    sleepGuard.begin()
    defer { sleepGuard.end() }

    for elapsed in 1...seconds {
        try await Task.sleep(for: .seconds(1))
        if elapsed % 10 == 0 || elapsed == seconds {
            let sys = systemStats.snapshot()
            let m = micStats.snapshot()
            print("... \(elapsed)/\(seconds) s · buffers sistema=\(sys.buffers) mic=\(m.buffers)")
        }
    }

    mic.stop()
    await system.stop()

    do {
        let result = try recorder.write(to: outputURL)
        print(String(format: "Escrito %@ · %.0f s · pico L(mic)=%.4f · pico R(sistema)=%.4f", outputURL.path, result.seconds, result.micPeak, result.systemPeak))
        if result.micPeak == 0 { print("[aviso] Canal izquierdo (mic) en silencio total.") }
        if result.systemPeak == 0 { print("[aviso] Canal derecho (sistema) en silencio total.") }
        exit(result.micPeak > 0 && result.systemPeak > 0 ? 0 : 1)
    } catch {
        print("[error] Escribiendo WAV: \(error.localizedDescription)")
        exit(1)
    }

default:
    print("Uso: aria-capture [--version | wav [segundos] | system | mic | check | model | transcribe [archivo.wav] | note [texto] | claude <texto> | enhance [--offline] [--polish] [--speakers <mapa>] [--template <nombre>] [archivo.wav] | menubar | open | history | calls | calendar | chat [--meeting <id>] [--last <n>] <pregunta> | recipe [<nombre>] [--meeting <id>] [--last <n>] | brief [--with <nombres>] [--title <titulo>] | search <palabras> | template | ai test | mcp | config [clave valor] | import <ruta> [--source nombre] | import-granola <directorio-json>]")
    exit(2)
}
