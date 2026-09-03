import 'package:flutter/material.dart';

/// Features that existed on the client dashboard in commit `440e62a`
/// ("Mac changes", Nov 2025). Everything else is treated as not-yet-ready
/// for legacy clients.
class LegacyClientFeatures {
  LegacyClientFeatures._();

  /// Working tiles for a legacy client, in the original dashboard order.
  static const List<String> allowedTitles = [
    'Payments',
    'NT Payments',
    'Non Tender Payments',
    'Documents',
    'Gallery',
    'Updates',
    'Scheduler',
    'Notes & Comments',
    'ChatBox',
    'Checklist',
    'Request Drawings',
  ];

  /// Newer client-facing tiles that stay visible but are not opened.
  static const List<String> comingSoonTitles = [
    'Client Portal',
    'My tasks',
    'My Tasks',
    'Project Timeline',
    'Client Information',
    'Upload payment proofs',
    'Timeline Gallery',
    'Virtual Tour',
    'Chat V1',
    'Project Status',
    'Site Visit Reports',
  ];

  static const String comingSoonMessage = 'Feature coming soon';

  static bool isAllowed(String? title) {
    final normalized = _normalize(title);
    if (normalized.isEmpty) return false;
    if (allowedTitles.any((item) => _normalize(item) == normalized)) {
      return true;
    }
    if (normalized.contains('non tender') || normalized == 'nt payments') {
      return true;
    }
    if (normalized == 'latest updates' || normalized.startsWith('payments')) {
      return true;
    }
    return false;
  }

  static String _normalize(String? title) {
    return (title ?? '').trim().toLowerCase();
  }
}

Future<void> showFeatureComingSoon(
  BuildContext context, {
  String? featureName,
}) {
  final subtitle = (featureName != null && featureName.trim().isNotEmpty)
      ? '${featureName.trim()} will be available soon.'
      : 'This feature will be available soon.';

  return showDialog<void>(
    context: context,
    builder: (dialogContext) {
      return AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text(
          LegacyClientFeatures.comingSoonMessage,
          style: TextStyle(
            fontSize: 17,
            fontWeight: FontWeight.w800,
            color: Color(0xFF1B254B),
          ),
        ),
        content: Text(
          subtitle,
          style: const TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w500,
            color: Color(0xFF5B6578),
            height: 1.4,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text(
              'OK',
              style: TextStyle(
                fontWeight: FontWeight.w700,
                color: Color(0xFF1B254B),
              ),
            ),
          ),
        ],
      );
    },
  );
}
