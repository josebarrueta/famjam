import Foundation
import Security

public protocol AuthSessionStore: Sendable {
    func load() async throws -> AuthSession?
    func save(_ session: AuthSession) async throws
    func delete() async throws
}

public enum AuthSessionStoreError: Error, Equatable {
    case keychain(OSStatus)
}

public actor KeychainAuthSessionStore: AuthSessionStore {
    private let service: String
    private let account: String

    public init(service: String = "dev.rallyroo.app.authentication", account: String = "session") {
        self.service = service
        self.account = account
    }

    public func load() async throws -> AuthSession? {
        var query = baseQuery
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = item as? Data else {
            throw AuthSessionStoreError.keychain(status)
        }
        return try JSONDecoder().decode(AuthSession.self, from: data)
    }

    public func save(_ session: AuthSession) async throws {
        let data = try JSONEncoder().encode(session)
        let status = SecItemUpdate(
            baseQuery as CFDictionary,
            [kSecValueData as String: data] as CFDictionary
        )
        if status == errSecItemNotFound {
            var item = baseQuery
            item[kSecValueData as String] = data
            let addStatus = SecItemAdd(item as CFDictionary, nil)
            guard addStatus == errSecSuccess else {
                throw AuthSessionStoreError.keychain(addStatus)
            }
        } else if status != errSecSuccess {
            throw AuthSessionStoreError.keychain(status)
        }
    }

    public func delete() async throws {
        let status = SecItemDelete(baseQuery as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw AuthSessionStoreError.keychain(status)
        }
    }

    private var baseQuery: [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
        ]
    }
}
