import Foundation

struct ChatMessageGroup: Equatable, Identifiable {
    let speaker: String
    let isYou: Bool
    let messages: [LiveTranscriptLine]

    var id: String { "\(speaker)-\(startTimestamp)-\(messages.count)" }
    var startTimestamp: TimeInterval { messages.first?.timestamp ?? 0 }

    func appending(_ line: LiveTranscriptLine) -> ChatMessageGroup {
        ChatMessageGroup(speaker: speaker, isYou: isYou, messages: messages + [line])
    }
}

enum ChatTimelineItem: Equatable, Identifiable {
    case messages(ChatMessageGroup)
    case pause(PauseInterval)

    var id: String {
        switch self {
        case .messages(let group): return "g-\(group.id)"
        case .pause(let interval): return "p-\(interval.transcriptOffsetSeconds)"
        }
    }

    var offset: TimeInterval {
        switch self {
        case .messages(let group): return group.startTimestamp
        case .pause(let interval): return interval.transcriptOffsetSeconds
        }
    }
}

enum ChatBubbleLogic {

    /// Agrupa líneas consecutivas del mismo hablante en un solo bloque de burbuja.
    static func grouped(_ lines: [LiveTranscriptLine]) -> [ChatMessageGroup] {
        timeline(lines: lines, pauses: []).compactMap {
            if case .messages(let group) = $0 { return group }
            return nil
        }
    }

    /// Agrupa mensajes e intercala los marcadores de pausa en el punto correcto del eje de
    /// tiempo activo, partiendo un grupo en dos si una pausa ocurrió en medio de él.
    static func timeline(lines: [LiveTranscriptLine], pauses: [PauseInterval]) -> [ChatTimelineItem] {
        let sortedPauses = pauses.sorted { $0.transcriptOffsetSeconds < $1.transcriptOffsetSeconds }
        var items: [ChatTimelineItem] = []
        var pauseIndex = 0
        var currentGroup: ChatMessageGroup?

        func flushGroup() {
            if let group = currentGroup { items.append(.messages(group)) }
            currentGroup = nil
        }

        for line in lines {
            while pauseIndex < sortedPauses.count, sortedPauses[pauseIndex].transcriptOffsetSeconds <= line.timestamp {
                flushGroup()
                items.append(.pause(sortedPauses[pauseIndex]))
                pauseIndex += 1
            }
            if let existing = currentGroup, existing.speaker == line.speaker {
                currentGroup = existing.appending(line)
            } else {
                flushGroup()
                currentGroup = ChatMessageGroup(
                    speaker: line.speaker,
                    isYou: line.speaker == LiveTranscriptFeed.youLabel,
                    messages: [line]
                )
            }
        }
        flushGroup()
        while pauseIndex < sortedPauses.count {
            items.append(.pause(sortedPauses[pauseIndex]))
            pauseIndex += 1
        }
        return items
    }
}

enum ChatPanelAnchor: Equatable {
    case leading
    case trailing
}

enum ChatPanelLayout {

    static let gap: CGFloat = 10

    /// Decide a qué lado de la píldora abrir el panel: prefiere el lado con espacio suficiente
    /// y, si ninguno alcanza, el que tenga más espacio disponible.
    static func anchor(pillFrame: CGRect, screenFrame: CGRect, panelWidth: CGFloat) -> ChatPanelAnchor {
        let spaceOnRight = screenFrame.maxX - pillFrame.maxX
        let spaceOnLeft = pillFrame.minX - screenFrame.minX
        if spaceOnRight >= panelWidth + gap { return .trailing }
        if spaceOnLeft >= panelWidth + gap { return .leading }
        return spaceOnRight >= spaceOnLeft ? .trailing : .leading
    }

    /// Origen (esquina inferior izquierda, coordenadas AppKit) del panel, alineado por arriba
    /// con la píldora y recortado para no salirse de la pantalla.
    static func origin(pillFrame: CGRect, screenFrame: CGRect, panelSize: CGSize, anchor: ChatPanelAnchor) -> CGPoint {
        let x = anchor == .trailing ? pillFrame.maxX + gap : pillFrame.minX - panelSize.width - gap
        let clampedX = min(max(x, screenFrame.minX), max(screenFrame.minX, screenFrame.maxX - panelSize.width))
        let y = pillFrame.maxY - panelSize.height
        let clampedY = min(max(y, screenFrame.minY), max(screenFrame.minY, screenFrame.maxY - panelSize.height))
        return CGPoint(x: clampedX, y: clampedY)
    }
}
