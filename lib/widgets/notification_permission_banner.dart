import 'package:flutter/material.dart';

import '../app_theme.dart';
import '../services/push/notification_permission_controller.dart';

/// Shown on the main dashboard while notification permission is off.
class NotificationPermissionBanner extends StatefulWidget {
  final ValueNotifier<bool>? visible;
  final VoidCallback? onEnable;

  const NotificationPermissionBanner({
    super.key,
    this.visible,
    this.onEnable,
  });

  @override
  State<NotificationPermissionBanner> createState() =>
      _NotificationPermissionBannerState();
}

class _NotificationPermissionBannerState
    extends State<NotificationPermissionBanner> {
  @override
  void initState() {
    super.initState();
    if (widget.visible == null) {
      NotificationPermissionController.instance.refresh();
    }
  }

  @override
  Widget build(BuildContext context) {
    final listenable =
        widget.visible ?? NotificationPermissionController.instance.bannerVisible;
    return ValueListenableBuilder<bool>(
      valueListenable: listenable,
      builder: (context, show, _) {
        if (!show) return const SizedBox.shrink();
        const accent = Color(0xFFD97706);
        return Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
          child: Material(
            color: accent.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(14),
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.fromLTRB(14, 12, 14, 8),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: accent.withValues(alpha: 0.22)),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Padding(
                    padding: EdgeInsets.only(top: 1),
                    child: Icon(
                      Icons.notifications_off_outlined,
                      color: accent,
                      size: 20,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Notifications are disabled',
                          style: TextStyle(
                            color: AppTheme.darkTextPrimary,
                            fontSize: 14,
                            fontWeight: FontWeight.w800,
                            height: 1.2,
                          ),
                        ),
                        const SizedBox(height: 2),
                        const Text(
                          'Turn on notifications to receive important updates and chat messages.',
                          style: TextStyle(
                            color: AppTheme.mutedGrey,
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            height: 1.3,
                          ),
                        ),
                        TextButton(
                          onPressed: widget.onEnable ??
                              NotificationPermissionController.instance.enable,
                          style: TextButton.styleFrom(
                            foregroundColor: accent,
                            padding: EdgeInsets.zero,
                            visualDensity: VisualDensity.compact,
                          ),
                          child: const Text(
                            'Enable Notifications',
                            style: TextStyle(fontWeight: FontWeight.w800),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}
