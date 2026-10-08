import Foundation
import Security

/// Every account's sync settings and credentials, kept in the Keychain (the
/// auth header is a secret) as one JSON item. A background run - which may
/// start while the app isn't running - reads these to know what to sync and
/// as whom, and a conflict notification's action looks the account up here
/// instead of carrying credentials in the notification itself.
///
/// `kSecAttrAccessibleAfterFirstUnlock`, not "when unlocked": a background
/// task can fire with the phone locked.
///
/// All accounts live in one item, so a write must never be built on a
/// failed read: an unreadable item makes `upsert`/`remove` do nothing (and
/// say so) rather than save a map holding only one account, and an update
/// replaces the item in place instead of deleting it first.
final class SyncConfigStore {
  private struct KeychainError: Error { let status: OSStatus }

  private let service: String
  private let account = "configs"
  private let lock = NSLock()

  init(service: String = "dev.ayushya.noo.sync-configs") {
    self.service = service
  }

  /// Empty if there are none - or if the item can't be read, in which case
  /// nothing runs in the background until it can.
  func all() -> [SyncAccountConfig] {
    lock.lock()
    defer { lock.unlock() }
    return Array(((try? load()) ?? [:]).values).sorted { $0.accountId < $1.accountId }
  }

  func config(for accountId: String) -> SyncAccountConfig? {
    lock.lock()
    defer { lock.unlock() }
    return (try? load())?[accountId]
  }

  /// False if it couldn't be stored (the previous contents are untouched).
  @discardableResult
  func upsert(_ config: SyncAccountConfig) -> Bool {
    lock.lock()
    defer { lock.unlock() }
    do {
      var configs = try load()
      configs[config.accountId] = config
      try save(configs)
      return true
    } catch {
      NSLog("[Sync] couldn't store config for %@: %@", config.accountId, String(describing: error))
      return false
    }
  }

  @discardableResult
  func remove(accountId: String) -> Bool {
    lock.lock()
    defer { lock.unlock() }
    do {
      var configs = try load()
      guard configs.removeValue(forKey: accountId) != nil else { return true }
      try save(configs)
      return true
    } catch {
      NSLog("[Sync] couldn't remove config for %@: %@", accountId, String(describing: error))
      return false
    }
  }

  func removeAll() {
    lock.lock()
    defer { lock.unlock() }
    SecItemDelete(baseQuery() as CFDictionary)
  }

  // MARK: - Keychain

  private func baseQuery() -> [String: Any] {
    [
      kSecClass as String: kSecClassGenericPassword,
      kSecAttrService as String: service,
      kSecAttrAccount as String: account,
    ]
  }

  /// `[:]` only when nothing is stored yet; any other failure throws.
  private func load() throws -> [String: SyncAccountConfig] {
    var query = baseQuery()
    query[kSecReturnData as String] = true
    query[kSecMatchLimit as String] = kSecMatchLimitOne
    var result: AnyObject?
    let status = SecItemCopyMatching(query as CFDictionary, &result)
    if status == errSecItemNotFound { return [:] }
    guard status == errSecSuccess, let data = result as? Data else { throw KeychainError(status: status) }
    return try JSONDecoder().decode([String: SyncAccountConfig].self, from: data)
  }

  private func save(_ configs: [String: SyncAccountConfig]) throws {
    guard !configs.isEmpty else {
      let status = SecItemDelete(baseQuery() as CFDictionary)
      if status != errSecSuccess && status != errSecItemNotFound { throw KeychainError(status: status) }
      return
    }
    let data = try JSONEncoder().encode(configs)  // before touching the item
    let status = SecItemUpdate(
      baseQuery() as CFDictionary, [kSecValueData as String: data] as CFDictionary)
    if status == errSecItemNotFound {
      var query = baseQuery()
      query[kSecValueData as String] = data
      query[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
      let added = SecItemAdd(query as CFDictionary, nil)
      if added != errSecSuccess { throw KeychainError(status: added) }
    } else if status != errSecSuccess {
      throw KeychainError(status: status)
    }
  }
}
