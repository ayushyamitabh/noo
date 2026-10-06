import Foundation
import Security

/// The signed-in account, as much of it as the Share Extension needs to list
/// folders and upload: the app writes it when an account becomes active and
/// clears it on sign-out. Compiled into both targets.
struct SharedAccount: Codable, Equatable {
  let serverUrl: String
  let username: String
  /// `Basic ...` - the app password never leaves the Keychain as plain text.
  let authHeader: String
  /// Shown in the picker, e.g. "alice@cloud.example.com".
  let displayName: String
}

/// Keeps the [SharedAccount] in a Keychain access group both the app and the
/// extension are entitled to (`keychain-access-groups`). The group's full id
/// carries the signing team's prefix, so it's injected into each target's
/// Info.plist as `NooKeychainAccessGroup` (= `$(AppIdentifierPrefix)` +
/// `dev.ayushya.noo.shared`) instead of being hard-coded - both processes
/// then always agree on it, with or without a team.
enum SharedAccountStore {
  private static let service = "dev.ayushya.noo.shared-account"
  private static let account = "active"

  static var accessGroup: String? {
    Bundle.main.object(forInfoDictionaryKey: "NooKeychainAccessGroup") as? String
  }

  private static func baseQuery() -> [String: Any] {
    var query: [String: Any] = [
      kSecClass as String: kSecClassGenericPassword,
      kSecAttrService as String: service,
      kSecAttrAccount as String: account,
    ]
    if let group = accessGroup, !group.isEmpty {
      query[kSecAttrAccessGroup as String] = group
    }
    return query
  }

  static func save(_ value: SharedAccount) throws {
    let data = try JSONEncoder().encode(value)
    clear()
    var query = baseQuery()
    query[kSecValueData as String] = data
    query[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
    let status = SecItemAdd(query as CFDictionary, nil)
    guard status == errSecSuccess else {
      throw NSError(domain: NSOSStatusErrorDomain, code: Int(status))
    }
  }

  static func load() -> SharedAccount? {
    var query = baseQuery()
    query[kSecReturnData as String] = true
    query[kSecMatchLimit as String] = kSecMatchLimitOne
    var result: AnyObject?
    guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
      let data = result as? Data
    else { return nil }
    return try? JSONDecoder().decode(SharedAccount.self, from: data)
  }

  static func clear() {
    SecItemDelete(baseQuery() as CFDictionary)
  }
}
