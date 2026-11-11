import 'package:flutter/material.dart';
import '../../../theme/design_tokens.dart';
import 'noo_floating_shadow.dart';

/// The hero tag shared by the bottom bar's Search button and the bottom
/// search field on `SearchView`, so the bar morphs into the field when search
/// opens and back into the bar when it closes.
const String kSearchBarHeroTag = 'noo-search-bar';

/// Wraps the bottom bar's Search entry (or the search field it becomes) in
/// the shared [Hero]. The flight draws one continuous pill - the button's
/// circle stretching into the field's pill - with the magnifier fading out
/// and the placeholder fading in as it widens (and the reverse on close),
/// rather than the default Hero's stretched copy of whichever widget it
/// happens to be showing.
class NooSearchHero extends StatelessWidget {
  final Widget child;

  /// Placeholder shown once the pill is wide enough to be the field.
  final String placeholder;

  const NooSearchHero({
    super.key,
    required this.child,
    this.placeholder = 'Search files',
  });

  @override
  Widget build(BuildContext context) {
    return Hero(
      tag: kSearchBarHeroTag,
      flightShuttleBuilder: (flightContext, animation, direction, from, to) =>
          _SearchMorph(
            animation: animation,
            placeholder: placeholder,
            theme: Theme.of(to),
          ),
      child: child,
    );
  }
}

class _SearchMorph extends StatelessWidget {
  final Animation<double> animation;
  final String placeholder;
  final ThemeData theme;

  const _SearchMorph({
    required this.animation,
    required this.placeholder,
    required this.theme,
  });

  @override
  Widget build(BuildContext context) {
    final colors = theme.extension<NooColors>()!;
    return AnimatedBuilder(
      animation: animation,
      builder: (context, _) {
        // 0 = the bar's button, 1 = the search field (running backwards on
        // pop, so this is "how open" in both directions).
        final t = animation.value.clamp(0.0, 1.0);
        final iconOpacity = (1 - t * 4).clamp(0.0, 1.0);
        final fieldOpacity = ((t - 0.35) / 0.5).clamp(0.0, 1.0);
        return LayoutBuilder(
          builder: (context, constraints) {
            final radius = BorderRadius.circular(
              constraints.biggest.shortestSide / 2,
            );
            return NooFloatingShadow(
              radius: radius,
              child: Material(
                color: colors.surface,
                borderRadius: radius,
                clipBehavior: Clip.antiAlias,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    Opacity(
                      opacity: iconOpacity,
                      child: Icon(
                        Icons.search_rounded,
                        size: 24,
                        color: colors.fg1,
                      ),
                    ),
                    if (fieldOpacity > 0)
                      Opacity(
                        opacity: fieldOpacity,
                        child: OverflowBox(
                          alignment: Alignment.centerLeft,
                          minWidth: 0,
                          maxWidth: double.infinity,
                          child: Padding(
                            padding: const EdgeInsets.only(left: 20),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  Icons.search_rounded,
                                  size: 22,
                                  color: colors.fg3,
                                ),
                                const SizedBox(width: 12),
                                Text(
                                  placeholder,
                                  maxLines: 1,
                                  softWrap: false,
                                  style: NooText.body.copyWith(
                                    fontSize: 16,
                                    color: colors.fg3,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }
}
