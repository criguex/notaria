import SwiftUI

struct MeetingNotepadView: View {
    @ObservedObject var notepad: MeetingNotepadController

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Notas propias").font(.headline)
            Text("Se guardan solas mientras escribes. Al detener, estructuran la nota junto al transcript.")
                .font(.caption)
                .foregroundStyle(.secondary)
            TextEditor(text: $notepad.text)
                .font(.body)
                .scrollContentBackground(.hidden)
                .frame(minHeight: 160, maxHeight: 260)
                .padding(6)
                .background(RoundedRectangle(cornerRadius: 8).fill(BrandColor.papel.opacity(0.35)))
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(BrandColor.arena, lineWidth: 1))
                .onChange(of: notepad.text) { _, _ in notepad.noteChanged() }
        }
    }
}

struct OwnNotesSectionView: View {
    let meetingID: Int64

    @State private var text = ""
    @State private var original = ""
    @State private var saveMessage: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Notas propias").font(.headline)
            TextEditor(text: $text)
                .font(.body)
                .scrollContentBackground(.hidden)
                .frame(minHeight: 120, maxHeight: 220)
                .padding(6)
                .background(RoundedRectangle(cornerRadius: 8).fill(BrandColor.papel.opacity(0.35)))
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(BrandColor.arena, lineWidth: 1))
            HStack(spacing: 10) {
                Button("Guardar notas propias") { save() }
                    .disabled(text == original)
                if let saveMessage {
                    Text(saveMessage).font(.caption).foregroundStyle(.secondary)
                }
            }
        }
        .task(id: meetingID) { load() }
    }

    private func load() {
        guard let store = try? MeetingStore(), let loaded = try? store.ownNotes(meetingID: meetingID) else { return }
        text = loaded
        original = loaded
        saveMessage = nil
    }

    private func save() {
        do {
            let store = try MeetingStore()
            try store.setOwnNotes(text, meetingID: meetingID)
            original = text
            saveMessage = "Guardado."
        } catch {
            saveMessage = "Error: \(error.localizedDescription)"
        }
    }
}
