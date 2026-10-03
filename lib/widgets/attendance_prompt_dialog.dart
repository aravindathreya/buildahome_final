import 'dart:async';

import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';

import '../app_theme.dart';
import '../services/attendance_service.dart';
import '../services/location_service.dart';
import '../services/staff_location_tracker.dart';
import '../widgets/attendance_note_sheet.dart';

/// Once per IST day, prompts staff who still need to check in.
Future<void> maybePromptForAttendance(BuildContext context) async {
  try {
    if (await AttendanceService.wasPromptedToday()) {
      debugPrint('[Attendance] skip — already prompted today');
      return;
    }

    // Keep network wait bounded; do not timeout the dialog itself.
    final status = await AttendanceService.getStatus()
        .timeout(const Duration(seconds: 12));
    if (!status.canCheckIn) {
      debugPrint('[Attendance] skip — cannot check in / already done');
      await AttendanceService.markPromptedToday();
      return;
    }
    if (!context.mounted) return;

    debugPrint('[Attendance] showing check-in prompt');
    await AttendanceService.markPromptedToday();
    await showAttendancePromptDialog(context, initialStatus: status);
  } catch (e) {
    debugPrint('[Attendance] prompt failed: $e');
    // Silent on startup — user can still open Attendance from the menu.
  }
}

Future<void> showAttendancePromptDialog(
  BuildContext context, {
  AttendanceStatus? initialStatus,
}) {
  return showDialog<void>(
    context: context,
    useRootNavigator: true,
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

  Future<void> _checkIn({bool overrideLocation = false}) async {
    if (_submitting) return;
    final position = _position;
    final match = _inRange;
    if (position == null) {
      setState(() => _error = 'Waiting for your location…');
      await _refreshLocation();
      return;
    }
    if (match == null && !overrideLocation) {
      setState(() {
        _error =
            'You are outside all assigned workspaces. Move closer, or override location with a note.';
      });
      return;
    }

    final note = await showAttendanceNoteSheet(
      context,
      title: overrideLocation ? 'Override location' : 'Check in',
      subtitle: overrideLocation
          ? 'You are outside your assigned workspace. A note is required to check in from here.'
          : 'Add a note for this check-in, or leave it blank.',
      confirmLabel: overrideLocation ? 'Override and check in' : 'Check in',
      requireNote: overrideLocation,
    );
    if (note == null || !mounted) return;

    final nearest = match ?? (_matches.isNotEmpty ? _matches.first : null);

    setState(() {
      _submitting = true;
      _error = null;
    });

    try {
      await AttendanceService.checkIn(
        latitude: position.latitude,
        longitude: position.longitude,
        workspaceId: nearest?.assignment.workspaceId,
        notes: note,
        overrideLocation: overrideLocation,
      );
      unawaited(StaffLocationTracker.instance.start());
      if (!mounted) return;
      Navigator.of(context).pop();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            nearest == null
                ? 'Checked in'
                : 'Checked in at ${nearest.assignment.workspaceName}',
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

  @override
  Widget build(BuildContext context) {
    final canCheckIn = _status?.canCheckIn == true;
    final inRange = _inRange != null;

    return AlertDialog(
      backgroundColor: AppTheme.darkBackgroundSecondary,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      titlePadding: const EdgeInsets.fromLTRB(24, 24, 24, 0),
      contentPadding: const EdgeInsets.fromLTRB(24, 16, 24, 12),
      actionsPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      title: const Text(
        'Mark today’s attendance',
        style: TextStyle(
          color: AppTheme.darkTextPrimary,
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
                const SizedBox(height: 20),
                _promptActions(canCheckIn: canCheckIn, inRange: inRange),
              ],
            ),
    );
  }

  Widget _promptActions({
    required bool canCheckIn,
    required bool inRange,
  }) {
    final proceedEnabled =
        !_loading && !_submitting && !_locating && canCheckIn && _position != null;

    return Row(
      children: [
        Expanded(
          child: SizedBox(
            height: 48,
            child: OutlinedButton(
              onPressed:
                  _submitting ? null : () => Navigator.of(context).pop(),
              style: OutlinedButton.styleFrom(
                foregroundColor: AppTheme.accentBlue,
                disabledForegroundColor:
                    AppTheme.accentBlue.withValues(alpha: 0.45),
                side: const BorderSide(color: AppTheme.accentBlue, width: 1.4),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
              child: const Text(
                'Later',
                style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
              ),
            ),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: SizedBox(
            height: 48,
            child: ElevatedButton(
              onPressed: proceedEnabled
                  ? () => _checkIn(overrideLocation: !inRange)
                  : null,
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.navy,
                foregroundColor: Colors.white,
                disabledBackgroundColor: AppTheme.navy.withValues(alpha: 0.28),
                disabledForegroundColor: Colors.white.withValues(alpha: 0.72),
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
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
                      'Proceed',
                      style: TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 16,
                      ),
                    ),
            ),
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
                    color: AppTheme.darkTextPrimary,
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
            icon: const Icon(Icons.refresh_rounded, color: AppTheme.darkTextPrimary),
            tooltip: 'Refresh location',
          ),
        ],
      ),
    );
  }
}
