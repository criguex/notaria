import AppKit
import AVFoundation
import Darwin
import Foundation
import SwiftUI

@MainActor
final class RecordingController: ObservableObject {

    enum State: Equatable {
        case idle
        case recording(since: Date)
        case processing(step: String)
        case done(noteURL: URL)
        case failed(String)
    }

    @Published var state: State = .idle
    @Published var callDetected = false
    @Published var meetingNow: CalendarMeeting?
    @Published var upcomingMeeting: CalendarMeeting?
    @Published var recordingElapsed = ""
    @Published var isDictation = false
    @Published private(set) var session = RecordingSessionMachine()
    @Published private(set) var pauseLog = PauseLog()
    @Published var alwaysOn = AriaConfig.load().alwaysOn
    @Published var visualContextActive = false
    let showUpcoming = AriaConfig.load().showUpcoming

    private var autoStarted = false
    private var lastPromptKey: String?
    private static let autoStopSilenceSeconds: TimeInterval = 180

    let liveTranscriptFeed = LiveTranscriptFeed()
    let notepad = MeetingNotepadController()
    private var liveRunner: LiveTranscriptionRunner?

    private var system: SystemAudioCapture?
    private var mic: MicCapture?
    private var recorder: GrowableStereoRecorder?
    private var visualContext: VisualContextCapture?
    private let sleepGuard = SleepGuard()
    private var callTimer: Timer?
    private var elapsedTimer: Timer?

    init() {
        let config = AriaConfig.load()
        if config.retentionDays > 0, let store = try? MeetingStore() {
            if let purged = try? store.purge(olderThanDays: config.retentionDays), purged > 0 {
                print("[retención] \(purged) reunión(es) de más de \(config.retentionDays) días eliminadas del historial.")
            }
        }
        callTimer = Timer.scheduledTimer(withTimeInterval: 7, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                switch self.state {
                case .idle, .done:
                    let signal = CallDetector.currentSignal()
                    self.callDetected = signal.probableCall
                    self.meetingNow = signal.meetingNow
                    self.upcomingMeeting = self.showUpcoming && signal.meetingNow == nil
                        ? MeetingCalendar.shared.nextMeeting()
                        : nil
                    if self.callDetected, self.alwaysOn, ConsentManager.hasConsent {
                        self.autoStarted = true
                        self.start()
                    } else if let key = MeetingPromptDecider.pendingKey(
                        micInUse: signal.micInUse,
                        callApps: signal.callApps,
                        meetingNow: signal.meetingNow,
                        alwaysOn: self.alwaysOn,
                        isRecording: self.isRecording,
                        lastKey: self.lastPromptKey
                    ) {
                        self.lastPromptKey = key
                        let joinURL = signal.meetingNow?.videoLink.flatMap { MeetingJoinLink.resolve(videoLink: $0) }
                        MeetingPromptWindowController.shared.present(
                            title: MeetingPromptDecider.promptTitle(meetingNow: signal.meetingNow),
                            subtitle: MeetingPromptDecider.promptSubtitle(meetingNow: signal.meetingNow),
                            joinURL: joinURL
                        ) { [weak self] in
                            self?.start()
                        }
                    }
                default:
                    self.callDetected = false
                }
            }
        }
        elapsedTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                if case .recording = self.state {
                    let phaseAfterTick = self.session.tick(1)
                    let total = Int(self.session.elapsedSeconds)
                    self.recordingElapsed = String(format: "%d:%02d", total / 60, total % 60)
                    switch phaseAfterTick {
                    case .stopped:
                        print("[always-on] cuenta atrás agotada sin respuesta — deteniendo y generando nota.")
                        StillThereWarningWindowController.shared.dismiss()
                        self.stopAndGenerate()
                    case .awaitingStillThereConfirmation:
                        if StillThereWarningWindowController.shared.isPresenting {
                            StillThereWarningWindowController.shared.updateCountdown(self.stillThereCountdown)
                        } else {
                            StillThereWarningWindowController.shared.present(
                                remainingSeconds: self.stillThereCountdown,
                                onKeepGoing: { [weak self] in self?.keepRecordingAfterStillThereWarning() },
                                onStop: { [weak self] in self?.stopFromStillThereWarning() }
                            )
                        }
                    case .recording:
                        if self.autoStarted, total > 60,
                           let silence = self.recorder?.secondsSinceSystemAudio,
                           silence > Self.autoStopSilenceSeconds,
                           self.session.raiseStillThereWarning() {
                            print("[always-on] \(Int(silence)) s sin audio del sistema — mostrando aviso '¿sigues ahí?'.")
                            StillThereWarningWindowController.shared.present(
                                remainingSeconds: self.stillThereCountdown,
                                onKeepGoing: { [weak self] in self?.keepRecordingAfterStillThereWarning() },
                                onStop: { [weak self] in self?.stopFromStillThereWarning() }
                            )
                        }
                    case .paused:
                        break
                    }
                } else if !self.recordingElapsed.isEmpty {
                    self.recordingElapsed = ""
                }
            }
        }
    }

    func toggleAlwaysOn() {
        if alwaysOn {
            alwaysOn = false
            autoStarted = false
            persistAlwaysOn(false)
            return
        }
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = "Activar modo always-on"
        alert.informativeText = """
        Aria quedará escuchando señales de llamada (micrófono en uso + apps de reuniones) y \
        empezará a grabar AUTOMÁTICAMENTE cuando detecte una, con el indicador ● REC siempre \
        visible. Se detiene sola tras 3 minutos sin audio del sistema, o cuando tú la detengas.

        Mientras el modo esté activo verás el ícono de oreja en la barra: Aria está escuchando. \
        Puedes pausarlo desde este mismo menú en cualquier momento y revisar todo lo capturado \
        en "Recientes". La retención se configura con retentionDays (aria-capture config).
        """
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Activar always-on")
        alert.addButton(withTitle: "Cancelar")
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        alwaysOn = true
        persistAlwaysOn(true)
    }

    private func persistAlwaysOn(_ value: Bool) {
        var config = AriaConfig.load()
        config.alwaysOn = value
        try? config.save()
    }

    var isRecording: Bool {
        if case .recording = state { return true }
        return false
    }

    var isPaused: Bool { session.isPaused }
    var isAwaitingStillThere: Bool { session.isAwaitingConfirmation }
    var stillThereCountdown: Int { Int(session.countdownRemaining.rounded(.up)) }

    func pauseRecording() {
        guard isRecording, session.pause() else { return }
        pauseLog.beginPause(at: Date(), activeOffsetSeconds: session.elapsedSeconds)
        recorder?.setPaused(true)
        liveRunner?.pause()
        visualContext?.setPaused(true)
    }

    func resumeRecording() {
        guard isRecording, session.resume() else { return }
        pauseLog.endPause(at: Date())
        recorder?.setPaused(false)
        liveRunner?.resume()
        visualContext?.setPaused(false)
    }

    private func keepRecordingAfterStillThereWarning() {
        guard session.keepRecording() else { return }
        recorder?.resetSilenceClock()
    }

    private func stopFromStillThereWarning() {
        session.stop()
        stopAndGenerate()
    }

    func start(dictationOnly: Bool = false) {
        guard case .idle = state else {
            if case .done = state { state = .idle; start(dictationOnly: dictationOnly) }
            return
        }
        guard ConsentManager.requestIfNeeded() else { return }
        Task {
            guard await Permissions.ensureAll(dictationOnly: dictationOnly) else {
                let needsScreen = RequiredPermissions.needsScreenRecording(dictationOnly: dictationOnly)
                state = .failed("Faltan permisos de Micrófono\(needsScreen ? " o Grabación de pantalla" : "").")
                return
            }
            let recorder = GrowableStereoRecorder()
            let mic = MicCapture()
            mic.onBuffer = { recorder.addMic($0, atHostSeconds: $1) }
            var system: SystemAudioCapture?
            if !dictationOnly {
                let capture = SystemAudioCapture()
                capture.onBuffer = { recorder.addSystem($0, atHostSeconds: $1) }
                system = capture
            }
            do {
                if let system { try await system.start() }
                try mic.start()
            } catch {
                if let system { await system.stop() }
                mic.stop()
                state = .failed("No se pudo iniciar la captura: \(error.localizedDescription)")
                return
            }
            recorder.begin(epochSeconds: AVAudioTime.seconds(forHostTime: mach_absolute_time()))
            self.recorder = recorder
            self.system = system
            self.mic = mic
            self.isDictation = dictationOnly
            sleepGuard.begin()
            session = RecordingSessionMachine()
            pauseLog = PauseLog()
            let since = Date()
            state = .recording(since: since)
            notepad.begin(since: since)
            let config = AriaConfig.load()
            if !dictationOnly, config.visualContextEnabled {
                let capture = VisualContextCapture(
                    excludedBundleIDs: config.excludedVisualContextBundleIDs,
                    changedRatioThreshold: config.visualContextChangeThreshold
                )
                capture.start(sessionStart: since)
                visualContext = capture
                visualContextActive = true
            } else {
                visualContext = nil
                visualContextActive = false
            }
            let runner = LiveTranscriptionRunner(recorder: recorder, feed: liveTranscriptFeed)
            runner.start()
            liveRunner = runner
            RecordingPillWindowController.shared.show(controller: self, feed: liveTranscriptFeed)
        }
    }

    func stopAndGenerate() {
        guard case .recording(let since) = state, let recorder else { return }
        state = .processing(step: "guardando audio")
        autoStarted = false
        session.stop()
        pauseLog.endPause(at: Date())
        let pauses = pauseLog.intervals
        StillThereWarningWindowController.shared.dismiss()
        liveRunner?.stop()
        liveRunner = nil
        RecordingPillWindowController.shared.hide()
        let ownNotesDraft = notepad.finish()
        visualContext?.stop()
        let pendingVisualCaptures = visualContext?.pendingCaptures ?? []
        visualContext = nil
        visualContextActive = false
        let visualRecords: [VisualCaptureRecord] = pendingVisualCaptures.enumerated().map { index, capture in
            VisualCaptureRecord(
                elapsedSeconds: capture.elapsedSeconds,
                ocrText: capture.ocrText,
                imageFileName: VisualContextStorage.imageFileName(index: index + 1)
            )
        }
        let visualContextSummary = VisualContextPrompt.summaryBlock(captures: visualRecords)
        Task {
            mic?.stop()
            await system?.stop()
            sleepGuard.end()
            self.mic = nil
            self.system = nil
            self.recorder = nil

            do {
                let stamp = DateFormatter()
                stamp.dateFormat = "yyyy-MM-dd HHmm"
                let wavURL = FileManager.default.homeDirectoryForCurrentUser
                    .appendingPathComponent("Documents/Aria/Grabaciones/\(stamp.string(from: since)).wav")
                let written = try recorder.write(to: wavURL)

                let calendarMeeting = MeetingCalendar.shared.meeting(overlapping: since, to: Date())

                state = .processing(step: "transcribiendo (\(Int(written.seconds)) s)")
                let transcription = try await transcribeWav(path: wavURL.path)
                let speakerResolution = SpeakerResolutionPipeline.resolve(
                    segments: transcription.segments,
                    calendarMeeting: calendarMeeting,
                    speakerEmbeddings: transcription.speakerEmbeddings,
                    voiceMemoryEnabled: AriaConfig.load().voiceMemoryEnabled
                )
                var segments = speakerResolution.segments
                if AriaConfig.load().transcriptPolish, !segments.isEmpty,
                   let polishBackend = ClaudeCLIClient.preferredBackend() {
                    state = .processing(step: "puliendo transcript")
                    if let polished = try? await TranscriptPolisher.polish(
                        segments: segments,
                        calendarMeeting: calendarMeeting,
                        client: polishBackend
                    ) {
                        segments = polished
                    }
                }
                let transcript = TranscriptFormatter.render(segments, pauses: pauses)
                let legacyNotes = NotesStore().rawMarkdown.trimmingCharacters(in: .whitespacesAndNewlines)
                let ownNotes = MeetingNotepadLogic.mergedOwnNotes(legacyNotes, ownNotesDraft)
                let speakerFallback = SpeakerNaming.orderedSpeakerLabels(in: segments).map(SpeakerNaming.cleanLabel)
                let participants = CalendarMeeting.participants(meeting: calendarMeeting, fallback: speakerFallback)

                let note: MeetingNote
                if let backend = ClaudeCLIClient.preferredBackend(), !transcript.isEmpty {
                    state = .processing(step: "generando nota con Claude")
                    let enhancer = MeetingEnhancer(client: backend)
                    let enhanced = try await enhancer.enhance(
                        transcript: transcript,
                        notes: ownNotes,
                        date: since,
                        durationSeconds: transcription.durationSeconds,
                        calendarMeeting: calendarMeeting,
                        visualContext: visualContextSummary
                    )
                    let bodyWithNotes = MeetingNotepadLogic.appendingOwnNotesSection(to: enhanced.markdown, ownNotes: ownNotes)
                    let body = PauseLogic.appendingPausesSection(to: bodyWithNotes, pauses: pauses)
                    note = MeetingNote(
                        title: calendarMeeting?.title ?? enhanced.title,
                        date: since,
                        participants: participants,
                        durationSeconds: transcription.durationSeconds,
                        body: body,
                        transcript: transcript,
                        companies: calendarMeeting?.companies ?? [],
                        pauses: pauses
                    )
                } else {
                    let timeFormatter = DateFormatter()
                    timeFormatter.dateFormat = "HH:mm"
                    let bodyWithNotes = MeetingNotepadLogic.appendingOwnNotesSection(
                        to: "## Transcript\n\(transcript.isEmpty ? "_(sin voz detectada)_" : transcript)",
                        ownNotes: ownNotes
                    )
                    let body = PauseLogic.appendingPausesSection(to: bodyWithNotes, pauses: pauses)
                    note = MeetingNote(
                        title: calendarMeeting?.title ?? "Reunion \(timeFormatter.string(from: since)) (sin enhance)",
                        date: since,
                        participants: participants,
                        durationSeconds: transcription.durationSeconds,
                        body: body,
                        transcript: nil,
                        companies: calendarMeeting?.companies ?? [],
                        pauses: pauses
                    )
                }
                let url = try ObsidianWriter().write(note)
                let keepAudio = AriaConfig.load().keepAudio
                if !keepAudio {
                    try? FileManager.default.removeItem(at: wavURL)
                }
                var savedVisualImagePaths: [(elapsedSeconds: Double, ocrText: String, imagePath: String)] = []
                if !visualRecords.isEmpty {
                    let (stem, capturesDir) = VisualContextStorage.capturesDirectory(forNoteAt: url)
                    do {
                        try VisualContextStorage.writeImages(
                            zip(visualRecords, pendingVisualCaptures).map { ($0.imageFileName, $1.jpegData) },
                            toDirectory: capturesDir
                        )
                        try VisualContextStorage.appendSection(noteStem: stem, captures: visualRecords, toNoteAt: url)
                        savedVisualImagePaths = visualRecords.map {
                            (elapsedSeconds: $0.elapsedSeconds, ocrText: $0.ocrText, imagePath: capturesDir.appendingPathComponent($0.imageFileName).path)
                        }
                    } catch {
                        print("[contexto visual] no se pudieron guardar las capturas: \(error.localizedDescription)")
                    }
                }
                if let store = try? MeetingStore(),
                   let meetingID = try? store.saveMeeting(
                        date: since,
                        title: note.title,
                        durationSeconds: transcription.durationSeconds,
                        notePath: url.path,
                        wavPath: keepAudio ? wavURL.path : nil,
                        segments: segments,
                        quickNotes: NotesStore().all(),
                        ownNotes: ownNotes,
                        pauses: pauses
                   ) {
                    try? store.insertVisualCaptures(savedVisualImagePaths, meetingID: meetingID)
                    try? store.saveSpeakerEmbeddings(speakerResolution.embeddings, meetingID: meetingID)
                }
                try? NotesStore().clear()
                state = .done(noteURL: url)
            } catch {
                state = .failed(error.localizedDescription)
            }
        }
    }
}

struct NotesWindowView: View {
    @State private var draft = ""
    @State private var notes: [QuickNote] = NotesStore().all()
    @State private var errorMessage = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Notas de la reunión en curso — se funden en la nota al generarla y el notepad queda limpio.")
                .font(.caption)
                .foregroundStyle(.secondary)
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 4) {
                        if notes.isEmpty {
                            Text("Sin notas todavía. Escribe abajo y presiona Enter.")
                                .foregroundStyle(.secondary)
                        }
                        ForEach(Array(notes.enumerated()), id: \.offset) { _, note in
                            Text(note.timestamp.isEmpty ? "• \(note.text)" : "• [\(note.timestamp)] \(note.text)")
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .textSelection(.enabled)
                        }
                        Color.clear.frame(height: 1).id("bottom")
                    }
                }
                .onChange(of: notes.count) {
                    proxy.scrollTo("bottom", anchor: .bottom)
                }
            }
            if !errorMessage.isEmpty {
                Text(errorMessage).font(.caption).foregroundStyle(.red)
            }
            HStack {
                TextField("Escribe una nota y Enter…", text: $draft)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit(addNote)
                Button("Añadir", action: addNote)
                    .disabled(draft.trimmingCharacters(in: .whitespaces).isEmpty)
                Button("Limpiar") {
                    try? NotesStore().clear()
                    notes = []
                }
                .disabled(notes.isEmpty)
            }
        }
        .padding()
        .frame(minWidth: 440, minHeight: 300)
        .onAppear { notes = NotesStore().all() }
    }

    private func addNote() {
        let text = draft.trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty else { return }
        do {
            try NotesStore().append(text)
            notes = NotesStore().all()
            draft = ""
            errorMessage = ""
        } catch {
            errorMessage = "No se pudo guardar: \(error.localizedDescription)"
        }
    }
}

struct ChatWindowView: View {
    @State private var question = ""
    @State private var conversation = ""
    @State private var busy = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ScrollViewReader { proxy in
                ScrollView {
                    Text(conversation.isEmpty ? "Pregunta lo que quieras sobre tus reuniones grabadas.\nEj.: ¿qué prometí esta semana?" : conversation)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .textSelection(.enabled)
                        .foregroundStyle(conversation.isEmpty ? .secondary : .primary)
                        .id("bottom")
                }
                .onChange(of: conversation) {
                    proxy.scrollTo("bottom", anchor: .bottom)
                }
            }
            HStack {
                TextField("¿Qué prometí esta semana?", text: $question)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit(send)
                Button(busy ? "Pensando…" : "Preguntar", action: send)
                    .disabled(busy || question.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding()
        .frame(minWidth: 480, minHeight: 340)
    }

    private func send() {
        let asked = question.trimmingCharacters(in: .whitespaces)
        guard !asked.isEmpty, !busy else { return }
        busy = true
        question = ""
        conversation += (conversation.isEmpty ? "" : "\n\n") + "🧑 \(asked)\n\n"
        Task {
            do {
                _ = try await MeetingChat.answer(question: asked) { chunk in
                    Task { @MainActor in conversation += chunk }
                }
            } catch {
                conversation += "[error] \(error.localizedDescription)"
            }
            busy = false
        }
    }
}

struct AriaMenuView: View {
    @ObservedObject var controller: RecordingController
    @Environment(\.openWindow) private var openWindow

    private var recordButtonTitle: String {
        if let meeting = controller.meetingNow, controller.callDetected {
            return "Grabar \"\(meeting.title)\""
        }
        return controller.callDetected ? "Grabar esta llamada" : "Grabar reunión"
    }

    private var cardMeeting: CalendarMeeting? { controller.meetingNow ?? controller.upcomingMeeting }

    var body: some View {
        if let meeting = cardMeeting {
            let card = MeetingCardBuilder.build(
                meeting: meeting,
                at: Date(),
                nativeAppInstalled: meeting.videoLink.map(MeetingJoinLink.isNativeAppAvailable(forVideoLink:)) ?? false
            )
            MeetingCardView(
                viewModel: card,
                onJoin: { if let url = card.joinURL { NSWorkspace.shared.open(url) } },
                onJoinAndTakeNotes: {
                    if let url = card.joinURL { NSWorkspace.shared.open(url) }
                    controller.start()
                }
            )
            Divider()
        }
        Button("Abrir NotarIA") { MainWindowBridge.shared.triggerOpen() }
            .keyboardShortcut("a", modifiers: [.command, .shift])
        Divider()
        switch controller.state {
        case .idle:
            if controller.callDetected {
                Label("Parece que estás en una llamada", systemImage: "phone.fill")
            }
            Button(recordButtonTitle) { controller.start() }
            Button {
                controller.start(dictationOnly: true)
            } label: {
                Label("Modo dictado (solo mic)", systemImage: "mic")
            }
        case .recording(let since):
            if controller.isPaused {
                Label("En pausa\(controller.isDictation ? " (modo dictado)" : "") — iniciada \(since.formatted(date: .omitted, time: .shortened))", systemImage: "pause.circle")
            } else {
                Label("Grabando\(controller.isDictation ? " (modo dictado)" : "") desde \(since.formatted(date: .omitted, time: .shortened))", systemImage: "record.circle")
            }
            Button(controller.isPaused ? "Reanudar grabación" : "Pausar grabación") {
                if controller.isPaused { controller.resumeRecording() } else { controller.pauseRecording() }
            }
            Button("Detener y generar nota") { controller.stopAndGenerate() }
        case .processing(let step):
            Text("Procesando: \(step)…")
        case .done(let noteURL):
            Text("Nota lista")
            Button("Abrir nota") { NSWorkspace.shared.open(noteURL) }
            Button("Grabar otra reunión") { controller.start() }
        case .failed(let message):
            Text("Error: \(message)").lineLimit(3)
            Button("Reintentar") {
                controller.state = .idle
                controller.start()
            }
        }
        Button {
            NSApp.activate(ignoringOtherApps: true)
            openWindow(id: "aria-notes")
        } label: {
            Label("Notas rápidas…", systemImage: "note.text")
        }
        Divider()
        if controller.alwaysOn {
            Label("Always-on activo: NotarIA está escuchando llamadas", systemImage: "ear")
        }
        Button(controller.alwaysOn ? "Pausar always-on" : "Activar always-on…") {
            controller.toggleAlwaysOn()
        }
        if let recents = try? MeetingStore().recentMeetings(limit: 5), !recents.isEmpty {
            Divider()
            Menu("Recientes") {
                ForEach(recents, id: \.id) { record in
                    Button("\(record.date.formatted(date: .abbreviated, time: .shortened)) — \(record.title)") {
                        NSWorkspace.shared.open(URL(fileURLWithPath: record.notePath))
                    }
                }
            }
            Button {
                NSApp.activate(ignoringOtherApps: true)
                openWindow(id: "aria-chat")
            } label: {
                Label("Preguntar a tus reuniones…", systemImage: "bubble.left.and.bubble.right")
            }
        }
        Divider()
        Button("Salir de NotarIA") { NSApp.terminate(nil) }
    }
}

struct AriaMenuBarApp: App {
    @StateObject private var controller = RecordingController()

    init() {
        NSApplication.shared.setActivationPolicy(.accessory)
        MainWindowBridge.shared.activate()
    }

    var body: some Scene {
        MenuBarExtra {
            AriaMenuView(controller: controller)
        } label: {
            MenuBarLabelContent(controller: controller, icon: menuBarIcon)
        }
        Window("NotarIA", id: "aria-main") {
            MainWindowView(controller: controller)
        }
        .defaultSize(width: 900, height: 600)
        Window("Chat con tus reuniones", id: "aria-chat") {
            ChatWindowView()
        }
        .defaultSize(width: 540, height: 400)
        Window("Notas rápidas", id: "aria-notes") {
            NotesWindowView()
        }
        .defaultSize(width: 460, height: 320)
    }

    private var menuBarIcon: MenuBarIconKind {
        switch controller.state {
        case .recording: return .symbol("record.circle.fill")
        case .processing: return .symbol("waveform.circle")
        case .failed: return .symbol("exclamationmark.circle")
        default:
            if controller.callDetected { return .symbol("phone.badge.waveform") }
            return controller.alwaysOn ? .symbol("ear.badge.waveform") : .brand
        }
    }
}

enum MenuBarIconKind {
    /// Glifo de marca NotarIA (sello + onda), estado de reposo.
    case brand
    /// SF Symbol para estados funcionales (grabando, procesando, error, etc.).
    case symbol(String)
}

struct MenuBarLabelContent: View {
    @ObservedObject var controller: RecordingController
    let icon: MenuBarIconKind
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Group {
            if case .recording = controller.state {
                HStack(spacing: 3) {
                    Image(systemName: controller.isPaused ? "pause.circle.fill" : "record.circle.fill")
                    Text(controller.isPaused ? "PAUSA \(controller.recordingElapsed)" : "REC \(controller.recordingElapsed)")
                }
            } else if case .idle = controller.state,
                      AriaConfig.load().showMenuBarTitle,
                      let title = MenuBarMeetingTitle.text(meetingNow: controller.meetingNow, upcoming: controller.upcomingMeeting, at: Date()) {
                HStack(spacing: 3) {
                    Image(systemName: "calendar.badge.clock")
                    Text(title).monospacedDigit()
                }
            } else {
                switch icon {
                case .brand:
                    if let brandImage = BrandAssets.menuBarImage() {
                        Image(nsImage: brandImage)
                    } else {
                        Image(systemName: "waveform")
                    }
                case .symbol(let name):
                    Image(systemName: name)
                }
            }
        }
        .onAppear {
            MainWindowBridge.shared.openAction = { openWindow(id: "aria-main") }
        }
    }
}
