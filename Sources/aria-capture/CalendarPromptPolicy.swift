import EventKit
import Foundation

/// Clasificación pura de una cuenta de calendario (EKSource) para decidir si
/// por defecto NotarIA debe ofrecer grabar sus reuniones. Exchange y los
/// CalDAV de Outlook/Office 365 son "cuentas de trabajo": arrancan con
/// "Ofrecer grabar" apagado (ver AriaConfig.promptExcludedCalendars/Accounts).
enum CalendarAccountKind: Equatable {
    case exchange
    case outlookCalDAV
    case other

    static func classify(sourceType: EKSourceType, sourceTitle: String) -> CalendarAccountKind {
        if sourceType == .exchange { return .exchange }
        if sourceType == .calDAV {
            let folded = sourceTitle.lowercased()
            if folded.contains("outlook") || folded.contains("office365") || folded.contains("office 365") {
                return .outlookCalDAV
            }
        }
        return .other
    }

    var isWorkAccountDefault: Bool { self != .other }
}

/// Resuelve si un calendario debe quedar excluido del aviso de grabación
/// ("Ofrecer grabar" apagado), combinando overrides explícitos del usuario
/// con el default de cuentas de trabajo. Pura y testeable: no toca EventKit.
enum CalendarPromptPolicy {

    static func isExcluded(
        calendarIdentifier: String,
        sourceIdentifier: String,
        accountKind: CalendarAccountKind,
        promptExcludedCalendars: [String],
        promptIncludedCalendars: [String],
        promptExcludedAccounts: [String]
    ) -> Bool {
        if promptIncludedCalendars.contains(calendarIdentifier) { return false }
        if promptExcludedCalendars.contains(calendarIdentifier) { return true }
        if promptExcludedAccounts.contains(sourceIdentifier) { return true }
        return accountKind.isWorkAccountDefault
    }

    /// Aplica el toggle "Ofrecer grabar" de un calendario concreto, devolviendo
    /// las listas `promptExcludedCalendars`/`promptIncludedCalendars` actualizadas
    /// (el identificador queda en una sola de las dos, nunca en ambas).
    static func togglingRecordingOffer(
        calendarIdentifier: String,
        enabled: Bool,
        excludedCalendars: [String],
        includedCalendars: [String]
    ) -> (excluded: [String], included: [String]) {
        var excluded = excludedCalendars.filter { $0 != calendarIdentifier }
        var included = includedCalendars.filter { $0 != calendarIdentifier }
        if enabled {
            included.append(calendarIdentifier)
        } else {
            excluded.append(calendarIdentifier)
        }
        return (excluded, included)
    }
}
