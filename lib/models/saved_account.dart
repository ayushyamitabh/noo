/// A saved Nextcloud login. The app password itself lives in secure
/// storage under a key derived from [id] - this model only carries the
/// non-secret identity fields that are safe to keep in SharedPreferences.
class SavedAccount {
  final String id;
  final String serverUrl;
  final String username;

  const SavedAccount({
    required this.id,
    required this.serverUrl,
    required this.username,
  });

  /// A deterministic id from the server + username, so re-adding the same
  /// account refreshes its stored password instead of creating a duplicate
  /// entry in the saved-accounts list.
  static String makeId(String serverUrl, String username) {
    String slug(String s) =>
        s.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '_');
    return '${slug(serverUrl)}__${slug(username)}';
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'serverUrl': serverUrl,
    'username': username,
  };

  factory SavedAccount.fromJson(Map<String, dynamic> json) => SavedAccount(
    id: json['id'] as String,
    serverUrl: json['serverUrl'] as String,
    username: json['username'] as String,
  );
}
