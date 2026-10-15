import SwiftUI

/// Tarjeta "Próxima reunión" del menú desplegable: título, hora, plataforma,
/// asistentes y botones de unirse — misma "shell" visual que los avisos flotantes
/// (ver ToastCardBackground) para mantener un solo lenguaje de marca.
struct MeetingCardView: View {
    let viewModel: MeetingCardViewModel
    let onJoin: () -> Void
    let onJoinAndTakeNotes: () -> Void

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Próxima reunión")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(BrandColor.toastSecondary(for: colorScheme))
            Text(viewModel.title)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(BrandColor.toastTitle(for: colorScheme))
                .lineLimit(2)
            HStack(spacing: 10) {
                Label(viewModel.timeLabel, systemImage: "clock")
                if let platform = viewModel.platformLabel {
                    Label(platform, systemImage: "video")
                }
            }
            .font(.system(size: 11))
            .foregroundStyle(BrandColor.toastSecondary(for: colorScheme))
            if let attendees = viewModel.attendeesLabel {
                Label(attendees, systemImage: "person.2")
                    .font(.system(size: 11))
                    .foregroundStyle(BrandColor.toastSecondary(for: colorScheme))
            }
            if viewModel.canJoin {
                HStack(spacing: 8) {
                    Button("Unirse", action: onJoin)
                        .buttonStyle(.bordered)
                        .tint(BrandColor.pizarra)
                    if viewModel.offerRecording {
                        Button("Unirse y tomar notas", action: onJoinAndTakeNotes)
                            .buttonStyle(.borderedProminent)
                            .tint(BrandColor.sello)
                    }
                }
                .padding(.top, 2)
            }
        }
        .padding(12)
        .frame(width: 300, alignment: .topLeading)
        .background(ToastCardBackground())
    }
}
