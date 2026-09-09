import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';

import '../AttendanceScreen.dart';
import '../app_theme.dart';
import '../services/attendance_service.dart';
import '../services/location_service.dart';
import '../widgets/dashboard_chrome.dart';

/// Once per IST day, prompts staff who still need to check in.
Future<void> maybePromptForAttendance(BuildContext context) async {
  try {
    if (await AttendanceService.wasPromptedToday()) return;

    final status = await AttendanceService.getStatus();
    if (!status.canCheckIn) {
      await AttendanceService.markPromptedToday();
      return;
    }
    if (!context.mounted) return;

    await AttendanceService.markPromptedToday();
    await showAttendancePromptDialog(context, initialStatus: status);
  } catch (_) {
    // Silent on startup — user can still open Attendance from the menu.
  }
}

Future<void> showAttendancePromptDialog(
  BuildContext context, {
  AttendanceStatus? initialStatus,
}) {
  return showDialog<void>(
    context: context,
    barrierDismissible: true,
    builder: (dialogContext) => _AttendancePromptDialog(
      initialStatus: initialStatus,
    ),
  );
}

class _AttendancePromptDialog extends StatefulWidget {
  final AttendanceStatus? initialStatus;

  const _AttendancePromptDialog({this.initialStatus});

  @override
  State<_AttendancePromptDialog> createState() =>
      _AttendancePromptDialogState();
}

class _AttendancePromptDialogState extends State<_AttendancePromptDialog> {
  AttendanceStatus? _status;
  bool _loading = true;
  bool _locating = false;
  bool _submitting = false;
  String? _error;
  Position? _position;
  List<GeofenceMatch> _matches = const [];
  GeofenceMatch? _inRange;

  @override
  void initState() {
    super.initState();
    _bootstrap();
  }

  Future<void> _bootstrap() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final status =
          widget.initialStatus ?? await AttendanceService.getStatus();
      if (!mounted) return;
      setState(() {
        _status = status;
        _loading = false;
      });
      await _refreshLocation();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = e.toString().replaceFirst(RegExp(r'^Exception:\s*'), '');
      });
    }
  }

  Future<void> _refreshLocation() async {
    setState(() {
      _locating = true;
      _error = null;
    });
    final result = await LocationService.getCurrentPosition();
    if (!mounted) return;

    if (!result.ok || result.position == null) {
      setState(() {
        _locating = false;
        _position = null;
        _matches = const [];
        _inRange = null;
        _error = result.error;
      });
      return;
    }

    final status = _status;
    final matches = status == null
        ? <GeofenceMatch>[]
        : LocationService.matchAssignments(
            latitude: result.position!.latitude,
            longitude: result.position!.longitude,
            assignments: status.assignments,
          );

    setState(() {
      _locating = false;
      _position = result.position;
      _matches = matches;
      _inRange = LocationService.nearestInRange(matches);
      _error = null;
    });
  }

  Future<void> _checkIn() async {
    if (_submitting) return;
    final position = _position;
    final match = _inRange;
    if (position == null) {
      setState(() => _error = 'Waiting for your location…');
      await _refreshLocation();
      return;
    }
    if (match == null) {
      setState(() {
        _error =
            'You are outside all assigned workspaces. Move closer to check in.';
      });
      return;
    }

    setState(() {
      _submitting = true;
      _error = null;
    });

    try {
      await AttendanceService.checkIn(
        latitude: position.latitude,
        longitude: position.longitude,
        workspaceId: match.assignment.workspaceId,
      );
      if (!mounted) return;
      Navigator.of(context).pop();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Checked in at ${match.assignment.workspaceName}',
          ),
          behavior: SnackBarBehavior.floating,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _submitting = false;
        _error = e.toString().replaceFirst(RegExp(r'^Exception:\s*'), '');
      });
    }
  }

  void _openFullScreen() {
    Navigator.of(context).pop();
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => DashboardChrome.wrap(
          DashboardChromeStyle.admin,
          const AttendanceScreen(),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final canCheckIn = _status?.canCheckIn == true;
    final inRange = _inRange != null;

    return AlertDialog(
      backgroundColor: Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      titlePadding: const EdgeInsets.fromLTRB(24, 24, 24, 0),
      contentPadding: const EdgeInsets.fromLTRB(24, 16, 24, 8),
      actionsPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      title: const Text(
        'Mark today’s attendance',
        style: TextStyle(
          color: AppTheme.navy,
          fontWeight: FontWeight.w800,
          fontSize: 18,
        ),
      ),
      content: _loading
          ? const SizedBox(
              height: 88,
              child: Center(
                child: SizedBox(
                  width: 22,
                  height: 22,
                  child: CircularProgressIndicator(strokeWidth: 2.4),
                ),
              ),
            )
          : Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _status == null
                      ? 'Confirm you are at your assigned workspace to check in.'
                      : '${_status!.dayName}, ${_status!.date}',
                  style: const TextStyle(
                    color: AppTheme.mutedGrey,
                    fontSize: 14,
                    height: 1.35,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 16),
                _locationCard(),
                if (_error != null) ...[
                  const SizedBox(height: 12),
                  Text(
                    _error!,
                    style: const TextStyle(
                      color: Color(0xFFDC2626),
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ],
            ),
      actions: [
        TextButton(
          onPressed: _submitting ? null : () => Navigator.of(context).pop(),
          child: const Text(
            'Later',
            style: TextStyle(
              color: AppTheme.mutedGrey,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
        TextButton(
          onPressed: _submitting ? null : _openFullScreen,
          child: const Text(
            'Details',
            style: TextStyle(
              color: AppTheme.navy,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
        ElevatedButton(
          onPressed: (_loading || _submitting || !canCheckIn || !inRange)
              ? null
              : _checkIn,
          style: ElevatedButton.styleFrom(
            backgroundColor: AppTheme.navy,
            foregroundColor: Colors.white,
            disabledBackgroundColor: AppTheme.navy.withValues(alpha: 0.35),
            elevation: 0,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          ),
          child: _submitting
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                    strokeWidth: 2.2,
                    color: Colors.white,
                  ),
                )
              : const Text(
                  'Check in',
                  style: TextStyle(fontWeight: FontWeight.w800),
                ),
        ),
      ],
    );
  }

  Widget _locationCard() {
    final match = _inRange;
    final nearest = _matches.isNotEmpty ? _matches.first : null;
    String title;
    String subtitle;
    Color accent;

    if (_locating) {
      title = 'Checking your location…';
      subtitle = 'Stay near your assigned workspace';
      accent = AppTheme.accentBlue;
    } else if (match != null) {
      title = match.assignment.workspaceName;
      subtitle =
          'Within range · ${match.distanceMeters.round()} m away';
      accent = const Color(0xFF059669);
    } else if (nearest != null) {
      title = nearest.assignment.workspaceName;
      subtitle =
          '${nearest.distanceMeters.round()} m away · need ≤ ${nearest.assignment.radiusMeters.round()} m';
      accent = const Color(0xFFD97706);
    } else if (_status?.assignments.isEmpty == true) {
      title = 'No workspace assigned';
      subtitle = 'Ask admin to assign your attendance location';
      accent = const Color(0xFFDC2626);
    } else {
      title = 'Location unavailable';
      subtitle = 'Enable GPS to check in';
      accent = AppTheme.mutedGrey;
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: accent.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: accent.withValues(alpha: 0.25)),
      ),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(Icons.location_on_rounded, color: accent, size: 22),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    color: AppTheme.navy,
                    fontWeight: FontWeight.w800,
                    fontSize: 14,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: const TextStyle(
                    color: AppTheme.mutedGrey,
                    fontWeight: FontWeight.w600,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            onPressed: (_locating || _submitting) ? null : _refreshLocation,
            icon: const Icon(Icons.refresh_rounded, color: AppTheme.navy),
            tooltip: 'Refresh location',
          ),
        ],
      ),
    );
  }
}
