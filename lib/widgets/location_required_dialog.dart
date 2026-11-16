import 'package:flutter/material.dart';

import '../app_theme.dart';
import '../services/location_service.dart';

/// Shown when a site-proof, geofence, or location-permission check fails.
const String kLocationRequiredDialogMessage =
    'Please enable location access in your mobile settings or update your site location';

const String kLocationRequiredSettingsButtonLabel = 'Open settings';

const String kLocationRequiredRecheckButtonLabel = 'Check location again';

/// How the location-required popup was closed.
enum LocationRequiredDialogResult {
  /// Close, barrier dismiss, or Open settings (settings open separately).
  dismissed,

  /// User asked the calling screen to run the location check again.
  recheck,
}

/// Returns true when [raw] is a client or server error about location
/// permission, GPS, or being too far from the project site.
bool isLocationOrSiteDistanceError(String? raw) {
  final message = raw?.trim().toLowerCase() ?? '';
  if (message.isEmpty) return false;

  const phrases = <String>[
    'must be on site',
    'must be on the site',
    'on site to continue',
    'go to the project site',
    'of the project site',
    'near the site',
    'near the project site',
    'device location is required',
    'location permission',
    'location services are turned off',
    'location is permanently denied',
    'unable to get your current location',
    'unable to read gps',
    'could not get your location',
    'could not read gps',
    'could not verify your distance',
    'project site location is not configured',
    'project site map coordinates',
    'away from site',
    'location required to check in',
    'location required to check out',
    'location required to upload',
    'location required to submit',
    'enable location access',
    'update your site location',
    'upload near the site',
    'submit near the site',
  ];
  for (final phrase in phrases) {
    if (message.contains(phrase)) return true;
  }
  if (message.contains('must be within') &&
      (message.contains('site') || message.contains(' m of'))) {
    return true;
  }
  if (message.contains('m away') && message.contains('site')) {
    return true;
  }
  if (message.contains('location') &&
      message.contains('permanently denied')) {
    return true;
  }
  return false;
}

/// Popup with the location message, Open settings, and Check location again.
///
/// Returns [LocationRequiredDialogResult.recheck] when the user wants the
/// calling screen to run the location check again.
Future<LocationRequiredDialogResult> showLocationRequiredDialog(
  BuildContext context,
) async {
  if (!context.mounted) return LocationRequiredDialogResult.dismissed;
  final result = await showDialog<LocationRequiredDialogResult>(
    context: context,
    useRootNavigator: true,
    builder: (dialogContext) {
      return AlertDialog(
        backgroundColor: AppTheme.darkBackgroundSecondary,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        contentPadding: const EdgeInsets.fromLTRB(24, 24, 24, 16),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              kLocationRequiredDialogMessage,
              style: TextStyle(
                color: AppTheme.darkTextPrimary,
                fontWeight: FontWeight.w600,
                fontSize: 16,
                height: 1.4,
              ),
            ),
            const SizedBox(height: 20),
            ElevatedButton(
              onPressed: () async {
                Navigator.of(dialogContext).pop(
                  LocationRequiredDialogResult.dismissed,
                );
                await LocationService.openRelevantLocationSettings();
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.navy,
                foregroundColor: Colors.white,
                elevation: 0,
                padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              child: const Text(
                kLocationRequiredSettingsButtonLabel,
                style: TextStyle(fontWeight: FontWeight.w700),
              ),
            ),
            const SizedBox(height: 8),
            OutlinedButton(
              onPressed: () {
                Navigator.of(dialogContext).pop(
                  LocationRequiredDialogResult.recheck,
                );
              },
              style: OutlinedButton.styleFrom(
                foregroundColor: AppTheme.darkTextPrimary,
                padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
                side: const BorderSide(color: AppTheme.navy),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              child: const Text(
                kLocationRequiredRecheckButtonLabel,
                style: TextStyle(fontWeight: FontWeight.w700),
              ),
            ),
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(
                LocationRequiredDialogResult.dismissed,
              ),
              child: const Text(
                'Close',
                style: TextStyle(
                  color: AppTheme.mutedGrey,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
        ),
      );
    },
  );
  return result ?? LocationRequiredDialogResult.dismissed;
}

/// Shows [showLocationRequiredDialog] when [message] is a location or
/// site-distance error. Returns true when the popup was shown so the
/// caller can skip the original error UI.
///
/// When the user taps Check location again, [onRecheck] is called after
/// the dialog closes.
Future<bool> showLocationRequiredDialogIfNeeded(
  BuildContext context,
  String? message, {
  Future<void> Function()? onRecheck,
}) async {
  if (!isLocationOrSiteDistanceError(message)) return false;
  if (!context.mounted) return true;
  final result = await showLocationRequiredDialog(context);
  if (result == LocationRequiredDialogResult.recheck && onRecheck != null) {
    await onRecheck();
  }
  return true;
}
