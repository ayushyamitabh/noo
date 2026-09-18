import 'package:flutter/material.dart';
import 'package:marquee/marquee.dart';

/// A plain, single-line ellipsized [Text] for content that fits, or an
/// auto-scrolling [Marquee] for text too long for the available width -
/// measured once via [TextPainter] rather than always marqueeing, so short
/// text just sits still like normal.
class MarqueeTitle extends StatelessWidget {
  final String text;
  final TextStyle? style;

  const MarqueeTitle({super.key, required this.text, required this.style});

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final painter = TextPainter(
          text: TextSpan(text: text, style: style),
          maxLines: 1,
          textDirection: Directionality.of(context),
        )..layout(maxWidth: double.infinity);

        if (painter.width <= constraints.maxWidth) {
          return Text(
            text,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: style,
          );
        }

        return SizedBox(
          height: painter.height,
          child: Marquee(
            text: text,
            style: style,
            blankSpace: 48,
            velocity: 30,
            startPadding: 0,
            pauseAfterRound: const Duration(seconds: 1),
            fadingEdgeStartFraction: 0.1,
            fadingEdgeEndFraction: 0.15,
          ),
        );
      },
    );
  }
}
