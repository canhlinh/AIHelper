//
//  KeychainService.swift
//  AIHelper
//

import Foundation
import Security

final class KeychainService: @unchecked Sendable {
    nonisolated static let shared = KeychainService()

    private let service: String
    private let account = "openai_api_key"
    private let legacyDefaultsKey = "openAIApiKey"

    private init() {
        service = Bundle.main.bundleIdentifier ?? "dev.lingcloud.aihelper"
    }

    nonisolated func getAPIKey() -> String {
        migrateLegacyAPIKeyIfNeeded()
        return readAPIKey() ?? ""
    }

    nonisolated func setAPIKey(_ value: String) {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            deleteAPIKey()
        } else {
            saveAPIKey(trimmed)
        }
    }

    nonisolated private func migrateLegacyAPIKeyIfNeeded() {
        guard readAPIKey() == nil else { return }
        let legacyValue = UserDefaults.standard.string(forKey: legacyDefaultsKey) ?? ""
        let trimmed = legacyValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        saveAPIKey(trimmed)
        UserDefaults.standard.removeObject(forKey: legacyDefaultsKey)
    }

    nonisolated private func readAPIKey() -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]

        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess,
              let data = result as? Data,
              let value = String(data: data, encoding: .utf8) else {
            return nil
        }
        return value
    }

    nonisolated private func saveAPIKey(_ value: String) {
        let data = Data(value.utf8)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]

        let attributes: [String: Any] = [
            kSecValueData as String: data
        ]

        let updateStatus = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if updateStatus == errSecItemNotFound {
            var item = query
            item[kSecValueData as String] = data
            SecItemAdd(item as CFDictionary, nil)
        }
    }

    nonisolated private func deleteAPIKey() {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        SecItemDelete(query as CFDictionary)
    }
}
