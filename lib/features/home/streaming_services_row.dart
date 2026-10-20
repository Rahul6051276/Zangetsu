import 'package:flutter/material.dart';

import '../../core/di/injector.dart';
import '../../core/metadata/streaming_providers.dart';
import '../../core/metadata/streaming_service.dart';
import '../../core/theme/app_colors.dart';
import '../../core/app_mode.dart';
import '../../core/theme/app_text.dart';
import '../../core/tv/tv_focusable.dart';
import '../../core/ui/row_skeleton.dart';
import '../../core/ui/streaming_prefs.dart';
import '../../l10n/l10n.dart';
import 'streaming_service_card.dart';

/// Home's streaming-service rail: a horizontal strip of service logos for the
/// user's country. Tapping one opens that service's catalogue.
class StreamingServicesRow extends StatefulWidget {
  const StreamingServicesRow({
    super.key,
    required this.onOpen,
    required this.onSeeAll,
    this.firstAutofocus = false,
  });

  final void Function(StreamingService) onOpen;
  final VoidCallback onSeeAll;

  /// TV only: give the first card D-pad focus when the pane opens.
  final bool firstAutofocus;

  @override
  State<StreamingServicesRow> createState() => _StreamingServicesRowState();
}

class _StreamingServicesRowState extends State<StreamingServicesRow> {
  /// Enough to fill a phone rail twice over without making the first paint wait
  /// on a long tail nobody scrolls to.
  static const int _max = 12;

  static const double _tileW = 128;
  static const double _tileH = 70;

  static const double _tvTileW = 168;
  static const double _tvTileH = 92;

  late Future<List<StreamingService>> _future;

  @override
  void initState() {
    super.initState();
    _future = sl.isRegistered<StreamingProvidersService>()
        ? sl<StreamingProvidersService>().list(StreamingPrefs.region)
        : Future.value(const []);
  }

  bool get _isTv => sl.isRegistered<AppMode>() && sl<AppMode>().isTv;

  /// Priority mapping to pin key Indian OTT providers up front:
  /// Netflix, Hotstar / JioCinema, SonyLIV, Zee5, Tata Play.
  List<StreamingService> _prioritizeServices(List<StreamingService> rawList) {
    if (rawList.isEmpty) return rawList;

    int priorityScore(StreamingService service) {
      final name = service.name.toLowerCase();
      final id = service.id;

      // 1. Netflix
      if (id == 8 || name.contains('netflix')) return 1;

      // 2. Jio / Hotstar / Disney+ Hotstar
      if (id == 122 || id == 220 || name.contains('hotstar') || name.contains('jio')) return 2;

      // 3. SonyLIV
      if (id == 237 || name.contains('sonyliv') || name.contains('sony liv')) return 3;

      // 4. Zee5
      if (id == 232 || name.contains('zee5') || name.contains('zee 5')) return 4;

      // 5. Tata Play / Tata Sky
      if (id == 604 || name.contains('tata play') || name.contains('tata sky') || name.contains('tatasky')) return 5;

      // 6. Amazon Prime Video
      if (id == 9 || id == 119 || name.contains('prime video') || name.contains('amazon')) return 6;

      return 100; // Remaining international / other services
    }

    final sorted = List<StreamingService>.from(rawList);
    sorted.sort((a, b) {
      final scoreA = priorityScore(a);
      final scoreB = priorityScore(b);
      if (scoreA != scoreB) {
        return scoreA.compareTo(scoreB);
      }
      return 0; // Maintain original TMDb popularity order if same priority
    });

    return sorted;
  }

  @override
  Widget build(BuildContext context) {
    final isTv = _isTv;
    final tileW = isTv ? _tvTileW : _tileW;
    final tileH = isTv ? _tvTileH : _tileH;
    return FutureBuilder<List<StreamingService>>(
      future: _future,
      builder: (context, snap) {
        if (snap.connectionState != ConnectionState.done) {
          return RowSkeleton(itemWidth: tileW, itemHeight: tileH);
        }
        final all = snap.data ?? const <StreamingService>[];
        if (all.isEmpty) return const SizedBox.shrink();

        // Sort our preferred Indian providers to the front before slicing
        final prioritized = _prioritizeServices(all);
        final services = prioritized.take(_max).toList();

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: isTv
                  ? const EdgeInsets.fromLTRB(48, 26, 48, 14)
                  : const EdgeInsets.fromLTRB(16, 26, 16, 14),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      context.l10n.streamingServices,
                      style: isTv
                          ? const TextStyle(
                              color: AppColors.textPrimary,
                              fontSize: 20,
                              fontWeight: FontWeight.w700,
                              letterSpacing: -0.2,
                            )
                          : AppText.headline,
                    ),
                  ),
                  if (!isTv)
                    GestureDetector(
                      onTap: widget.onSeeAll,
                      behavior: HitTestBehavior.opaque,
                      child: Padding(
                        padding: const EdgeInsetsDirectional.only(start: 8),
                        child: Text(
                          context.l10n.seeAll,
                          style: AppText.caption.copyWith(
                            color: AppColors.accent,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
            SizedBox(
              height: isTv ? tileH + 26 : tileH,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                clipBehavior: isTv ? Clip.none : Clip.hardEdge,
                padding: EdgeInsets.symmetric(horizontal: isTv ? 48 : 16),
                itemCount: services.length + (isTv ? 1 : 0),
                separatorBuilder: (_, _) => SizedBox(width: isTv ? 16 : 12),
                itemBuilder: (context, i) => Align(
                  alignment: Alignment.topCenter,
                  child: isTv && i == services.length
                      ? _SeeAllCard(
                          width: tileW,
                          height: tileH,
                          onTap: widget.onSeeAll,
                        )
                      : StreamingServiceCard(
                          service: services[i],
                          width: tileW,
                          height: tileH,
                          autofocus: widget.firstAutofocus && i == 0,
                          onTap: () => widget.onOpen(services[i]),
                        ),
                ),
              ),
            ),
            if (isTv) const SizedBox(height: 8),
          ],
        );
      },
    );
  }
}

class _SeeAllCard extends StatelessWidget {
  const _SeeAllCard({
    required this.width,
    required this.height,
    required this.onTap,
  });

  final double width;
  final double height;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => TvFocusable(
    key: const ValueKey('tv-service-rail-see-all'),
    variant: TvFocusVariant.float,
    scale: 1.06,
    borderRadius: 18,
    semanticLabel: context.l10n.seeAll,
    onTap: onTap,
    builder: (focused) => Container(
      width: width,
      height: height,
      decoration: ShapeDecoration(
        color: AppColors.surface2,
        shape: RoundedSuperellipseBorder(
          borderRadius: const BorderRadius.all(Radius.circular(18)),
          side: focused
              ? BorderSide(color: AppColors.accent, width: 2)
              : BorderSide.none,
        ),
      ),
      alignment: Alignment.center,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.grid_view_rounded,
            size: 26,
            color: focused ? AppColors.accent : AppColors.textSecondary,
          ),
          const SizedBox(height: 8),
          Text(
            context.l10n.seeAll,
            style: AppText.caption.copyWith(
              color: focused ? AppColors.accent : AppColors.textSecondary,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    ),
  );
}
