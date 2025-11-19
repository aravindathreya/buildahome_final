import 'package:buildahome/UserHome.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app_theme.dart';
import 'services/data_provider.dart';

class ProjectPickerScreen extends StatefulWidget {
  @override
  State<ProjectPickerScreen> createState() => _ProjectPickerScreenState();
}

class _ProjectPickerScreenState extends State<ProjectPickerScreen> {
  final TextEditingController _searchController = TextEditingController();

  List<dynamic> _projects = [];
  List<dynamic> _filteredProjects = [];
  bool _loading = true;
  bool _refreshing = false;
  String? _error;
  bool _navigating = false;

  @override
  void initState() {
    super.initState();
    _projects = List<dynamic>.from(DataProvider().projects);
    _filteredProjects = List<dynamic>.from(_projects);
    _loading = _projects.isEmpty;
    _searchController.addListener(_applyFilter);
    _loadProjects(force: true);
  }

  @override
  void dispose() {
    _searchController.removeListener(_applyFilter);
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadProjects({bool force = false}) async {
    setState(() {
      _error = null;
      if (_projects.isEmpty) {
        _loading = true;
      } else {
        _refreshing = true;
      }
    });

    try {
      await DataProvider().reloadData(force: force || _projects.isEmpty);
      final fetched = List<dynamic>.from(DataProvider().projects);
      if (!mounted) return;
      setState(() {
        _projects = fetched;
        _filteredProjects = _filterProjects(_searchController.text);
        _loading = false;
        _refreshing = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _refreshing = false;
        _error = 'Unable to load projects. Please try again.';
      });
    }
  }

  void _applyFilter() {
    setState(() {
      _filteredProjects = _filterProjects(_searchController.text);
    });
  }

  List<dynamic> _filterProjects(String query) {
    final lower = query.trim().toLowerCase();
    if (lower.isEmpty) {
      return List<dynamic>.from(_projects);
    }

    return _projects.where((project) {
      final name = project['name']?.toString().toLowerCase() ?? '';
      final id = project['id']?.toString() ?? '';
      final client = project['client_name']?.toString().toLowerCase() ?? '';
      return name.contains(lower) || id.contains(lower) || client.contains(lower);
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.backgroundPrimary,
      appBar: AppBar(
        title: Text('Select Project'),
        backgroundColor: AppTheme.backgroundSecondary,
      ),
      body: Stack(
        children: [
          Column(
            children: [
              _buildSearchBar(),
              if (_refreshing)
                LinearProgressIndicator(
                  minHeight: 2,
                  color: AppTheme.primaryColorConst,
                ),
              Expanded(
                child: _loading
                    ? _buildLoadingState()
                    : RefreshIndicator(
                        onRefresh: () => _loadProjects(force: true),
                        child: _buildProjectList(),
                      ),
              ),
            ],
          ),
          if (_navigating)
            Positioned.fill(
              child: Container(
                color: const Color.fromARGB(220, 0, 0, 0),
                child: Center(
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text('Opening project...', style: TextStyle(color: const Color.fromARGB(255, 255, 255, 255), fontWeight: FontWeight.w600)),
                      SizedBox(width: 8),
                      CircularProgressIndicator(
                        strokeWidth: 1,
                        value: 0.5,
                        valueColor: AlwaysStoppedAnimation<Color>(AppTheme.primaryColorConst),
                      ),
                      SizedBox(height: 12),
                      
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildSearchBar() {
    return Container(
      padding: EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.backgroundPrimary,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.2),
            blurRadius: 4,
            offset: Offset(0, 2),
          ),
        ],
      ),
      child: TextField(
        controller: _searchController,
        style: TextStyle(color: AppTheme.textPrimary),
        decoration: InputDecoration(
          hintText: 'Search projects by name, client, or ID',
          hintStyle: TextStyle(color: AppTheme.textSecondary),
          prefixIcon: Icon(Icons.search, color: AppTheme.primaryColorConst),
          filled: true,
          fillColor: AppTheme.backgroundPrimary,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide(
              color: AppTheme.primaryColorConst.withOpacity(0.3),
            ),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide(
              color: AppTheme.primaryColorConst.withOpacity(0.3),
            ),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide(
              color: AppTheme.primaryColorConst,
              width: 2,
            ),
          ),
          contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        ),
      ),
    );
  }

  Widget _buildLoadingState() {
    if (_error != null) {
      return _buildMessageState(
        icon: Icons.error_outline,
        message: _error!,
        action: TextButton(
          onPressed: () => _loadProjects(force: true),
          child: Text('Retry', style: TextStyle(color: AppTheme.primaryColorConst)),
        ),
      );
    }

    return Center(
      child: CircularProgressIndicator(
        valueColor: AlwaysStoppedAnimation<Color>(AppTheme.primaryColorConst),
      ),
    );
  }

  Widget _buildProjectList() {
    if (_filteredProjects.isEmpty) {
      return _buildMessageState(
        icon: Icons.travel_explore,
        message: 'No projects match your search.',
      );
    }

    return ListView.builder(
      padding: EdgeInsets.all(16),
      itemCount: _filteredProjects.length,
      itemBuilder: (context, index) {
        final project = _filteredProjects[index];
        final name = project['name']?.toString() ?? 'Unnamed Project';
        return InkWell(
          onTap: _navigating ? null : () => _openProject(project),
          child: Container(
            padding: EdgeInsets.symmetric(vertical: 12, horizontal: 8),
            decoration: BoxDecoration(
              border: Border(bottom: BorderSide(color: AppTheme.textPrimary.withOpacity(0.08))),
            ),
            child: Text(
              name,
              style: TextStyle(
                color: AppTheme.textPrimary,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildMessageState({required IconData icon, required String message, Widget? action}) {
    return ListView(
      physics: AlwaysScrollableScrollPhysics(),
      children: [
        SizedBox(height: 60),
        Icon(icon, size: 48, color: AppTheme.textSecondary),
        Padding(
          padding: EdgeInsets.symmetric(horizontal: 32, vertical: 16),
          child: Text(
            message,
            textAlign: TextAlign.center,
            style: TextStyle(color: AppTheme.textSecondary),
          ),
        ),
        if (action != null)
          Center(
            child: action,
          ),
      ],
    );
  }

  Future<void> _openProject(dynamic project) async {
    if (_navigating) return;
    final projectId = project['id'];
    final projectName = project['name']?.toString() ?? 'Project';

    if (projectId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Unable to open this project.')),
      );
      return;
    }

    setState(() {
      _navigating = true;
    });

    try {

      SharedPreferences prefs = await SharedPreferences.getInstance();
      print('projectId: $projectId, projectName: $projectName');
      await prefs.setString("project_id", projectId.toString());
      await prefs.setString("client_name", projectName);
      
      // Preload project data for non-Client users
      final role = prefs.getString('role');
      if (role != null && role != 'Client') {
        DataProvider().resetProjectData();
        DataProvider().loadProjectDataForNonClient(projectId.toString()).catchError((e) {
          print('[ProjectPicker] Error preloading project data: $e');
        });
      }
      
      if (!mounted) return;

      Future.delayed(Duration(seconds: 1), () {

      Navigator.of(context).pushReplacement(
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
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _navigating = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to open project. Please try again.')),
      );
    }
  }
}

