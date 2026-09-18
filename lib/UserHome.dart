import 'dart:async';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'LegacyClientHome.dart';
import 'UserDashboard.dart';
import 'app_theme.dart';
import 'services/app_deep_link_service.dart';
import 'services/client_generation_service.dart';
import 'services/data_provider.dart';

class Home extends StatefulWidget {
  final bool fromAdminDashboard;

  Home({Key? key, this.fromAdminDashboard = false}) : super(key: key);

  @override
  State<Home> createState() => _HomeState();
}

class _HomeState extends State<Home> {
  bool _resolving = true;
  bool _useLegacyProjectUi = false;

  @override
  void initState() {
    super.initState();
    if (widget.fromAdminDashboard) {
      DataProvider().resetProjectData();
    }
    ClientGenerationService.instance.generation
        .addListener(_onGenerationChanged);
    _resolveHome();
  }

  @override
  void dispose() {
    ClientGenerationService.instance.generation
        .removeListener(_onGenerationChanged);
    super.dispose();
  }

  void _onGenerationChanged() {
    if (!mounted || _resolving) return;
    final next = ClientGenerationService.instance.shouldUseLegacyProjectUi;
    if (next != _useLegacyProjectUi) {
      setState(() => _useLegacyProjectUi = next);
    }
  }

  Future<void> _resolveHome() async {
    final prefs = await SharedPreferences.getInstance();
    final role = prefs.getString('role');
    var projectId = prefs.getString('project_id')?.trim();

    if ((role ?? '').trim().toLowerCase() == 'client' &&
        (projectId == null || projectId.isEmpty)) {
      projectId = await DataProvider().ensureClientProjectSelected();
    }

    // Cache-first: paints the right shell immediately when generation is known.
    await ClientGenerationService.instance.ensureLoaded(projectId: projectId);
    if (!mounted) return;
    setState(() {
      _useLegacyProjectUi =
          ClientGenerationService.instance.shouldUseLegacyProjectUi;
      _resolving = false;
    });
    unawaited(AppDeepLinkService.instance.onAppReady());
  }

  @override
  Widget build(BuildContext context) {
    if (_resolving) {
      return Scaffold(
        backgroundColor: AppTheme.getBackgroundPrimary(context),
        body: const Center(
          child: SizedBox(
            width: 28,
            height: 28,
            child: CircularProgressIndicator(strokeWidth: 2.4),
          ),
        ),
      );
    }

    if (_useLegacyProjectUi) {
      return LegacyClientHome(fromAdminDashboard: widget.fromAdminDashboard);
    }

    return Scaffold(
      backgroundColor: AppTheme.getBackgroundPrimary(context),
      body: UserDashboardLayout(fromAdminDashboard: widget.fromAdminDashboard),
    );
  }
}
