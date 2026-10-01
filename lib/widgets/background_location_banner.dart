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
          title: const Text(
            'Turn off background location?',
            style: TextStyle(
              color: AppTheme.darkTextPrimary,
              fontWeight: FontWeight.w800,
              fontSize: 18,
            ),
          ),
          content: const Text(
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

  Widget _enableBanner() {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Material(
        color: const Color(0xFFFFFBEB),
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          onTap: _openSettings,
          borderRadius: BorderRadius.circular(14),
          child: Container(
            padding: const EdgeInsets.fromLTRB(12, 12, 10, 12),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: const Color(0xFFFDE68A)),
            ),
            child: Row(
              children: [
                const Icon(
                  Icons.location_searching_rounded,
                  color: Color(0xFFB45309),
                  size: 20,
                ),
                const SizedBox(width: 10),
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Background location is off',
                        style: TextStyle(
                          color: Color(0xFF92400E),
                          fontSize: 13,
                          fontWeight: FontWeight.w800,
                          height: 1.2,
                        ),
                      ),
                      SizedBox(height: 2),
                      Text(
                        'Allow location all the time so attendance can update after you check in.',
                        style: TextStyle(
                          color: Color(0xFFB45309),
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          height: 1.3,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                const Text(
                  'Settings',
                  style: TextStyle(
                    color: Color(0xFF92400E),
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const Icon(
                  Icons.chevron_right_rounded,
                  color: Color(0xFFB45309),
                  size: 18,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _allowedBanner({required bool backgroundOn}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Material(
        color: const Color(0xFFFFFBEB),
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          onTap: _confirmTurnOff,
          borderRadius: BorderRadius.circular(14),
          child: Container(
            padding: const EdgeInsets.fromLTRB(12, 12, 10, 12),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: const Color(0xFFF59E0B)),
            ),
            child: Row(
              children: [
                const Icon(
                  Icons.my_location_rounded,
                  color: Color(0xFF059669),
                  size: 20,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        backgroundOn
                            ? 'Background location is on'
                            : 'Location permission',
                        style: TextStyle(
                          color: AppTheme.darkTextPrimary,
                          fontSize: 13,
                          fontWeight: FontWeight.w800,
                          height: 1.2,
                        ),
                      ),
                      SizedBox(height: 2),
                      Text(
                        'Change this to not allow in settings.',
                        style: TextStyle(
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
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0xFFB45309),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: const Text(
                    'Turn off',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 12.5,
                      fontWeight: FontWeight.w800,
                    ),
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
