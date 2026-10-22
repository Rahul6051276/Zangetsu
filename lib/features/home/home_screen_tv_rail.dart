// The TV poster rail — one labelled row of D-pad cards.
part of 'home_screen_tv.dart';

// ── Poster Rail ───────────────────────────────────────────────────────────────

/// One labelled horizontal row of D-pad-focusable poster cards for a [HomeSection].
/// Public (not `_TvRail`) + [visibleForTesting] so tests can pump it directly.
@visibleForTesting
class TvRail extends StatelessWidget {
  const TvRail({
    super.key,
    required this.section,
    required this.onTap,
    this.onLongPress,
    this.onSeeAll,
    this.firstAutofocus = false,
  });

  final HomeSection section;
  final ValueChanged<MediaItem> onTap;

  /// Held OK on a poster — mirrors phone row long-press (info / My List sheet).
  /// Null keeps the snappy KeyDown tap (see [TvFocusable.onLongPress]).
  final ValueChanged<MediaItem>? onLongPress;
  final VoidCallback? onSeeAll;
  final bool firstAutofocus;

  @override
  Widget build(BuildContext context) {
    final items = section.items;
    final wide = posterLayout(context) == PosterCardLayout.wide;
    final titleInside = posterTitleInside(context, wide: wide);
    final cardScale = posterCardScale(context);
    final cardWidth = (wide ? 240.0 : 150.0) * cardScale;
    final cardHeight = (wide ? 135.0 : 225.0) * cardScale;
    return Padding(
      padding: const EdgeInsets.only(top: 26, bottom: 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Section title
          Padding(
            padding: const EdgeInsets.only(left: 12, right: 48),
            child: Text(
              section.title,
              style: const TextStyle(
                color: AppColors.textPrimary,
                fontSize: 20,
                fontWeight: FontWeight.w700,
                letterSpacing: -0.2,
              ),
            ),
          ),
          const SizedBox(height: 14),
          // Card row. Height = poster + portrait title + headroom for the
          // focused card's scale-up (the ListView is Clip.none so the growth and
          // its shadow spill past this box rather than being cropped). Kept snug
          // so rows don't float apart — the old +80 left a big dead band under
          // each title.
          SizedBox(
            height: cardHeight + (titleInside ? 20 : 44),
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              // Don't clip the focused card's scale-up + accent glow. Combined
              // with the extra row headroom above, the top rail (pinned under
              // the hero) no longer crops the focused poster/title.
              clipBehavior: Clip.none,
              padding: const EdgeInsets.only(left: 4, right: 40),
              // +1 trailing "See all" card (D-pad: navigate right past the last
              // poster to reach it). Only when a handler is supplied.
              itemCount: items.length + (onSeeAll != null ? 1 : 0),
              itemBuilder: (context, index) {
                if (index >= items.length) {
                  // Trailing "See all" card — opens the full paginated grid.
                  return Padding(
                    padding: const EdgeInsetsDirectional.only(end: 16),
                    child: Center(
                      child: SizedBox(
                        width: cardWidth,
                        height: cardHeight,
                        child: TvFocusable(
                          onTap: onSeeAll!,
                          waitForKeyUp: true,
                          variant: TvFocusVariant.float,
                          scale: 1.10,
                          semanticLabel: context.l10n.seeAll,
                          child: Container(
                            decoration: BoxDecoration(
                              color: AppColors.surface2,
                              borderRadius: BorderRadius.circular(8),
                            ),
                            alignment: Alignment.center,
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(
                                  Icons.arrow_forward_rounded,
                                  color: AppColors.textPrimary,
                                  size: 28,
                                ),
                                const SizedBox(height: 8),
                                // Excluded — the focusable above already
                                // announces 'See all' via semanticLabel.
                                ExcludeSemantics(
                                  child: Text(
                                    context.l10n.seeAll,
                                    style: TextStyle(
                                      color: AppColors.textPrimary,
                                      fontSize: 14,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  );
                }
                final item = items[index];
                // Only the poster ART gets the float focus (white outline hugs
                // the artwork); title placement follows the user's setting.
                return Padding(
                  padding: const EdgeInsetsDirectional.only(end: 16),
                  child: SizedBox(
                    width: cardWidth,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        TvFocusable(
                          autofocus: firstAutofocus && index == 0,
                          variant: TvFocusVariant.float,
                          scale: 1.06,
                          onTap: () => onTap(item),
                          // Touch gestures stay on PosterCard null — TvFocusable
                          // owns OK (and held-OK when [onLongPress] is set).
                          onLongPress: onLongPress == null
                              ? null
                              : () => onLongPress!(item),
                          semanticLabel: item.title,
                          child: SizedBox(
                            width: cardWidth,
                            height: cardHeight,
                            child: PosterCard(
                              title: item.title,
                              logoItem: item,
                              imageUrl: item.cover,
                              wideImageUrl: item.banner,
                              headers: item.coverHeaders,
                              cellWidth: cardWidth,
                              genres: item.genres,
                              isAdult: item.isAdult,
                              qualityBadge: item.quality,
                              dubBadge: item.dubBadge,
                              scoreBadge: item.score,
                              showTitle: false,
                              onTap: null,
                              onLongPress: null,
                            ),
                          ),
                        ),
                        if (!titleInside) ...[
                          const SizedBox(height: 10),
                          // The focusable already announces the title.
                          ExcludeSemantics(
                            child: PosterCardTitle(
                              title: item.title,
                              logoItem: item,
                              width: cardWidth,
                              maxHeight: 20,
                              maxLines: 1,
                              inside: false,
                              textStyle: const TextStyle(
                                color: AppColors.textSecondary,
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
