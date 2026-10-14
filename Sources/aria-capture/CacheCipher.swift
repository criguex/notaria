import CryptoKit
import Foundation
import Security

final class CacheCipher {

    static let keychainService = "aria-cache-key"
    private static let prefix = "enc1:"

    private let key: SymmetricKey

    init() throws {
        key = try Self.loadOrCreateKey()
    }

    func encrypt(_ plaintext: String) -> String {
        guard let data = plaintext.data(using: .utf8),
              let sealed = try? AES.GCM.seal(data, using: key),
              let combined = sealed.combined else {
            return plaintext
        }
        return Self.prefix + combined.base64EncodedString()
    }

    func decrypt(_ stored: String) -> String {
        guard stored.hasPrefix(Self.prefix) else { return stored }
        let base64 = String(stored.dropFirst(Self.prefix.count))
        guard let combined = Data(base64Encoded: base64),
              let sealed = try? AES.GCM.SealedBox(combined: combined),
              let data = try? AES.GCM.open(sealed, using: key),
              let text = String(data: data, encoding: .utf8) else {
            return "(no descifrable)"
        }
        return text
    }

    private static func loadOrCreateKey() throws -> SymmetricKey {
        if let stored = KeychainCLI.read(service: keychainService, account: "aria"),
           let data = Data(base64Encoded: stored), data.count == 32 {
            return SymmetricKey(data: data)
        }

        let newKey = SymmetricKey(size: .bits256)
        let base64 = newKey.withUnsafeBytes { Data($0) }.base64EncodedString()
        guard KeychainCLI.write(service: keychainService, account: "aria", secret: base64) else {
            throw NSError(domain: "aria.cipher", code: 1, userInfo: [
                NSLocalizedDescriptionKey: "No se pudo guardar la clave de cifrado en el Keychain."
            ])
        }
        return newKey
    }
}
