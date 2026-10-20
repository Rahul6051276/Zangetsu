import 'package:flutter/material.dart';

import '../../core/models/media_item.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text.dart';
import '../../core/tv/tv_back_button.dart';
import '../../core/tv/tv_focusable.dart';
import '../../core/tv/tv_poster_tile.dart';
import '../../core/ui/poster_card.dart';
import '../../core/zmode/metadata_filters.dart';
import '../../core/zmode/zmode_ids.dart';
import '../../l10n/l10n.dart';
import '../search/meta_filter_sheet.dart';

class SeeAllScreenTv extends StatefulWidget {
  const SeeAllScreenTv({
    super.key,
    required this.title,
    required this.items,
    required this.onTap,
    this.onLongPress,
    this.tagsFor,
    this.onLoadMore,
    this.onSearch,
    this.filterKind,
    this.initialFilters = const MetaFilters(),
  });

  final String title;
  final List<MediaItem> items;
  final void Function(MediaItem) onTap;
  final void Function(MediaItem)? onLongPress;
  final List<String> Function(MediaItem)? tagsFor;
  final Future<List<MediaItem>> Function(int page)? onLoadMore;
  final Future<MediaItemPage> Function(
    String query,
    MetaFilters filters,
    int page,
  )?
  onSearch;
  final ZKind? filterKind;
  final MetaFilters initialFilters;

  @override
  State<SeeAllScreenTv> createState() => _SeeAllScreenTvState();
}

class _SeeAllScreenTvState extends State<SeeAllScreenTv> {
  late final List<MediaItem> _items = [...widget.items];
  final Set<String> _seen = {};
  final ScrollController _controller = ScrollController();

  int _page = 1;
  bool _loading = false;
  bool _end = false;
  bool _showNextPage = false;
  bool _searching = false;
  int _queryGeneration = 0;
  late MetaFilters _filters;
  final TextEditingController _queryController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _filters = widget.initialFilters;
    for (final it in _items) {
      _seen.add(_keyOf(it));
    }
    if (widget.onLoadMore != null || widget.onSearch != null) {
      _controller.addListener(_onScroll);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    _queryController.dispose();
    super.dispose();
  }

  String _keyOf(MediaItem m) => m.id.isNotEmpty ? m.id : m.url;

  void _onScroll() {
    if (_loading || _end || !_controller.hasClients) return;
    final pos = _controller.position;
    if (pos.pixels >= pos.maxScrollExtent * 0.8) {
      _loadMore();
    }
  }

  void _maybeLoadFromIndex(int index) {
    if (widget.onLoadMore == null || _loading || _end) return;
    if (index < _items.length - tvPosterGridColumns(context) * 2) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _loadMore();
    });
  }

  Future<void> _loadMore() async {
    final loader = widget.onLoadMore;
    if ((loader == null && widget.onSearch == null) || _loading || _end) {
      return;
    }
    final generation = _queryGeneration;
    setState(() {
      _loading = true;
      _showNextPage = false;
    });
    List<MediaItem> next = const [];
    MediaItemPage? searchPage;
    try {
      if (widget.onSearch != null) {
        searchPage = await widget.onSearch!(
          _queryController.text.trim(),
          _filters,
          _page + 1,
        );
        next = searchPage.items;
      } else {
        next = await loader!(_page + 1);
      }
    } catch (_) {
      next = const [];
    }
    if (!mounted || generation != _queryGeneration) return;
    final fresh = <MediaItem>[];
    for (final it in next) {
      final k = _keyOf(it);
      if (_seen.add(k)) fresh.add(it);
    }
    setState(() {
      _loading = false;
      if (searchPage != null) {
        _page += 1;
        _items.addAll(fresh);
        _end = !searchPage.hasMore;
        _showNextPage = searchPage.hasMore;
      } else if (fresh.isEmpty) {
        _end = true;
      } else {
        _items.addAll(fresh);
        _page += 1;
      }
    });
  }

  Future<void> _runQuery(String query) async {
    if (widget.onSearch != null) {
      final generation = ++_queryGeneration;
      setState(() {
        _items.clear();
        _seen.clear();
        _page = 1;
        _end = false;
        _loading = true;
        _showNextPage = false;
      });
      var first = const MediaItemPage(items: <MediaItem>[], hasMore: false);
      try {
        first = await widget.onSearch!(query.trim(), _filters, 1);
      } catch (_) {
        first = const MediaItemPage(items: <MediaItem>[], hasMore: false);
      }
      if (!mounted || generation != _queryGeneration) return;
      final fresh = <MediaItem>[];
      for (final item in first.items) {
        if (_seen.add(_keyOf(item))) fresh.add(item);
      }
      setState(() {
        _items.addAll(fresh);
        _loading = false;
        _end = !first.hasMore;
        _showNextPage = first.hasMore;
      });
    } else {
      setState(() {});
    }
  }

  Future<void> _openFilters() async {
    final kind = widget.filterKind ?? ZKind.movie;
    final picked = await showMetaFilterDialog(
      context,
      kind,
      _filters,
      showStatus: false,
    );
    if (!mounted || picked == null) return;
    setState(() => _filters = picked);
    await _runQuery(_queryController.text);
  }

  void _toggleSearch() {
    if (!_searching) {
      setState(() => _searching = true);
      return;
    }
    final hadQuery = _queryController.text.trim().isNotEmpty;
    _queryController.clear();
    FocusScope.of(context).unfocus();
    setState(() => _searching = false);
    if (hadQuery) _runQuery('');
  }

  List<MediaItem> get _displayedItems {
    if (widget.onSearch != null) return _items;

    final q = _queryController.text.trim().toLowerCase();
    return _items.where((it) {
      if (q.isNotEmpty && !it.title.toLowerCase().contains(q)) {
        return false;
      }
      if (_filters.genres.isNotEmpty) {
        final matchesGenre = _filters.genres.any(
          (g) => it.genres.any((itemGenre) => itemGenre.toLowerCase() == g.toLowerCase()),
        );
        if (!matchesGenre) return false;
      }
      return true;
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final paginating = widget.onLoadMore != null || widget.onSearch != null;
    final displayed = _displayedItems;

    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(
        backgroundColor: AppColors.bg,
        automaticallyImplyLeading: false,
        toolbarHeight: 72,
        titleSpacing: 16,
        title: Row(
          children: [
            const TvBackButton(),
            const SizedBox(width: 16),
            Expanded(
              child: _searching
                  ? TextField(
                      key: const ValueKey('tv-see-all-search-field'),
                      controller: _queryController,
                      autofocus: true,
                      textInputAction: TextInputAction.search,
                      style: AppText.headline.copyWith(
                        color: AppColors.textPrimary,
                      ),
                      decoration: InputDecoration(
                        hintText: context.l10n.search2,
                        hintStyle: AppText.headline.copyWith(
                          color: AppColors.textTertiary,
                        ),
                        border: InputBorder.none,
                        isDense: true,
                      ),
                      onChanged: (val) {
                        if (widget.onSearch == null) {
                          setState(() {});
                        }
                      },
                      onSubmitted: _runQuery,
                    )
                  : Text(
                      widget.title,
                      style: AppText.headline,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
            ),
            TvFocusable(
              key: const ValueKey('tv-see-all-search'),
              variant: TvFocusVariant.float,
              semanticLabel: context.l10n.search2,
              onTap: _toggleSearch,
              builder: (focused) => Padding(
                padding: const EdgeInsets.all(12),
                child: Icon(
                  _searching ? Icons.close_rounded : Icons.search_rounded,
                  color: focused ? AppColors.accent : AppColors.textPrimary,
                ),
              ),
            ),
            TvFocusable(
              key: const ValueKey('tv-see-all-filter'),
              variant: TvFocusVariant.float,
              semanticLabel: context.l10n.filters,
              onTap: _openFilters,
              builder: (focused) => Padding(
                padding: const EdgeInsets.all(12),
                child: Icon(
                  Icons.filter_list_rounded,
                  color: focused || _filters.isNotEmpty
                      ? AppColors.accent
                      : AppColors.textPrimary,
                ),
              ),
            ),
          ],
        ),
      ),
      body: Stack(
        children: [
          if (displayed.isEmpty)
            Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (_loading)
                    const CircularProgressIndicator()
                  else
                    Text(context.l10n.noResults),
                  if (_showNextPage && !_loading) ...[
                    const SizedBox(height: 12),
                    TvFocusable(
                      key: const ValueKey('tv-see-all-next-page'),
                      semanticLabel: context.l10n.next,
                      onTap: _loadMore,
                      child: ExcludeFocus(
                        child: TextButton.icon(
                          onPressed: _loadMore,
                          icon: const Icon(Icons.arrow_forward_rounded),
                          label: Text(context.l10n.next),
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          if (displayed.isNotEmpty)
            GridView.builder(
              controller: paginating ? _controller : null,
              padding: const EdgeInsets.fromLTRB(40, 8, 40, 40),
              cacheExtent: 800,
              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: tvPosterGridColumns(context),
                childAspectRatio: tvPosterGridAspect(context),
                crossAxisSpacing: 18,
                mainAxisSpacing: 22,
              ),
              itemCount: displayed.length,
              itemBuilder: (context, i) {
                if (paginating) _maybeLoadFromIndex(i);
                final item = displayed[i];
                return TvPosterTile(
                  autofocus: i == 0,
                  title: item.title,
                  logoItem: item,
                  imageUrl: item.cover,
                  wideImageUrl: item.banner,
                  headers: item.coverHeaders,
                  genres: item.genres,
                  isAdult: item.isAdult,
                  scoreBadge: item.score,
                  qualityBadge: item.quality,
                  dubBadge: item.dubBadge,
                  tags: widget.tagsFor?.call(item) ?? const [],
                  onTap: () => widget.onTap(item),
                  onLongPress: widget.onLongPress == null
                      ? null
                      : () => widget.onLongPress!(item),
                );
              },
            ),
          if (paginating && _loading && displayed.isNotEmpty)
            const Positioned(
              bottom: 12,
              left: 0,
              right: 0,
              child: Center(
                child: SizedBox(
                  width: 26,
                  height: 26,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ),
            ),
          if (_showNextPage && displayed.isNotEmpty)
            Positioned(
              bottom: 8,
              left: 0,
              right: 0,
              child: Center(
                child: TvFocusable(
                  key: const ValueKey('tv-see-all-next-page'),
                  semanticLabel: context.l10n.next,
                  onTap: _loadMore,
                  child: ExcludeFocus(
                    child: TextButton.icon(
                      onPressed: _loadMore,
                      icon: const Icon(Icons.arrow_forward_rounded),
                      label: Text(context.l10n.next),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
