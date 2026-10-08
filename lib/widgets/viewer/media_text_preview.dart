import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import '../../models/nextcloud_item.dart';
import '../../providers/session_controller.dart';
import '../../theme/design_tokens.dart';

/// Space the viewer's floating top bar and bottom action bar cover, so the
/// text sits clear of them (and the status bar) instead of scrolling
/// underneath.
const double _kTopBarClearance = 72;
const double _kActionBarClearance = 112;

/// What the viewer's top bar needs from [MediaTextPreview]: whether to show
/// the Edit/Preview toggle and the Save button, their current state, and a way
/// to trigger them. The preview owns the text, the editing mode and the save;
/// this just mirrors that out so `FileViewerScreen` can draw the buttons in
/// its own top bar (they used to float inside the preview).
class TextPreviewController extends ChangeNotifier {
  bool _canToggleEditing = false;
  bool _editing = false;
  bool _dirty = false;
  bool _saving = false;
  bool _disposed = false;
  VoidCallback? _onToggleEditing;
  Future<void> Function()? _onSave;

  /// Markdown, writable (not the read-only Offline copy) and loaded - the
  /// Edit/Preview toggle only exists then.
  bool get canToggleEditing => _canToggleEditing;

  /// Markdown is currently showing its raw text (the toggle then offers
  /// "Preview"); false while rendered (it offers "Edit").
  bool get editing => _editing;

  /// The text differs from what's saved on the server.
  bool get dirty => _dirty;
  bool get saving => _saving;

  /// The Save button is shown once the content has changed, and stays (as a
  /// spinner) while the save is in flight.
  bool get showSave => _dirty || _saving;

  void toggleEditing() => _onToggleEditing?.call();
  Future<void> save() async => _onSave?.call();

  void _bind(VoidCallback toggleEditing, Future<void> Function() save) {
    _onToggleEditing = toggleEditing;
    _onSave = save;
  }

  /// The preview went away: nothing to toggle or save any more. Quiet (no
  /// notification) - it happens while the tree is being torn down.
  void _unbind() {
    _onToggleEditing = null;
    _onSave = null;
    _canToggleEditing = false;
    _editing = false;
    _dirty = false;
    _saving = false;
  }

  void _update({
    required bool canToggleEditing,
    required bool editing,
    required bool dirty,
    required bool saving,
  }) {
    if (_canToggleEditing == canToggleEditing &&
        _editing == editing &&
        _dirty == dirty &&
        _saving == saving) {
      return;
    }
    _canToggleEditing = canToggleEditing;
    _editing = editing;
    _dirty = dirty;
    _saving = saving;
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}

/// Text/markdown file preview and editor for [FileViewerScreen]'s static
/// (non-swipeable) path (`_textPreviewExtensions`). Content is always
/// editable when online - after tapping Edit; every file opens read-only
/// (Markdown rendered) with an Edit/Preview toggle - and Save appears once it
/// has changed. Both controls live in the viewer's
/// top bar, driven through [controller]. Opened from the Offline tab
/// ([localPathResolver] set) it is read-only, since the local copy has no
/// server to write back to.
class MediaTextPreview extends StatefulWidget {
  final NextcloudItem item;
  final SessionController session;

  /// Receives this preview's editing/save state and is how the top bar's
  /// buttons reach it. Optional so the preview also works on its own.
  final TextPreviewController? controller;

  /// When set, read bytes from the local path it resolves to instead of
  /// fetching from the server - see
  /// `FileViewerScreen.localPathResolver`'s doc comment.
  final Future<String?> Function(NextcloudItem item)? localPathResolver;

  const MediaTextPreview({
    super.key,
    required this.item,
    required this.session,
    this.controller,
    this.localPathResolver,
  });

  @override
  State<MediaTextPreview> createState() => _MediaTextPreviewState();
}

class _MediaTextPreviewState extends State<MediaTextPreview> {
  final _controller = TextEditingController();
  String? _saved;
  String? _error;
  bool _isSaving = false;
  bool _editing = false;
  final _focus = FocusNode();

  bool get _isMarkdown {
    final name = widget.item.name.toLowerCase();
    return name.endsWith('.md') || name.endsWith('.markdown');
  }

  /// Markdown shows rendered until the user taps Edit. Plain text has no
  /// rendered form, so it just shows its (read-only) text until then.
  bool get _showRendered => _isMarkdown && !_editing;

  bool get _readOnly => widget.localPathResolver != null;
  bool get _dirty => _saved != null && _controller.text != _saved;

  @override
  void initState() {
    super.initState();
    widget.controller?._bind(_toggleEditing, _save);
    _controller.addListener(() {
      setState(() {});
      _syncToolbar();
    });
    _load();
  }

  @override
  void dispose() {
    widget.controller?._unbind();
    _focus.dispose();
    _controller.dispose();
    super.dispose();
  }

  /// Mirrors the editing/save state out to the viewer's top bar. Only called
  /// from event handlers and async completions - never from build or
  /// initState, where notifying the bar's listeners would be illegal.
  void _syncToolbar() {
    widget.controller?._update(
      canToggleEditing: _saved != null && !_readOnly,
      editing: _editing,
      dirty: _dirty,
      saving: _isSaving,
    );
  }

  void _toggleEditing() {
    setState(() => _editing = !_editing);
    _syncToolbar();
    // Tapping Edit should put the cursor in the text, not just unlock it.
    if (_editing) {
      WidgetsBinding.instance.addPostFrameCallback(
        (_) => _focus.requestFocus(),
      );
    }
  }

  Future<void> _load() async {
    try {
      final List<int> bytes;
      if (widget.localPathResolver != null) {
        final localPath = await widget.localPathResolver!(widget.item);
        if (localPath == null) {
          if (mounted) {
            setState(() => _error = 'No longer available offline');
          }
          return;
        }
        bytes = await File(localPath).readAsBytes();
      } else {
        bytes = await widget.session.service!.fetchBytes(widget.item.path);
      }
      if (mounted) {
        final text = utf8.decode(bytes, allowMalformed: true);
        _controller.text = text;
        setState(() => _saved = text);
        _syncToolbar();
      }
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    }
  }

  Future<void> _save() async {
    final messenger = ScaffoldMessenger.of(context);
    final text = _controller.text;
    setState(() => _isSaving = true);
    _syncToolbar();
    var ok = false;
    try {
      ok = await widget.session.service!.putBytes(
        widget.item.path,
        utf8.encode(text),
      );
    } catch (_) {}
    if (!mounted) return;
    setState(() {
      _isSaving = false;
      if (ok) _saved = text;
    });
    _syncToolbar();
    messenger.showSnackBar(
      SnackBar(
        content: Text(ok ? 'Saved ${widget.item.name}' : 'Could not save file'),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.nooColors;
    if (_error != null) {
      return Center(
        child: Text(
          'Could not load file: $_error',
          style: TextStyle(color: colors.fg2),
        ),
      );
    }
    if (_saved == null) {
      return Center(child: CircularProgressIndicator(color: colors.accent));
    }
    final safe = MediaQuery.paddingOf(context);
    final style = NooText.mono.copyWith(color: colors.fg1, height: 1.5);
    final padding = EdgeInsets.fromLTRB(
      20,
      safe.top + _kTopBarClearance,
      20,
      safe.bottom + _kActionBarClearance,
    );
    return Container(
      color: colors.surface,
      child: Stack(
        children: [
          Positioned.fill(
            child: _showRendered
                ? Markdown(
                    data: _controller.text,
                    padding: padding,
                    selectable: true,
                    styleSheet: _markdownStyle(context, colors),
                    onTapLink: (_, href, _) {},
                  )
                : SingleChildScrollView(
                    padding: padding,
                    child: TextField(
                      controller: _controller,
                      focusNode: _focus,
                      // Read-only until Edit is tapped (always, for the
                      // Offline copy).
                      readOnly: _readOnly || !_editing,
                      maxLines: null,
                      keyboardType: TextInputType.multiline,
                      style: style,
                      cursorColor: colors.accentText,
                      decoration: const InputDecoration(
                        isDense: true,
                        border: InputBorder.none,
                        contentPadding: EdgeInsets.zero,
                      ),
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}

MarkdownStyleSheet _markdownStyle(BuildContext context, NooColors colors) {
  final body = NooText.body.copyWith(color: colors.fg1, height: 1.55);
  TextStyle heading(double size) =>
      NooText.title.copyWith(color: colors.fg1, fontSize: size, height: 1.25);
  return MarkdownStyleSheet.fromTheme(Theme.of(context)).copyWith(
    p: body,
    h1: heading(26),
    h2: heading(22),
    h3: heading(19),
    h4: heading(17),
    listBullet: body,
    a: body.copyWith(color: colors.accentText),
    blockquote: body.copyWith(color: colors.fg2),
    blockquoteDecoration: BoxDecoration(
      border: Border(left: BorderSide(color: colors.line, width: 3)),
    ),
    code: NooText.mono.copyWith(
      color: colors.fg1,
      backgroundColor: colors.surface2,
    ),
    codeblockDecoration: BoxDecoration(
      color: colors.surface2,
      borderRadius: BorderRadius.circular(NooRadii.input),
    ),
    horizontalRuleDecoration: BoxDecoration(
      border: Border(top: BorderSide(color: colors.line)),
    ),
  );
}
