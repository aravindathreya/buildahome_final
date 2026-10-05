import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'ProjectFocusScreen.dart';
import 'ProjectTimelineScreen.dart';
import 'ProjectTimelineStatusScreen.dart';
import 'app_theme.dart';
import 'services/data_provider.dart';
import 'widgets/project_situation_switcher.dart';

/// Single host for Focus / Status / Timeline / Schedule with swipeable [PageView].
class ProjectSituationShell extends StatefulWidget {
  final ProjectSituationTab initialTab;
  final String? salesSopId;

  const ProjectSituationShell({
    super.key,
    this.initialTab = ProjectSituationTab.focus,
    this.salesSopId,
  });

  /// Convenience entry points used by menus / dashboards.
  static Widget focus({String? salesSopId}) => ProjectSituationShell(
        initialTab: ProjectSituationTab.focus,
        salesSopId: salesSopId,
      );

  static Widget status() => const ProjectSituationShell(
        initialTab: ProjectSituationTab.status,
      );

  static Widget timeline() => const ProjectSituationShell(
        initialTab: ProjectSituationTab.timeline,
      );

  static Widget schedule() => const ProjectSituationShell(
        initialTab: ProjectSituationTab.schedule,
      );

  @override
  State<ProjectSituationShell> createState() => _ProjectSituationShellState();
}

class _ProjectSituationShellState extends State<ProjectSituationShell> {
  late final List<ProjectSituationTab> _tabs;
  late final PageController _pageController;
  late int _index;

  final _focusKey = GlobalKey<ProjectFocusScreenState>();
  final _statusKey = GlobalKey<ProjectTimelineStatusScreenState>();
  final _timelineKey = GlobalKey<ProjectTimelineScreenState>();
  final _scheduleKey = GlobalKey<ProjectTimelineScreenState>();

  @override
  void initState() {
    super.initState();
    _tabs = _buildTabs();
    final initial = _tabs.contains(widget.initialTab)
        ? widget.initialTab
        : ProjectSituationTab.focus;
    _index = _tabs.indexOf(initial);
    if (_index < 0) _index = 0;
    _pageController = PageController(initialPage: _index);
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  List<ProjectSituationTab> _buildTabs() {
    final role = (DataProvider().currentRole ?? '').trim().toLowerCase();
    final showSchedule = role.isNotEmpty && role != 'client';
    return [
      ProjectSituationTab.focus,
      ProjectSituationTab.status,
      ProjectSituationTab.timeline,
      if (showSchedule) ProjectSituationTab.schedule,
    ];
  }

  ProjectSituationTab get _currentTab => _tabs[_index];

  String get _title {
    switch (_currentTab) {
      case ProjectSituationTab.focus:
        return 'Project Focus';
      case ProjectSituationTab.status:
        return 'Project Status';
      case ProjectSituationTab.timeline:
        return 'Project Timeline';
      case ProjectSituationTab.schedule:
        return 'Schedule';
    }
  }

  bool get _isRefreshing {
    switch (_currentTab) {
      case ProjectSituationTab.focus:
        return _focusKey.currentState?.isRefreshing ?? false;
      case ProjectSituationTab.status:
        return _statusKey.currentState?.isRefreshing ?? false;
      case ProjectSituationTab.timeline:
        return _timelineKey.currentState?.isRefreshing ?? false;
      case ProjectSituationTab.schedule:
        return _scheduleKey.currentState?.isRefreshing ?? false;
    }
  }

  Future<void> _refreshCurrent() async {
    switch (_currentTab) {
      case ProjectSituationTab.focus:
        await _focusKey.currentState?.refresh();
        break;
      case ProjectSituationTab.status:
        await _statusKey.currentState?.refresh();
        break;
      case ProjectSituationTab.timeline:
        await _timelineKey.currentState?.refresh();
        break;
      case ProjectSituationTab.schedule:
        await _scheduleKey.currentState?.refresh();
        break;
    }
    if (mounted) setState(() {});
  }

  void _onTabSelected(ProjectSituationTab tab) {
    final i = _tabs.indexOf(tab);
    if (i < 0 || i == _index) return;
    _pageController.animateToPage(
      i,
      duration: const Duration(milliseconds: 280),
      curve: Curves.easeOutCubic,
    );
  }

  @override
  Widget build(BuildContext context) {
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light.copyWith(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.light,
      ),
      child: Scaffold(
        backgroundColor: AppTheme.getBackgroundPrimary(context),
        appBar: AppBar(
          backgroundColor: AppTheme.getBackgroundSecondary(context),
          foregroundColor: AppTheme.darkTextPrimary,
          elevation: 0,
          scrolledUnderElevation: 0,
          iconTheme: IconThemeData(color: AppTheme.darkTextPrimary),
          actionsIconTheme: IconThemeData(color: AppTheme.darkTextPrimary),
          leading: IconButton(
            icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 20),
            onPressed: () => Navigator.maybePop(context),
          ),
          title: Text(
            _title,
            style: TextStyle(
              color: AppTheme.darkTextPrimary,
              fontSize: 20,
              fontWeight: FontWeight.w800,
              letterSpacing: -0.4,
            ),
          ),
          bottom: ProjectSituationSwitcher(
            selected: _currentTab,
            onChanged: _onTabSelected,
            showSchedule: _tabs.contains(ProjectSituationTab.schedule),
          ),
          actions: [
            IconButton(
              tooltip: 'Refresh',
              onPressed: _isRefreshing ? null : _refreshCurrent,
              icon: _isRefreshing
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: AppTheme.navy,
                      ),
                    )
                  : Icon(Icons.refresh_rounded,
                      color: AppTheme.darkTextPrimary),
            ),
            const SizedBox(width: 8),
          ],
        ),
        body: SafeArea(
          child: PageView(
            controller: _pageController,
            onPageChanged: (i) {
              setState(() => _index = i);
            },
            children: [
              for (final tab in _tabs) _pageFor(tab),
            ],
          ),
        ),
      ),
    );
  }

  Widget _pageFor(ProjectSituationTab tab) {
    switch (tab) {
      case ProjectSituationTab.focus:
        return ProjectFocusScreen(
          key: _focusKey,
          salesSopId: widget.salesSopId,
          embedded: true,
        );
      case ProjectSituationTab.status:
        return ProjectTimelineStatusScreen(
          key: _statusKey,
          embedded: true,
        );
      case ProjectSituationTab.timeline:
        return ProjectTimelineScreen(
          key: _timelineKey,
          embedded: true,
        );
      case ProjectSituationTab.schedule:
        return ProjectTimelineScreen.fullSchedule(
          key: _scheduleKey,
          embedded: true,
        );
    }
  }
}
