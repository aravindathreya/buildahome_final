import 'package:buildAhome/UserHome.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'app_theme.dart';
import 'services/data_provider.dart';

class ProjectPickerScreen {
  static bool _isShowing = false;
  static DateTime? _lastClosedTime;
  static const Duration _cooldownDuration = Duration(milliseconds: 500);
  
  static Future<void> show(BuildContext context) async {
    // Prevent opening picker if already showing
    if (_isShowing) return;
    
    // Prevent opening if closed recently (cooldown period)
    if (_lastClosedTime != null) {
      final timeSinceClose = DateTime.now().difference(_lastClosedTime!);
      if (timeSinceClose < _cooldownDuration) {
        return;
      }
    }
    
    _isShowing = true;
    final searchController = TextEditingController();
    final parentContext = context;
    var isClosing = false;
    
    try {
      List<dynamic> projects = [];
      bool loading = true;
      
      // Load projects initially
      try {
        await DataProvider().reloadData(force: true);
        projects = List<dynamic>.from(DataProvider().projects);
        loading = false;
      } catch (e) {
        loading = false;
      }
      
      await showModalBottomSheet(
      context: parentContext,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      isDismissible: true,
      enableDrag: true,
      builder: (sheetContext) => Container(
        height: MediaQuery.of(sheetContext).size.height * 0.8,
        decoration: BoxDecoration(
          color: AppTheme.getBackgroundSecondary(sheetContext),
          borderRadius: BorderRadius.only(
            topLeft: Radius.circular(20),
            topRight: Radius.circular(20),
          ),
        ),
        child: StatefulBuilder(
          builder: (context, setModalState) {
            final query = searchController.text.toLowerCase().trim();
            final filtered = query.isEmpty
                ? projects
                : projects.where((project) {
                    final name = project['name']?.toString().toLowerCase() ?? '';
                    final id = project['id']?.toString() ?? '';
                    final client = project['client_name']?.toString().toLowerCase() ?? '';
                    return name.contains(query) || id.contains(query) || client.contains(query);
                  }).toList();

            return Column(
              children: [
                Container(
                  padding: EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: AppTheme.getBackgroundPrimary(context),
                    borderRadius: BorderRadius.only(
                      topLeft: Radius.circular(20),
                      topRight: Radius.circular(20),
                    ),
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: 4,
                        height: 20,
                        decoration: BoxDecoration(
                          color: AppTheme.getPrimaryColor(context),
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                      SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          'Select Project',
                          style: TextStyle(
                            color: AppTheme.getTextPrimary(context),
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      IconButton(
                        icon: Icon(Icons.close, color: AppTheme.getTextSecondary(context)),
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
                Container(
                  padding: EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: AppTheme.getBackgroundPrimary(context),
                    boxShadow: [
                      BoxShadow(
                        color: Theme.of(context).brightness == Brightness.dark 
                            ? Colors.black.withOpacity(0.3)
                            : Colors.black.withOpacity(0.05),
                        blurRadius: 4,
                        offset: Offset(0, 2),
                      ),
                    ],
                  ),
                  child: TextField(
                    controller: searchController,
                    style: TextStyle(color: AppTheme.getTextPrimary(context), fontSize: 14),
                    onChanged: (value) {
                      if (isClosing) return;
                      setModalState(() {});
                    },
                    decoration: InputDecoration(
                      hintText: 'Search projects by name, ID, or client...',
                      hintStyle: TextStyle(color: AppTheme.getTextSecondary(context)),
                      prefixIcon: Icon(Icons.search, color: AppTheme.getPrimaryColor(context)),
                      suffixIcon: searchController.text.isNotEmpty
                          ? IconButton(
                              icon: Icon(Icons.clear, color: AppTheme.getTextSecondary(context), size: 20),
                              onPressed: () {
                                if (isClosing) return;
                                searchController.clear();
                                setModalState(() {});
                              },
                            )
                          : null,
                      filled: true,
                      fillColor: AppTheme.getBackgroundSecondary(context),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide(
                          color: AppTheme.getPrimaryColor(context).withOpacity(0.2),
                        ),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide(
                          color: AppTheme.getPrimaryColor(context).withOpacity(0.2),
                        ),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide(
                          color: AppTheme.getPrimaryColor(context),
                          width: 2,
                        ),
                      ),
                      contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                    ),
                  ),
                ),
                Expanded(
                  child: loading
                      ? Center(
                          child: CircularProgressIndicator(
                            valueColor: AlwaysStoppedAnimation<Color>(AppTheme.getPrimaryColor(context)),
                          ),
                        )
                      : projects.isEmpty
                          ? Center(
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(Icons.folder_open, size: 48, color: AppTheme.getTextSecondary(context)),
                                  SizedBox(height: 16),
                                  Text(
                                    'No projects available',
                                    style: TextStyle(
                                      color: AppTheme.getTextSecondary(context),
                                      fontSize: 14,
                                    ),
                                  ),
                                ],
                              ),
                            )
                          : filtered.isEmpty
                              ? Center(
                                  child: Column(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      Icon(Icons.search_off, size: 48, color: AppTheme.getTextSecondary(context)),
                                      SizedBox(height: 16),
                                      Text(
                                        'No projects match your search',
                                        style: TextStyle(
                                          color: AppTheme.getTextSecondary(context),
                                          fontSize: 14,
                                        ),
                                      ),
                                    ],
                                  ),
                                )
                              : ListView.builder(
                                  padding: EdgeInsets.all(16),
                                  itemCount: filtered.length,
                                  itemBuilder: (context, index) {
                                    final project = filtered[index];
                                    final projectId = project['id']?.toString();
                                    final projectName = project['name']?.toString() ?? 'Unnamed Project';
                                    final clientName = project['client_name']?.toString();

                                    return Container(
                                      margin: EdgeInsets.only(bottom: 8),
                                      decoration: BoxDecoration(
                                        color: AppTheme.getBackgroundPrimary(context),
                                        borderRadius: BorderRadius.circular(10),
                                        border: Border.all(
                                          color: AppTheme.getPrimaryColor(context).withOpacity(0.2),
                                          width: 1,
                                        ),
                                      ),
                                      child: Material(
                                        color: Colors.transparent,
                                        child: InkWell(
                                          onTap: () async {
                                            if (projectId == null) return;
                                            
                                            SharedPreferences prefs = await SharedPreferences.getInstance();
                                            await prefs.setString("project_id", projectId);
                                            await prefs.setString("client_name", projectName);

                                            await DataProvider().onProjectSelected(
                                              erpProjectId: projectId,
                                              project: Map<String, dynamic>.from(project),
                                            );
                                            
                                            final role = prefs.getString('role');
                                            if (role != null && role != 'Client') {
                                              DataProvider().resetProjectData();
                                              DataProvider().loadProjectDataForNonClient(projectId).catchError((e) {
                                                print('[ProjectPicker] Error preloading project data: $e');
                                              });
                                            }
                                            
                                            isClosing = true;
                                            FocusManager.instance.primaryFocus?.unfocus();
                                            searchController.clear();
                                            Navigator.pop(sheetContext);

                                            await Future.delayed(
                                              const Duration(milliseconds: 120),
                                            );
                                            if (!parentContext.mounted) return;
                                            Navigator.of(parentContext).push(
                                              PageRouteBuilder(
                                                transitionDuration: Duration(milliseconds: 320),
                                                reverseTransitionDuration: Duration(milliseconds: 240),
                                                pageBuilder: (context, animation, secondaryAnimation) => Home(fromAdminDashboard: true),
                                                transitionsBuilder: (context, animation, secondaryAnimation, child) {
                                                  final curvedAnimation = CurvedAnimation(
                                                    parent: animation,
                                                    curve: Curves.easeOutCubic,
                                                    reverseCurve: Curves.easeInCubic,
                                                  );
                                                  return FadeTransition(
                                                    opacity: curvedAnimation,
                                                    child: SlideTransition(
                                                      position: Tween<Offset>(
                                                        begin: const Offset(0.05, 0.04),
                                                        end: Offset.zero,
                                                      ).animate(curvedAnimation),
                                                      child: ScaleTransition(
                                                        scale: Tween<double>(
                                                          begin: 0.98,
                                                          end: 1.0,
                                                        ).animate(curvedAnimation),
                                                        child: child,
                                                      ),
                                                    ),
                                                  );
                                                },
                                              ),
                                            );
                                          },
                                          borderRadius: BorderRadius.circular(10),
                                          child: Padding(
                                            padding: EdgeInsets.all(12),
                                            child: Row(
                                              children: [
                                                Container(
                                                  padding: EdgeInsets.all(6),
                                                  decoration: BoxDecoration(
                                                    color: AppTheme.getPrimaryColor(context).withOpacity(0.15),
                                                    borderRadius: BorderRadius.circular(6),
                                                  ),
                                                  child: Icon(
                                                    Icons.folder_special,
                                                    color: AppTheme.getPrimaryColor(context),
                                                    size: 16,
                                                  ),
                                                ),
                                                SizedBox(width: 12),
                                                Expanded(
                                                  child: Column(
                                                    crossAxisAlignment: CrossAxisAlignment.start,
                                                    children: [
                                                      Text(
                                                        projectName,
                                                        style: TextStyle(
                                                          color: AppTheme.getTextPrimary(context),
                                                          fontSize: 14,
                                                          fontWeight: FontWeight.w600,
                                                        ),
                                                      ),
                                                      if (clientName != null && clientName.isNotEmpty) ...[
                                                        SizedBox(height: 2),
                                                        Text(
                                                          clientName,
                                                          style: TextStyle(
                                                            color: AppTheme.getTextSecondary(context),
                                                            fontSize: 11,
                                                          ),
                                                        ),
                                                      ],
                                                      if (projectId != null) ...[
                                                        SizedBox(height: 2),
                                                        Text(
                                                          'ID: $projectId',
                                                          style: TextStyle(
                                                            color: AppTheme.getTextSecondary(context),
                                                            fontSize: 10,
                                                          ),
                                                        ),
                                                      ],
                                                    ],
                                                  ),
                                                ),
                                              ],
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
  }
}
