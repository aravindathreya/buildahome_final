import 'dart:async';

import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';

import 'app_theme.dart';
import 'services/attendance_service.dart';
import 'services/location_service.dart';
import 'services/staff_location_tracker.dart';
import 'widgets/background_location_banner.dart';
import 'widgets/employer_tracking_indicator.dart';
import 'widgets/dashboard_chrome.dart';
import 'widgets/themed_scaffold.dart';

class AttendanceScreen extends StatefulWidget {
  const AttendanceScreen({super.key});

  @override
  State<AttendanceScreen> createState() => _AttendanceScreenState();
}

class _AttendanceScreenState extends State<AttendanceScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;

  AttendanceStatus? _status;
  AttendanceHistory? _history;
  bool _loadingStatus = true;
  bool _loadingHistory = false;
  bool _locating = false;
  bool _submitting = false;
  String? _statusError;
  String? _historyError;
  String? _actionError;
  Position? _position;
  List<GeofenceMatch> _matches = const [];
  final TextEditingController _noteController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _loadAll();
  }

  @override
  void dispose() {
    _noteController.dispose();
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _loadAll() async {
    await Future.wait([_loadStatus(), _loadHistory()]);
  }

  Future<void> _loadStatus() async {
    setState(() {
      _loadingStatus = true;
      _statusError = null;
    });
    try {
      final status = await AttendanceService.getStatus();
      if (!mounted) return;
      setState(() {
        _status = status;
        _loadingStatus = false;
      });
      await _refreshLocation();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loadingStatus = false;
        _statusError = _cleanError(e);
      });
    }
  }

  Future<void> _loadHistory() async {
    setState(() {
      _loadingHistory = true;
      _historyError = null;
    });
    try {
      final now = DateTime.now();
      final start = DateFormat('yyyy-MM-dd').format(DateTime(now.year, now.month, 1));
      final end = DateFormat('yyyy-MM-dd').format(now);
      final history = await AttendanceService.getHistory(
        startDate: start,
        endDate: end,
      );
      if (!mounted) return;
      setState(() {
        _history = history;
        _loadingHistory = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loadingHistory = false;
        _historyError = _cleanError(e);
      });
    }
  }

  Future<void> _refreshLocation() async {
    setState(() {
      _locating = true;
      _actionError = null;
    });

    final result = await LocationService.getCurrentPosition();
    if (!mounted) return;

    if (!result.ok || result.position == null) {
      setState(() {
        _locating = false;
        _position = null;
        _matches = const [];
        _actionError = result.error;
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
      _actionError = null;
    });
  }

  GeofenceMatch? get _inRange => LocationService.nearestInRange(_matches);

  bool _isOpenShift(AttendanceStatus status) {
    final record = status.record;
    if (record == null) return status.canCheckOut;
    return record.hasCheckedIn && !record.hasCheckedOut;
  }

  bool _isComplete(AttendanceStatus status) {
    final record = status.record;
    return record?.hasCheckedIn == true && record?.hasCheckedOut == true;
  }

  int? _clockMinutes(String raw) {
    final text = raw.trim().toLowerCase();
    if (text.isEmpty) return null;
    final match = RegExp(r'(\d{1,2}):(\d{2})').firstMatch(text);
    if (match == null) return null;
    var hour = int.tryParse(match.group(1)!);
    final minute = int.tryParse(match.group(2)!);
    if (hour == null || minute == null || minute > 59) return null;
    if (text.contains('pm') && hour < 12) hour += 12;
    if (text.contains('am') && hour == 12) hour = 0;
    if (hour > 23) return null;
    return hour * 60 + minute;
  }

  bool _outsideWorkingHours(AttendanceStatus status) {
    if (!status.isScheduledToday) return true;
    final now = DateTime.now();
    final minutes = now.hour * 60 + now.minute;
    final covering =
        status.assignments.where((assignment) => assignment.coversToday);
    final source = covering.isEmpty ? status.assignments : covering;
    var sawWindow = false;
    for (final assignment in source) {
      final start = _clockMinutes(assignment.workStartTime);
      final end = _clockMinutes(assignment.workEndTime);
      if (start == null || end == null) continue;
      sawWindow = true;
      final inside = start <= end
          ? minutes >= start && minutes <= end
          : minutes >= start || minutes <= end;
      if (inside) return false;
    }
    return sawWindow;
  }

  bool _outsideCheckoutLocation(AttendanceStatus status) {
    final checkedInId = status.record?.workspaceId;
    if (checkedInId == null) return _inRange == null;
    for (final match in _matches) {
      if (match.withinRadius && match.assignment.workspaceId == checkedInId) {
        return false;
      }
    }
    return true;
  }

  _AttendanceOverride _checkInOverride(AttendanceStatus status) {
    final reasons = <String>[];
    final open = _isOpenShift(status);
    final complete = _isComplete(status);
    if (complete) reasons.add('Attendance is already complete.');
    if (open) reasons.add('You are already checked in.');
    final outsideHours = _outsideWorkingHours(status) ||
        (!status.canCheckIn && !open && !complete);
    if (outsideHours) reasons.add('You are outside working hours.');
    final outsideLocation = _inRange == null;
    if (outsideLocation) {
      reasons.add('You are outside your assigned location.');
    }
    return _AttendanceOverride(
      reasons: reasons,
      location: outsideLocation,
      schedule: outsideHours || complete || open,
    );
  }

  _AttendanceOverride _checkOutOverride(AttendanceStatus status) {
    final reasons = <String>[];
    final open = _isOpenShift(status);
    final complete = _isComplete(status);
    if (!open) {
      reasons.add(
        complete
            ? 'Attendance is already complete.'
            : 'You have not checked in yet.',
      );
    }
    final outsideLocation = _outsideCheckoutLocation(status);
    final outsideHours = _outsideWorkingHours(status) ||
        (open && !status.canCheckOut && !outsideLocation);
    if (outsideHours) reasons.add('You are outside working hours.');
    if (outsideLocation) {
      reasons.add('You are outside your assigned location.');
    }
    return _AttendanceOverride(
      reasons: reasons,
      location: outsideLocation,
      schedule: !open || outsideHours || complete,
    );
  }

  /// Returns the override note, or null if the user cancels.
  Future<String?> _confirmOverride({
    required bool checkingOut,
    required List<String> reasons,
  }) {
    final generated = reasons.join(' ');
    final typed = _noteController.text.trim();
    final initial = typed.isEmpty ? generated : '$generated $typed';
    return showDialog<String>(
      context: context,
      builder: (dialogContext) => _LocationOverrideDialog(
        checkingOut: checkingOut,
        initialNote: initial,
        reasons: reasons,
      ),
    );
  }

  Future<void> _checkIn() async {
    if (_submitting) return;
    final status = _status;
    if (status == null) return;

    final position = _position;
    if (position == null) {
      setState(() => _actionError = 'Location required to check in.');
      await _refreshLocation();
      return;
    }

    final override = _checkInOverride(status);
    var note = _noteController.text.trim();
    if (override.reasons.isNotEmpty) {
      final entered = await _confirmOverride(
        checkingOut: false,
        reasons: override.reasons,
      );
      if (entered == null || !mounted) return;
      note = entered;
      _noteController.text = entered;
    }

    final match = _inRange;
    final nearest = match ?? (_matches.isNotEmpty ? _matches.first : null);

    setState(() {
      _submitting = true;
      _actionError = null;
    });

    try {
      final record = await AttendanceService.checkIn(
        latitude: position.latitude,
        longitude: position.longitude,
        workspaceId: nearest?.assignment.workspaceId,
        notes: note,
        overrideLocation: override.location,
        scheduleOverride: override.schedule,
      );
      _noteController.clear();
      await AttendanceService.markPromptedToday();
      unawaited(StaffLocationTracker.instance.start());
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Checked in at ${record.workspaceName}'),
          behavior: SnackBarBehavior.floating,
        ),
      );
      await _loadAll();
    } catch (e) {
      if (!mounted) return;
      setState(() => _actionError = _cleanError(e));
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  Future<void> _checkOut() async {
    if (_submitting) return;
    final status = _status;
    if (status == null) return;

    final position = _position;
    if (position == null) {
      setState(() => _actionError = 'Location required to check out.');
      await _refreshLocation();
      return;
    }

    final override = _checkOutOverride(status);
    var note = _noteController.text.trim();
    if (override.reasons.isNotEmpty) {
      final entered = await _confirmOverride(
        checkingOut: true,
        reasons: override.reasons,
      );
      if (entered == null || !mounted) return;
      note = entered;
      _noteController.text = entered;
    }

    setState(() {
      _submitting = true;
      _actionError = null;
    });

    try {
      await AttendanceService.checkOut(
        latitude: position.latitude,
        longitude: position.longitude,
        notes: note,
        overrideLocation: override.location,
        scheduleOverride: override.schedule,
      );
      _noteController.clear();
      StaffLocationTracker.instance.stop();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Checked out successfully'),
          behavior: SnackBarBehavior.floating,
        ),
      );
      await _loadAll();
    } catch (e) {
      if (!mounted) return;
      setState(() => _actionError = _cleanError(e));
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  String _cleanError(Object e) =>
      e.toString().replaceFirst(RegExp(r'^Exception:\s*'), '');

  Future<void> _openMaps(String? link) async {
    if (link == null || link.trim().isEmpty) return;
    final uri = Uri.tryParse(link.trim());
    if (uri == null) return;
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  @override
  Widget build(BuildContext context) {
    final isAdminChrome =
        DashboardChrome.of(context) == DashboardChromeStyle.admin;
    final appBarFg = isAdminChrome ? Colors.white : AppTheme.darkTextPrimary;

    return ThemedScaffold(
      title: 'Attendance',
      actions: [
        IconButton(
          tooltip: 'Refresh',
          onPressed: _submitting ? null : _loadAll,
          icon: Icon(Icons.refresh_rounded, color: appBarFg),
        ),
      ],
      bottom: PreferredSize(
        preferredSize: const Size.fromHeight(84),
        child: Container(
          color: AppTheme.darkBackgroundSecondary,
          padding: const EdgeInsets.fromLTRB(18, 8, 18, 16),
          child: Container(
            height: 48,
            padding: const EdgeInsets.all(4),
            decoration: BoxDecoration(
              color: AppTheme.darkBackgroundPrimaryLight,
              borderRadius: BorderRadius.circular(14),
            ),
            child: TabBar(
              controller: _tabController,
              indicatorSize: TabBarIndicatorSize.tab,
              dividerColor: Colors.transparent,
              splashFactory: NoSplash.splashFactory,
              overlayColor: WidgetStateProperty.all(Colors.transparent),
              labelPadding: EdgeInsets.zero,
              indicator: BoxDecoration(
                color: AppTheme.navy,
                borderRadius: BorderRadius.circular(11),
              ),
              labelColor: Colors.white,
              unselectedLabelColor: AppTheme.mutedGrey,
              labelStyle: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
              ),
              unselectedLabelStyle: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
              tabs: const [
                SizedBox(
                  height: 40,
                  child: Center(child: Text('Today')),
                ),
                SizedBox(
                  height: 40,
                  child: Center(child: Text('History')),
                ),
              ],
            ),
          ),
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          RefreshIndicator(
            onRefresh: _loadAll,
            child: _buildTodayTab(),
          ),
          RefreshIndicator(
            onRefresh: _loadHistory,
            child: _buildHistoryTab(),
          ),
        ],
      ),
    );
  }

  Widget _buildTodayTab() {
    if (_loadingStatus && _status == null) {
      return ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        children: const [
          SizedBox(height: 120),
          Center(child: CircularProgressIndicator(strokeWidth: 2.4)),
        ],
      );
    }

    if (_statusError != null && _status == null) {
      return ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(24),
        children: [
          const SizedBox(height: 48),
          Icon(Icons.error_outline_rounded,
              size: 42, color: Colors.red.shade400),
          const SizedBox(height: 12),
          Text(
            _statusError!,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: AppTheme.darkTextPrimary,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 16),
          Center(
            child: TextButton(
              onPressed: _loadStatus,
              child: const Text('Retry'),
            ),
          ),
        ],
      );
    }

    final status = _status!;
    final inRange = _inRange != null;

    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(16, 22, 16, 28),
      children: [
        const BackgroundLocationBanner(),
        _statusHeader(status),
        const SizedBox(height: 14),
        _locationBanner(inRange: inRange),
        if (_actionError != null) ...[
          const SizedBox(height: 12),
          _errorBanner(_actionError!),
        ],
        const SizedBox(height: 16),
        _noteField(),
        const SizedBox(height: 12),
        _actionButtons(status),
        if (status.record != null) ...[
          const SizedBox(height: 16),
          _recordCard(status.record!),
        ],
        const SizedBox(height: 20),
        const Text(
          'Assigned workspaces',
          style: TextStyle(
            color: AppTheme.darkTextPrimary,
            fontWeight: FontWeight.w800,
            fontSize: 16,
          ),
        ),
        const SizedBox(height: 10),
        if (status.assignments.isEmpty)
          _emptyCard('No workspaces assigned for attendance.')
        else
          ...status.assignments.map(_assignmentTile),
      ],
    );
  }

  Widget _statusHeader(AttendanceStatus status) {
    final checkedIn = status.record?.hasCheckedIn == true;
    final checkedOut = status.record?.hasCheckedOut == true;
    String headline;
    Color color;
    if (checkedOut) {
      headline = 'Checked out';
      color = AppTheme.mutedGrey;
    } else if (checkedIn) {
      headline = 'Checked in';
      color = const Color(0xFF059669);
    } else if (status.canCheckIn) {
      headline = 'Not checked in';
      color = const Color(0xFFD97706);
    } else if (_outsideWorkingHours(status)) {
      headline = 'Off schedule';
      color = const Color(0xFFD97706);
    } else {
      headline = 'No check-in needed';
      color = AppTheme.mutedGrey;
    }

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: AppTheme.darkBackgroundSecondary,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppTheme.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '${status.dayName}, ${status.date}',
            style: const TextStyle(
              color: AppTheme.mutedGrey,
              fontWeight: FontWeight.w600,
              fontSize: 13,
            ),
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              Container(
                width: 10,
                height: 10,
                decoration: BoxDecoration(color: color, shape: BoxShape.circle),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  headline,
                  style: const TextStyle(
                    color: AppTheme.darkTextPrimary,
                    fontWeight: FontWeight.w800,
                    fontSize: 20,
                  ),
                ),
              ),
            ],
          ),
          if (checkedIn && !checkedOut) const EmployerTrackingIndicator(),
          if (status.user != null) ...[
            const SizedBox(height: 8),
            Text(
              '${status.user!.name} · ${status.user!.role}',
              style: const TextStyle(
                color: AppTheme.mutedGrey,
                fontWeight: FontWeight.w600,
                fontSize: 13,
              ),
            ),
          ],
          if (!status.isScheduledToday) ...[
            const SizedBox(height: 10),
            Text(
              'Today is outside your assigned schedule. Check-in may be marked off-schedule.',
              style: TextStyle(
                color: Colors.orange.shade800,
                fontWeight: FontWeight.w600,
                fontSize: 12,
                height: 1.35,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _locationBanner({required bool inRange}) {
    String title;
    String subtitle;
    Color accent;

    if (_locating) {
      title = 'Getting your location…';
      subtitle = 'This is required to mark attendance';
      accent = AppTheme.accentBlue;
    } else if (inRange && _inRange != null) {
      final m = _inRange!;
      title = 'Inside ${m.assignment.workspaceName}';
      subtitle = '${m.distanceMeters.round()} m from centre';
      accent = const Color(0xFF059669);
    } else if (_matches.isNotEmpty) {
      final m = _matches.first;
      title = 'Outside geofence';
      subtitle =
          'Nearest: ${m.assignment.workspaceName} · ${m.distanceMeters.round()} m (need ≤ ${m.assignment.radiusMeters.round()} m)';
      accent = const Color(0xFFD97706);
    } else if (_position != null) {
      title = 'Location ready';
      subtitle = 'No workspace coordinates to compare';
      accent = AppTheme.mutedGrey;
    } else {
      title = 'Location not available';
      subtitle = 'Enable GPS to check in or out';
      accent = const Color(0xFFDC2626);
    }

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: accent.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: accent.withValues(alpha: 0.22)),
      ),
      child: Row(
        children: [
          Icon(Icons.my_location_rounded, color: accent),
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
                    height: 1.3,
                  ),
                ),
              ],
            ),
          ),
          TextButton(
            onPressed: (_locating || _submitting) ? null : _refreshLocation,
            child: const Text('Refresh'),
          ),
          if (_actionError != null &&
              (_actionError!.toLowerCase().contains('permission') ||
                  _actionError!.toLowerCase().contains('turned off') ||
                  _actionError!.toLowerCase().contains('settings')))
            TextButton(
              onPressed: () => LocationService.openAppSettings(),
              child: const Text('Settings'),
            ),
        ],
      ),
    );
  }

  Widget _noteField() {
    return TextField(
      controller: _noteController,
      minLines: 1,
      maxLines: 3,
      textCapitalization: TextCapitalization.sentences,
      decoration: InputDecoration(
        labelText: 'Note (optional)',
        hintText: 'Optional note for this attendance',
        filled: true,
        fillColor: AppTheme.darkBackgroundPrimaryLight,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: AppTheme.border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: AppTheme.border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: AppTheme.navy, width: 1.4),
        ),
      ),
    );
  }

  Widget _actionButtons(AttendanceStatus status) {
    final checkedOut = status.record?.hasCheckedOut == true;
    final checkedIn = status.record?.hasCheckedIn == true && !checkedOut;
    if (checkedIn) {
      return OutlinedButton.icon(
        onPressed: _submitting ? null : _checkOut,
        icon: const Icon(Icons.logout_rounded, size: 18),
        label: const Text('Check out'),
        style: OutlinedButton.styleFrom(
          foregroundColor: AppTheme.darkTextPrimary,
          side: const BorderSide(color: AppTheme.navy),
          minimumSize: const Size.fromHeight(48),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
          textStyle: const TextStyle(
            fontFamily: 'Mulish-Regular',
            fontSize: 14.5,
            fontWeight: FontWeight.w700,
          ),
        ),
      );
    }

    return ElevatedButton.icon(
      onPressed: _submitting ? null : _checkIn,
      icon: const Icon(Icons.login_rounded, size: 18),
      label: const Text('Check in'),
      style: ElevatedButton.styleFrom(
        backgroundColor: AppTheme.navy,
        foregroundColor: Colors.white,
        disabledBackgroundColor: AppTheme.navy.withValues(alpha: 0.3),
        elevation: 0,
        minimumSize: const Size.fromHeight(48),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
        ),
        textStyle: const TextStyle(
          fontFamily: 'Mulish-Regular',
          fontSize: 14.5,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }

  Widget _recordCard(AttendanceRecord record) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.darkBackgroundSecondary,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppTheme.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Text(
                'Today’s record',
                style: TextStyle(
                  color: AppTheme.darkTextPrimary,
                  fontWeight: FontWeight.w800,
                  fontSize: 15,
                ),
              ),
              const Spacer(),
              _statusChip(record.status),
            ],
          ),
          const SizedBox(height: 12),
          _kv('Workspace', record.workspaceName.isEmpty
              ? '—'
              : record.workspaceName),
          _kv('Check in', record.checkInAt ?? '—'),
          _kv('Check out', record.checkOutAt ?? '—'),
          if (record.note != null) _kv('Note', record.note!),
          if (record.checkInLocationOverride)
            _kv('Check-in location', 'Overridden'),
          if (record.checkOutLocationOverride)
            _kv('Check-out location', 'Overridden'),
          if (record.distanceM != null)
            _kv('Distance', '${record.distanceM!.round()} m'),
        ],
      ),
    );
  }

  Widget _assignmentTile(AttendanceAssignment assignment) {
    GeofenceMatch? match;
    for (final m in _matches) {
      if (m.assignment.workspaceId == assignment.workspaceId) {
        match = m;
        break;
      }
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppTheme.darkBackgroundSecondary,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: match?.withinRadius == true
              ? const Color(0xFF059669).withValues(alpha: 0.35)
              : AppTheme.border,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  assignment.workspaceName,
                  style: const TextStyle(
                    color: AppTheme.darkTextPrimary,
                    fontWeight: FontWeight.w800,
                    fontSize: 15,
                  ),
                ),
              ),
              if (match != null)
                Text(
                  match.withinRadius
                      ? 'In range'
                      : '${match.distanceMeters.round()} m',
                  style: TextStyle(
                    color: match.withinRadius
                        ? const Color(0xFF059669)
                        : AppTheme.mutedGrey,
                    fontWeight: FontWeight.w700,
                    fontSize: 12,
                  ),
                ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            '${assignment.workStartTime} – ${assignment.workEndTime}'
            '${assignment.daysLabel.isNotEmpty ? ' · ${assignment.daysLabel}' : ''}',
            style: const TextStyle(
              color: AppTheme.mutedGrey,
              fontWeight: FontWeight.w600,
              fontSize: 12,
            ),
          ),
          Text(
            'Geofence radius ${assignment.radiusMeters.round()} m',
            style: const TextStyle(
              color: AppTheme.mutedGrey,
              fontWeight: FontWeight.w600,
              fontSize: 12,
            ),
          ),
          if (assignment.locationLink != null &&
              assignment.locationLink!.trim().isNotEmpty)
            TextButton(
              onPressed: () => _openMaps(assignment.locationLink),
              style: TextButton.styleFrom(
                padding: EdgeInsets.zero,
                minimumSize: const Size(0, 32),
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              child: const Text('Open in Maps'),
            ),
        ],
      ),
    );
  }

  Widget _buildHistoryTab() {
    if (_loadingHistory && _history == null) {
      return ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        children: const [
          SizedBox(height: 120),
          Center(child: CircularProgressIndicator(strokeWidth: 2.4)),
        ],
      );
    }

    if (_historyError != null && _history == null) {
      return ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(24),
        children: [
          const SizedBox(height: 48),
          Text(
            _historyError!,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: AppTheme.darkTextPrimary,
              fontWeight: FontWeight.w700,
            ),
          ),
          Center(
            child: TextButton(
              onPressed: _loadHistory,
              child: const Text('Retry'),
            ),
          ),
        ],
      );
    }

    final history = _history;
    if (history == null || history.daily.isEmpty) {
      return ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(24),
        children: [
          const SizedBox(height: 48),
          _emptyCard('No attendance records this month yet.'),
        ],
      );
    }

    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(16, 22, 16, 28),
      children: [
        if (history.summary.isNotEmpty) _summaryCard(history.summary),
        const SizedBox(height: 12),
        ...history.daily.map((row) => _historyTile(row)),
      ],
    );
  }

  Widget _summaryCard(Map<String, dynamic> summary) {
    final present = summary['present'] ?? summary['present_count'];
    final late = summary['late'] ?? summary['late_count'];
    final absent = summary['absent'] ?? summary['absent_count'];
    final percent = summary['attendance_percent'] ??
        summary['percentage'] ??
        summary['percent'];

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.darkBackgroundSecondary,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppTheme.border),
      ),
      child: Row(
        children: [
          _summaryStat('Present', present?.toString() ?? '—'),
          _summaryStat('Late', late?.toString() ?? '—'),
          _summaryStat('Absent', absent?.toString() ?? '—'),
          _summaryStat(
            '%',
            percent == null
                ? '—'
                : percent is num
                    ? '${percent.toStringAsFixed(0)}%'
                    : percent.toString(),
          ),
        ],
      ),
    );
  }

  Widget _summaryStat(String label, String value) {
    return Expanded(
      child: Column(
        children: [
          Text(
            value,
            style: const TextStyle(
              color: AppTheme.darkTextPrimary,
              fontWeight: FontWeight.w800,
              fontSize: 18,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            style: const TextStyle(
              color: AppTheme.mutedGrey,
              fontWeight: FontWeight.w600,
              fontSize: 11,
            ),
          ),
        ],
      ),
    );
  }

  Widget _historyTile(AttendanceDailyRow row) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppTheme.darkBackgroundSecondary,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppTheme.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  row.dayName == null || row.dayName!.isEmpty
                      ? row.date
                      : '${row.dayName}, ${row.date}',
                  style: const TextStyle(
                    color: AppTheme.darkTextPrimary,
                    fontWeight: FontWeight.w800,
                    fontSize: 14,
                  ),
                ),
              ),
              if (row.status != null && row.status!.isNotEmpty)
                _statusChip(row.status!),
            ],
          ),
          if (row.workspaceName != null && row.workspaceName!.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(
              row.workspaceName!,
              style: const TextStyle(
                color: AppTheme.mutedGrey,
                fontWeight: FontWeight.w600,
                fontSize: 12,
              ),
            ),
          ],
          const SizedBox(height: 6),
          Text(
            'In: ${row.checkInAt ?? '—'}  ·  Out: ${row.checkOutAt ?? '—'}',
            style: const TextStyle(
              color: AppTheme.mutedGrey,
              fontWeight: FontWeight.w600,
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }

  Widget _statusChip(String status) {
    Color bg;
    Color fg;
    switch (status.toLowerCase()) {
      case 'present':
        bg = const Color(0xFFD1FAE5);
        fg = const Color(0xFF047857);
        break;
      case 'late':
        bg = const Color(0xFFFFEDD5);
        fg = const Color(0xFFC2410C);
        break;
      case 'off_schedule':
        bg = const Color(0xFFE0E7FF);
        fg = const Color(0xFF4338CA);
        break;
      default:
        bg = AppTheme.darkBackgroundPrimaryLight;
        fg = AppTheme.mutedGrey;
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        status.replaceAll('_', ' '),
        style: TextStyle(
          color: fg,
          fontWeight: FontWeight.w800,
          fontSize: 11,
        ),
      ),
    );
  }

  Widget _kv(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 88,
            child: Text(
              label,
              style: const TextStyle(
                color: AppTheme.mutedGrey,
                fontWeight: FontWeight.w600,
                fontSize: 13,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(
                color: AppTheme.darkTextPrimary,
                fontWeight: FontWeight.w700,
                fontSize: 13,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _errorBanner(String message) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFFEE2E2),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        message,
        style: const TextStyle(
          color: Color(0xFFB91C1C),
          fontWeight: FontWeight.w600,
          fontSize: 13,
        ),
      ),
    );
  }

  Widget _emptyCard(String message) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: AppTheme.darkBackgroundSecondary,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppTheme.border),
      ),
      child: Text(
        message,
        textAlign: TextAlign.center,
        style: const TextStyle(
          color: AppTheme.mutedGrey,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

class _AttendanceOverride {
  final List<String> reasons;
  final bool location;
  final bool schedule;

  const _AttendanceOverride({
    required this.reasons,
    required this.location,
    required this.schedule,
  });
}

class _LocationOverrideDialog extends StatefulWidget {
  final bool checkingOut;
  final String initialNote;
  final List<String> reasons;

  const _LocationOverrideDialog({
    required this.checkingOut,
    required this.initialNote,
    required this.reasons,
  });

  @override
  State<_LocationOverrideDialog> createState() =>
      _LocationOverrideDialogState();
}

class _LocationOverrideDialogState extends State<_LocationOverrideDialog> {
  late final TextEditingController _noteController;
  String _error = '';

  @override
  void initState() {
    super.initState();
    _noteController = TextEditingController(text: widget.initialNote);
  }

  @override
  void dispose() {
    _noteController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: AppTheme.darkBackgroundSecondary,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      title: const Text(
        'Override attendance?',
        style: TextStyle(
          color: AppTheme.darkTextPrimary,
          fontWeight: FontWeight.w800,
          fontSize: 18,
        ),
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            widget.reasons.join('\n'),
            style: const TextStyle(
              color: AppTheme.mutedGrey,
              fontWeight: FontWeight.w600,
              height: 1.35,
            ),
          ),
          const SizedBox(height: 14),
          TextField(
            controller: _noteController,
            minLines: 1,
            maxLines: 3,
            textCapitalization: TextCapitalization.sentences,
            decoration: InputDecoration(
              labelText: 'Note',
              filled: true,
              fillColor: const Color(0xFFF8FAFC),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          ),
          if (_error.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              _error,
              style: const TextStyle(
                color: Color(0xFFDC2626),
                fontWeight: FontWeight.w600,
                fontSize: 13,
              ),
            ),
          ],
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text(
            'Cancel',
            style: TextStyle(
              color: AppTheme.mutedGrey,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
        ElevatedButton(
          onPressed: () {
            final note = _noteController.text.trim();
            if (note.isEmpty) {
              setState(() {
                _error = 'A note is required to override location.';
              });
              return;
            }
            Navigator.of(context).pop(note);
          },
          style: ElevatedButton.styleFrom(
            backgroundColor: AppTheme.navy,
            foregroundColor: Colors.white,
            elevation: 0,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
          child: Text(
            widget.checkingOut
                ? 'Override and check out'
                : 'Override and check in',
            style: const TextStyle(
              fontFamily: 'Mulish-Regular',
              fontSize: 14.5,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ],
    );
  }
}
