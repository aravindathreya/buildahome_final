import 'package:buildAhome/UserHome.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'app_theme.dart';
import 'chat_v1/chat_v1_api.dart';
import 'chat_v1/chat_v1_app.dart';
import 'chat_v1/chat_v1_mapper.dart';
import 'chat_v1/chat_v1_utils.dart';
import 'services/data_provider.dart';
import 'services/project_open_timing.dart';
import 'widgets/opening_project_splash.dart';
import 'widgets/searchable_select.dart';
import 'widgets/skeleton_loader.dart';

class ProjectPickerScreen {
  static bool _isShowing = false;
  static DateTime? _lastClosedTime;
  static const Duration _cooldownDuration = Duration(milliseconds: 500);

  static const Color _muted = Color(0xFF8A94A6);
  static const Color _border = Color(0xFF334155);
  static const Color _softShadow = Color(0x14000000);

  /// Pick a project and persist it, without opening the project Home screen.
  /// Returns `true` if a project was selected.
  static Future<bool> pick(BuildContext context) {
    return show(context, openHomeOnSelect: false);
  }

  /// Shows the project picker. When [openHomeOnSelect] is true (default),
  /// selecting a project opens the project workspace. When false, only
  /// persists the selection and returns `true`.
  static Future<bool> show(
    BuildContext context, {
    bool openHomeOnSelect = true,
    bool forChat = false,
  }) async {
    // Prevent opening picker if already showing
    if (_isShowing) return false;

    // Prevent opening if closed recently (cooldown period)
    if (_lastClosedTime != null) {
      final timeSinceClose = DateTime.now().difference(_lastClosedTime!);
      if (timeSinceClose < _cooldownDuration) {
        return false;
      }
    }

    _isShowing = true;
    final searchController = TextEditingController();
    final parentContext = context;
    var isClosing = false;
    var didSelect = false;

    try {
      final provider = DataProvider();
      // Open immediately with whatever is already cached from app startup.
      List<dynamic> projects = List<dynamic>.from(provider.projects);
      bool loading = projects.isEmpty;
      Map<String, ChatProjectUnread> unreadByKey = const {};

      // Kick off / refresh project load without blocking the sheet open.
      void Function(void Function())? sheetSetState;
      final refreshFuture = () async {
        try {
          await provider.loadProjects(
            force: forChat ||
                projects.isEmpty ||
                provider.lastProjectsLoad == null,
          );
        } catch (_) {}
        return List<dynamic>.from(provider.projects);
      }();

      refreshFuture.then((loaded) {
        if (isClosing) return;
        final apply = sheetSetState;
        if (apply == null) {
          projects = loaded;
          loading = false;
          return;
        }
        apply(() {
          projects = loaded;
          loading = false;
        });
      });

      if (forChat) {
        ChatV1Api.instance.unreadHintsByProjectKey().then((loaded) {
          if (isClosing) return;
          final apply = sheetSetState;
          if (apply == null) {
            unreadByKey = loaded;
            return;
          }
          apply(() => unreadByKey = loaded);
        }, onError: (e) {
          print('[ProjectPicker] Unread chats failed: $e');
        });
      }

      await showModalBottomSheet(
        context: parentContext,
        backgroundColor: Colors.transparent,
        isScrollControlled: true,
        isDismissible: true,
        enableDrag: true,
        builder: (sheetContext) => Container(
          height: MediaQuery.of(sheetContext).size.height * 0.82,
          decoration: BoxDecoration(
            color: AppTheme.darkBackgroundSecondary,
            borderRadius: BorderRadius.only(
              topLeft: Radius.circular(24),
              topRight: Radius.circular(24),
            ),
            boxShadow: [
              BoxShadow(
                color: _softShadow,
                blurRadius: 24,
                offset: Offset(0, -4),
              ),
            ],
          ),
          child: StatefulBuilder(
            builder: (context, setModalState) {
              sheetSetState = setModalState;

              final query = searchController.text.toLowerCase().trim();
              final filtered = (query.isEmpty
                      ? projects
                      : projects.where((project) {
                          final name =
                              project['name']?.toString().toLowerCase() ?? '';
                          final id = project['id']?.toString() ?? '';
                          final client = project['client_name']
                                  ?.toString()
                                  .toLowerCase() ??
                              '';
                          return name.contains(query) ||
                              id.contains(query) ||
                              client.contains(query);
                        }))
                  .toList();
              if (forChat && unreadByKey.isNotEmpty) {
                filtered.sort((a, b) {
                  final aHint = _projectUnread(a, unreadByKey);
                  final bHint = _projectUnread(b, unreadByKey);
                  final byRecent =
                      bHint.activityAt.compareTo(aHint.activityAt);
                  if (byRecent != 0) return byRecent;
                  final an = a['name']?.toString().toLowerCase() ?? '';
                  final bn = b['name']?.toString().toLowerCase() ?? '';
                  return an.compareTo(bn);
                });
              }

              return Column(
                children: [
                  const SizedBox(height: 10),
                  Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: const Color(0xFF334155),
                      borderRadius: BorderRadius.circular(999),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 16, 12, 8),
                    child: Row(
                      children: [
                        Container(
                          width: 40,
                          height: 40,
                          decoration: BoxDecoration(
                            color: AppTheme.darkBackgroundPrimaryLight,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Icon(
                            Icons.folder_special_rounded,
                            color: AppTheme.darkTextPrimary,
                            size: 20,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Select Project',
                                style: TextStyle(
                                  color: AppTheme.darkTextPrimary,
                                  fontSize: 18,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                              Text(
                                loading
                                    ? 'Loading projects...'
                                    : forChat
                                        ? '${filtered.length} project${filtered.length == 1 ? '' : 's'} · unread in green'
                                        : '${filtered.length} project${filtered.length == 1 ? '' : 's'}',
                                style: const TextStyle(
                                  color: _muted,
                                  fontSize: 12.5,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ],
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.close_rounded, color: _muted),
                          onPressed: () {
                            isClosing = true;
                            FocusManager.instance.primaryFocus?.unfocus();
                            searchController.clear();
                            Navigator.pop(sheetContext);
                          },
                        ),
                      ],
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 4, 20, 12),
                    child: TextField(
                      controller: searchController,
                      textCapitalization: TextCapitalization.sentences,
                      inputFormatters: const [FirstLetterCapitalFormatter()],
                      style: TextStyle(
                        color: AppTheme.darkTextPrimary,
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                      ),
                      onChanged: (value) {
                        if (isClosing) return;
                        setModalState(() {});
                      },
                      decoration: InputDecoration(
                        hintText: 'Search by name, ID, or client',
                        hintStyle: const TextStyle(
                          color: _muted,
                          fontWeight: FontWeight.w500,
                        ),
                        prefixIcon: Icon(
                          Icons.search_rounded,
                          color: AppTheme.darkTextPrimary,
                        ),
                        suffixIcon: searchController.text.isNotEmpty
                            ? IconButton(
                                icon: const Icon(
                                  Icons.clear_rounded,
                                  color: _muted,
                                  size: 20,
                                ),
                                onPressed: () {
                                  if (isClosing) return;
                                  searchController.clear();
                                  setModalState(() {});
                                },
                              )
                            : null,
                        filled: true,
                        fillColor: AppTheme.darkBackgroundPrimary,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(14),
                          borderSide: const BorderSide(color: _border),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(14),
                          borderSide: const BorderSide(color: _border),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(14),
                          borderSide: const BorderSide(
                            color: AppTheme.accentBlue,
                            width: 1.5,
                          ),
                        ),
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 14,
                        ),
                      ),
                    ),
                  ),
                  Expanded(
                    child: loading
                        ? const SkeletonSheetLoader(itemCount: 6)
                        : projects.isEmpty
                            ? const _EmptyState(
                                icon: Icons.folder_open_rounded,
                                title: 'No projects available',
                                subtitle:
                                    'Projects will appear here once loaded.',
                              )
                            : filtered.isEmpty
                                ? const _EmptyState(
                                    icon: Icons.search_off_rounded,
                                    title: 'No matching projects',
                                    subtitle:
                                        'Try a different name, ID, or client.',
                                  )
                                : ListView.builder(
                                    padding: const EdgeInsets.fromLTRB(
                                        20, 4, 20, 24),
                                    itemCount: filtered.length,
                                    itemBuilder: (context, index) {
                                      final project = filtered[index];
                                      final projectId =
                                          project['id']?.toString();
                                      final projectName =
                                          project['name']?.toString() ??
                                              'Unnamed Project';
                                      final clientName =
                                          project['client_name']?.toString();
                                      final accents = const [
                                        Color(0xFFEAB308),
                                        Color(0xFF2563EB),
                                        Color(0xFF22C55E),
                                        Color(0xFF8B5CF6),
                                        Color(0xFFF97316),
                                      ];
                                      final accent =
                                          accents[index % accents.length];
                                      final unreadHint = forChat
                                          ? _projectUnread(project, unreadByKey)
                                          : null;
                                      final unread = unreadHint?.unread ?? 0;
                                      final messagePreview = forChat
                                          ? _chatMessagePreview(unreadHint)
                                          : '';
                                      final activityAt = unreadHint?.lastActivity;
                                      final rowAccent = unread > 0
                                          ? const Color(0xFF22C55E)
                                          : accent;

                                      return Container(
                                        margin:
                                            const EdgeInsets.only(bottom: 10),
                                        decoration: BoxDecoration(
                                          color: AppTheme.darkBackgroundPrimaryLight,
                                          borderRadius:
                                              BorderRadius.circular(16),
                                          border: Border.all(
                                            color: unread > 0
                                                ? const Color(0xFF22C55E)
                                                : _border,
                                          ),
                                          boxShadow: const [
                                            BoxShadow(
                                              color: _softShadow,
                                              blurRadius: 12,
                                              offset: Offset(0, 4),
                                            ),
                                          ],
                                        ),
                                        child: Material(
                                          color: Colors.transparent,
                                          child: InkWell(
                                            onTap: () async {
                                              if (projectId == null) return;

                                              isClosing = true;
                                              didSelect = true;
                                              FocusManager
                                                  .instance.primaryFocus
                                                  ?.unfocus();
                                              searchController.clear();
                                              Navigator.pop(sheetContext);

                                              if (!parentContext.mounted) {
                                                return;
                                              }

                                              Future<void> persistProject(
                                                  [ProjectOpenTiming?
                                                      timing]) async {
                                                Future<void> run() async {
                                                  final prefs =
                                                      await SharedPreferences
                                                          .getInstance();
                                                  await prefs.setString(
                                                      "project_id", projectId);
                                                  await prefs.setString(
                                                      "client_name",
                                                      projectName);

                                                  await DataProvider()
                                                      .onProjectSelected(
                                                    erpProjectId: projectId,
                                                    project: Map<String,
                                                        dynamic>.from(project),
                                                  );

                                                  final role =
                                                      prefs.getString('role');
                                                  if (role != null &&
                                                      role != 'Client') {
                                                    DataProvider()
                                                        .resetProjectData();
                                                    DataProvider()
                                                        .loadProjectDataForNonClient(
                                                            projectId)
                                                        .catchError((e) {
                                                      print(
                                                          '[ProjectPicker] Error preloading project data: $e');
                                                    });
                                                  }
                                                }

                                                if (timing != null) {
                                                  await timing.measure(
                                                      'prepare_persist', run);
                                                } else {
                                                  await run();
                                                }
                                              }

                                              if (!openHomeOnSelect && !forChat) {
                                                await persistProject();
                                                return;
                                              }

                                              if (forChat) {
                                                await persistProject();
                                                if (!parentContext.mounted) {
                                                  return;
                                                }
                                                await Navigator.of(
                                                        parentContext)
                                                    .push(
                                                  MaterialPageRoute(
                                                    builder: (_) =>
                                                        ChatV1App.openQuick(
                                                      erpProjectId: projectId,
                                                      project:
                                                          Map<String, dynamic>
                                                              .from(project),
                                                      openConversation: unread >
                                                              0
                                                          ? unreadHint
                                                              ?.conversation
                                                          : null,
                                                    ),
                                                  ),
                                                );
                                                return;
                                              }

                                              // Splash immediately; load while it shows.
                                              await OpeningProjectGate.push(
                                                parentContext,
                                                projectName: projectName,
                                                destination: Home(
                                                  fromAdminDashboard: true,
                                                ),
                                                prepare: (timing) =>
                                                    persistProject(timing),
                                              );
                                            },
                                            borderRadius:
                                                BorderRadius.circular(16),
                                            child: ClipRRect(
                                              borderRadius:
                                                  BorderRadius.circular(16),
                                              child: IntrinsicHeight(
                                                child: Row(
                                                  crossAxisAlignment:
                                                      CrossAxisAlignment
                                                          .stretch,
                                                  children: [
                                                    Container(
                                                      width: 4,
                                                      color: rowAccent,
                                                    ),
                                                    Expanded(
                                                      child: Padding(
                                                        padding:
                                                            const EdgeInsets
                                                                .all(14),
                                                        child: Row(
                                                          children: [
                                                            Container(
                                                              width: 44,
                                                              height: 44,
                                                              decoration:
                                                                  BoxDecoration(
                                                                color: accent
                                                                    .withValues(
                                                                        alpha:
                                                                            0.12),
                                                                borderRadius:
                                                                    BorderRadius
                                                                        .circular(
                                                                            12),
                                                              ),
                                                              child: Icon(
                                                                Icons
                                                                    .home_work_outlined,
                                                                color: accent,
                                                                size: 22,
                                                              ),
                                                            ),
                                                            const SizedBox(
                                                                width: 12),
                                                            Expanded(
                                                              child: Column(
                                                                crossAxisAlignment:
                                                                    CrossAxisAlignment
                                                                        .start,
                                                                children: [
                                                                  Text(
                                                                    projectName,
                                                                    style:
                                                                        TextStyle(
                                                                      color:
                                                                          AppTheme.darkTextPrimary,
                                                                      fontSize:
                                                                          14.5,
                                                                      fontWeight:
                                                                          FontWeight
                                                                              .w800,
                                                                    ),
                                                                    maxLines:
                                                                        1,
                                                                    overflow:
                                                                        TextOverflow
                                                                            .ellipsis,
                                                                  ),
                                                                  if (clientName !=
                                                                          null &&
                                                                      clientName
                                                                          .isNotEmpty &&
                                                                      messagePreview
                                                                          .isEmpty) ...[
                                                                    const SizedBox(
                                                                        height:
                                                                            3),
                                                                    Text(
                                                                      clientName,
                                                                      style:
                                                                          const TextStyle(
                                                                        color:
                                                                            _muted,
                                                                        fontSize:
                                                                            12,
                                                                        fontWeight:
                                                                            FontWeight.w500,
                                                                      ),
                                                                      maxLines:
                                                                          1,
                                                                      overflow:
                                                                          TextOverflow
                                                                              .ellipsis,
                                                                    ),
                                                                  ],
                                                                  if (messagePreview
                                                                      .isNotEmpty) ...[
                                                                    const SizedBox(
                                                                        height:
                                                                            4),
                                                                    Text(
                                                                      messagePreview,
                                                                      style:
                                                                          TextStyle(
                                                                        color: unread >
                                                                                0
                                                                            ? AppTheme.darkTextPrimary
                                                                            : _muted,
                                                                        fontSize:
                                                                            12.5,
                                                                        fontWeight: unread >
                                                                                0
                                                                            ? FontWeight.w700
                                                                            : FontWeight.w500,
                                                                      ),
                                                                      maxLines:
                                                                          1,
                                                                      overflow:
                                                                          TextOverflow
                                                                              .ellipsis,
                                                                    ),
                                                                  ],
                                                                  if (unread >
                                                                      0) ...[
                                                                    const SizedBox(
                                                                        height:
                                                                            6),
                                                                    Container(
                                                                      padding: const EdgeInsets
                                                                          .symmetric(
                                                                        horizontal:
                                                                            8,
                                                                        vertical:
                                                                            3,
                                                                      ),
                                                                      decoration:
                                                                          BoxDecoration(
                                                                        color: const Color(
                                                                                0xFF22C55E)
                                                                            .withValues(
                                                                                alpha: 0.16),
                                                                        borderRadius:
                                                                            BorderRadius.circular(99),
                                                                      ),
                                                                      child:
                                                                          Text(
                                                                        '$unread',
                                                                        style: const TextStyle(
                                                                          color:
                                                                              Color(0xFF22C55E),
                                                                          fontSize:
                                                                              11,
                                                                          fontWeight:
                                                                              FontWeight.w800,
                                                                        ),
                                                                      ),
                                                                    ),
                                                                  ],
                                                                ],
                                                              ),
                                                            ),
                                                            Column(
                                                              mainAxisAlignment:
                                                                  MainAxisAlignment
                                                                      .center,
                                                              crossAxisAlignment:
                                                                  CrossAxisAlignment
                                                                      .end,
                                                              children: [
                                                                if (activityAt !=
                                                                        null &&
                                                                    activityAt
                                                                            .millisecondsSinceEpoch >
                                                                        0)
                                                                  Text(
                                                                    ChatV1Utils
                                                                        .timeAgo(
                                                                            activityAt),
                                                                    style:
                                                                        TextStyle(
                                                                      color: unread >
                                                                              0
                                                                          ? const Color(
                                                                              0xFF22C55E)
                                                                          : _muted,
                                                                      fontSize:
                                                                          11,
                                                                      fontWeight:
                                                                          FontWeight
                                                                              .w700,
                                                                    ),
                                                                  ),
                                                                const Icon(
                                                                  Icons
                                                                      .chevron_right_rounded,
                                                                  color:
                                                                      _muted,
                                                                ),
                                                              ],
                                                            ),
                                                          ],
                                                        ),
                                                      ),
                                                    ),
                                                  ],
                                                ),
                                              ),
                                            ),
                                          ),
                                        ),
                                      );
                                    },
                                  ),
                  ),
                ],
              );
            },
          ),
        ),
      );
    } finally {
      _isShowing = false;
      _lastClosedTime = DateTime.now();
      await Future.delayed(const Duration(milliseconds: 400));
      searchController.dispose();
    }

    return didSelect;
  }

}

class _EmptyState extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;

  const _EmptyState({
    required this.icon,
    required this.title,
    required this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 64,
              height: 64,
              decoration: BoxDecoration(
                color: AppTheme.darkBackgroundPrimaryLight,
                borderRadius: BorderRadius.circular(18),
              ),
              child: Icon(icon, size: 30, color: AppTheme.darkTextPrimary),
            ),
            const SizedBox(height: 16),
            Text(
              title,
              style: TextStyle(
                color: AppTheme.darkTextPrimary,
                fontSize: 15,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              subtitle,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: ProjectPickerScreen._muted,
                fontSize: 13,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

String _chatMessagePreview(ChatProjectUnread? hint) {
  final conversation = hint?.conversation;
  if (conversation == null || conversation.isEmpty) return '';
  final last = conversation['last_message'];
  if (last != null) {
    final formatted = ChatV1Mapper.formatLastMessagePreview(last);
    if (!formatted.isEmpty) return formatted.label;
  }
  for (final key in const [
    'last_message_preview',
    'last_message_text',
    'preview',
  ]) {
    final text = conversation[key]?.toString().trim() ?? '';
    if (text.isNotEmpty && text.toLowerCase() != 'null') return text;
  }
  return '';
}

ChatProjectUnread _projectUnread(
  dynamic project,
  Map<String, ChatProjectUnread> unreadByKey,
) {
  const none = ChatProjectUnread(unread: 0, conversation: {});
  if (project is! Map || unreadByKey.isEmpty) return none;
  ChatProjectUnread? newest;
  var unread = 0;
  final keys = <String>[
    for (final key in const [
      'id',
      'project_id',
      'sales_sop_id',
      'salesSopId',
      'sop_id',
      'sales_sop_project_id',
    ])
      project[key]?.toString().trim() ?? '',
  ];
  final cached = DataProvider().cachedSalesSopId(project['id']?.toString());
  if (cached != null) keys.add(cached);
  for (final id in keys) {
    if (id.isEmpty) continue;
    final hint = unreadByKey[id];
    if (hint == null) continue;
    if (hint.unread > unread) unread = hint.unread;
    if (newest == null || hint.activityAt.isAfter(newest.activityAt)) {
      newest = hint;
    }
  }
  if (newest == null) return none;
  if (newest.unread == unread) return newest;
  return ChatProjectUnread(
    unread: unread,
    conversation: newest.conversation,
    lastActivity: newest.lastActivity,
  );
}
