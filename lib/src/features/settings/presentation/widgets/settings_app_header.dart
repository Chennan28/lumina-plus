import 'package:flutter/material.dart';
import 'package:ereader/l10n/app_localizations.dart';
import 'package:flutter_svg/svg.dart';

/// Displays the app icon, logo SVG, and version string at the top of the
/// Settings screen.
class SettingsAppHeader extends StatelessWidget {
  const SettingsAppHeader({super.key, required this.version});

  final String version;

  static const _appSvgPath = 'assets/icons/icon.svg';

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // App icon
        Container(
          width: 96,
          height: 96,
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: Theme.of(
                context,
              ).colorScheme.outline.withValues(alpha: 0.5),
              width: 1.5,
            ),
          ),
          child: SvgPicture.asset(_appSvgPath, width: 56, height: 56),
        ),

        const SizedBox(height: 16),

        // App name
        Text(
          AppLocalizations.of(context)!.appName,
          style: Theme.of(context).textTheme.titleLarge?.copyWith(
            fontWeight: FontWeight.w700,
            letterSpacing: 0.5,
          ),
        ),

        const SizedBox(height: 8),

        // Version number
        if (version.isNotEmpty)
          Text(
            'v$version',
            style: TextStyle(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
              fontSize: 14,
            ),
          ),
      ],
    );
  }
}
