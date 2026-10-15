import AppKit
import AVFoundation
import CoreGraphics
import EventKit
import SwiftUI

enum MainSidebarItem: String, CaseIterable, Identifiable {
    case hoy = "Hoy"
    case historial = "Historial"
    case chat = "Chat"
    case recipes = "Recipes"
    case ajustes = "Ajustes"

    var id: String { rawValue }

    var symbol: String {
        switch self {
        case .hoy: return "calendar"
        case .historial: return "clock.arrow.circlepath"
        case .chat: return "bubble.left.and.bubble.right"
        case .recipes: return "sparkles"
        case .ajustes: return "gearshape"
        }
    }
}

struct MainWindowView: View {
    @ObservedObject var controller: RecordingController
    @State private var selection: MainSidebarItem? = .historial

    var body: some View {
        NavigationSplitView {
            List(MainSidebarItem.allCases, selection: $selection) { item in
                Label(item.rawValue, systemImage: item.symbol).tag(item)
            }
            .navigationTitle("NotarIA")
        } detail: {
            switch selection {
            case .hoy:
                TodaySectionView(controller: controller)
            case .historial, nil:
                HistorialView()
            case .chat:
                ChatSectionView()
            case .recipes:
                RecipesSectionView()
            case .ajustes:
                SettingsSectionView()
            }
        }
        .frame(minWidth: 860, minHeight: 560)
        .tint(BrandColor.sello)
        .onDisappear { NSApp.setActivationPolicy(.accessory) }
        .onReceive(NotificationCenter.default.publisher(for: MainWindowBridge.focusHoyNotificationName)) { _ in
            selection = .hoy
        }
    }
}

struct AgendaMeetingSelection: Identifiable {
    let id: String
    let meeting: CalendarMeeting
    let matchedMeetingID: Int64?

    init(meeting: CalendarMeeting, matchedMeetingID: Int64?) {
        self.meeting = meeting
        self.matchedMeetingID = matchedMeetingID
        self.id = meeting.eventIdentifier ?? "\(meeting.start.timeIntervalSince1970)-\(meeting.title)"
    }
}

struct TodaySectionView: View {
    @ObservedObject var controller: RecordingController
    @State private var todayMeetings: [CalendarMeeting] = []
    @State private var recentRecords: [MeetingRecord] = []
    @State private var selectedAgendaItem: AgendaMeetingSelection?
    @State private var calendarStatus: EKAuthorizationStatus = MeetingCalendar.authorizationStatus
    @State private var isRequestingCalendarAccess = false

    private static let refreshInterval: TimeInterval = 180

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Text("Hoy").font(.largeTitle).bold()

                if let message = CalendarAccessPolicy.message(for: calendarStatus) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(message).foregroundStyle(.secondary)
                        if let actionLabel = CalendarAccessPolicy.actionLabel(for: calendarStatus) {
                            Button(actionLabel) { handleCalendarAccessAction() }
                                .disabled(isRequestingCalendarAccess)
                        }
                    }
                }

                if CalendarAccessPolicy.hasFullAccess(calendarStatus), !todayMeetings.isEmpty {
                    Text("Agenda del día").font(.headline).foregroundStyle(.secondary)
                    VStack(alignment: .leading, spacing: 10) {
                        ForEach(Array(todayMeetings.enumerated()), id: \.offset) { _, meeting in
                            let matched = MeetingRecordingLinker.match(meeting: meeting, in: recentRecords)
                            HStack(spacing: 12) {
                                VStack(alignment: .leading, spacing: 2) {
                                    HStack(spacing: 4) {
                                        Text(meeting.title)
                                        if hasVideoLink(meeting) {
                                            Image(systemName: "video.fill").foregroundStyle(.blue).font(.caption)
                                        }
                                        if matched != nil {
                                            Label("Grabada", systemImage: "waveform.circle.fill")
                                                .font(.caption2)
                                                .foregroundStyle(BrandColor.sello)
                                        }
                                    }
                                    .font(.body)
                                    HStack(spacing: 2) {
                                        Text(meeting.start.formatted(date: .omitted, time: .shortened))
                                        Text("-")
                                        Text(meeting.end.formatted(date: .omitted, time: .shortened))
                                    }
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    if !meeting.attendees.isEmpty {
                                        Text(meeting.attendees.joined(separator: ", "))
                                            .font(.caption2)
                                            .foregroundStyle(.secondary)
                                            .lineLimit(1)
                                    }
                                }
                                Spacer()
                                Button("Brief") {
                                    Task {
                                        await prepareBrief(for: meeting)
                                    }
                                }
                                .font(.caption)
                                .buttonStyle(.bordered)
                            }
                            .padding(8)
                            .background(Color(.controlBackgroundColor))
                            .cornerRadius(6)
                            .contentShape(Rectangle())
                            .onTapGesture {
                                selectedAgendaItem = AgendaMeetingSelection(meeting: meeting, matchedMeetingID: matched?.id)
                            }
                        }
                    }
                } else if CalendarAccessPolicy.shouldShowEmptyAgenda(status: calendarStatus, meetingsCount: todayMeetings.count) {
                    Text("Sin reuniones en el calendario hoy.").foregroundStyle(.secondary)
                }

                Divider()

                if let meeting = controller.meetingNow {
                    Label("Grabando: \(meeting.title)", systemImage: "calendar")
                } else if let next = controller.upcomingMeeting {
                    Label(
                        "Próxima: \(next.title) · \(next.start.formatted(date: .omitted, time: .shortened)) (\(next.countdown(at: Date())))",
                        systemImage: "calendar.badge.clock"
                    )
                }

                if controller.callDetected {
                    Label("Parece que estás en una llamada ahora.", systemImage: "phone.badge.waveform")
                }

                Divider()

                switch controller.state {
                case .idle:
                    Button("Grabar reunión") { controller.start() }
                case .recording(let since):
                    Text("Grabando desde \(since.formatted(date: .omitted, time: .shortened)) · \(controller.recordingElapsed)")
                    Button("Detener y generar nota") { controller.stopAndGenerate() }
                case .processing(let step):
                    Text("Procesando: \(step)…")
                case .done(let url):
                    Button("Abrir última nota") { NSWorkspace.shared.open(url) }
                case .failed(let message):
                    Text("Error: \(message)").foregroundStyle(.red)
                }

                if controller.notepad.isActive {
                    Divider()
                    MeetingNotepadView(notepad: controller.notepad)
                }

                Spacer()
            }
            .padding()
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .navigationTitle("Hoy")
        .task {
            refresh()
        }
        .task {
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: UInt64(Self.refreshInterval * 1_000_000_000))
                refresh()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            refresh()
        }
        .sheet(item: $selectedAgendaItem) { item in
            NavigationStack {
                Group {
                    if let matchedMeetingID = item.matchedMeetingID {
                        MeetingDetailView(meetingID: matchedMeetingID)
                    } else {
                        NotRecordedMeetingDetailView(meeting: item.meeting, controller: controller)
                    }
                }
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cerrar") { selectedAgendaItem = nil }
                    }
                }
            }
            .frame(minWidth: 760, minHeight: 560)
        }
    }

    private func refresh() {
        calendarStatus = MeetingCalendar.authorizationStatus
        loadTodayMeetings()
        recentRecords = (try? MeetingStore().recentMeetings(limit: 200)) ?? []
    }

    private func handleCalendarAccessAction() {
        switch CalendarAccessPolicy.action(for: calendarStatus) {
        case .none:
            break
        case .request:
            isRequestingCalendarAccess = true
            Task {
                _ = try? await MeetingCalendar.shared.requestAccess()
                isRequestingCalendarAccess = false
                refresh()
            }
        case .openSystemSettings:
            if let url = URL(string: CalendarAccessPolicy.systemSettingsURL) {
                NSWorkspace.shared.open(url)
            }
        }
    }

    private func loadTodayMeetings() {
        let calendar = MeetingCalendar.shared
        let today = Date()
        let startOfDay = Calendar.current.startOfDay(for: today)
        let endOfDay = Calendar.current.date(byAdding: .day, value: 1, to: startOfDay)!
        todayMeetings = calendar.meetings(from: startOfDay, to: endOfDay)
            .sorted { $0.start < $1.start }
    }

    private func hasVideoLink(_ meeting: CalendarMeeting) -> Bool {
        return !(meeting.videoLink?.isEmpty ?? true)
    }

    private func prepareBrief(for meeting: CalendarMeeting) async {
        await MeetingBriefAction.copyToClipboard(attendees: meeting.attendees, title: meeting.title)
    }
}

enum MeetingBriefAction {
    static func copyToClipboard(attendees: [String], title: String) async {
        do {
            let answer = try await MeetingBrief.generate(attendees: attendees, title: title)
            let pasteboard = NSPasteboard.general
            pasteboard.clearContents()
            pasteboard.setString(answer.text, forType: .string)
        } catch {
            NSLog("Error preparando brief: \(error)")
        }
    }
}

struct NotRecordedMeetingDetailView: View {
    let meeting: CalendarMeeting
    @ObservedObject var controller: RecordingController
    @State private var preparingBrief = false

    private var joinURL: URL? {
        meeting.videoLink.flatMap {
            MeetingJoinLink.resolve(videoLink: $0, nativeAppInstalled: MeetingJoinLink.isNativeAppAvailable(forVideoLink: $0))
        }
    }

    private var canOfferJoin: Bool {
        joinURL != nil && meeting.end > Date() && !meeting.promptExcluded
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Text(meeting.title).font(.title2).bold()

                HStack(spacing: 2) {
                    Text(meeting.start.formatted(date: .complete, time: .shortened))
                    Text("–")
                    Text(meeting.end.formatted(date: .omitted, time: .shortened))
                }
                .font(.subheadline)
                .foregroundStyle(.secondary)

                if let platform = MeetingPromptDecider.platformLabel(videoLink: meeting.videoLink) {
                    Label(platform, systemImage: "video")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                if !meeting.attendees.isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Asistentes").font(.headline)
                        Text(meeting.attendees.joined(separator: ", "))
                            .textSelection(.enabled)
                    }
                }

                Divider()

                Label("No se grabó esta reunión", systemImage: "waveform.slash")
                    .foregroundStyle(.secondary)

                HStack(spacing: 10) {
                    Button(preparingBrief ? "Preparando…" : "Brief") {
                        preparingBrief = true
                        Task {
                            await MeetingBriefAction.copyToClipboard(attendees: meeting.attendees, title: meeting.title)
                            preparingBrief = false
                        }
                    }
                    .disabled(preparingBrief)
                    if canOfferJoin, let joinURL {
                        Button("Unirse y tomar notas") {
                            NSWorkspace.shared.open(joinURL)
                            controller.start()
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(BrandColor.sello)
                    }
                }

                Spacer()
            }
            .padding()
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .navigationTitle(meeting.title)
    }
}

@MainActor
final class HistoryListModel: ObservableObject {
    @Published var query = ""
    @Published var sourceFilter: MeetingSourceFilter = .all
    @Published var selectedID: Int64?
    @Published private(set) var sections: [MeetingDaySection] = []
    @Published private(set) var searchResults: [MeetingRecord] = []
    @Published private(set) var errorMessage: String?

    func reload() {
        guard let store = try? MeetingStore() else {
            errorMessage = "No se pudo abrir el historial de reuniones."
            return
        }
        let all = (try? store.recentMeetings(limit: 10_000)) ?? []
        errorMessage = nil
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            sections = MeetingHistoryViewModel.grouped(MeetingHistoryViewModel.filtered(all, source: sourceFilter))
            searchResults = []
        } else {
            let hits = (try? MeetingSearch.search(trimmed, store: store, limit: 50)) ?? []
            let order = MeetingHistoryViewModel.meetingIDOrder(fromHits: hits)
            searchResults = MeetingHistoryViewModel.visibleRecords(all: all, source: sourceFilter, searchHitsOrder: order)
            sections = []
        }
    }
}

struct HistorialView: View {
    @StateObject private var model = HistoryListModel()

    var body: some View {
        NavigationSplitView {
            VStack(spacing: 0) {
                VStack(spacing: 8) {
                    TextField("Buscar en reuniones…", text: $model.query)
                        .textFieldStyle(.roundedBorder)
                    Picker("Origen", selection: $model.sourceFilter) {
                        ForEach(MeetingSourceFilter.allCases) { filter in
                            Text(filter.label).tag(filter)
                        }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                }
                .padding(10)
                if let errorMessage = model.errorMessage {
                    Text(errorMessage).foregroundStyle(.red).font(.caption).padding(.horizontal, 10)
                }
                List(selection: $model.selectedID) {
                    if model.query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        ForEach(model.sections) { section in
                            Section(Self.dayLabel(section.day)) {
                                ForEach(section.records) { record in
                                    MeetingRow(record: record).tag(record.id)
                                }
                            }
                        }
                    } else if model.searchResults.isEmpty {
                        Text("Sin resultados.").foregroundStyle(.secondary)
                    } else {
                        ForEach(model.searchResults) { record in
                            MeetingRow(record: record).tag(record.id)
                        }
                    }
                }
                .listStyle(.sidebar)
            }
            .navigationTitle("Historial")
            .task { model.reload() }
            .onChange(of: model.query) { model.reload() }
            .onChange(of: model.sourceFilter) { model.reload() }
        } detail: {
            if let id = model.selectedID {
                MeetingDetailView(meetingID: id)
            } else {
                Text("Selecciona una reunión.").foregroundStyle(.secondary)
            }
        }
    }

    static func dayLabel(_ day: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .full
        return formatter.string(from: day).capitalized
    }
}

struct MeetingRow: View {
    let record: MeetingRecord

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 6) {
                Text(record.title)
                if record.source != "aria" {
                    Text(record.source.uppercased())
                        .font(.caption2)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1)
                        .background(Color.secondary.opacity(0.15))
                        .clipShape(Capsule())
                }
            }
            Text("\(record.date.formatted(date: .abbreviated, time: .shortened)) · \(Self.duration(record.durationSeconds))")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    static func duration(_ seconds: Double) -> String {
        String(format: "%d:%02d", Int(seconds) / 60, Int(seconds) % 60)
    }
}

struct PausesSummaryView: View {
    let recordedSeconds: Double
    let pauses: [PauseInterval]

    private var totalPaused: Double { PauseLogic.totalPausedSeconds(pauses) }
    private var wallClock: Double { PauseLogic.wallClockSeconds(recordedSeconds: recordedSeconds, pauses: pauses) }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(
                "Duración grabada real: \(MeetingRow.duration(recordedSeconds))"
                + " · Reunión completa: \(MeetingRow.duration(wallClock))"
                + " (\(pauses.count) pausa\(pauses.count == 1 ? "" : "s"), \(MeetingRow.duration(totalPaused)) en pausa)"
            )
            .font(.caption)
            .foregroundStyle(.secondary)
            ForEach(Array(pauses.enumerated()), id: \.offset) { _, pause in
                Text("⏸ \(PauseLogic.rangeLabel(for: pause))")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

struct MeetingDetailView: View {
    let meetingID: Int64
    @State private var record: MeetingRecord?
    @State private var noteMarkdown = ""
    @State private var segments: [TranscriptSegment] = []
    @State private var pauses: [PauseInterval] = []
    @State private var errorMessage: String?
    @State private var shareMenuOpen = false
    @State private var editingSegmentIndex: Int?
    @State private var editingSegmentText = ""
    @State private var renamingSpeaker: String?
    @State private var newSpeakerName = ""
    @State private var showRegenerateAlert = false
    @State private var visualCaptureCount = 0
    @Environment(\.openWindow) private var openWindow

    private var summaryMarkdown: String { MeetingNoteMarkdown.summaryOnly(noteMarkdown) }

    var body: some View {
        Group {
            if let record {
                VStack(alignment: .leading, spacing: 12) {
                    header(record: record)
                    GeometryReader { proxy in
                        if MeetingDetailLayout.isWide(width: proxy.size.width) {
                            HStack(alignment: .top, spacing: 16) {
                                summaryPane().frame(maxWidth: .infinity, maxHeight: .infinity)
                                Divider()
                                transcriptPane().frame(maxWidth: .infinity, maxHeight: .infinity)
                            }
                        } else {
                            VStack(alignment: .leading, spacing: 16) {
                                summaryPane().frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
                                Divider()
                                transcriptPane().frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
                            }
                        }
                    }
                }
                .padding()
            } else if let errorMessage {
                Text(errorMessage).foregroundStyle(.red).padding()
            } else {
                ProgressView().padding()
            }
        }
        .navigationTitle(record?.title ?? "Reunión")
        .alert("Regenerar nota", isPresented: $showRegenerateAlert) {
            Button("Cancelar", role: .cancel) {}
            Button("Regenerar") {
                regenerateNote()
            }
        } message: {
            Text("Esto generará una nueva nota con los cambios realizados en el transcript.")
        }
        .task(id: meetingID) { load() }
    }

    @ViewBuilder
    private func header(record: MeetingRecord) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(record.title).font(.title2).bold()
                Spacer()
                Menu {
                    Button("Copiar como Markdown") {
                        copyAsMarkdown()
                    }
                    Button("Copiar con formato") {
                        copyAsRich()
                    }
                    Button("Exportar a PDF") {
                        exportPDF()
                    }
                    Divider()
                    Button("Enviar a Slack") {
                        sendToSlack()
                    }
                    Button("Crear en Notion") {
                        sendToNotion()
                    }
                } label: {
                    Label("Compartir", systemImage: "square.and.arrow.up")
                }
                Button("Abrir en Obsidian") {
                    NSWorkspace.shared.open(URL(fileURLWithPath: record.notePath))
                }
                Button("Mostrar en Finder") {
                    NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: record.notePath)])
                }
            }
            Text(record.date.formatted(date: .complete, time: .shortened))
                .font(.caption)
                .foregroundStyle(.secondary)
            if !pauses.isEmpty {
                PausesSummaryView(recordedSeconds: record.durationSeconds, pauses: pauses)
            }
        }
    }

    @ViewBuilder
    private func summaryPane() -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("Resumen").font(.headline).foregroundStyle(.secondary)
                if let attributed = try? AttributedString(
                    markdown: summaryMarkdown,
                    options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)
                ) {
                    Text(attributed).textSelection(.enabled)
                } else {
                    Text(summaryMarkdown).textSelection(.enabled)
                }

                Divider()
                OwnNotesSectionView(meetingID: meetingID)

                if visualCaptureCount > 0 {
                    Divider()
                    HStack {
                        Label("Contexto visual: \(visualCaptureCount) captura(s)", systemImage: "eye")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Spacer()
                        Button("Borrar capturas") { deleteVisualCaptures() }
                            .font(.caption)
                    }
                }

                if !segments.isEmpty {
                    Divider()
                    ParticipantsPanelView(meetingID: meetingID) {
                        segments = (try? MeetingStore().segments(meetingID: meetingID)) ?? segments
                    }
                }
            }
            .padding(.trailing, 4)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    @ViewBuilder
    private func transcriptPane() -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Transcript").font(.headline)
                Spacer()
                if !segments.isEmpty {
                    Button("Abrir transcripción en ventana") {
                        openWindow(id: "aria-transcript", value: meetingID)
                    }
                    .font(.caption)
                    Button("Regenerar nota") {
                        showRegenerateAlert = true
                    }
                    .font(.caption)
                }
            }
            if segments.isEmpty {
                Text("Sin transcripción (reunión no grabada o sin voz detectada).")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(
                            Array(TranscriptFormatter.timeline(segments: segments, pauses: pauses).enumerated()),
                            id: \.offset
                        ) { _, item in
                            switch item {
                            case .segment(let index, let segment):
                                segmentRow(index: index, segment: segment)
                            case .pause(let pause):
                                Text("⏸ \(PauseLogic.rangeLabel(for: pause))")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                                    .padding(.vertical, 2)
                            }
                        }
                        if let speaker = renamingSpeaker {
                            renameSpeakerPanel(speaker: speaker)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
    }

    @ViewBuilder
    private func segmentRow(index: Int, segment: TranscriptSegment) -> some View {
        if editingSegmentIndex == index {
            VStack(alignment: .leading, spacing: 4) {
                TextField("Texto", text: $editingSegmentText)
                    .textFieldStyle(.roundedBorder)
                HStack {
                    Button("Guardar") {
                        saveSegmentEdit(index: index)
                    }
                    Button("Cancelar") {
                        editingSegmentIndex = nil
                    }
                }
                .font(.caption)
            }
        } else {
            HStack(spacing: 8) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("[\(Self.timestamp(segment.start))] \(segment.speaker):")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(segment.text)
                        .textSelection(.enabled)
                }
                Spacer()
                Button("Editar") {
                    editingSegmentIndex = index
                    editingSegmentText = segment.text
                }
                .font(.caption)
                Button("Renombrar") {
                    renamingSpeaker = segment.speaker
                    newSpeakerName = segment.speaker
                }
                .font(.caption)
            }
            .padding(8)
            .background(Color(.controlBackgroundColor))
            .cornerRadius(4)
        }
    }

    @ViewBuilder
    private func renameSpeakerPanel(speaker: String) -> some View {
        Divider()
        VStack(alignment: .leading, spacing: 8) {
            Text("Renombrar '\(speaker)' a:").font(.caption)
            TextField("Nuevo nombre", text: $newSpeakerName)
                .textFieldStyle(.roundedBorder)
            HStack {
                Button("Renombrar") {
                    saveSpeakerRename(oldSpeaker: speaker)
                }
                Button("Cancelar") {
                    renamingSpeaker = nil
                }
            }
            .font(.caption)
        }
    }

    private func load() {
        do {
            let store = try MeetingStore()
            guard let found = try store.recentMeetings(limit: 10_000).first(where: { $0.id == meetingID }) else {
                errorMessage = "No se encontró la reunión en el historial."
                return
            }
            record = found
            segments = try store.segments(meetingID: meetingID)
            pauses = try store.pauses(meetingID: meetingID)
            noteMarkdown = (try? String(contentsOf: URL(fileURLWithPath: found.notePath), encoding: .utf8))
                ?? "_(no se pudo leer la nota en \(found.notePath))_"
            visualCaptureCount = (try? store.visualCaptures(meetingID: meetingID).count) ?? 0
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func deleteVisualCaptures() {
        do {
            let store = try MeetingStore()
            let paths = try store.deleteVisualCaptures(meetingID: meetingID)
            for path in paths {
                try? FileManager.default.removeItem(atPath: path)
            }
            if let first = paths.first {
                try? FileManager.default.removeItem(at: URL(fileURLWithPath: first).deletingLastPathComponent())
            }
            visualCaptureCount = 0
        } catch {
            errorMessage = "Error borrando capturas: \(error.localizedDescription)"
        }
    }

    private func saveSegmentEdit(index: Int) {
        do {
            let store = try MeetingStore()
            try store.updateSegmentText(meetingID: meetingID, segmentIndex: index, newText: editingSegmentText)
            segments = try store.segments(meetingID: meetingID)
            editingSegmentIndex = nil
        } catch {
            errorMessage = "Error guardando: \(error.localizedDescription)"
        }
    }

    private func saveSpeakerRename(oldSpeaker: String) {
        guard !newSpeakerName.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        do {
            let store = try MeetingStore()
            try store.renameSpeaker(meetingID: meetingID, oldSpeaker: oldSpeaker, newSpeaker: newSpeakerName)
            for i in segments.indices {
                if segments[i].speaker == oldSpeaker {
                    segments[i].speaker = newSpeakerName
                }
            }
            renamingSpeaker = nil
        } catch {
            errorMessage = "Error renombrando: \(error.localizedDescription)"
        }
    }

    private func regenerateNote() {
        guard let record = record else { return }
        let noteURL = URL(fileURLWithPath: record.notePath)
        let parentURL = noteURL.deletingLastPathComponent()
        try? FileManager.default.removeItem(at: noteURL)
        NSWorkspace.shared.open(parentURL)
    }

    static func timestamp(_ seconds: Double) -> String {
        String(format: "%d:%02d", Int(seconds) / 60, Int(seconds) % 60)
    }

    private func copyAsMarkdown() {
        let exporter = ClipboardExporter(title: record?.title ?? "", noteMarkdown: noteMarkdown)
        do {
            try exporter.copyAsMarkdown()
            errorMessage = nil
        } catch {
            errorMessage = "Error al copiar: \(error.localizedDescription)"
        }
    }

    private func copyAsRich() {
        let exporter = ClipboardExporter(title: record?.title ?? "", noteMarkdown: noteMarkdown)
        do {
            try exporter.copyAsRich()
            errorMessage = nil
        } catch {
            errorMessage = "Error al copiar: \(error.localizedDescription)"
        }
    }

    private func exportPDF() {
        guard let record else { return }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.pdf]
        panel.nameFieldStringValue = "\(record.title).pdf"
        panel.begin { result in
            if result == .OK, let url = panel.url {
                do {
                    let exporter = PDFExporter(title: record.title, noteMarkdown: noteMarkdown, date: record.date)
                    try exporter.exportToFile(at: url)
                    errorMessage = nil
                } catch {
                    errorMessage = "Error al exportar PDF: \(error.localizedDescription)"
                }
            }
        }
    }

    private func sendToSlack() {
        guard let record else { return }
        guard let webhook = KeychainStore.slackWebhookURL(), let url = URL(string: webhook) else {
            errorMessage = "Slack no configurado en Ajustes"
            return
        }

        Task {
            do {
                let exporter = SlackExporter(title: record.title, noteMarkdown: noteMarkdown, date: record.date, webhookURL: url)
                try await exporter.send()
                await MainActor.run {
                    errorMessage = nil
                }
            } catch {
                await MainActor.run {
                    errorMessage = "Error al enviar a Slack: \(error.localizedDescription)"
                }
            }
        }
    }

    private func sendToNotion() {
        guard let record else { return }
        let token = KeychainCLI.read(service: "aria-notion", account: "token")
        let config = AriaConfig.load()

        guard !config.notionDatabaseID.isEmpty, let token else {
            errorMessage = "Notion no configurado en Ajustes o token no guardado en Keychain"
            return
        }

        Task {
            do {
                let exporter = NotionExporter(title: record.title, noteMarkdown: noteMarkdown, date: record.date, token: token, parentDatabaseID: config.notionDatabaseID)
                try await exporter.send()
                await MainActor.run {
                    errorMessage = nil
                }
            } catch {
                await MainActor.run {
                    errorMessage = "Error al enviar a Notion: \(error.localizedDescription)"
                }
            }
        }
    }
}

@MainActor
final class ChatSessionModel: ObservableObject {
    @Published var turns: [ChatTurn] = []
    @Published var draft = ""
    @Published var busy = false

    func ask() {
        guard let question = ChatSessionLogic.trimmedQuestion(draft), !busy else { return }
        draft = ""
        busy = true
        turns = ChatSessionLogic.appendingQuestion(turns, question: question)
        let index = turns.count - 1
        Task {
            do {
                _ = try await MeetingChat.answer(question: question) { chunk in
                    Task { @MainActor in
                        self.turns = ChatSessionLogic.appendingChunk(self.turns, chunk: chunk, at: index)
                    }
                }
            } catch {
                turns = ChatSessionLogic.markError(turns, at: index, message: error.localizedDescription)
            }
            busy = false
        }
    }
}

struct ChatSectionView: View {
    @StateObject private var model = ChatSessionModel()

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        if model.turns.isEmpty {
                            Text("Pregunta lo que quieras sobre tus reuniones grabadas.\nEj.: ¿qué prometí esta semana?")
                                .foregroundStyle(.secondary)
                        }
                        ForEach(model.turns) { turn in
                            VStack(alignment: .leading, spacing: 4) {
                                Text("🧑 \(turn.question)").bold()
                                Text(turn.answer.isEmpty ? "…" : turn.answer)
                                    .foregroundStyle(turn.isError ? .red : .primary)
                                    .textSelection(.enabled)
                            }
                        }
                        Color.clear.frame(height: 1).id("bottom")
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .onChange(of: model.turns) { _, _ in proxy.scrollTo("bottom", anchor: .bottom) }
            }
            HStack {
                TextField("¿Qué prometí esta semana?", text: $model.draft)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit { model.ask() }
                Button(model.busy ? "Pensando…" : "Preguntar") { model.ask() }
                    .disabled(model.busy || model.draft.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding()
        .navigationTitle("Chat")
    }
}

struct SettingsSectionView: View {
    @State private var config = AriaConfig.load()
    @State private var micAuthStatus: AVAuthorizationStatus = Permissions.microphoneStatus()
    @State private var screenGranted = Permissions.screenRecordingGranted()
    @State private var calendarAuthStatus: EKAuthorizationStatus = MeetingCalendar.authorizationStatus
    @State private var savedMessage: String?
    @State private var slackWebhookInput = ""
    @State private var slackSavedMessage: String?
    @State private var loginItemEnabled = LoginItemManager.isEnabled
    @State private var loginItemMessage: String?
    @State private var calendarListings: [MeetingCalendar.CalendarListing] = []

    var body: some View {
        Form {
            Section("Inicio") {
                if LoginItemManager.isRunningFromAppBundle {
                    Toggle("Abrir NotarIA al iniciar sesión", isOn: Binding(
                        get: { loginItemEnabled },
                        set: { newValue in
                            loginItemEnabled = newValue
                            loginItemMessage = LoginItemManager.setEnabled(newValue)
                            if loginItemMessage != nil { loginItemEnabled = LoginItemManager.isEnabled }
                        }
                    ))
                } else {
                    Text("Abrir al iniciar sesión solo está disponible desde NotarIA.app instalada (ejecuta scripts/install-local.sh), no desde el binario de desarrollo.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Text(LoginItemManager.statusDescription).font(.caption).foregroundStyle(.secondary)
                if let loginItemMessage {
                    Text(loginItemMessage).font(.caption).foregroundStyle(.red)
                }
            }
            Section("Permisos") {
                permissionRow(
                    "Calendario",
                    statusLabel: CalendarAccessPolicy.settingsLabel(for: calendarAuthStatus),
                    actionLabel: CalendarAccessPolicy.actionLabel(for: calendarAuthStatus),
                    action: {
                        performAction(
                            CalendarAccessPolicy.action(for: calendarAuthStatus),
                            request: requestCalendarAccess,
                            settingsURL: CalendarAccessPolicy.systemSettingsURL
                        )
                    }
                )
                permissionRow(
                    "Micrófono",
                    statusLabel: MicrophonePermissionPolicy.statusLabel(micAuthStatus),
                    actionLabel: MicrophonePermissionPolicy.actionLabel(micAuthStatus),
                    action: {
                        performAction(
                            MicrophonePermissionPolicy.action(micAuthStatus),
                            request: requestMicAccess,
                            settingsURL: Permissions.micSettingsURL
                        )
                    }
                )
                permissionRow(
                    "Grabación de pantalla",
                    statusLabel: ScreenRecordingPermissionPolicy.statusLabel(granted: screenGranted),
                    actionLabel: ScreenRecordingPermissionPolicy.actionLabel(granted: screenGranted),
                    action: {
                        performAction(
                            ScreenRecordingPermissionPolicy.action(granted: screenGranted),
                            request: requestScreenAccess,
                            settingsURL: Permissions.screenSettingsURL
                        )
                    }
                )
            }
            Section("Calendario Google / Outlook") {
                Text("""
                Aria lee el calendario con EventKit, el mismo framework que usa Calendar.app. Solo ve las \
                cuentas que macOS ya tiene agregadas en Ajustes del Sistema — por eso hoy solo aparecen \
                tus reuniones de iCloud.

                Para que vea tus reuniones reales de Google y Outlook/Teams, sin tocar código:
                1. Ajustes del Sistema → Cuentas de Internet (o Internet Accounts)
                2. Agregar cuenta → Google → inicia sesión y activa "Calendarios"
                3. Agregar cuenta → Microsoft Exchange (o Outlook) → inicia sesión y activa "Calendarios"
                4. Vuelve aquí: EventKit las verá automáticamente, sin reiniciar Aria.
                """)
                .font(.caption)
                .foregroundStyle(.secondary)
                Button("Ajustes del sistema…") {
                    if let url = URL(string: "x-apple.systempreferences:com.apple.preferences.internetaccounts") {
                        NSWorkspace.shared.open(url)
                    }
                }
            }
            Section("Calendarios") {
                Text("""
                "Mostrar en agenda" oculta el calendario por completo (agenda de Hoy, tarjeta del menú, \
                título de la barra y aviso de grabación). "Ofrecer grabar" solo quita el botón "Unirse y \
                tomar notas" y el aviso automático — siempre puedes grabar a mano desde el menú.
                """)
                .font(.caption)
                .foregroundStyle(.secondary)
                if calendarListings.isEmpty {
                    Text("Sin calendarios visibles todavía.").font(.caption).foregroundStyle(.secondary)
                } else {
                    ForEach(calendarGroups, id: \.source) { group in
                        Text(group.source).font(.subheadline.bold())
                        ForEach(group.listings) { listing in
                            HStack {
                                Text(listing.title)
                                Spacer()
                                Toggle("Mostrar en agenda", isOn: Binding(
                                    get: { !listing.ignored },
                                    set: { toggleAgenda(listing, show: $0) }
                                ))
                                Toggle("Ofrecer grabar", isOn: Binding(
                                    get: { !listing.promptExcluded },
                                    set: { toggleRecordingOffer(listing, offer: $0) }
                                ))
                            }
                        }
                    }
                }
            }
            Section("General") {
                TextField("Carpeta de Obsidian", text: $config.obsidianDir)
                TextField("Modelo de Claude", text: $config.claudeModel)
                Picker("Modelo de Whisper", selection: $config.whisperModel) {
                    ForEach(AriaConfig.validWhisperModels, id: \.self) { Text($0).tag($0) }
                }
                Picker("Idioma", selection: $config.language) {
                    ForEach(AriaConfig.validLanguages, id: \.self) { Text($0).tag($0) }
                }
            }
            AIProviderSettingsSection()
            Section("Captura") {
                Toggle("Mantener audio (.wav)", isOn: $config.keepAudio)
                Toggle("Pulir transcript con Claude", isOn: $config.transcriptPolish)
                Toggle("Mostrar próxima reunión", isOn: $config.showUpcoming)
                Toggle("Ignorar eventos sin participantes", isOn: $config.ignoreNoParticipants)
                Stepper(
                    "Retención: \(config.retentionDays == 0 ? "sin borrado" : "\(config.retentionDays) días")",
                    value: $config.retentionDays,
                    in: 0...365
                )
                TextField("Calendarios a ignorar (separados por coma)", text: $config.calendarIgnore)
            }
            Section("Contexto visual") {
                Toggle("Activar contexto visual (capturas + OCR local)", isOn: $config.visualContextEnabled)
                Text("""
                Apagado por defecto. Si lo activas, mientras grabas Aria toma capturas de pantalla \
                completa cuando cambia el contenido (o cada 30 s como mínimo) y les hace OCR 100% \
                local con Vision — la imagen nunca sale de este Mac ni se sube a ningún servicio. \
                Se omite si la app al frente está en la lista de exclusión. Las capturas quedan \
                junto a la nota en Reuniones/<nota>/capturas/ y se pueden borrar desde el detalle \
                de cada reunión.
                """)
                .font(.caption)
                .foregroundStyle(.secondary)
                TextField("Apps excluidas (bundle id, separadas por coma)", text: $config.visualContextExcludedApps)
                Stepper(
                    "Sensibilidad al cambio: \(String(format: "%.1f%%", config.visualContextChangeThreshold * 100))",
                    value: $config.visualContextChangeThreshold,
                    in: 0.005...0.2,
                    step: 0.005
                )
            }
            ImportSectionView()
            Section("Compartir & Exportar") {
                HStack {
                    SecureField(
                        KeychainStore.slackWebhookURL() == nil ? "Slack Webhook URL (se guarda en Keychain)" : "Slack Webhook URL configurado — escribe para reemplazarlo",
                        text: $slackWebhookInput
                    )
                    Button("Guardar webhook") { saveSlackWebhook() }
                        .disabled(slackWebhookInput.trimmingCharacters(in: .whitespaces).isEmpty)
                }
                if let slackSavedMessage {
                    Text(slackSavedMessage).font(.caption).foregroundStyle(.secondary)
                }
                TextField("Notion Database ID", text: $config.notionDatabaseID)
            }
            if let savedMessage {
                Text(savedMessage).foregroundStyle(.green).font(.caption)
            }
            Button("Guardar ajustes") { save() }
        }
        .formStyle(.grouped)
        .navigationTitle("Ajustes")
        .task {
            refreshPermissions()
            reloadCalendarListings()
        }
    }

    private struct CalendarGroup {
        let source: String
        let listings: [MeetingCalendar.CalendarListing]
    }

    private var calendarGroups: [CalendarGroup] {
        var order: [String] = []
        var bySource: [String: [MeetingCalendar.CalendarListing]] = [:]
        for listing in calendarListings {
            if bySource[listing.source] == nil { order.append(listing.source) }
            bySource[listing.source, default: []].append(listing)
        }
        return order.map { CalendarGroup(source: $0, listings: bySource[$0] ?? []) }
    }

    private func reloadCalendarListings() {
        calendarListings = MeetingCalendar.shared.calendarListings()
    }

    private func toggleAgenda(_ listing: MeetingCalendar.CalendarListing, show: Bool) {
        var updated = AriaConfig.load()
        var names = Set(updated.ignoredCalendars)
        let key = listing.title.trimmingCharacters(in: .whitespaces).lowercased()
        if show { names.remove(key) } else { names.insert(key) }
        updated.calendarIgnore = names.sorted().joined(separator: ", ")
        try? updated.save()
        config = updated
        reloadCalendarListings()
    }

    private func toggleRecordingOffer(_ listing: MeetingCalendar.CalendarListing, offer: Bool) {
        var updated = AriaConfig.load()
        let result = CalendarPromptPolicy.togglingRecordingOffer(
            calendarIdentifier: listing.id,
            enabled: offer,
            excludedCalendars: updated.promptExcludedCalendarIDs,
            includedCalendars: updated.promptIncludedCalendarIDs
        )
        updated.promptExcludedCalendars = result.excluded.joined(separator: ",")
        updated.promptIncludedCalendars = result.included.joined(separator: ",")
        try? updated.save()
        config = updated
        reloadCalendarListings()
    }

    private func permissionRow(_ name: String, statusLabel: String, actionLabel: String?, action: @escaping () -> Void) -> some View {
        HStack {
            Text(name)
            Spacer()
            Text(statusLabel).foregroundStyle(.secondary)
            if let actionLabel {
                Button(actionLabel, action: action)
            }
        }
    }

    private func performAction(_ action: PermissionRowAction, request: @escaping () -> Void, settingsURL: String) {
        switch action {
        case .none:
            break
        case .request:
            request()
        case .openSystemSettings:
            if let url = URL(string: settingsURL) {
                NSWorkspace.shared.open(url)
            }
        }
    }

    private func requestCalendarAccess() {
        Task {
            _ = try? await MeetingCalendar.shared.requestAccess()
            refreshPermissions()
        }
    }

    private func requestMicAccess() {
        Task {
            _ = await Permissions.ensureMicrophone()
            refreshPermissions()
        }
    }

    private func requestScreenAccess() {
        _ = Permissions.ensureScreenRecording()
        refreshPermissions()
    }

    private func refreshPermissions() {
        micAuthStatus = Permissions.microphoneStatus()
        screenGranted = Permissions.screenRecordingGranted()
        calendarAuthStatus = MeetingCalendar.authorizationStatus
    }

    private func save() {
        do {
            try config.save()
            savedMessage = "Guardado."
        } catch {
            savedMessage = "Error: \(error.localizedDescription)"
        }
    }

    private func saveSlackWebhook() {
        let trimmed = slackWebhookInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let ok = KeychainStore.saveSlackWebhookURL(trimmed)
        slackWebhookInput = ""
        slackSavedMessage = ok ? "Webhook guardado en Keychain." : "Error guardando en Keychain."
    }
}

struct RecipesSectionView: View {
    @State private var recipes: [Recipe] = []
    @State private var templates: [Recipe] = []
    @State private var selectedRecipe: String?
    @State private var selectedTemplate: String?
    @State private var recipeResult = ""
    @State private var applying = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Recipes & Plantillas").font(.largeTitle).bold()

            HStack(spacing: 16) {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Recipes").font(.headline)
                    List(recipes, id: \.name, selection: $selectedRecipe) { recipe in
                        Text(recipe.name).tag(recipe.name)
                    }
                    .listStyle(.plain)
                    .frame(minHeight: 120)
                }

                VStack(alignment: .leading, spacing: 10) {
                    Text("Plantillas").font(.headline)
                    List(templates, id: \.name, selection: $selectedTemplate) { template in
                        Text(template.name).tag(template.name)
                    }
                    .listStyle(.plain)
                    .frame(minHeight: 120)
                }
            }
            .frame(height: 200)

            Divider()

            if !recipeResult.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Resultado").font(.headline)
                    ScrollView {
                        Text(recipeResult)
                            .textSelection(.enabled)
                            .padding(8)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .frame(minHeight: 100)
                    .background(Color(.controlBackgroundColor))
                    .cornerRadius(6)

                    HStack {
                        Button("Copiar") {
                            let pasteboard = NSPasteboard.general
                            pasteboard.clearContents()
                            pasteboard.setString(recipeResult, forType: .string)
                        }
                        Button("Limpiar") {
                            recipeResult = ""
                        }
                    }
                }
            }

            HStack {
                if let selected = selectedRecipe {
                    Button("Aplicar recipe") {
                        applyRecipe(selected)
                    }
                    .disabled(applying)
                } else {
                    Text("Selecciona una recipe").foregroundStyle(.secondary)
                }

                Spacer()

                if applying {
                    ProgressView().scaleEffect(0.8)
                }
            }

            Spacer()
        }
        .padding()
        .navigationTitle("Recipes & Plantillas")
        .task {
            loadRecipesAndTemplates()
        }
    }

    private func loadRecipesAndTemplates() {
        recipes = RecipeStore().list()
        templates = TemplateStore().list()
    }

    private func applyRecipe(_ name: String) {
        guard let recipe = recipes.first(where: { $0.name == name }) else { return }
        applying = true
        Task {
            do {
                let result = try await MeetingChat.answer(question: recipe.prompt) { _ in }
                recipeResult = result.text
            } catch {
                recipeResult = "Error: \(error.localizedDescription)"
            }
            applying = false
        }
    }
}
