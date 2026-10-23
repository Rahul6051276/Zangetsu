import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';

import '../../core/profiles/klipy_gif_service.dart';
import '../../core/theme/app_colors.dart';

Future<KlipyGif?> showProfileKlipyGifPicker(
  BuildContext context,
  KlipyGifService service,
) => showModalBottomSheet<KlipyGif>(
  context: context,
  isScrollControlled: true,
  backgroundColor: Colors.transparent,
  builder: (_) => _KlipyGifPicker(service: service),
);

class _KlipyGifPicker extends StatefulWidget {
  const _KlipyGifPicker({required this.service});

  final KlipyGifService service;

  @override
  State<_KlipyGifPicker> createState() => _KlipyGifPickerState();
}

class _KlipyGifPickerState extends State<_KlipyGifPicker> {
  final _query = TextEditingController();
  Timer? _debounce;
  CancelToken? _cancelToken;
  List<KlipyGif> _results = const [];
  bool _loading = false;
  bool _failed = false;

  @override
  void dispose() {
    _debounce?.cancel();
    _cancelToken?.cancel();
    _query.dispose();
    super.dispose();
  }

  void _search(String value) {
    _debounce?.cancel();
    _cancelToken?.cancel();
    if (value.trim().isEmpty) {
      setState(() {
        _results = const [];
        _loading = false;
        _failed = false;
      });
      return;
    }
    setState(() {
      _loading = true;
      _failed = false;
    });
    _debounce = Timer(const Duration(milliseconds: 350), () async {
      final token = CancelToken();
      _cancelToken = token;
      try {
        final results = await widget.service.search(value, cancelToken: token);
        if (!mounted || token.isCancelled) return;
        setState(() {
          _results = results;
          _loading = false;
        });
      } catch (_) {
        if (!mounted || token.isCancelled) return;
        setState(() {
          _results = const [];
          _loading = false;
          _failed = true;
        });
      }
    });
  }

  void _select(KlipyGif gif) {
    unawaited(widget.service.registerSelection(gif, _query.text));
    Navigator.of(context).pop(gif);
  }

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.sizeOf(context);
    return SizedBox(
      height: media.height * 0.84,
      child: SafeArea(
        top: false,
        child: Material(
          color: AppColors.bg,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
          clipBehavior: Clip.antiAlias,
          child: Padding(
            padding: EdgeInsets.fromLTRB(
              16,
              18,
              16,
              MediaQuery.viewInsetsOf(context).bottom + 12,
            ),
            child: Column(
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        'Choose a GIF',
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                    ),
                    IconButton(
                      tooltip: 'Close',
                      onPressed: () => Navigator.of(context).pop(),
                      icon: const Icon(Icons.close_rounded),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                TextField(
                  key: const ValueKey('profile-gif-search'),
                  controller: _query,
                  autofocus: true,
                  enabled: widget.service.isConfigured,
                  onChanged: _search,
                  textInputAction: TextInputAction.search,
                  decoration: InputDecoration(
                    hintText: 'Search KLIPY',
                    prefixIcon: const Icon(Icons.search_rounded),
                    filled: true,
                    fillColor: AppColors.settingsCard,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(18),
                      borderSide: BorderSide.none,
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                Expanded(
                  child: !widget.service.isConfigured
                      ? const Center(
                          child: Text(
                            'GIF search is not configured in this build.',
                            textAlign: TextAlign.center,
                          ),
                        )
                      : _loading
                      ? const Center(child: CircularProgressIndicator())
                      : _failed
                      ? const Center(
                          child: Text(
                            'Could not load GIFs. Check your connection.',
                          ),
                        )
                      : _results.isEmpty
                      ? Center(
                          child: Text(
                            _query.text.trim().isEmpty
                                ? 'Search for a GIF'
                                : 'No GIFs found',
                            style: Theme.of(context).textTheme.bodyLarge,
                          ),
                        )
                      : GridView.builder(
                          key: const ValueKey('profile-gif-results'),
                          itemCount: _results.length,
                          gridDelegate:
                              const SliverGridDelegateWithFixedCrossAxisCount(
                                crossAxisCount: 3,
                                crossAxisSpacing: 8,
                                mainAxisSpacing: 8,
                              ),
                          itemBuilder: (context, index) {
                            final gif = _results[index];
                            return Semantics(
                              button: true,
                              label: gif.title.isEmpty
                                  ? 'Select GIF'
                                  : 'Select ${gif.title}',
                              child: InkWell(
                                key: ValueKey('profile-gif-option-${gif.slug}'),
                                onTap: () => _select(gif),
                                borderRadius: BorderRadius.circular(14),
                                child: ClipRRect(
                                  borderRadius: BorderRadius.circular(14),
                                  child: Image(
                                    image: NetworkImage(gif.thumbnailUrl),
                                    fit: BoxFit.cover,
                                    errorBuilder: (_, _, _) => ColoredBox(
                                      color: AppColors.settingsCard,
                                      child: const Center(
                                        child: Icon(
                                          Icons.broken_image_outlined,
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            );
                          },
                        ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Powered by KLIPY',
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: AppColors.textSecondary,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
