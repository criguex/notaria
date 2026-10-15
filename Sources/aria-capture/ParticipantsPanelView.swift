import AppKit
import SwiftUI

/// Capa 4: panel "Participantes" del detalle de reunión — tiempo de habla, nombre sugerido,
/// confirmar/renombrar/fusionar con un clic. Vive en archivo propio (no en `MainWindowView.swift`,
/// compartido con otro agente) y se embebe ahí con una sola línea.
struct ParticipantsPanelView: View {
    let meetingID: Int64
    var onSpeakersChanged: () -> Void = {}

    @State private var segments: [TranscriptSegment] = []
    @State private var errorMessage: String?
    @State private var mergeSource = ""
    @State private var mergeTarget = ""
    @State private var manualRenameLabel: String?
    @State private var manualRenameText = ""
    @State private var rememberVoice = true
    @State private var labelsWithVoiceProfile: Set<String> = []
    @State private var voiceMemoryEnabled = false

    private var speakerLabels: [String] {
        SpeakerNaming.orderedSpeakerLabels(in: segments)
    }

    private var speakingSeconds: [String: Double] {
        SpeakerNaming.speakingSeconds(in: segments)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Participantes").font(.headline)
            if let errorMessage {
                Text(errorMessage).font(.caption).foregroundStyle(.red)
            }
            if speakerLabels.isEmpty {
                Text("Sin hablantes detectados todavía.").font(.caption).foregroundStyle(.secondary)
            } else {
                ForEach(speakerLabels, id: \.self) { label in
                    row(for: label)
                }
                if speakerLabels.count > 1 {
                    mergeControls
                }
            }
        }
        .task(id: meetingID) { load() }
    }

    @ViewBuilder
    private func row(for label: String) -> some View {
        let seconds = speakingSeconds[label] ?? 0
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(label).bold()
                Text(Self.formattedDuration(seconds)).font(.caption).foregroundStyle(.secondary)
                Spacer()
                if let pending = SpeakerNaming.pendingConfirmation(in: label) {
                    Button("Confirmar: \(pending.suggestedName)") {
                        rename(label: label, to: pending.suggestedName)
                    }
                    .font(.caption)
                }
                Button("Renombrar") {
                    manualRenameLabel = label
                    manualRenameText = SpeakerNaming.pendingConfirmation(in: label)?.suggestedName ?? label
                }
                .font(.caption)
            }
            if manualRenameLabel == label {
                HStack {
                    TextField("Nombre", text: $manualRenameText).textFieldStyle(.roundedBorder)
                    if voiceMemoryEnabled, labelsWithVoiceProfile.contains(label) {
                        Toggle("Recordar esta voz", isOn: $rememberVoice)
                            .toggleStyle(.checkbox)
                            .font(.caption)
                    }
                    Button("Guardar") { rename(label: label, to: manualRenameText) }
                    Button("Cancelar") { manualRenameLabel = nil }
                }
                .font(.caption)
            }
        }
        .padding(8)
        .background(Color(.controlBackgroundColor))
        .cornerRadius(4)
    }

    private var mergeControls: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Fusionar dos hablantes").font(.caption).foregroundStyle(.secondary)
            HStack {
                Picker("", selection: $mergeSource) {
                    Text("Elegir…").tag("")
                    ForEach(speakerLabels, id: \.self) { Text($0).tag($0) }
                }
                .labelsHidden()
                Text("→")
                Picker("", selection: $mergeTarget) {
                    Text("Elegir…").tag("")
                    ForEach(speakerLabels, id: \.self) { Text($0).tag($0) }
                }
                .labelsHidden()
                Button("Fusionar") { merge() }
                    .disabled(mergeSource.isEmpty || mergeTarget.isEmpty || mergeSource == mergeTarget)
            }
            .font(.caption)
        }
    }

    private func load() {
        voiceMemoryEnabled = AriaConfig.load().voiceMemoryEnabled
        do {
            let store = try MeetingStore()
            segments = try store.segments(meetingID: meetingID)
            labelsWithVoiceProfile = Set(try store.speakerEmbeddings(meetingID: meetingID).keys)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func rename(label: String, to newName: String) {
        let trimmed = newName.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        do {
            let store = try MeetingStore()
            let embedding = try store.speakerEmbeddings(meetingID: meetingID)[label]
            try store.renameSpeaker(meetingID: meetingID, oldSpeaker: label, newSpeaker: trimmed)
            try store.renameSpeakerProfile(meetingID: meetingID, oldLabel: label, newLabel: trimmed)
            if voiceMemoryEnabled, rememberVoice, let embedding {
                _ = try? VoiceMemoryStore().upsert(name: trimmed, embedding: embedding)
            }
            manualRenameLabel = nil
            load()
            onSpeakersChanged()
        } catch {
            errorMessage = "Error renombrando: \(error.localizedDescription)"
        }
    }

    private func merge() {
        guard !mergeSource.isEmpty, !mergeTarget.isEmpty, mergeSource != mergeTarget else { return }
        do {
            let store = try MeetingStore()
            try store.renameSpeaker(meetingID: meetingID, oldSpeaker: mergeSource, newSpeaker: mergeTarget)
            try store.renameSpeakerProfile(meetingID: meetingID, oldLabel: mergeSource, newLabel: mergeTarget)
            mergeSource = ""
            mergeTarget = ""
            load()
            onSpeakersChanged()
        } catch {
            errorMessage = "Error fusionando: \(error.localizedDescription)"
        }
    }

    static func formattedDuration(_ seconds: Double) -> String {
        let total = Int(seconds)
        return String(format: "%d:%02d", total / 60, total % 60)
    }
}
