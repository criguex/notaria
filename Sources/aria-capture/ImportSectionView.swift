import AppKit
import SwiftUI

struct ImportSectionView: View {
    @State private var isImporting = false
    @State private var resultMessage: String?
    @State private var resultIsError = false

    var body: some View {
        Section("Importar notas") {
            Text("Importa carpetas o archivos .md, .txt, .vtt, .srt o .json (ver docs/IMPORT-FORMAT.md).")
                .font(.caption)
                .foregroundStyle(.secondary)
            Button(isImporting ? "Importando…" : "Importar…") { presentPanel() }
                .disabled(isImporting)
            if let resultMessage {
                Text(resultMessage)
                    .font(.caption)
                    .foregroundStyle(resultIsError ? .red : .green)
            }
        }
    }

    private func presentPanel() {
        let panel = NSOpenPanel()
        panel.title = "Importar notas"
        panel.canChooseDirectories = true
        panel.canChooseFiles = true
        panel.allowsMultipleSelection = false
        panel.prompt = "Importar"
        guard panel.runModal() == .OK, let url = panel.url else { return }

        isImporting = true
        resultMessage = nil
        DispatchQueue.global(qos: .userInitiated).async {
            do {
                let result = try GenericImporter.importPath(url, sourceOverride: nil)
                DispatchQueue.main.async {
                    isImporting = false
                    resultIsError = !result.failed.isEmpty
                    resultMessage = "Importadas: \(result.imported) · Actualizadas: \(result.updated) · Fallidas: \(result.failed.count)"
                }
            } catch {
                DispatchQueue.main.async {
                    isImporting = false
                    resultIsError = true
                    resultMessage = "Error: \(error.localizedDescription)"
                }
            }
        }
    }
}
