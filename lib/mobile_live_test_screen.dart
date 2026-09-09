import 'package:flutter/material.dart';

import 'app_theme.dart';
import 'MyTasksScreen.dart';
import 'mobile_live_test_widgets.dart';
import 'models/mobile_live_test.dart';
import 'services/mobile_live_test_access.dart';
import 'services/mobile_live_test_autoplay.dart';
import 'services/mobile_live_test_controller.dart';
import 'services/mobile_live_test_service.dart';
import 'services/mobile_live_test_workflow.dart';
import 'widgets/themed_scaffold.dart';

/// Dedicated Mobile Live Test surface. Isolated from production My Tasks.
class MobileLiveTestScreen extends StatefulWidget {
  final MobileLiveTestController? controller;

  const MobileLiveTestScreen({
    super.key,
    this.controller,
  });

  @override
  State<MobileLiveTestScreen> createState() => _MobileLiveTestScreenState();
}

class _MobileLiveTestScreenState extends State<MobileLiveTestScreen>
    with WidgetsBindingObserver {
  late final MobileLiveTestController _controller;
  late final bool _ownsController;
  bool? _authorized;
  String? _deviceToken;
  bool _autoRunning = false;
  String? _autoStatus;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _ownsController = widget.controller == null;
    _controller = widget.controller ?? MobileLiveTestController();
    MobileLiveTestWorkflow.service = _controller.service;
    _controller.addListener(_onChanged);
    MobileLiveTestAutoPlay.instance.addListener(_onAutoPlayChanged);
    _bootstrap();
  }

  Future<void> _bootstrap() async {
    final allowed = await _controller.service.canEnableForCurrentUser();
    if (!mounted) return;
    setState(() => _authorized = allowed);
    if (!allowed) return;
    _deviceToken = await _controller.service.store.readDeviceToken();
    await _controller.restoreAndRefresh();
    if (!mounted) return;
    if (_controller.enabled) {
      _controller.startSync();
    }
  }

  void _onChanged() {
    if (!mounted) return;
    setState(() {});
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (!_controller.enabled) return;
    if (state == AppLifecycleState.resumed) {
      _controller.startSync();
      _controller.refresh();
    } else if (state == AppLifecycleState.inactive ||
        state == AppLifecycleState.paused ||
        state == AppLifecycleState.hidden ||
        state == AppLifecycleState.detached) {
      _controller.stopSync();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _controller.removeListener(_onChanged);
    MobileLiveTestAutoPlay.instance.removeListener(_onAutoPlayChanged);
    MobileLiveTestAutoPlay.instance.stop();
    _controller.stopSync(notify: false);
    if (identical(MobileLiveTestWorkflow.service, _controller.service)) {
      MobileLiveTestWorkflow.service = null;
    }
    if (_ownsController) {
      _controller.dispose();
    }
    super.dispose();
  }

  Future<void> _enable() async {
    try {
      await _controller.enable();
      _deviceToken = await _controller.service.store.readDeviceToken();
    } on MobileLiveTestException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.message)),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.toString())),
      );
    }
  }

  Future<void> _confirmDisable() async {
    final should = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Disable Test Mode?'),
          content: const Text(
            'This device will disconnect from Mobile Test Mode. '
            'The backend workflow run is not cancelled.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Disable'),
            ),
          ],
        );
      },
    );
    if (should == true) {
      await _controller.disable();
    }
  }

  List<dynamic> _myTasks() {
    return _controller.visibleTasks
        .map((task) => task.toMyTasksMap(deviceToken: _deviceToken))
        .toList();
  }

  void _onAutoPlayChanged() {
    if (!mounted) return;
    setState(() {
      _autoRunning = MobileLiveTestAutoPlay.instance.running;
      _autoStatus = MobileLiveTestAutoPlay.instance.status;
    });
  }

  Future<void> _startAutoRun() async {
    if (_autoRunning || _controller.visibleTasks.isEmpty) return;
    MobileLiveTestAutoPlay.instance.start();
    setState(() {
      _autoRunning = true;
      _autoStatus = MobileLiveTestAutoPlay.instance.status;
    });
  }

  void _stopAutoRun() {
    MobileLiveTestAutoPlay.instance.stop();
    if (!mounted) return;
    setState(() {
      _autoRunning = false;
      _autoStatus = MobileLiveTestAutoPlay.instance.status;
    });
  }

  Future<List<dynamic>> _refreshMyTasks() async {
    await _controller.refresh();
    _deviceToken = await _controller.service.store.readDeviceToken();
    return _myTasks();
  }

  @override
  Widget build(BuildContext context) {
    return ThemedScaffold(
      title: MobileLiveTestAccess.menuTitle,
      actions: [
        if (_authorized == true && _controller.enabled)
          TextButton(
            onPressed: _controller.loading ? null : _confirmDisable,
            child: const Text(
              'Disable',
              style: TextStyle(fontWeight: FontWeight.w700),
            ),
          ),
      ],
      body: _authorized == null
          ? const Center(child: CircularProgressIndicator())
          : _authorized == false
              ? const _UnauthorizedState()
              : !_controller.enabled
                  ? RefreshIndicator(
                      color: AppTheme.navy,
                      onRefresh: () async {},
                      child: ListView(
                        physics: const AlwaysScrollableScrollPhysics(),
                        padding: const EdgeInsets.fromLTRB(18, 8, 18, 28),
                        children: [
                          const _Header(),
                          const SizedBox(height: 16),
                          if (_controller.error != null) ...[
                            MobileLiveTestErrorBanner(
                                message: _controller.error!),
                            const SizedBox(height: 16),
                          ],
                          if (_controller.loading)
                            const Padding(
                              padding: EdgeInsets.only(top: 48),
                              child: Center(child: CircularProgressIndicator()),
                            )
                          else
                            _EnableCard(
                              loading: _controller.loading,
                              onEnable: _enable,
                            ),
                        ],
                      ),
                    )
                  : Column(
                      children: [
                        Padding(
                          padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              if (_controller.error != null) ...[
                                MobileLiveTestErrorBanner(
                                    message: _controller.error!),
                                const SizedBox(height: 8),
                              ],
                              _StatusCard(
                                connectionLabel: _controller.connectionLabel,
                              ),
                              if (!_controller.isWaiting) ...[
                                const SizedBox(height: 8),
                                _AutoRunBar(
                                  running: _autoRunning,
                                  status: _autoStatus,
                                  enabled: !_controller.loading &&
                                      _controller.visibleTasks.isNotEmpty,
                                  onAutoRun: _startAutoRun,
                                  onStop: _stopAutoRun,
                                ),
                              ],
                            ],
                          ),
                        ),
                        const SizedBox(height: 8),
                        if (_controller.isWaiting)
                          const Padding(
                            padding: EdgeInsets.fromLTRB(18, 8, 18, 18),
                            child: _WaitingCard(),
                          )
                        else
                          Expanded(
                            child: MyTasksScreen(
                              tasks: _myTasks(),
                              onRefresh: _refreshMyTasks,
                              showCreateTask: false,
                              embedded: true,
                            ),
                          ),
                      ],
                    ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header();

  @override
  Widget build(BuildContext context) {
    return const Text(
      'Mobile Live Test',
      style: TextStyle(
        fontSize: 22,
        fontWeight: FontWeight.w800,
        color: AppTheme.navy,
        letterSpacing: -0.3,
      ),
    );
  }
}

class _UnauthorizedState extends StatelessWidget {
  const _UnauthorizedState();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Padding(
        padding: EdgeInsets.all(28),
        child: Text(
          'Mobile Test Mode is restricted to Super Admin.',
          textAlign: TextAlign.center,
          style: TextStyle(
            color: AppTheme.mutedGrey,
            fontSize: 15,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }
}

class _EnableCard extends StatelessWidget {
  final bool loading;
  final VoidCallback onEnable;

  const _EnableCard({
    required this.loading,
    required this.onEnable,
  });

  @override
  Widget build(BuildContext context) {
    return MobileLiveTestPanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Enable Test Mode on this device',
            style: TextStyle(
              fontWeight: FontWeight.w800,
              fontSize: 16,
              color: AppTheme.navy,
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            'This registers the phone as a Test Device. Production My Tasks stay unchanged, and only the live-test run assigned to this device will appear here.',
            style: TextStyle(
              color: AppTheme.mutedGrey,
              height: 1.45,
            ),
          ),
          const SizedBox(height: 18),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: loading ? null : onEnable,
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.navy,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              child: Text(loading ? 'Registering…' : 'Enable Test Mode'),
            ),
          ),
        ],
      ),
    );
  }
}

class _StatusCard extends StatelessWidget {
  final String connectionLabel;

  const _StatusCard({
    required this.connectionLabel,
  });

  @override
  Widget build(BuildContext context) {
    final connected = connectionLabel.toLowerCase().contains('connect');
    return Row(
      children: [
        Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: connected
                ? const Color(0xFF16A34A)
                : const Color(0xFF94A3B8),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            'Status: $connectionLabel',
            style: const TextStyle(
              fontWeight: FontWeight.w800,
              color: AppTheme.navy,
            ),
          ),
        ),
      ],
    );
  }
}

class _WaitingCard extends StatelessWidget {
  const _WaitingCard();

  @override
  Widget build(BuildContext context) {
    return const MobileLiveTestPanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Mobile Test Mode Enabled',
            style: TextStyle(
              fontWeight: FontWeight.w800,
              fontSize: 16,
              color: AppTheme.navy,
            ),
          ),
          SizedBox(height: 8),
          Text(
            'Waiting for a Mobile Live Test to be assigned.',
            style: TextStyle(
              color: AppTheme.mutedGrey,
              height: 1.45,
            ),
          ),
        ],
      ),
    );
  }
}

class _AutoRunBar extends StatelessWidget {
  final bool running;
  final bool enabled;
  final String? status;
  final VoidCallback onAutoRun;
  final VoidCallback onStop;

  const _AutoRunBar({
    required this.running,
    required this.enabled,
    required this.status,
    required this.onAutoRun,
    required this.onStop,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: ElevatedButton(
                onPressed: running || !enabled ? null : onAutoRun,
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.navy,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
                child: const Text('Auto Run'),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: OutlinedButton(
                onPressed: running ? onStop : null,
                style: OutlinedButton.styleFrom(
                  foregroundColor: const Color(0xFFB91C1C),
                  side: const BorderSide(color: Color(0xFFB91C1C)),
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
                child: const Text('Stop'),
              ),
            ),
          ],
        ),
        if (status != null && status!.trim().isNotEmpty) ...[
          const SizedBox(height: 8),
          Text(
            status!,
            style: const TextStyle(
              color: AppTheme.navySoft,
              fontSize: 12.5,
              fontWeight: FontWeight.w600,
              height: 1.35,
            ),
          ),
        ],
      ],
    );
  }
}
