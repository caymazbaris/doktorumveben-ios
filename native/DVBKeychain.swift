import Foundation
import Security

/// Tur 235 — Sanctum jetonunu Keychain'de saklar.
///
/// NEDEN UserDefaults DEĞİL: jeton, hastanın tüm sağlık verisine (randevu, belge,
/// onam) erişim anahtarıdır. UserDefaults yedeklemelerde düz metin taşınır; Keychain
/// `ThisDeviceOnly` ile hem şifreli hem de cihazdan çıkmaz.
enum DVBKeychain {

    private static let service = "com.doktorumveben.app"
    private static let account = "sanctum_token"

    static func save(_ token: String) {
        guard let data = token.data(using: .utf8) else { return }
        delete()

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecValueData as String: data,
            // Cihaz kilidi açıkken erişilebilir + yedeklemeyle BAŞKA cihaza taşınmaz.
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
        ]
        SecItemAdd(query as CFDictionary, nil)
    }

    static func read() -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]

        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data,
              let token = String(data: data, encoding: .utf8),
              !token.isEmpty
        else { return nil }

        return token
    }

    static func delete() {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        SecItemDelete(query as CFDictionary)
    }
}
