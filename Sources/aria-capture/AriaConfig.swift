import Foundation

struct AriaConfig: Codable {
    var claudeModel = "claude-opus-4-8"
    var obsidianDir = "~/Documents/Aria/Reuniones"
    var keepAudio = false
    var whisperModel = "small"
    var systemPromptPath: String?
    var alwaysOn = false
    var retentionDays = 0
    var language = "es"
    var transcriptPolish = false
    var showUpcoming = true
    var showMenuBarTitle = true
    var ignoreNoParticipants = false
    var calendarIgnore = ""
    var promptExcludedCalendars = ""
    var promptIncludedCalendars = ""
    var promptExcludedAccounts = ""
    var aiProvider = AIProviderKind.auto
    var aiModel = ""
    var aiBaseURL = ""
    var notionDatabaseID: String = ""
    var visualContextEnabled = false
    var visualContextExcludedApps = VisualAppExclusionPolicy.defaultExcludedBundleIDs.joined(separator: ",")
    var visualContextChangeThreshold = 0.02
    var speakerSeparationEnabled = false
    var voiceMemoryEnabled = false
    var participantsAccessibilityEnabled = false

    init() {}

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        claudeModel = try container.decodeIfPresent(String.self, forKey: .claudeModel) ?? claudeModel
        obsidianDir = try container.decodeIfPresent(String.self, forKey: .obsidianDir) ?? obsidianDir
        keepAudio = try container.decodeIfPresent(Bool.self, forKey: .keepAudio) ?? keepAudio
        whisperModel = try container.decodeIfPresent(String.self, forKey: .whisperModel) ?? whisperModel
        systemPromptPath = try container.decodeIfPresent(String.self, forKey: .systemPromptPath)
        alwaysOn = try container.decodeIfPresent(Bool.self, forKey: .alwaysOn) ?? alwaysOn
        retentionDays = try container.decodeIfPresent(Int.self, forKey: .retentionDays) ?? retentionDays
        language = try container.decodeIfPresent(String.self, forKey: .language) ?? language
        transcriptPolish = try container.decodeIfPresent(Bool.self, forKey: .transcriptPolish) ?? transcriptPolish
        showUpcoming = try container.decodeIfPresent(Bool.self, forKey: .showUpcoming) ?? showUpcoming
        showMenuBarTitle = try container.decodeIfPresent(Bool.self, forKey: .showMenuBarTitle) ?? showMenuBarTitle
        ignoreNoParticipants = try container.decodeIfPresent(Bool.self, forKey: .ignoreNoParticipants) ?? ignoreNoParticipants
        calendarIgnore = try container.decodeIfPresent(String.self, forKey: .calendarIgnore) ?? calendarIgnore
        promptExcludedCalendars = try container.decodeIfPresent(String.self, forKey: .promptExcludedCalendars) ?? promptExcludedCalendars
        promptIncludedCalendars = try container.decodeIfPresent(String.self, forKey: .promptIncludedCalendars) ?? promptIncludedCalendars
        promptExcludedAccounts = try container.decodeIfPresent(String.self, forKey: .promptExcludedAccounts) ?? promptExcludedAccounts
        aiProvider = try container.decodeIfPresent(AIProviderKind.self, forKey: .aiProvider) ?? aiProvider
        aiModel = try container.decodeIfPresent(String.self, forKey: .aiModel) ?? aiModel
        aiBaseURL = try container.decodeIfPresent(String.self, forKey: .aiBaseURL) ?? aiBaseURL
        notionDatabaseID = try container.decodeIfPresent(String.self, forKey: .notionDatabaseID) ?? notionDatabaseID
        visualContextEnabled = try container.decodeIfPresent(Bool.self, forKey: .visualContextEnabled) ?? visualContextEnabled
        visualContextExcludedApps = try container.decodeIfPresent(String.self, forKey: .visualContextExcludedApps) ?? visualContextExcludedApps
        visualContextChangeThreshold = try container.decodeIfPresent(Double.self, forKey: .visualContextChangeThreshold) ?? visualContextChangeThreshold
        speakerSeparationEnabled = try container.decodeIfPresent(Bool.self, forKey: .speakerSeparationEnabled) ?? speakerSeparationEnabled
        voiceMemoryEnabled = try container.decodeIfPresent(Bool.self, forKey: .voiceMemoryEnabled) ?? voiceMemoryEnabled
        participantsAccessibilityEnabled = try container.decodeIfPresent(Bool.self, forKey: .participantsAccessibilityEnabled) ?? participantsAccessibilityEnabled
    }

    var ignoredCalendars: [String] {
        calendarIgnore
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespaces).lowercased() }
            .filter { !$0.isEmpty }
    }

    private static func parsedIdentifierList(_ raw: String) -> [String] {
        raw
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }

    /// Identificadores de EKCalendar (`calendarIdentifier`) con "Ofrecer grabar" apagado explícitamente.
    var promptExcludedCalendarIDs: [String] { Self.parsedIdentifierList(promptExcludedCalendars) }

    /// Identificadores de EKCalendar con "Ofrecer grabar" encendido explícitamente — tiene prioridad
    /// para reactivar "Ofrecer grabar" en un calendario excluido antes.
    var promptIncludedCalendarIDs: [String] { Self.parsedIdentifierList(promptIncludedCalendars) }

    /// Identificadores de EKSource (cuentas completas) con "Ofrecer grabar" apagado para todos sus calendarios.
    var promptExcludedAccountIDs: [String] { Self.parsedIdentifierList(promptExcludedAccounts) }

    var excludedVisualContextBundleIDs: [String] {
        VisualAppExclusionPolicy.parsedList(visualContextExcludedApps)
    }

    static let validWhisperModels = ["tiny", "base", "small", "medium", "large-v3"]
    static let validLanguages = ["es", "en", "auto"]

    static var fileURL: URL {
        AriaHome.directory
            .appendingPathComponent("Library/Application Support/Aria/config.json")
    }

    static func load() -> AriaConfig {
        migrateLegacySlackWebhookIfNeeded()
        guard let data = try? Data(contentsOf: fileURL),
              let config = try? JSONDecoder().decode(AriaConfig.self, from: data) else {
            return AriaConfig()
        }
        return config
    }

    /// 13.5 guardaba el Slack Webhook URL en disco (config.json). Lo movemos a Keychain
    /// (como las demás keys) y lo borramos del JSON, una sola vez por archivo legado.
    private static func migrateLegacySlackWebhookIfNeeded() {
        guard let data = try? Data(contentsOf: fileURL),
              var json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let legacyURL = json["slackWebhookURL"] as? String,
              !legacyURL.isEmpty
        else { return }
        if KeychainStore.slackWebhookURL() == nil {
            KeychainStore.saveSlackWebhookURL(legacyURL)
        }
        json.removeValue(forKey: "slackWebhookURL")
        if let rewritten = try? JSONSerialization.data(withJSONObject: json, options: [.prettyPrinted, .sortedKeys]) {
            try? rewritten.write(to: fileURL)
        }
    }

    func save() throws {
        try FileManager.default.createDirectory(
            at: Self.fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(self).write(to: Self.fileURL)
    }

    var resolvedObsidianDir: URL {
        if let env = ProcessInfo.processInfo.environment["ARIA_OBSIDIAN_DIR"], !env.isEmpty {
            return URL(fileURLWithPath: (env as NSString).expandingTildeInPath, isDirectory: true)
        }
        return URL(fileURLWithPath: (obsidianDir as NSString).expandingTildeInPath, isDirectory: true)
    }

    var resolvedSystemPrompt: String? {
        guard let path = systemPromptPath else { return nil }
        return try? String(
            contentsOf: URL(fileURLWithPath: (path as NSString).expandingTildeInPath),
            encoding: .utf8
        )
    }

    var listing: String {
        """
        claudeModel      = \(claudeModel)
        obsidianDir      = \(obsidianDir)
        keepAudio        = \(keepAudio)
        whisperModel     = \(whisperModel)
        systemPromptPath = \(systemPromptPath ?? "(default integrado)")
        alwaysOn         = \(alwaysOn)
        retentionDays    = \(retentionDays)\(retentionDays == 0 ? " (sin borrado automático)" : "")
        language         = \(language)\(language == "auto" ? " (whisper detecta; la nota sale en el idioma de la reunión)" : "")
        transcriptPolish = \(transcriptPolish)\(transcriptPolish ? " (Claude corrige el transcript antes del enhance)" : "")
        showUpcoming     = \(showUpcoming) (próxima reunión en menú y barra)
        showMenuBarTitle = \(showMenuBarTitle) (título + cuenta atrás junto al glifo de la barra)
        ignoreNoParticipants = \(ignoreNoParticipants)\(ignoreNoParticipants ? " (detección ignora eventos sin invitados ni link de video)" : "")
        calendarIgnore   = \(calendarIgnore.isEmpty ? "(ninguno)" : calendarIgnore)
        promptExcludedCalendars = \(promptExcludedCalendars.isEmpty ? "(ninguno)" : promptExcludedCalendars) (calendarios sin "Ofrecer grabar")
        promptIncludedCalendars = \(promptIncludedCalendars.isEmpty ? "(ninguno)" : promptIncludedCalendars) (overrides explícitos encendidos)
        promptExcludedAccounts  = \(promptExcludedAccounts.isEmpty ? "(ninguno)" : promptExcludedAccounts) (cuentas EKSource sin "Ofrecer grabar")
        aiProvider       = \(aiProvider.rawValue) — \(aiProvider.label)
        aiModel          = \(aiModel.isEmpty ? "(usa claudeModel si aplica)" : aiModel)
        aiBaseURL        = \(aiBaseURL.isEmpty ? "(default del proveedor)" : aiBaseURL)
        slackWebhookURL  = \(KeychainStore.slackWebhookURL() == nil ? "(no configurado)" : "●●●●●●●● (Keychain)")
        notionDatabaseID = \(notionDatabaseID.isEmpty ? "(no configurado)" : notionDatabaseID)
        visualContextEnabled = \(visualContextEnabled) (capturas + OCR local durante la grabación)
        visualContextExcludedApps = \(visualContextExcludedApps.isEmpty ? "(ninguna)" : visualContextExcludedApps)
        visualContextChangeThreshold = \(visualContextChangeThreshold) (fracción de la huella de luminancia que debe cambiar para disparar una captura)
        speakerSeparationEnabled = \(speakerSeparationEnabled)\(speakerSeparationEnabled ? " (separa voces dentro del canal del sistema en Hablante 1/2/3…)" : "")
        voiceMemoryEnabled = \(voiceMemoryEnabled)\(voiceMemoryEnabled ? " (recuerda voces confirmadas, cifrado local)" : "")
        participantsAccessibilityEnabled = \(participantsAccessibilityEnabled)\(participantsAccessibilityEnabled ? " (lee participantes de Zoom/Teams vía Accesibilidad)" : "")
        (archivo: \(Self.fileURL.path))
        """
    }

    func displayValue(forKey key: String) -> String? {
        switch key {
        case "claudeModel": return claudeModel
        case "obsidianDir": return obsidianDir
        case "keepAudio": return String(keepAudio)
        case "whisperModel": return whisperModel
        case "systemPromptPath": return systemPromptPath ?? "(default integrado)"
        case "alwaysOn": return String(alwaysOn)
        case "retentionDays": return String(retentionDays)
        case "language": return language
        case "transcriptPolish": return String(transcriptPolish)
        case "showUpcoming": return String(showUpcoming)
        case "showMenuBarTitle": return String(showMenuBarTitle)
        case "ignoreNoParticipants": return String(ignoreNoParticipants)
        case "calendarIgnore": return calendarIgnore.isEmpty ? "(ninguno)" : calendarIgnore
        case "promptExcludedCalendars": return promptExcludedCalendars.isEmpty ? "(ninguno)" : promptExcludedCalendars
        case "promptIncludedCalendars": return promptIncludedCalendars.isEmpty ? "(ninguno)" : promptIncludedCalendars
        case "promptExcludedAccounts": return promptExcludedAccounts.isEmpty ? "(ninguno)" : promptExcludedAccounts
        case "aiProvider": return aiProvider.rawValue
        case "aiModel": return aiModel.isEmpty ? "(ninguno)" : aiModel
        case "aiBaseURL": return aiBaseURL.isEmpty ? "(ninguno)" : aiBaseURL
        case "slackWebhookURL": return KeychainStore.slackWebhookURL() == nil ? "(no configurado)" : "●●●●●●●● (Keychain)"
        case "notionDatabaseID": return notionDatabaseID.isEmpty ? "(no configurado)" : "●●●●●●●●"
        case "visualContextEnabled": return String(visualContextEnabled)
        case "visualContextExcludedApps": return visualContextExcludedApps.isEmpty ? "(ninguna)" : visualContextExcludedApps
        case "visualContextChangeThreshold": return String(visualContextChangeThreshold)
        case "speakerSeparationEnabled": return String(speakerSeparationEnabled)
        case "voiceMemoryEnabled": return String(voiceMemoryEnabled)
        case "participantsAccessibilityEnabled": return String(participantsAccessibilityEnabled)
        default: return nil
        }
    }

    mutating func set(key: String, value: String) throws {
        switch key {
        case "claudeModel":
            claudeModel = value
        case "obsidianDir":
            obsidianDir = value
        case "keepAudio":
            guard let flag = Bool(value.lowercased()) else {
                throw Self.validationError("keepAudio debe ser true o false")
            }
            keepAudio = flag
        case "whisperModel":
            guard Self.validWhisperModels.contains(value) else {
                throw Self.validationError("whisperModel debe ser uno de: \(Self.validWhisperModels.joined(separator: ", "))")
            }
            whisperModel = value
        case "systemPromptPath":
            systemPromptPath = value.isEmpty ? nil : value
        case "alwaysOn":
            guard let flag = Bool(value.lowercased()) else {
                throw Self.validationError("alwaysOn debe ser true o false")
            }
            alwaysOn = flag
        case "retentionDays":
            guard let days = Int(value), days >= 0 else {
                throw Self.validationError("retentionDays debe ser un entero >= 0 (0 = sin borrado)")
            }
            retentionDays = days
        case "language":
            let normalized = value.lowercased()
            guard Self.validLanguages.contains(normalized) else {
                throw Self.validationError("language debe ser uno de: \(Self.validLanguages.joined(separator: ", "))")
            }
            language = normalized
        case "transcriptPolish":
            guard let flag = Bool(value.lowercased()) else {
                throw Self.validationError("transcriptPolish debe ser true o false")
            }
            transcriptPolish = flag
        case "showUpcoming":
            guard let flag = Bool(value.lowercased()) else {
                throw Self.validationError("showUpcoming debe ser true o false")
            }
            showUpcoming = flag
        case "showMenuBarTitle":
            guard let flag = Bool(value.lowercased()) else {
                throw Self.validationError("showMenuBarTitle debe ser true o false")
            }
            showMenuBarTitle = flag
        case "ignoreNoParticipants":
            guard let flag = Bool(value.lowercased()) else {
                throw Self.validationError("ignoreNoParticipants debe ser true o false")
            }
            ignoreNoParticipants = flag
        case "calendarIgnore":
            calendarIgnore = value == "(ninguno)" ? "" : value
        case "promptExcludedCalendars":
            promptExcludedCalendars = value == "(ninguno)" ? "" : value
        case "promptIncludedCalendars":
            promptIncludedCalendars = value == "(ninguno)" ? "" : value
        case "promptExcludedAccounts":
            promptExcludedAccounts = value == "(ninguno)" ? "" : value
        case "aiProvider":
            guard let kind = AIProviderKind(rawValue: value) else {
                throw Self.validationError("aiProvider debe ser uno de: \(AIProviderKind.allCases.map(\.rawValue).joined(separator: ", "))")
            }
            aiProvider = kind
        case "aiModel":
            aiModel = value == "(ninguno)" ? "" : value
        case "aiBaseURL":
            aiBaseURL = value == "(ninguno)" ? "" : value
        case "slackWebhookURL":
            guard KeychainStore.saveSlackWebhookURL(value) else {
                throw Self.validationError("No se pudo guardar el Slack Webhook URL en Keychain")
            }
        case "notionDatabaseID":
            notionDatabaseID = value
        case "visualContextEnabled":
            guard let flag = Bool(value.lowercased()) else {
                throw Self.validationError("visualContextEnabled debe ser true o false")
            }
            visualContextEnabled = flag
        case "visualContextExcludedApps":
            visualContextExcludedApps = value == "(ninguna)" ? "" : value
        case "visualContextChangeThreshold":
            guard let threshold = Double(value), threshold > 0, threshold < 1 else {
                throw Self.validationError("visualContextChangeThreshold debe ser un número entre 0 y 1 (fracción de cambio)")
            }
            visualContextChangeThreshold = threshold
        case "speakerSeparationEnabled":
            guard let flag = Bool(value.lowercased()) else {
                throw Self.validationError("speakerSeparationEnabled debe ser true o false")
            }
            speakerSeparationEnabled = flag
        case "voiceMemoryEnabled":
            guard let flag = Bool(value.lowercased()) else {
                throw Self.validationError("voiceMemoryEnabled debe ser true o false")
            }
            voiceMemoryEnabled = flag
        case "participantsAccessibilityEnabled":
            guard let flag = Bool(value.lowercased()) else {
                throw Self.validationError("participantsAccessibilityEnabled debe ser true o false")
            }
            participantsAccessibilityEnabled = flag
        default:
            throw Self.validationError("Clave desconocida '\(key)'. Válidas: claudeModel, obsidianDir, keepAudio, whisperModel, systemPromptPath, alwaysOn, retentionDays, language, transcriptPolish, showUpcoming, showMenuBarTitle, ignoreNoParticipants, calendarIgnore, promptExcludedCalendars, promptIncludedCalendars, promptExcludedAccounts, aiProvider, aiModel, aiBaseURL, slackWebhookURL, notionDatabaseID, visualContextEnabled, visualContextExcludedApps, visualContextChangeThreshold, speakerSeparationEnabled, voiceMemoryEnabled, participantsAccessibilityEnabled")
        }
    }

    private static func validationError(_ message: String) -> NSError {
        NSError(domain: "aria.config", code: 1, userInfo: [NSLocalizedDescriptionKey: message])
    }
}
