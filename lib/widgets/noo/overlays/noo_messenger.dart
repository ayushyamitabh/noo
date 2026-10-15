import 'dart:async';
import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';
import '../../../theme/design_tokens.dart';
import '../noo_layout.dart';

/// A drop-in for `ScaffoldMessenger.of(context)` that gives each platform its
/// own transient message: Material's [SnackBar] on Android, and on iOS - which has no snackbar - a small banner that drops
/// in from under the status bar, fades after a few seconds and can be
/// swiped away.
///
/// Call sites keep passing a [SnackBar] (only its `content`, `action` and
/// `duration` are used on iOS), so switching a screen over is just
/// `ScaffoldMessenger.of(context)` -> `NooMessenger.of(context)`. Like the
/// scaffold messenger it's meant to be grabbed *before* an `await` and used
/// after.
class NooMessenger {
  final ScaffoldMessengerState _messenger;
  final OverlayState? _overlay;
  final bool _ios;

  const NooMessenger._(this._messenger, this._overlay, this._ios);

  static NooMessenger of(BuildContext context) {
    final ios = NooLayout.iosStyle(context);
    return NooMessenger._(
      ScaffoldMessenger.of(context),
      ios ? Overlay.maybeOf(context, rootOverlay: true) : null,
      ios,
    );
  }

  bool get _banner => _ios && _overlay != null;

  void showSnackBar(SnackBar snackBar) {
    if (!_banner) {
      _messenger.showSnackBar(snackBar);
      return;
    }
    _IosBanner.show(_overlay!, snackBar);
  }

  void hideCurrentSnackBar() {
    if (!_banner) {
      _messenger.hideCurrentSnackBar();
      return;
    }
    _IosBanner.dismissCurrent();
  }
}

/// The iOS presentation. One at a time: a new message replaces the current one.
class _IosBanner extends StatefulWidget {
  final SnackBar snackBar;
  final VoidCallback onGone;
  const _IosBanner({required this.snackBar, required this.onGone});

  static OverlayEntry? _entry;
  static _IosBannerState? _state;

  static void show(OverlayState overlay, SnackBar snackBar) {
    dismissCurrent(immediately: true);
    late final OverlayEntry entry;
    entry = OverlayEntry(
      builder: (_) => _IosBanner(
        snackBar: snackBar,
        onGone: () {
          if (_entry == entry) {
            _entry = null;
            _state = null;
          }
          entry.remove();
          entry.dispose();
        },
      ),
    );
    _entry = entry;
    overlay.insert(entry);
  }

  static void dismissCurrent({bool immediately = false}) {
    final state = _state;
    if (state != null) {
      state.dismiss(immediately: immediately);
    }
  }

  @override
  State<_IosBanner> createState() => _IosBannerState();
}

class _IosBannerState extends State<_IosBanner>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 320),
    reverseDuration: const Duration(milliseconds: 220),
  );
  late final Animation<double> _curve = CurvedAnimation(
    parent: _controller,
    curve: Curves.easeOutCubic,
    reverseCurve: Curves.easeInCubic,
  );
  Timer? _timer;
  bool _leaving = false;

  @override
  void initState() {
    super.initState();
    _IosBanner._state = this;
    _controller.forward();
    final duration = widget.snackBar.duration;
    _timer = Timer(duration, dismiss);
  }

  Future<void> dismiss({bool immediately = false}) async {
    if (_leaving) return;
    _leaving = true;
    _timer?.cancel();
    if (!immediately && mounted) {
      await _controller.reverse();
    }
    widget.onGone();
  }

  @override
  void dispose() {
    _timer?.cancel();
    _controller.dispose();
    if (_IosBanner._state == this) _IosBanner._state = null;
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.nooColors;
    final top = MediaQuery.paddingOf(context).top + 8;
    final action = widget.snackBar.action;
    return Positioned(
      top: top,
      left: 16,
      right: 16,
      child: AnimatedBuilder(
        animation: _curve,
        builder: (context, child) => Opacity(
          opacity: _curve.value,
          child: Transform.translate(
            offset: Offset(0, -24 * (1 - _curve.value)),
            child: child,
          ),
        ),
        child: Align(
          alignment: Alignment.topCenter,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: GestureDetector(
              onTap: dismiss,
              onVerticalDragEnd: (details) {
                if ((details.primaryVelocity ?? 0) < -150) dismiss();
              },
              child: Semantics(
                liveRegion: true,
                container: true,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(NooRadii.card),
                  child: BackdropFilter(
                    filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: colors.surface.withValues(alpha: 0.9),
                        border: Border.all(color: colors.line),
                        borderRadius: BorderRadius.circular(NooRadii.card),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 12,
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Flexible(
                              child: DefaultTextStyle(
                                style: NooText.body.copyWith(color: colors.fg1),
                                child: widget.snackBar.content,
                              ),
                            ),
                            if (action != null) ...[
                              const SizedBox(width: 12),
                              GestureDetector(
                                behavior: HitTestBehavior.opaque,
                                onTap: () {
                                  action.onPressed();
                                  dismiss();
                                },
                                child: Text(
                                  action.label,
                                  style: NooText.body.copyWith(
                                    color: colors.accentText,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
