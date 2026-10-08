import Foundation
import Security

/// One signed-in account, as much of it as the Share Extension needs to list
/// folders and upload. Compiled into both targets.
struct SharedAccount: Codable, Equatable, Identifiable {
  let id: String
  let serverUrl: String
  let username: String
  /// `Basic ...` - the app password never leaves the Keychain as plain text.
  let authHeader: String
  /// Shown in the picker, e.g. "alice@cloud.example.com".
  let displayName: String
  /// The app's Files "hidden files" filter for this account - `hide` (the
  /// default), `only` or `include` (see `HiddenFilter`). The share sheet
  /// follows it instead of having a setting of its own.
  let hiddenFilter: String
  /// The app's storage scope for this account - `cloud` (the default),
  /// `external` or `all` (see `StorageFilter`).
  let storageScope: String

  init(
    id: String, serverUrl: String, username: String, authHeader: String, displayName: String,
    hiddenFilter: String = "hide", storageScope: String = "cloud"
  ) {
    self.id = id
    self.serverUrl = serverUrl
    self.username = username
    self.authHeader = authHeader
    self.displayName = displayName
    self.hiddenFilter = hiddenFilter
    self.storageScope = storageScope
  }

  /// Tolerates data written before a field existed instead of failing the
  /// whole decode (which would look like "signed out" to the extension).
  init(from decoder: Decoder) throws {
    let c = try decoder.container(keyedBy: CodingKeys.self)
    self.init(
      id: try c.decode(String.self, forKey: .id),
      serverUrl: try c.decode(String.self, forKey: .serverUrl),
      username: try c.decode(String.self, forKey: .username),
      authHeader: try c.decode(String.self, forKey: .authHeader),
      displayName: try c.decode(String.self, forKey: .displayName),
      hiddenFilter: try c.decodeIfPresent(String.self, forKey: .hiddenFilter) ?? "hide",
      storageScope: try c.decodeIfPresent(String.self, forKey: .storageScope) ?? "cloud"
    )
  }
}

/// Everything the app publishes for the extension: every account that can
/// upload, which one is active in the app, and the app-lock settings the
/// extension has to honour. The app rewrites it whenever any of that changes.
struct SharedAccounts: Codable, Equatable {
  var accounts: [SharedAccount]
  var activeId: String?
  /// Settings -> Security: the three independent locks. `loginLockEnabled`
  /// (unlock to open the app) is carried for completeness; the extension's own
  /// gates are the other two.
  var loginLockEnabled: Bool
  var lockAccountSwitching: Bool
  var lockHiddenFiles: Bool

  /// The account the app is currently using, else the first one.
  var active: SharedAccount? {
    accounts.first { $0.id == activeId } ?? accounts.first
  }

  /// Uploading to an account other than the active one is "switching" in
  /// the app's terms, so it needs the same unlock.
  var needsUnlockToSwitchAccount: Bool { lockAccountSwitching }

  /// Showing hidden folders needs the same unlock the app asks for when you
  /// turn hidden files on.
  var needsUnlockForHidden: Bool { lockHiddenFiles }

  /// What choosing [account] (with [hidden] folders to show) asks the user
  /// to unlock. One action, one prompt - when both the account switch and
  /// the hidden folders need it, a single authentication covers both.
  func unlockNeeds(choosing account: SharedAccount, showing hidden: HiddenFilter) -> SelectionUnlock {
    SelectionUnlock(
      switchesAccount: account.id != active?.id && needsUnlockToSwitchAccount,
      showsHidden: hidden != .hide && needsUnlockForHidden)
  }

  /// Turning hidden folders on (from `hide`) is what the app locks; going
  /// back to `hide`, or between the two revealing modes, never asks.
  func needsUnlockToChangeHidden(from old: HiddenFilter, to new: HiddenFilter) -> Bool {
    old == .hide && new != .hide && needsUnlockForHidden
  }
}

/// Keeps the [SharedAccounts] in a Keychain access group both the app and the
/// extension are entitled to (`keychain-access-groups`). The group's full id
/// carries the signing team's prefix, so it's injected into each target's
/// Info.plist as `NooKeychainAccessGroup` (= `$(AppIdentifierPrefix)` +
/// `dev.ayushya.noo.shared`) instead of being hard-coded - both processes
/// then always agree on it, with or without a team.
enum SharedAccountStore {
  private static let service = "dev.ayushya.noo.shared-accounts"
  private static let account = "all"

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

  static func save(_ value: SharedAccounts) throws {
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

  static func load() -> SharedAccounts? {
    var query = baseQuery()
    query[kSecReturnData as String] = true
    query[kSecMatchLimit as String] = kSecMatchLimitOne
    var result: AnyObject?
    guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
      let data = result as? Data,
      let decoded = try? JSONDecoder().decode(SharedAccounts.self, from: data),
      !decoded.accounts.isEmpty
    else { return nil }
    return decoded
  }

  static func clear() {
    SecItemDelete(baseQuery() as CFDictionary)
    // The first version kept a single account under its own service name;
    // don't leave that credential behind.
    var legacy = baseQuery()
    legacy[kSecAttrService as String] = "dev.ayushya.noo.shared-account"
    legacy[kSecAttrAccount as String] = "active"
    SecItemDelete(legacy as CFDictionary)
  }
}

/// What one selection needs unlocked - see `SharedAccounts.unlockNeeds`.
struct SelectionUnlock: Equatable {
  let switchesAccount: Bool
  let showsHidden: Bool

  var needsPrompt: Bool { switchesAccount || showsHidden }
}
