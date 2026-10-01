import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import '../../models/nextcloud_item.dart';
import '../../providers/session_controller.dart';
import '../../theme/design_tokens.dart';
import '../noo/core/noo_button.dart';

/// Space the viewer's floating top bar and bottom action bar cover, so the
/// text sits clear of them (and the status bar) instead of scrolling
/// underneath.
const double _kTopBarClearance = 72;
const double _kActionBarClearance = 112;

/// Text/markdown file preview and editor for [FileViewerScreen]'s static
/// (non-swipeable) path (`_textPreviewExtensions`). Content is always
/// editable when online; a Save button appears once it has changed. Markdown
/// files open rendered, with an Edit/Preview toggle. Opened
/// from the Offline tab ([localPathResolver] set) it is read-only, since the
/// local copy has no server to write back to.
class MediaTextPreview extends StatefulWidget {
  final NextcloudItem item;
  final SessionController session;

  /// When set, read bytes from the local path it resolves to instead of
  /// fetching from the server - see
  /// `FileViewerScreen.localPathResolver`'s doc comment.
  final Future<String?> Function(NextcloudItem item)? localPathResolver;

  const MediaTextPreview({
    super.key,
    required this.item,
    required this.session,
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

  bool get _isMarkdown {
    final name = widget.item.name.toLowerCase();
    return name.endsWith('.md') || name.endsWith('.markdown');
  }

  bool get _showRendered => _isMarkdown && !_editing;

  bool get _readOnly => widget.localPathResolver != null;
  bool get _dirty => _saved != null && _controller.text != _saved;

  @override
  void initState() {
    super.initState();
    _controller.addListener(() => setState(() {}));
    _load();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
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
      }
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    }
  }

  Future<void> _save() async {
    final messenger = ScaffoldMessenger.of(context);
    final text = _controller.text;
    setState(() => _isSaving = true);
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
                      readOnly: _readOnly,
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
          if (_isMarkdown && !_readOnly)
            Positioned(
              right: 20,
              top: safe.top + _kTopBarClearance - 8,
              child: NooButton(
                variant: NooButtonVariant.tonal,
                size: NooButtonSize.compact,
                icon: _editing ? LucideIcons.eye : LucideIcons.pencil,
                onTap: () => setState(() => _editing = !_editing),
                child: Text(_editing ? 'Preview' : 'Edit'),
              ),
            ),
          if (_dirty)
            Positioned(
              right: 20,
              bottom: safe.bottom + _kActionBarClearance,
              child: NooButton(
                size: NooButtonSize.card,
                icon: LucideIcons.save,
                disabled: _isSaving,
                onTap: _isSaving ? null : _save,
                child: Text(_isSaving ? 'Saving…' : 'Save'),
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
