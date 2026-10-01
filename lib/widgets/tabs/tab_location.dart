/// Turns a full item path plus its own name into a display-friendly parent
/// folder label - shared by Recent ("action + location") and Trash
/// ("original location") per `DESIGN_SYSTEM.md` §4.
String tabLocationLabel(String fullPath, String name) {
  final folder = fullPath.length >= name.length
      ? fullPath.substring(0, fullPath.length - name.length)
      : fullPath;
  final trimmed = folder.replaceAll(RegExp(r'^/+|/+$'), '');
  return trimmed.isEmpty ? 'Home' : trimmed;
}
