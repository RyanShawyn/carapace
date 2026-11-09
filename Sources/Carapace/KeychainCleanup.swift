import Foundation
import Security

/// 一次性清理旧版本 AI 功能留在 Keychain 里的 API Key。
enum KeychainCleanup {
    static let service = "com.ryan.carapace.ai"

    @discardableResult
    static func purge() -> Int {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecMatchLimit as String: kSecMatchLimitAll,
            kSecReturnAttributes as String: true
        ]
        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let items = result as? [[String: Any]] else { return 0 }

        var removed = 0
        for item in items {
            var delete = item
            delete[kSecClass as String] = kSecClassGenericPassword
            if SecItemDelete(delete as CFDictionary) == errSecSuccess {
                removed += 1
            }
        }
        return removed
    }
}