import AppKit
import Foundation

/// `aria-capture preview-toast [prompt|still-there]` — muestra el aviso flotante
/// correspondiente con datos de ejemplo durante unos segundos y sale. No grava nada,
/// no toca micrófono/audio de sistema, no inicia sesión en ningún servicio.
@MainActor
enum PreviewToast {

    static let previewSeconds: TimeInterval = 8

    static func run(kind: String) {
        // Necesario para que AppKit pueda crear y dibujar el NSPanel fuera de una app
        // "de verdad": política accessory = sin ícono en el Dock ni activar la app.
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)

        switch kind {
        case "still-there":
            print("[preview-toast] Aviso '¿Sigues en la reunión?' de ejemplo durante \(Int(previewSeconds))s — no se detiene nada real.")
            StillThereWarningWindowController.shared.present(
                remainingSeconds: 18,
                totalSeconds: Int(RecordingSessionMachine.defaultCountdownSeconds),
                onKeepGoing: {},
                onStop: {}
            )
        case "prompt":
            let meeting = CalendarMeeting(
                title: "Sync semanal: QA + producto",
                start: Date().addingTimeInterval(120),
                end: Date().addingTimeInterval(1_920),
                attendees: ["Ana", "Luis"],
                isAllDay: false
            )
            print("[preview-toast] Aviso '¿Tomar notas con NotarIA?' (sin link) de ejemplo durante \(Int(previewSeconds))s — no se grabará nada.")
            MeetingPromptWindowController.shared.present(
                title: MeetingPromptDecider.promptTitle(meetingNow: meeting),
                subtitle: MeetingPromptDecider.promptSubtitle(meetingNow: meeting),
                onStart: {}
            )
        case "prompt-link":
            let meeting = CalendarMeeting(
                title: "Sync semanal: QA + producto",
                start: Date().addingTimeInterval(120),
                end: Date().addingTimeInterval(1_920),
                attendees: ["Ana", "Luis"],
                isAllDay: false,
                videoLink: "https://meet.google.com/aaa-bbbb-ccc"
            )
            print("[preview-toast] Aviso con 'Unirse y tomar notas' de ejemplo durante \(Int(previewSeconds))s — link de muestra, no se abre nada real ni se grabará.")
            MeetingPromptWindowController.shared.present(
                title: MeetingPromptDecider.promptTitle(meetingNow: meeting),
                subtitle: MeetingPromptDecider.promptSubtitle(meetingNow: meeting),
                joinURL: meeting.videoLink.flatMap { MeetingJoinLink.resolve(videoLink: $0, nativeAppInstalled: false) },
                onStart: {}
            )
        default:
            print("[error] Vista previa desconocida: \(kind). Usa: aria-capture preview-toast [prompt|prompt-link|still-there]")
            exit(1)
        }

        // Bombea el run loop (sin app.run()) lo justo para que la animación de entrada,
        // el hover del botón de cierre y la cuenta atrás se vean en vivo.
        RunLoop.current.run(until: Date().addingTimeInterval(previewSeconds))

        MeetingPromptWindowController.shared.dismiss()
        StillThereWarningWindowController.shared.dismiss()
        // Deja correr la animación de salida antes de terminar el proceso.
        RunLoop.current.run(until: Date().addingTimeInterval(0.4))
        exit(0)
    }
}
