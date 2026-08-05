import 'package:buildAhome/UserHome.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'services/data_provider.dart';
import 'widgets/opening_project_splash.dart';
import 'widgets/skeleton_loader.dart';

class ProjectPickerScreen {
  static bool _isShowing = false;
  static DateTime? _lastClosedTime;
  static const Duration _cooldownDuration = Duration(milliseconds: 500);

  static const Color _navy = Color(0xFF1B254B);
  static const Color _muted = Color(0xFF8A94A6);
  static const Color _border = Color(0xFFE8ECF1);
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

      // Kick off / refresh project load without blocking the sheet open.
      void Function(void Function())? sheetSetState;
      final refreshFuture = () async {
        try {
          await provider.loadProjects(
            force: projects.isEmpty || provider.lastProjectsLoad == null,
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

      await showModalBottomSheet(
        context: parentContext,
        backgroundColor: Colors.transparent,
        isScrollControlled: true,
        isDismissible: true,
        enableDrag: true,
        builder: (sheetContext) => Container(
          height: MediaQuery.of(sheetContext).size.height * 0.82,
          decoration: const BoxDecoration(
            color: Colors.white,
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
              final filtered = query.isEmpty
                  ? projects
                  : projects.where((project) {
                      final name =
                          project['name']?.toString().toLowerCase() ?? '';
                      final id = project['id']?.toString() ?? '';
                      final client =
                          project['client_name']?.toString().toLowerCase() ??
                              '';
                      return name.contains(query) ||
                          id.contains(query) ||
                          client.contains(query);
                    }).toList();

              return Column(
                children: [
                  const SizedBox(height: 10),
                  Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: const Color(0xFFD7DEE8),
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
                            color: const Color(0xFFEEF2FF),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: const Icon(
                            Icons.folder_special_rounded,
                            color: _navy,
                            size: 20,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                'Select Project',
                                style: TextStyle(
                                  color: _navy,
                                  fontSize: 18,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                              Text(
                                loading
                                    ? 'Loading projects...'
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
                      style: const TextStyle(
                        color: _navy,
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
                        prefixIcon: const Icon(
                          Icons.search_rounded,
                          color: _navy,
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
                        fillColor: const Color(0xFFF7F8FB),
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
                          borderSide:
                              const BorderSide(color: _navy, width: 1.5),
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

                                      return Container(
                                        margin:
                                            const EdgeInsets.only(bottom: 10),
                                        decoration: BoxDecoration(
                                          color: Colors.white,
                                          borderRadius:
                                              BorderRadius.circular(16),
                                          border:
                                              Border.all(color: _border),
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

                                              Future<void> persistProject() async {
                                                final prefs =
                                                    await SharedPreferences
                                                        .getInstance();
                                                await prefs.setString(
                                                    "project_id", projectId);
                                                await prefs.setString(
                                                    "client_name", projectName);

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

                                              if (!openHomeOnSelect) {
                                                await persistProject();
                                                return;
                                              }

                                              // Splash immediately; load while it shows.
                                              await OpeningProjectGate.push(
                                                parentContext,
                                                projectName: projectName,
                                                destination: Home(
                                                  fromAdminDashboard: true,
                                                ),
                                                prepare: persistProject,
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
                                                      color: accent,
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
                                                                        const TextStyle(
                                                                      color:
                                                                          _navy,
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
                                                                          .isNotEmpty) ...[
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
                                                                  if (projectId !=
                                                                      null) ...[
                                                                    const SizedBox(
                                                                        height:
                                                                            3),
                                                                    Text(
                                                                      'ID: $projectId',
                                                                      style:
                                                                          const TextStyle(
                                                                        color:
                                                                            _muted,
                                                                        fontSize:
                                                                            11,
                                                                        fontWeight:
                                                                            FontWeight.w600,
                                                                      ),
                                                                    ),
                                                                  ],
                                                                ],
                                                              ),
                                                            ),
                                                            const Icon(
                                                              Icons
                                                                  .chevron_right_rounded,
                                                              color: _muted,
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
                color: const Color(0xFFEEF2FF),
                borderRadius: BorderRadius.circular(18),
              ),
              child: Icon(icon, size: 30, color: ProjectPickerScreen._navy),
            ),
            const SizedBox(height: 16),
            Text(
              title,
              style: const TextStyle(
                color: ProjectPickerScreen._navy,
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
