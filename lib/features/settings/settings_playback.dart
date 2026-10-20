// Playback settings: quality, autoplay, speed, subtitles.
part of 'settings_screen.dart';

// ---------------------------------------------------------------------------
// Playback
// ---------------------------------------------------------------------------

class PlaybackSettingsScreen extends StatefulWidget {
  const PlaybackSettingsScreen({super.key});

  @override
  State<PlaybackSettingsScreen> createState() => _PlaybackSettingsScreenState();
}

class _PlaybackSettingsScreenState extends State<PlaybackSettingsScreen> {
  PlaybackPrefs get _prefs => sl<PlaybackPrefs>();

  int _cacheBytes = 0;
  bool _shadersReady = ShaderPresets.downloaded;
  bool _shaderDownloading = false;
  double _shaderProgress = 0;

  @override
  void initState() {
    super.initState();
    _loadCacheSize();
    ShaderPresets.refreshDownloaded().then((v) {
      if (mounted) setState(() => _shadersReady = v);
    });
  }

  Future<void> _downloadShaders() async {
    if (_shaderDownloading) return;
    setState(() {
      _shaderDownloading = true;
      _shaderProgress = 0;
    });
    final ok = await ShaderPresets.download(
      onProgress: (p) {
        if (mounted) setState(() => _shaderProgress = p);
      },
    );
    if (!mounted) return;
    setState(() {
      _shaderDownloading = false;
      _shadersReady = ok;
    });
    if (!ok) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(context.l10n.shaderDownloadFailedCheckNetwork)));
    } else {
      if (_prefs.videoShaderStyle == 'off') {
        await _prefs.setVideoShaderStyle('a');
      }
      if (mounted) setState(() {});
    }
  }

  Future<void> _pickShaderStyle() async {
    final l10n = context.l10n;
    final picked = await _pick<String>(
      title: l10n.anime4kEnhancement,
      options: shaderStylePickerOptions(l10n),
      current: _prefs.videoShaderStyle,
    );
    if (picked == null) return;
    await _prefs.setVideoShaderStyle(picked);
    if (mounted) setState(() {});
  }

  Future<void> _pickShaderTier() async {
    final l10n = context.l10n;
    final picked = await _pick<String>(
      title: l10n.anime4kGPUTier,
      options: shaderTierPickerOptions(l10n),
      current: _prefs.videoShaderTier,
    );
    if (picked == null) return;
    await _prefs.setVideoShaderTier(picked);
    if (mounted) setState(() {});
  }

  Future<void> _loadCacheSize() async {
    final n = await MediaCache.sizeBytes();
    if (mounted) setState(() => _cacheBytes = n);
  }

  Future<void> _clearCache() async {
    await MediaCache.clear();
    await _loadCacheSize();
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(context.l10n.cacheCleared)));
  }

  static List<(String, String)> _bufferSizeOptions(AppLocalizations l10n) => [
    ('low', l10n.bufferSizeLow),
    ('default', l10n.bufferSizeDefault),
    ('high', l10n.bufferSizeHigh),
  ];
  static List<(String, String)> _bufferLengthOptions(AppLocalizations l10n) => [
    ('low', l10n.bufferLengthLow),
    ('default', l10n.bufferLengthDefault),
    ('high', l10n.bufferLengthHigh),
    ('max', l10n.bufferLengthMax),
  ];

  Future<void> _pickBufferSize() async {
    final l10n = context.l10n;
    final picked = await _pick<String>(
      title: l10n.videoBufferSize,
      options: _bufferSizeOptions(l10n),
      current: _prefs.videoBufferSize,
    );
    if (picked == null) return;
    await _prefs.setVideoBufferSize(picked);
    if (mounted) setState(() {});
  }

  Future<void> _pickBufferLength() async {
    final l10n = context.l10n;
    final picked = await _pick<String>(
      title: l10n.videoBufferLength,
      options: _bufferLengthOptions(l10n),
      current: _prefs.videoBufferLength,
    );
    if (picked == null) return;
    await _prefs.setVideoBufferLength(picked);
    if (mounted) setState(() {});
  }

  Future<void> _pickPlayerInfo() async {
    final selected = _prefs.playerInfoFields.toSet();
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: AppColors.surface,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheet) => SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                margin: const EdgeInsets.only(top: 12, bottom: 8),
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: AppColors.textTertiary.withValues(alpha: 0.5),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 4, 20, 2),
                child: Align(
                  alignment: AlignmentDirectional.centerStart,
                  child: Text(context.l10n.playerInfoOverlay, style: AppText.headline),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
                child: Align(
                  alignment: AlignmentDirectional.centerStart,
                  child: Text(
                    context.l10n.pickWhatShowsOverVideo,
                    style: AppText.caption,
                  ),
                ),
              ),
              const Divider(color: AppColors.hairline, height: 1),
              Flexible(
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      for (final f in kPlayerInfoFields)
                        CheckboxListTile(
                          value: selected.contains(f.$1),
                          onChanged: (v) => setSheet(() {
                            if (v == true) {
                              selected.add(f.$1);
                            } else {
                              selected.remove(f.$1);
                            }
                          }),
                          title: Text(f.$2, style: AppText.body),
                          activeColor: AppColors.accent,
                          controlAffinity: ListTileControlAffinity.trailing,
                          dense: true,
                        ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 8),
            ],
          ),
        ),
      ),
    );
    final ordered = [
      for (final f in kPlayerInfoFields)
        if (selected.contains(f.$1)) f.$1,
    ];
    await _prefs.setPlayerInfoFields(ordered);
    if (mounted) setState(() {});
  }

  static const List<(String, String)> _qualityOptions = [
    ('auto', 'Auto'),
    ('highest', 'Highest'),
    ('1080p', '1080p'),
    ('720p', '720p'),
    ('480p', '480p'),
  ];

  static List<(TvDecoderMode, String)> _tvDecoderModeOptions(
    AppLocalizations l10n,
  ) => [
    (TvDecoderMode.hardwareOnly, l10n.tvDecoderHardwareOnly),
    (TvDecoderMode.hardwareFirst, l10n.tvDecoderHardwareFirst),
    (TvDecoderMode.softwareFirst, l10n.tvDecoderSoftwareFirst),
  ];

  static String _tvDecoderModeLabel(
    TvDecoderMode mode,
    AppLocalizations l10n,
  ) => switch (mode) {
    TvDecoderMode.hardwareOnly => l10n.tvDecoderHardwareOnly,
    TvDecoderMode.hardwareFirst => l10n.tvDecoderHardwareFirst,
    TvDecoderMode.softwareFirst => l10n.tvDecoderSoftwareFirst,
  };

  Future<void> _pickTvDecoderMode() async {
    final l10n = context.l10n;
    final picked = await _pick<TvDecoderMode>(
      title: l10n.tvDecoderMode,
      options: _tvDecoderModeOptions(l10n),
      current: _prefs.tvDecoderMode,
    );
    if (picked == null) return;
    await _prefs.setTvDecoderMode(picked);
    if (mounted) setState(() {});
  }

  static const List<(String, String)> _audioOptions = [('sub', 'Sub'), ('dub', 'Dub')];

  static const List<(double, String)> _speedOptions = [
    (0.5, '0.5x'),
    (0.75, '0.75x'),
    (1.0, '1x'),
    (1.25, '1.25x'),
    (1.5, '1.5x'),
    (2.0, '2x'),
    (2.5, '2.5x'),
    (3.0, '3x'),
    (4.0, '4x'),
    (5.0, '5x'),
  ];

  static const List<(int, String)> _skipOptions = [(5, '5s'), (10, '10s'), (15, '15s'), (30, '30s')];

  String _labelFor<T>(List<(T, String)> options, T value, String fallback) {
    for (final (v, label) in options) {
      if (v == value) return label;
    }
    return fallback;
  }

  Future<T?> _pick<T>({required String title, required List<(T, String)> options, required T current}) {
    if (sl<AppMode>().isTv) {
      return showDialog<T>(
        context: context,
        barrierColor: Colors.black54,
        builder: (ctx) => Dialog(
          backgroundColor: AppColors.surface,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          insetPadding: const EdgeInsets.symmetric(horizontal: 80, vertical: 48),
          child: SizedBox(
            width: 400,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(24, 20, 24, 12),
                  child: Text(title, style: AppText.title.copyWith(color: AppColors.textPrimary)),
                ),
                const Divider(height: 1, color: AppColors.hairline),
                Flexible(
                  child: ConstrainedBox(
                    constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.6),
                    child: ListView(
                      shrinkWrap: true,
                      clipBehavior: Clip.none,
                      padding: const EdgeInsets.only(bottom: 12),
                      children: [
                        for (final (value, label) in options)
                          TvListFocusable(
                            autofocus: value == current,
                            semanticLabel: label,
                            onTap: () => Navigator.pop(ctx, value),
                            child: ExcludeSemantics(
                              child: Padding(
                                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
                                child: Row(
                                  children: [
                                    Expanded(child: Text(label, style: AppText.headline)),
                                    if (value == current) Icon(Icons.check, color: AppColors.accent, size: 20),
                                  ],
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }
    return showModalBottomSheet<T>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              margin: const EdgeInsets.only(top: 12, bottom: 8),
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                color: AppColors.textTertiary.withValues(alpha: 0.5),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 8),
              child: Align(
                alignment: AlignmentDirectional.centerStart,
                child: Text(title, style: AppText.headline),
              ),
            ),
            const Divider(color: AppColors.hairline, height: 1),
            Flexible(
              child: ConstrainedBox(
                constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.6),
                child: ListView(
                  shrinkWrap: true,
                  padding: const EdgeInsets.only(bottom: 8),
                  children: [
                    for (final (value, label) in options)
                      ListTile(
                        onTap: () => Navigator.pop(ctx, value),
                        title: Text(label, style: AppText.body.copyWith(color: AppColors.textPrimary)),
                        trailing: value == current ? Icon(Icons.check, color: AppColors.accent) : null,
                      ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _pickQuality() async {
    final picked = await _pick<String>(
      title: context.l10n.defaultQuality,
      options: _qualityOptions,
      current: _prefs.defaultQuality,
    );
    if (picked == null) return;
    await _prefs.setDefaultQuality(picked);
    if (mounted) setState(() {});
  }

  Future<void> _pickDecoder() async {
    final l10n = context.l10n;
    final picked = await _pick<String>(title: l10n.videoDecoder, options: videoDecoderOptions(l10n), current: _prefs.videoDecoder);
    if (picked == null) return;
    await _prefs.setVideoDecoder(picked);
    if (mounted) setState(() {});
  }

  Future<void> _pickRenderer() async {
    final l10n = context.l10n;
    final picked = await _pick<String>(title: l10n.videoRenderer, options: videoRendererOptions(l10n), current: _prefs.videoOutput);
    if (picked == null) return;
    await _prefs.setVideoOutput(picked);
    if (mounted) setState(() {});
  }

  Future<void> _pickAudio() async {
    final picked = await _pick<String>(title: context.l10n.defaultAudio, options: _audioOptions, current: _prefs.defaultCategory);
    if (picked == null) return;
    await _prefs.setDefaultCategory(picked);
    if (mounted) setState(() {});
  }

  Future<void> _pickSpeed() async {
    final picked = await _pick<double>(title: context.l10n.defaultSpeed, options: _speedOptions, current: _prefs.defaultSpeed);
    if (picked == null) return;
    await _prefs.setDefaultSpeed(picked);
    if (mounted) setState(() {});
  }

  Future<void> _pickSkip() async {
    final picked = await _pick<int>(title: context.l10n.doubleTapSkip, options: _skipOptions, current: _prefs.doubleTapSeconds);
    if (picked == null) return;
    await _prefs.setDoubleTapSeconds(picked);
    if (mounted) setState(() {});
  }

  Future<void> _pickSeekSecondsForTV() async {
    final picked = await _pick<int>(
      title: context.l10n.seekButtonDuration,
      options: _skipOptions,
      current: _prefs.tvSeekSeconds,
    );
    if (picked == null) return;
    await _prefs.setTvSeekSeconds(picked);
    if (mounted) setState(() {});
  }

  Future<void> _pickPlayer() async {
    final players = await ExternalPlayer().installed();
    if (!mounted) return;
    final androidPlayerLabel = context.l10n.androidPlayer;
    final options = <(String, String)>[
      ('', context.l10n.builtInPlayer),
      (PlaybackPrefs.androidPlayerId, androidPlayerLabel),
      for (final p in players) (p.package, p.known ? p.label : '${p.label}${context.l10n.noSubsResumeSuffix}'),
    ];
    if (players.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.l10n.noOtherVideoAppsFound)),
      );
    }
    final picked = await _pick<String>(
      title: context.l10n.defaultPlayer,
      options: options,
      current: _prefs.externalPlayerPackage,
    );
    if (picked == null) return;
    final match = players.where((p) => p.package == picked);
    final label = picked == PlaybackPrefs.androidPlayerId
        ? androidPlayerLabel
        : match.isEmpty
            ? ''
            : match.first.label;
    await _prefs.setExternalPlayer(picked, picked.isEmpty ? '' : label);
    if (mounted) setState(() {});
  }

  Widget _toggleRow({
    required IconData icon,
    required String title,
    required bool value,
    required ValueChanged<bool> onChanged,
    String? subtitle,
  }) {
    return SettingsTile(
      icon: icon,
      title: title,
      subtitle: subtitle,
      subtitleMaxLines: null,
      onTap: () => onChanged(!value),
      trailing: Switch.adaptive(
        value: value,
        onChanged: onChanged,
        activeThumbColor: AppColors.accent,
        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final isTv = sl<AppMode>().isTv;

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.playback),
        backgroundColor: Colors.transparent,
        elevation: 0,
      ),
      body: ListView(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        children: [
          SettingsCard(
            children: [
              SettingsTile(
                icon: Icons.play_circle_outline,
                title: l10n.defaultPlayer,
                subtitle: _prefs.externalPlayerName.isEmpty
                    ? l10n.builtInPlayer
                    : _prefs.externalPlayerName,
                onTap: _pickPlayer,
              ),
              if (isTv) ...[
                _toggleRow(
                  icon: Icons.tv,
                  title: l10n.nativeTvPlayer,
                  subtitle: l10n.nativeTvPlayerDescription,
                  value: _prefs.nativeTvPlayer,
                  onChanged: (v) async {
                    await _prefs.setNativeTvPlayer(v);
                    if (mounted) setState(() {});
                  },
                ),
                SettingsTile(
                  icon: Icons.developer_board,
                  title: l10n.tvDecoderMode,
                  subtitle: _tvDecoderModeLabel(_prefs.tvDecoderMode, l10n),
                  onTap: _pickTvDecoderMode,
                ),
              ],
              if (!isTv) ...[
                SettingsTile(
                  icon: Icons.videocam_outlined,
                  title: l10n.videoDecoder,
                  subtitle: _labelFor(videoDecoderOptions(l10n), _prefs.videoDecoder, _prefs.videoDecoder),
                  onTap: _pickDecoder,
                ),
                SettingsTile(
                  icon: Icons.brush_outlined,
                  title: l10n.videoRenderer,
                  subtitle: _labelFor(videoRendererOptions(l10n), _prefs.videoOutput, _prefs.videoOutput),
                  onTap: _pickRenderer,
                ),
              ],
              SettingsTile(
                icon: Icons.high_quality_outlined,
                title: l10n.defaultQuality,
                subtitle: _labelFor(_qualityOptions, _prefs.defaultQuality, _prefs.defaultQuality),
                onTap: _pickQuality,
              ),
              SettingsTile(
                icon: Icons.audiotrack_outlined,
                title: l10n.defaultAudio,
                subtitle: _labelFor(_audioOptions, _prefs.defaultCategory, _prefs.defaultCategory),
                onTap: _pickAudio,
              ),
              SettingsTile(
                icon: Icons.speed_outlined,
                title: l10n.defaultSpeed,
                subtitle: _labelFor(_speedOptions, _prefs.defaultSpeed, '${_prefs.defaultSpeed}x'),
                onTap: _pickSpeed,
              ),
            ],
          ),
          const SizedBox(height: 16),
          SettingsCard(
            children: [
              if (isTv)
                SettingsTile(
                  icon: Icons.timer_outlined,
                  title: l10n.seekButtonDuration,
                  subtitle: _labelFor(_skipOptions, _prefs.tvSeekSeconds, '${_prefs.tvSeekSeconds}s'),
                  onTap: _pickSeekSecondsForTV,
                )
              else
                SettingsTile(
                  icon: Icons.timer_outlined,
                  title: l10n.doubleTapSkip,
                  subtitle: _labelFor(_skipOptions, _prefs.doubleTapSeconds, '${_prefs.doubleTapSeconds}s'),
                  onTap: _pickSkip,
                ),
              _toggleRow(
                icon: Icons.screen_lock_portrait_outlined,
                title: l10n.keepScreenOn,
                value: _prefs.keepScreenOn,
                onChanged: (v) async {
                  await _prefs.setKeepScreenOn(v);
                  if (mounted) setState(() {});
                },
              ),
              _toggleRow(
                icon: Icons.info_outline,
                title: l10n.playerInfoOverlay,
                value: _prefs.playerInfoOverlay,
                onChanged: (v) async {
                  await _prefs.setPlayerInfoOverlay(v);
                  if (mounted) setState(() {});
                },
              ),
              _toggleRow(
                icon: Icons.label_outline,
                title: l10n.showQualityLabel,
                subtitle: l10n.showQualityLabelSubtitle,
                value: _prefs.showQualityLabel,
                onChanged: (v) async {
                  await _prefs.setShowQualityLabel(v);
                  if (mounted) setState(() {});
                },
              ),
            ],
          ),
          const SizedBox(height: 16),
          SettingsCard(
            children: [
              SettingsTile(
                icon: Icons.sd_card_alert_outlined,
                title: l10n.videoBufferSize,
                subtitle: _labelFor(_bufferSizeOptions(l10n), _prefs.videoBufferSize, _prefs.videoBufferSize),
                onTap: _pickBufferSize,
              ),
              SettingsTile(
                icon: Icons.straighten_outlined,
                title: l10n.videoBufferLength,
                subtitle: _labelFor(_bufferLengthOptions(l10n), _prefs.videoBufferLength, _prefs.videoBufferLength),
                onTap: _pickBufferLength,
              ),
              SettingsTile(
                icon: Icons.delete_outline,
                title: l10n.clearVideoCache,
                subtitle: MediaCache.formatBytes(_cacheBytes),
                onTap: _clearCache,
              ),
            ],
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }
}
