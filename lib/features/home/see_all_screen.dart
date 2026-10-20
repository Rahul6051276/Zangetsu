import 'package:flutter/material.dart';

import '../../core/app_mode.dart';
import '../../core/di/injector.dart';
import '../../core/models/media_item.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text.dart';
import '../../core/ui/poster_card.dart';
import '../../core/ui/reveal_item.dart';
import '../../core/zmode/metadata_filters.dart';
import '../../core/zmode/zmode_ids.dart';
import '../../l10n/l10n.dart';
import '../search/meta_filter_sheet.dart';
import 'see_all_screen_tv.dart';

class SeeAllScreen extends StatefulWidget {
  const SeeAllScreen({
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
  )? onSearch;
  final ZKind? filterKind;
  final MetaFilters initialFilters;

  @override
  State<SeeAllScreen> createState() => _SeeAllScreenState();
}

class _SeeAllScreenState extends State<SeeAllScreen> {
  late final List<MediaItem> _rawItems = [...widget.items];
  late List<MediaItem> _items = [...widget.items];
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

  int _itemScore(MediaItem item) {
    final s = item.score;
    if (s == null) return 0;
    return s;
  }

  void _applyLocalFilters() {
    final query = _queryController.text.trim().toLowerCase();
    var filtered = _rawItems.where((item) {
      if (query.isNotEmpty && !item.title.toLowerCase().contains(query)) {
        return false;
      }
      if (_filters.year != null && _filters.year! > 0) {
        final yearStr = _filters.year.toString();
        if (!item.title.contains(yearStr)) return false;
      }
      if (_filters.minScore != null && _filters.minScore! > 0) {
        final score = _itemScore(item);
        final target = _filters.minScore!;
        if (score < target) return false;
      }
      return true;
    }).toList();

    if (_filters.sort == MetaSort.score) {
      filtered.sort((a, b) => _itemScore(b).compareTo(_itemScore(a)));
    }

    setState(() {
      _items = filtered;
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
        _rawItems.addAll(fresh);
        _end = !searchPage.hasMore;
        _showNextPage = searchPage.hasMore;
      } else if (fresh.isEmpty) {
        _end = true;
      } else {
        _rawItems.addAll(fresh);
        _page += 1;
        if (_queryController.text.isNotEmpty || !_filters.isEmpty) {
          _applyLocalFilters();
        } else {
          _items.addAll(fresh);
        }
      }
    });
  }

  Future<void> _runQuery(String query) async {
    if (widget.onSearch == null) {
      _applyLocalFilters();
      return;
    }
    final search = widget.onSearch!;
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
      first = await search(query.trim(), _filters, 1);
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
  }

  Future<void> _openFilters() async {
    final effectiveKind = widget.filterKind ?? ZKind.movie;
    final picked = await showMetaFilterSheet(
      context,
      effectiveKind,
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

  @override
  Widget build(BuildContext context) {
    if (sl<AppMode>().isTv) {
      return SeeAllScreenTv(
        title: widget.title,
        items: widget.items,
        onTap: widget.onTap,
        onLongPress: widget.onLongPress,
        tagsFor: widget.tagsFor,
        onLoadMore: widget.onLoadMore,
        onSearch: widget.onSearch,
        filterKind: widget.filterKind ?? ZKind.movie,
        initialFilters: widget.initialFilters,
      );
    }
    final cellW = posterGridCellWidth(context);
    final paginating = widget.onLoadMore != null || widget.onSearch != null;
    final showSpinner = paginating && _loading;

    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(
        backgroundColor: AppColors.bg,
        title: _searching
            ? TextField(
                key: const ValueKey('see-all-search-field'),
                controller: _queryController,
                autofocus: true,
                textInputAction: TextInputAction.search,
                style: AppText.body.copyWith(color: AppColors.textPrimary),
                decoration: InputDecoration(
                  hintText: context.l10n.search2,
                  border: InputBorder.none,
                  isDense: true,
                ),
                onChanged: (val) {
                  if (widget.onSearch == null) _applyLocalFilters();
                },
                onSubmitted: _runQuery,
              )
            : Text(widget.title, style: AppText.headline),
        actions: [
          IconButton(
            key: const ValueKey('see-all-search'),
            tooltip: context.l10n.search2,
            onPressed: _toggleSearch,
            icon: Icon(
              _searching ? Icons.close_rounded : Icons.search_rounded,
            ),
          ),
          IconButton(
            key: const ValueKey('see-all-filter'),
            tooltip: context.l10n.filters,
            onPressed: _openFilters,
            icon: Icon(
              Icons.filter_list_rounded,
              color: _filters.isEmpty ? null : AppColors.accent,
            ),
          ),
        ],
      ),
      body: _items.isEmpty
          ? Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (_loading)
                    const CircularProgressIndicator()
                  else
                    Text(context.l10n.noResults),
                  if (_showNextPage && !_loading) ...[
                    const SizedBox(height: 12),
                    TextButton.icon(
                      key: const ValueKey('see-all-next-page'),
                      onPressed: _loadMore,
                      icon: const Icon(Icons.arrow_forward_rounded),
                      label: Text(context.l10n.next),
                    ),
                  ],
                ],
              ),
            )
          : GridView.builder(
              controller: paginating ? _controller : null,
              padding: const EdgeInsets.all(16),
              cacheExtent: 800,
              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: posterGridColumns(context),
                childAspectRatio: posterGridAspect(context),
                crossAxisSpacing: 12,
                mainAxisSpacing: 16,
              ),
              itemCount: _items.length,
              itemBuilder: (context, i) {
                final item = _items[i];
                return RevealItem(
                  index: i,
                  child: PosterCard(
                    title: item.title,
                    logoItem: item,
                    imageUrl: item.cover,
                    wideImageUrl: item.banner,
                    genres: item.genres,
                    isAdult: item.isAdult,
                    headers: item.coverHeaders,
                    tags: widget.tagsFor?.call(item) ?? const [],
                    qualityBadge: item.quality,
                    scoreBadge: item.score,
                    dubBadge: item.dubBadge,
                    cellWidth: cellW,
                    onTap: () => widget.onTap(item),
                    onLongPress: widget.onLongPress == null
                        ? null
                        : () => widget.onLongPress!(item),
                  ),
                );
              },
            ),
      bottomNavigationBar: showSpinner && _items.isNotEmpty
          ? const SizedBox(
              height: 48,
              child: Center(
                child: SizedBox(
                  width: 22,
                  height: 22,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ),
            )
          : _showNextPage && _items.isNotEmpty
          ? SizedBox(
              height: 56,
              child: Center(
                child: TextButton.icon(
                  key: const ValueKey('see-all-next-page'),
                  onPressed: _loadMore,
                  icon: const Icon(Icons.arrow_forward_rounded),
                  label: Text(context.l10n.next),
                ),
              ),
            )
          : null,
    );
  }
}
