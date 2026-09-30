import 'dart:async';

import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:intl/intl.dart';

import '../services/attendance_service.dart';
import '../services/location_service.dart';
import '../services/staff_location_tracker.dart';
import 'attendance_note_sheet.dart';

/// Staff home check-in control. Replaces the chat banner for non-clients.
class StaffCheckInCard extends StatefulWidget {
  const StaffCheckInCard({super.key});

  static final Set<Future<void> Function()> _refreshes =
      <Future<void> Function()>{};

  static Future<void> refreshAll() {
    return Future.wait(_refreshes.map((refresh) => refresh()));
  }

  @override
  State<StaffCheckInCard> createState() => _StaffCheckInCardState();
}

class _StaffCheckInCardState extends State<StaffCheckInCard>
    with WidgetsBindingObserver {
  AttendanceStatus? _status;
  Position? _position;
  List<GeofenceMatch> _matches = const [];
  bool _loading = true;
  bool _locating = false;
  bool _submitting = false;
  String? _error;
  late final Future<void> Function() _onRefresh;

  @override
  void initState() {
    super.initState();
    _onRefresh = _load;
    WidgetsBinding.instance.addObserver(this);
    StaffCheckInCard._refreshes.add(_onRefresh);
    _load();
  }

  @override
  void dispose() {
    StaffCheckInCard._refreshes.remove(_onRefresh);
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _load();
  }

  GeofenceMatch? get _inRange => LocationService.nearestInRange(_matches);

  Future<void> _load() async {
    if (!mounted) return;
    setState(() {
      _loading = _status == null;
      _error = null;
    });
    try {
      final status = await AttendanceService.getStatus();
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
        _error = _clean(e);
      });
    }
  }

  Future<void> _refreshLocation() async {
    if (!mounted) return;
    setState(() => _locating = true);
    final result = await LocationService.getCurrentPosition();
    if (!mounted) return;
    if (!result.ok || result.position == null) {
      setState(() {
        _locating = false;
        _position = null;
        _matches = const [];
        _error = result.error;
      });
      return;
    }
    final status = _status;
    setState(() {
      _locating = false;
      _position = result.position;
      _matches = status == null
          ? const <GeofenceMatch>[]
          : LocationService.matchAssignments(
              latitude: result.position!.latitude,
              longitude: result.position!.longitude,
              assignments: status.assignments,
            );
      _error = null;
    });
  }

  Future<void> _checkIn({required bool overrideLocation}) async {
    if (_submitting) return;
    final status = _status;
    final position = _position;
    if (status == null || !status.canCheckIn) return;
    if (position == null) {
      await _refreshLocation();
      return;
    }

    final match = _inRange;
    if (match == null && !overrideLocation) {
      setState(() {
        _error =
            'You must be inside an assigned workspace to check in, or override location with a note.';
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
      final record = await AttendanceService.checkIn(
        latitude: position.latitude,
        longitude: position.longitude,
        workspaceId: nearest?.assignment.workspaceId,
        notes: note,
        overrideLocation: overrideLocation,
      );
      await AttendanceService.markPromptedToday();
      unawaited(StaffLocationTracker.instance.start());
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            record.workspaceName.trim().isEmpty
                ? 'Checked in'
                : 'Checked in at ${record.workspaceName}',
          ),
          behavior: SnackBarBehavior.floating,
        ),
      );
      await _load();
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = _clean(e));
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  Future<void> _checkOut({bool overrideLocation = false}) async {
    if (_submitting) return;
    final status = _status;
    final position = _position;
    if (status == null || !status.canCheckOut) return;
    if (position == null) {
      await _refreshLocation();
      return;
    }

    final checkedInId = status.record?.workspaceId;
    GeofenceMatch? checkoutMatch;
    for (final match in _matches) {
      if (!match.withinRadius) continue;
      if (checkedInId != null && match.assignment.workspaceId == checkedInId) {
        checkoutMatch = match;
        break;
      }
      checkoutMatch ??= match;
    }
    if (checkoutMatch == null && !overrideLocation) {
      setState(() {
        _error =
            'You must be at your check-in workspace to check out, or override location with a note.';
      });
      return;
    }

    final note = await showAttendanceNoteSheet(
      context,
      title: overrideLocation ? 'Override location' : 'Check out',
      subtitle: overrideLocation
          ? 'You are outside your check-in workspace. A note is required to check out from here.'
          : 'Add a note for this check-out, or leave it blank.',
      confirmLabel: overrideLocation ? 'Override and check out' : 'Check out',
      requireNote: overrideLocation,
    );
    if (note == null || !mounted) return;

    setState(() {
      _submitting = true;
      _error = null;
    });
    try {
      await AttendanceService.checkOut(
        latitude: position.latitude,
        longitude: position.longitude,
        notes: note,
        overrideLocation: overrideLocation,
      );
      StaffLocationTracker.instance.stop();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Checked out'),
          behavior: SnackBarBehavior.floating,
        ),
      );
      await _load();
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = _clean(e));
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  String _clean(Object error) =>
      error.toString().replaceFirst(RegExp(r'^Exception:\s*'), '');

  String _clockLabel() {
    final raw = _status?.record?.checkInAt;
    if (raw == null || raw.trim().isEmpty) return '';
    final parsed = DateTime.tryParse(raw.trim().replaceFirst(' ', 'T'));
    if (parsed == null) return raw;
    return DateFormat('h:mm a').format(parsed.toLocal());
  }

  String get _title {
    final status = _status;
    if (status == null) return 'Attendance';
    if (status.canCheckOut) return 'Checked in';
    if (status.canCheckIn) return 'Check in';
    if (status.record?.hasCheckedIn == true) return 'Attendance marked';
    return 'Attendance';
  }

  String get _subtitle {
    if (_loading || _locating) return 'Getting your location…';
    if (_error != null) return _error!;
    final status = _status;
    if (status == null) return 'Pull to refresh attendance';
    if (status.canCheckOut) {
      final time = _clockLabel();
      final place = status.record?.workspaceName.trim() ?? '';
      if (_inRange == null && _position != null) {
        return time.isNotEmpty
            ? 'In at $time · override location to check out'
            : 'Outside your workspace · override location to check out';
      }
      if (time.isNotEmpty && place.isNotEmpty) return 'In at $time · $place';
      if (time.isNotEmpty) return 'In at $time';
      return 'You are clocked in';
    }
    if (!status.canCheckIn) {
      return status.record?.hasCheckedIn == true
          ? 'You are done for today'
          : 'No check-in needed right now';
    }
    final match = _inRange;
    if (match != null) {
      return 'At ${match.assignment.workspaceName} · add a note when you check in';
    }
    if (_matches.isNotEmpty) {
      return 'Outside ${_matches.first.assignment.workspaceName} · override with a note';
    }
    if (_position == null) return 'Enable location to clock in';
    return 'Add a note if you need to override your location';
  }

  String get _buttonLabel {
    final status = _status;
    if (status == null) return 'Check in';
    if (status.canCheckOut && _inRange == null && _position != null) {
      return 'Override';
    }
    if (status.canCheckOut) return 'Check out';
    if (status.canCheckIn && _inRange == null && _position != null) {
      return 'Override';
    }
    if (status.canCheckIn) return 'Check in';
    return 'Done';
  }

  VoidCallback? get _onPressed {
    if (_submitting || _loading || _locating) return null;
    final status = _status;
    if (status == null) return null;
    if (status.canCheckOut) {
      if (_position == null) return _refreshLocation;
      if (_inRange != null) return () => _checkOut(overrideLocation: false);
      return () => _checkOut(overrideLocation: true);
    }
    if (!status.canCheckIn) return null;
    if (_position == null) return _refreshLocation;
    if (_inRange != null) return () => _checkIn(overrideLocation: false);
    return () => _checkIn(overrideLocation: true);
  }

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        boxShadow: const [
          BoxShadow(
            color: Color(0x332563EB),
            blurRadius: 18,
            offset: Offset(0, 8),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(18),
        clipBehavior: Clip.antiAlias,
        child: Ink(
          decoration: const BoxDecoration(
            borderRadius: BorderRadius.all(Radius.circular(18)),
            gradient: LinearGradient(
              colors: [Color(0xFF1B254B), Color(0xFF2563EB)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
          ),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 14, 16),
            child: Row(
              children: [
                Container(
                  width: 52,
                  height: 52,
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.18),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    _status?.canCheckOut == true
                        ? Icons.verified_rounded
                        : Icons.login_rounded,
                    color: Colors.white,
                    size: 26,
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _title,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 20,
                          fontWeight: FontWeight.w800,
                          letterSpacing: -0.3,
                          height: 1.1,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        _subtitle,
                        style: const TextStyle(
                          color: Color(0xE6FFFFFF),
                          fontSize: 13.5,
                          fontWeight: FontWeight.w500,
                          height: 1.25,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 10),
                _actionButton(),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _actionButton() {
    final enabled = _onPressed != null;
    return Material(
      color: enabled ? Colors.white : Colors.white.withValues(alpha: 0.55),
      borderRadius: BorderRadius.circular(999),
      child: InkWell(
        onTap: _onPressed,
        borderRadius: BorderRadius.circular(999),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          child: _submitting
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                    strokeWidth: 2.2,
                    color: Color(0xFF1B254B),
                  ),
                )
              : Text(
                  _buttonLabel,
                  style: const TextStyle(
                    color: Color(0xFF1B254B),
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                  ),
                ),
        ),
      ),
    );
  }
}
