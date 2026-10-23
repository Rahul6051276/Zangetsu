import 'package:flutter/material.dart';

import '../../core/di/injector.dart';
import '../../core/mihon/mihon_extension_service.dart';
import '../../core/provider/cf_solve_needed.dart';
import '../../core/provider/provider_manager.dart';
import '../../core/repository/source_actions.dart' as source_actions;
import '../../core/repository/source_repository.dart';
import '../../core/theme/app_colors.dart';
import '../../l10n/l10n.dart';

/// Per-source overflow actions shared by Home and the detail source picker.
class SourcePickerRowActions extends StatelessWidget {
  const SourcePickerRowActions({
    super.key,
    required this.sourceId,
    this.onCloudflareSolved,
  });

  final String sourceId;
  final Future<void> Function(String sourceId)? onCloudflareSolved;

  static const Color _cfOrange = Color(0xFFF48120);

  @override
  Widget build(BuildContext context) {
    final flaggedUrl = CfSolveNeeded.urlFor(sourceId);
    final solveTarget =
        flaggedUrl ?? sl<SourceRepository>().baseUrlFor(sourceId);
    final showSolve = solveTarget.isNotEmpty;
    final showSignIn = source_actions.webViewUrlFor(sourceId) != null;
    final flagged = flaggedUrl != null;
    final isJs =
        !sourceId.startsWith('ani:') &&
        !sourceId.startsWith('mihon:') &&
        !sourceId.startsWith('cs:') &&
        !sourceId.startsWith('lnr:');

    return FutureBuilder<bool>(
      future: source_actions.hasSourceSettings(sourceId),
      builder: (context, snapshot) {
        final showSettings = snapshot.data == true;
        final menuSolve = showSolve && !flagged;
        final hasMenu = menuSolve || showSignIn || showSettings;
        if (!flagged && !hasMenu) return const SizedBox.shrink();
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (flagged)
              IconButton(
                visualDensity: VisualDensity.compact,
                tooltip: context.l10n.solveCloudflare,
                icon: const Badge(
                  backgroundColor: _cfOrange,
                  smallSize: 8,
                  child: Icon(Icons.shield_rounded, size: 18),
                ),
                color: _cfOrange,
                onPressed: () =>
                    _solveCloudflare(sourceId, solveTarget, isJs: isJs),
              ),
            if (hasMenu)
              _overflow(
                context,
                sourceId,
                solveTarget,
                isJs: isJs,
                showSolve: menuSolve,
                showSignIn: showSignIn,
                showSettings: showSettings,
              ),
          ],
        );
      },
    );
  }

  Widget _overflow(
    BuildContext context,
    String id,
    String solveTarget, {
    required bool isJs,
    required bool showSolve,
    required bool showSignIn,
    required bool showSettings,
  }) => PopupMenuButton<VoidCallback>(
    tooltip: context.l10n.more,
    padding: EdgeInsets.zero,
    icon: const Icon(Icons.more_vert_rounded, size: 18),
    iconColor: AppColors.textSecondary,
    onSelected: (run) => run(),
    itemBuilder: (_) => [
      if (showSolve)
        PopupMenuItem<VoidCallback>(
          value: () => _solveCloudflare(id, solveTarget, isJs: isJs),
          child: Text(context.l10n.solveCloudflare),
        ),
      if (showSignIn)
        PopupMenuItem<VoidCallback>(
          value: () => source_actions.openSourceWebView(id),
          child: Text(context.l10n.signInToSource),
        ),
      if (showSettings)
        PopupMenuItem<VoidCallback>(
          value: () => source_actions.openSourceSettings(
            context,
            id,
            sl<SourceRepository>().displayName(id),
          ),
          child: Text(context.l10n.sourceSettings),
        ),
    ],
  );

  Future<void> _solveCloudflare(
    String id,
    String fallbackTarget, {
    required bool isJs,
  }) async {
    final target =
        await sl<SourceRepository>().cfSolveTargetFor(id) ?? fallbackTarget;
    if (target.isEmpty) return;
    if (isJs) {
      await sl<ProviderManager>().solveCloudflareForHost(
        Uri.parse(target).host,
        target,
      );
    } else {
      await MihonExtensionService.solveCloudflare(target);
    }
    await onCloudflareSolved?.call(id);
  }
}
