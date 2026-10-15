import AppKit
import Foundation

enum MeetingPlatform: String, Equatable {
    case meet = "Meet"
    case teams = "Teams"
    case zoom = "Zoom"
    case webex = "Webex"
    case other

    static func detect(fromURL link: String) -> MeetingPlatform? {
        guard let name = BrowserMeetingDetector.provider(forURL: link) else { return nil }
        return MeetingPlatform(rawValue: name) ?? .other
    }
}

/// Resuelve el link de "Unirse" de un evento: Meet/Webex/otros siempre quedan en
/// https; Teams/Zoom prefieren el esquema de su app nativa (msteams:/zoommtg:)
/// cuando está instalada, igual que el enlace "Open Microsoft Teams" del propio
/// Teams o el handler zoommtg:// documentado por Zoom.
enum MeetingJoinLink {

    static func resolve(videoLink: String, nativeAppInstalled: Bool) -> URL? {
        guard !videoLink.isEmpty else { return nil }
        guard nativeAppInstalled, let platform = MeetingPlatform.detect(fromURL: videoLink) else {
            return URL(string: videoLink)
        }
        switch platform {
        case .teams: return teamsNativeURL(from: videoLink) ?? URL(string: videoLink)
        case .zoom: return zoomNativeURL(from: videoLink) ?? URL(string: videoLink)
        case .meet, .webex, .other: return URL(string: videoLink)
        }
    }

    static func resolve(videoLink: String) -> URL? {
        resolve(videoLink: videoLink, nativeAppInstalled: isNativeAppAvailable(forVideoLink: videoLink))
    }

    static func nativeScheme(for platform: MeetingPlatform) -> String? {
        switch platform {
        case .teams: return "msteams"
        case .zoom: return "zoommtg"
        case .meet, .webex, .other: return nil
        }
    }

    static func isNativeAppAvailable(forVideoLink link: String) -> Bool {
        guard let platform = MeetingPlatform.detect(fromURL: link),
              let scheme = nativeScheme(for: platform),
              let probe = URL(string: "\(scheme)://")
        else { return false }
        return NSWorkspace.shared.urlForApplication(toOpen: probe) != nil
    }

    static func teamsNativeURL(from link: String) -> URL? {
        for host in ["https://teams.microsoft.com", "https://teams.live.com"] {
            if link.hasPrefix(host) {
                return URL(string: "msteams:\(link.dropFirst(host.count))")
            }
        }
        return nil
    }

    static func zoomNativeURL(from link: String) -> URL? {
        guard let components = URLComponents(string: link),
              let host = components.host, host.contains("zoom.us")
        else { return nil }
        let parts = components.path.split(separator: "/").map(String.init)
        guard let keyIndex = parts.firstIndex(where: { $0 == "j" || $0 == "my" }),
              parts.count > keyIndex + 1
        else { return nil }
        var output = URLComponents()
        output.scheme = "zoommtg"
        output.host = "zoom.us"
        output.path = "/join"
        var items = [URLQueryItem(name: "action", value: "join"), URLQueryItem(name: "confno", value: parts[keyIndex + 1])]
        if let pwd = components.queryItems?.first(where: { $0.name == "pwd" })?.value {
            items.append(URLQueryItem(name: "pwd", value: pwd))
        }
        output.queryItems = items
        return output.url
    }
}

/// Qué botones mostrar en el aviso de reunión (MeetingPromptPanel): si el evento
/// tiene link de videollamada, "Unirse y tomar notas" + "Solo tomar notas"; sin
/// link, se mantiene el flujo original ("Grabar"/"Ignorar").
enum MeetingPromptLayout: Equatable {
    case noLink
    case withLink(joinURL: URL)

    static func decide(videoLink: String?, nativeAppInstalled: Bool) -> MeetingPromptLayout {
        guard let videoLink, let url = MeetingJoinLink.resolve(videoLink: videoLink, nativeAppInstalled: nativeAppInstalled) else {
            return .noLink
        }
        return .withLink(joinURL: url)
    }
}
