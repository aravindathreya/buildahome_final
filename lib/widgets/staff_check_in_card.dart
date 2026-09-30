import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../services/attendance_service.dart';
import 'attendance_open_splash.dart';
import 'employer_tracking_indicator.dart';

/// Staff home attendance card. Opens the attendance page.
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
  bool _loading = true;
  String? _error;
  bool _opening = false;
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
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = e.toString().replaceFirst(RegExp(r'^Exception:\s*'), '');
      });
    }
  }

  Future<void> _open() async {
    if (_opening) return;
    setState(() => _opening = true);
    try {
      await AttendanceOpenSplash.push(context);
      if (mounted) await _load();
    } finally {
      if (mounted) setState(() => _opening = false);
    }
  }

  String _clockLabel() {
    final raw = _status?.record?.checkInAt;
    if (raw == null || raw.trim().isEmpty) return '';
    final parsed = DateTime.tryParse(raw.trim().replaceFirst(' ', 'T'));
    if (parsed == null) return raw;
    return DateFormat('h:mm a').format(parsed.toLocal());
  }

  String get _title {
    final status = _status;
    if (_loading || status == null) return 'Attendance';
    if (status.canCheckOut) return 'Checked in';
    if (status.record?.hasCheckedIn == true) return 'Attendance marked';
    if (!status.canCheckIn) return 'Off schedule';
    return 'Check in';
  }

  String get _subtitle {
    if (_loading) return 'Loading attendance…';
    if (_error != null) return _error!;
    final status = _status;
    if (status == null) return 'Open attendance';
    if (status.canCheckOut) {
      final time = _clockLabel();
      final place = status.record?.workspaceName.trim() ?? '';
      if (time.isNotEmpty && place.isNotEmpty) return 'In at $time · $place';
      if (time.isNotEmpty) return 'In at $time';
      return 'You are clocked in';
    }
    if (status.record?.hasCheckedIn == true) return 'You are done for today';
    if (!status.canCheckIn) {
      return 'Outside your schedule. Open attendance to check in.';
    }
    return 'Open attendance to clock in';
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
          child: InkWell(
            onTap: _opening ? null : _open,
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
                        const EmployerTrackingIndicator(onDark: true),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
