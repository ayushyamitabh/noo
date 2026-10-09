import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../services/native_channel.dart';
import '../theme/design_tokens.dart';

/// File providers may take time to export a drop before the picker can open.
class DropPreparationOverlay extends StatelessWidget {
  const DropPreparationOverlay({
    super.key,
    required this.child,
    this.preparation,
  });

  final Widget child;
  final Stream<int>? preparation;
  static final _preparation = quietEvents<int>(
    const EventChannel('dev.ayushya.noo/drop_preparation'),
    (event) => (event as num).toInt(),
  );

  @override
  Widget build(BuildContext context) => StreamBuilder<int>(
    stream: preparation ?? _preparation,
    initialData: 0,
    builder: (context, snapshot) {
      final count = snapshot.data ?? 0;
      final colors = context.nooColors;
      return Stack(
        fit: StackFit.expand,
        children: [
          child,
          if (count > 0) ...[
            const ModalBarrier(dismissible: false, color: Color(0x55000000)),
            Center(
              child: Semantics(
                liveRegion: true,
                child: Material(
                  color: colors.surface2,
                  borderRadius: BorderRadius.circular(20),
                  elevation: 8,
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        SizedBox(
                          width: 24,
                          height: 24,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: colors.accent,
                          ),
                        ),
                        const SizedBox(width: 16),
                        Text(
                          count == 1
                              ? 'Preparing file…'
                              : 'Preparing $count files…',
                          style: NooText.body.copyWith(color: colors.fg1),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        ],
      );
    },
  );
}
