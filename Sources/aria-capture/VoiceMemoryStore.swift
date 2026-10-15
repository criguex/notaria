import Foundation

struct VoiceProfile: Codable, Equatable {
    var name: String
    var embedding: SpeakerEmbedding
    var updatedAt: Date
}

/// Capa 2d (opt-in, `AriaConfig.voiceMemoryEnabled`): cuando el usuario confirma/renombra un
/// "Hablante N" a un nombre real, guarda su embedding de voz cifrado y local para reconocerla en
/// próximas reuniones. Un JSON cifrado (mismo patrón que `MeetingStore`/`CacheCipher`, campo a
/// campo con AES-GCM) en vez de una tabla SQLite porque es un diccionario chico sin necesidad de
/// queries — nunca sale del Mac, el usuario puede borrar cualquier perfil.
final class VoiceMemoryStore {

    static var defaultFileURL: URL {
        AriaHome.applicationSupportDirectory
            .appendingPathComponent("Aria/voice-memory.json")
    }

    static let defaultMatchThreshold: Float = 0.86

    private let fileURL: URL
    private let cipher: CacheCipher

    init(fileURL: URL? = nil) throws {
        self.fileURL = fileURL ?? Self.defaultFileURL
        self.cipher = try CacheCipher()
    }

    func load() -> [VoiceProfile] {
        guard let encrypted = try? String(contentsOf: fileURL, encoding: .utf8) else { return [] }
        let decrypted = cipher.decrypt(encrypted)
        guard let data = decrypted.data(using: .utf8),
              let profiles = try? JSONDecoder().decode([VoiceProfile].self, from: data) else {
            return []
        }
        return profiles
    }

    @discardableResult
    func upsert(name: String, embedding: SpeakerEmbedding) throws -> [VoiceProfile] {
        var profiles = load()
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return profiles }
        if let index = profiles.firstIndex(where: { $0.name.lowercased() == trimmed.lowercased() }) {
            profiles[index] = VoiceProfile(name: trimmed, embedding: embedding, updatedAt: Date())
        } else {
            profiles.append(VoiceProfile(name: trimmed, embedding: embedding, updatedAt: Date()))
        }
        try save(profiles)
        return profiles
    }

    @discardableResult
    func delete(name: String) throws -> [VoiceProfile] {
        var profiles = load()
        profiles.removeAll { $0.name.lowercased() == name.lowercased() }
        try save(profiles)
        return profiles
    }

    /// Mejor coincidencia por similitud coseno contra los perfiles guardados, si pasa el umbral.
    func match(_ embedding: SpeakerEmbedding, threshold: Float = VoiceMemoryStore.defaultMatchThreshold) -> (name: String, confidence: Double)? {
        Self.bestMatch(embedding, in: load(), threshold: threshold)
    }

    /// Variante pura (sin IO) para tests y para matchear contra un snapshot ya cargado.
    static func bestMatch(_ embedding: SpeakerEmbedding, in profiles: [VoiceProfile], threshold: Float = VoiceMemoryStore.defaultMatchThreshold) -> (name: String, confidence: Double)? {
        var best: (name: String, similarity: Float)?
        for profile in profiles {
            let similarity = SpeakerEmbedding.cosineSimilarity(profile.embedding, embedding)
            if best == nil || similarity > best!.similarity {
                best = (profile.name, similarity)
            }
        }
        guard let best, best.similarity >= threshold else { return nil }
        return (best.name, Double(best.similarity))
    }

    private func save(_ profiles: [VoiceProfile]) throws {
        let data = try JSONEncoder().encode(profiles)
        guard let json = String(data: data, encoding: .utf8) else { return }
        try FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true
        )
        try cipher.encrypt(json).write(to: fileURL, atomically: true, encoding: .utf8)
    }
}
