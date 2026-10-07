import 'dart:async';

import 'package:flutter/material.dart';

import '../app_theme.dart';
import '../services/location_service.dart';

/// Shown above staff check-in so background location can be turned on or off.
class BackgroundLocationBanner extends StatefulWidget {
  const BackgroundLocationBanner({super.key});

  @override
  State<BackgroundLocationBanner> createState() =>
      _BackgroundLocationBannerState();
}

class _BackgroundLocationBannerState extends State<BackgroundLocationBanner>
    with WidgetsBindingObserver {
  bool? _backgroundOn;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    unawaited(_refresh());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      unawaited(_refresh());
    }
  }

  Future<void> _refresh() async {
    final backgroundOn = await LocationService.hasBackgroundAccess();
    if (!mounted) return;
    setState(() => _backgroundOn = backgroundOn);
  }

  Future<void> _openSettings() async {
    await LocationService.openBackgroundLocationSettings();
  }

  Future<void> _confirmTurnOff() async {
    final turnOff = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          backgroundColor: AppTheme.darkBackgroundSecondary,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          title: Text(
            'Turn off background location?',
            style: TextStyle(
              color: AppTheme.darkTextPrimary,
              fontWeight: FontWeight.w800,
              fontSize: 18,
            ),
          ),
          content: Text(
            'Attendance monitoring uses background location. Turning this off may flag your attendance within the company',
            style: TextStyle(
              color: AppTheme.darkTextPrimary,
              fontSize: 14.5,
              fontWeight: FontWeight.w500,
              height: 1.4,
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text(
                'Keep on',
                style: TextStyle(
                  color: AppTheme.mutedGrey,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: const Text(
                'Turn off',
                style: TextStyle(
                  color: Color(0xFFB45309),
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          ],
        );
      },
    );
    if (turnOff != true || !mounted) return;
    await LocationService.openBackgroundLocationSettings();
  }

  @override
  Widget build(BuildContext context) {
    final backgroundOn = _backgroundOn;
    if (backgroundOn == null) return const SizedBox.shrink();

    return Column(
      children: [
        if (!backgroundOn) _enableBanner(),
        _allowedBanner(backgroundOn: backgroundOn),
      ],
    );
  }

  static const Color _warning = Color(0xFFD97706);
  static const Color _success = Color(0xFF059669);

  Widget _enableBanner() {
    return _tile(
      accent: _warning,
      icon: Icons.location_searching_rounded,
      title: 'Background location is off',
      subtitle:
          'Allow location all the time so attendance can update after you check in.',
      onTap: _openSettings,
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: const [
          Text(
            'Settings',
            style: TextStyle(
              color: _warning,
              fontSize: 13,
              fontWeight: FontWeight.w800,
            ),
          ),
          Icon(Icons.chevron_right_rounded, color: _warning, size: 18),
        ],
      ),
    );
  }

  Widget _allowedBanner({required bool backgroundOn}) {
    return _tile(
      accent: _success,
      icon: Icons.my_location_rounded,
      title: backgroundOn ? 'Background location is on' : 'Location permission',
      subtitle: 'Change this to not allow in settings.',
      onTap: _confirmTurnOff,
      trailing: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: _warning.withValues(alpha: 0.14),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: _warning.withValues(alpha: 0.4)),
        ),
        child: const Text(
          'Turn off',
          style: TextStyle(
            color: _warning,
            fontSize: 12.5,
            fontWeight: FontWeight.w800,
          ),
        ),
      ),
    );
  }

  Widget _tile({
    required Color accent,
    required IconData icon,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
    required Widget trailing,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Material(
        color: accent.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(14),
          child: Container(
            padding: const EdgeInsets.fromLTRB(14, 12, 10, 12),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: accent.withValues(alpha: 0.22)),
            ),
            child: Row(
              children: [
                Icon(icon, color: accent, size: 20),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: TextStyle(
                          color: AppTheme.darkTextPrimary,
                          fontSize: 14,
                          fontWeight: FontWeight.w800,
                          height: 1.2,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        subtitle,
                        style: const TextStyle(
                          color: AppTheme.mutedGrey,
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          height: 1.3,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                trailing,
              ],
            ),
          ),
        ),
      ),
    );
  }
}
