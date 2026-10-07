import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../project_picker.dart';
import '../../services/data_provider.dart';
import '../chat_v1_app.dart';
import '../chat_v1_project_summaries.dart';
import '../chat_v1_theme.dart';
import '../chat_v1_utils.dart';
import '../widgets/chat_v1_common.dart';
import '../widgets/chat_v1_opening_splash.dart';

/// Staff chat entry: every project this user can access, with unread counts
/// and the latest message. Tapping a project opens that project's chats.
class ChatV1ProjectsScreen extends StatefulWidget {
  const ChatV1ProjectsScreen({super.key});

  /// Route body for menus: chat splash over the project list.
  static Widget openQuick() {
    return ChatV1OpenSplash(
      child: Theme(
        data: ChatV1Theme.data(dark: true),
        child: const ChatV1ProjectsScreen(),
      ),
    );
  }

  @override
  State<ChatV1ProjectsScreen> createState() => _ChatV1ProjectsScreenState();
}

class _ChatV1ProjectsScreenState extends State<ChatV1ProjectsScreen> {
  static const _accents = [
    Color(0xFFEAB308),
    Color(0xFF3B82F6),
    Color(0xFF22C55E),
    Color(0xFF8B5CF6),
    Color(0xFFF97316),
  ];

  final _store = ChatProjectSummaryStore.instance;
  final _search = TextEditingController();
  String _query = '';
  Timer? _searchDebounce;
  List<dynamic> _projects = const [];
  bool _loadingProjects = false;
  bool _opening = false;

  @override
  void initState() {
    super.initState();
    _projects = List<dynamic>.from(DataProvider().projects);
    _store.byKey.addListener(_onSummaries);
    unawaited(_reload(forceProjects: _projects.isEmpty));
  }

  @override
  void dispose() {
    _searchDebounce?.cancel();
    _store.byKey.removeListener(_onSummaries);
    _search.dispose();
    super.dispose();
  }

  void _onSummaries() {
    if (mounted) setState(() {});
  }

  Future<void> _reload({bool forceProjects = true}) async {
    if (mounted) setState(() => _loadingProjects = _projects.isEmpty);
    await Future.wait([
      () async {
        try {
          await DataProvider().loadProjects(force: forceProjects);
        } catch (_) {}
        if (!mounted) return;
        setState(() {
          _projects = List<dynamic>.from(DataProvider().projects);
          _loadingProjects = false;
        });
      }(),
      _store.refresh(force: true),
    ]);
  }

  List<_ProjectRow> _rows() {
    final rows = <_ProjectRow>[];
    for (final raw in _projects) {
      if (raw is! Map) continue;
      final project = Map<String, dynamic>.from(raw);
      final id = project['id']?.toString() ?? '';
      if (id.isEmpty) continue;
      final name = project['name']?.toString() ?? 'Unnamed Project';
      final client = project['client_name']?.toString() ?? '';
      if (_query.isNotEmpty &&
          !name.toLowerCase().contains(_query) &&
          !client.toLowerCase().contains(_query) &&
          !id.contains(_query)) {
        continue;
      }
      rows.add(_ProjectRow(
        project: project,
        name: name,
        client: client,
        summary: _store.forProject(project),
      ));
    }
    rows.sort((a, b) {
      final byRecent = b.activityAt.compareTo(a.activityAt);
      if (byRecent != 0) return byRecent;
      return a.name.toLowerCase().compareTo(b.name.toLowerCase());
    });
    return rows;
  }

  Future<void> _open(_ProjectRow row) async {
    if (_opening) return;
    _opening = true;
    try {
      await ProjectPickerScreen.selectProject(row.project);
      if (!mounted) return;
      final summary = row.summary;
      await Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => ChatV1App.openQuick(
            erpProjectId: row.project['id']?.toString(),
            project: row.project,
            withSplash: false,
            title: row.name,
            openConversation: (summary?.unread ?? 0) > 0 &&
                    summary!.conversation.isNotEmpty
                ? summary.conversation
                : null,
          ),
        ),
      );
    } finally {
      _opening = false;
    }
    unawaited(_store.refresh(force: true));
  }

  @override
  Widget build(BuildContext context) {
    final rows = _rows();
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light,
      child: Scaffold(
        backgroundColor: ChatV1Theme.bg(context),
        body: SafeArea(
          child: Column(
            children: [
              _header(context),
              Padding(
                padding: const EdgeInsets.fromLTRB(14, 4, 14, 10),
                child: Cv1SearchField(
                  controller: _search,
                  hint: 'Search projects',
                  onChanged: (v) {
                    _searchDebounce?.cancel();
                    _searchDebounce =
                        Timer(const Duration(milliseconds: 140), () {
                      if (!mounted) return;
                      setState(() => _query = v.trim().toLowerCase());
                    });
                  },
                ),
              ),
              Expanded(
                child: RefreshIndicator(
                  color: ChatV1Theme.accent,
                  onRefresh: _reload,
                  child: _body(context, rows),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _body(BuildContext context, List<_ProjectRow> rows) {
    if (_loadingProjects && _projects.isEmpty) {
      return ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        children: const [
          SizedBox(height: 120),
          Center(child: CircularProgressIndicator()),
        ],
      );
    }
    if (rows.isEmpty) {
      return ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(40),
        children: [
          const SizedBox(height: 60),
          Icon(
            _query.isEmpty
                ? Icons.folder_open_rounded
                : Icons.search_off_rounded,
            size: 42,
            color: ChatV1Theme.textMuted(context),
          ),
          const SizedBox(height: 12),
          Text(
            _query.isEmpty
                ? 'No projects available'
                : 'No projects match your search',
            textAlign: TextAlign.center,
            style: TextStyle(color: ChatV1Theme.textSecondary(context)),
          ),
        ],
      );
    }
    return ListView.builder(
      physics: const BouncingScrollPhysics(
        parent: AlwaysScrollableScrollPhysics(),
      ),
      padding: const EdgeInsets.only(bottom: 32),
      itemCount: rows.length,
      itemBuilder: (context, index) => _tile(context, rows[index]),
    );
  }

  Widget _header(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 4, 4, 0),
      child: Row(
        children: [
          IconButton(
            onPressed: () => Navigator.of(context).maybePop(),
            icon: Icon(
              Icons.arrow_back_rounded,
              color: ChatV1Theme.text(context),
            ),
          ),
          Expanded(
            child: Text(
              'Chats',
              style: TextStyle(
                color: ChatV1Theme.text(context),
                fontSize: 22,
                fontWeight: FontWeight.w800,
                letterSpacing: -0.4,
              ),
            ),
          ),
          ValueListenableBuilder<int>(
            valueListenable: _store.totalUnread,
            builder: (context, total, _) {
              if (total <= 0) return const SizedBox.shrink();
              return Padding(
                padding: const EdgeInsets.only(right: 14),
                child: Cv1Badge(
                  label: '$total unread',
                  color: ChatV1Theme.unread,
                ),
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _tile(BuildContext context, _ProjectRow row) {
    final unread = row.summary?.unread ?? 0;
    final preview = row.summary?.preview ?? '';
    final subtitle = preview.isNotEmpty
        ? preview
        : row.client.isNotEmpty
            ? row.client
            : 'No messages yet';
    final accent = _accents[row.name.hashCode.abs() % _accents.length];
    final initial = row.name.trim().isEmpty ? '?' : row.name.trim()[0];

    return Material(
      color: ChatV1Theme.bg(context),
      child: InkWell(
        onTap: () => _open(row),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 11, 14, 11),
          child: Row(
            children: [
              Cv1Avatar(initials: initial.toUpperCase(), color: accent),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            row.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: ChatV1Theme.text(context),
                              fontWeight: FontWeight.w600,
                              fontSize: 16,
                            ),
                          ),
                        ),
                        if (row.summary?.hasActivity == true)
                          Text(
                            ChatV1Utils.timeAgo(row.summary!.activityAt),
                            style: TextStyle(
                              color: unread > 0
                                  ? ChatV1Theme.unread
                                  : ChatV1Theme.textMuted(context),
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            subtitle,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: unread > 0
                                  ? ChatV1Theme.text(context)
                                  : ChatV1Theme.textSecondary(context),
                              fontSize: 14,
                              fontWeight:
                                  unread > 0 ? FontWeight.w600 : FontWeight.w400,
                            ),
                          ),
                        ),
                        if (unread > 0) ...[
                          const SizedBox(width: 6),
                          Cv1UnreadBadge(count: unread),
                        ],
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ProjectRow {
  final Map<String, dynamic> project;
  final String name;
  final String client;
  final ChatProjectSummary? summary;

  const _ProjectRow({
    required this.project,
    required this.name,
    required this.client,
    required this.summary,
  });

  DateTime get activityAt =>
      summary?.activityAt ?? DateTime.fromMillisecondsSinceEpoch(0);
}
