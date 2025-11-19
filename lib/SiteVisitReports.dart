import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app_theme.dart';
import 'services/data_provider.dart';
import 'widgets/searchable_select.dart';

class SiteVisitReportsScreen extends StatefulWidget {
  @override
  State<SiteVisitReportsScreen> createState() => _SiteVisitReportsScreenState();
}

class _SiteVisitReportsScreenState extends State<SiteVisitReportsScreen> {
  final TextEditingController _noteController = TextEditingController();
  final TextEditingController _userIdFilterController = TextEditingController();

  bool _isTask = false;
  bool _submitting = false;
  bool _fetchingReports = false;
  bool _myReportsOnly = true;

  List<dynamic> _projects = [];
  bool _projectsLoading = false;
  dynamic _createProject;
  dynamic _viewProject;

  List<dynamic> _reports = [];
  bool _hasSearched = false;
  String? _reportsError;

  @override
  void initState() {
    super.initState();
    _primeProjects();
  }

  @override
  void dispose() {
    _noteController.dispose();
    _userIdFilterController.dispose();
    super.dispose();
  }

  Future<void> _primeProjects() async {
    setState(() {
      _projectsLoading = true;
    });

    // First check if projects are already loaded
    var dataProvider = DataProvider();
    var projects = dataProvider.projects;
    
    // If projects are empty or we need to refresh, reload data
    if (projects.isEmpty) {
      await dataProvider.reloadData(force: true);
      projects = dataProvider.projects;
    } else {
      // Projects are already loaded, but refresh in background if needed
      dataProvider.reloadData(force: false).then((_) {
        if (mounted) {
          setState(() {
            _projects = dataProvider.projects;
          });
        }
      });
    }

    if (!mounted) return;
    setState(() {
      _projects = projects;
      _projectsLoading = false;
    });
  }

  Future<void> _ensureProjectsLoaded() async {
    if (_projects.isEmpty && !_projectsLoading) {
      await _primeProjects();
    }
  }

  Future<void> _openProjectPicker({required bool forCreate}) async {
    await _ensureProjectsLoaded();
    if (_projects.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('No projects available. Please try again later.')),
      );
      return;
    }

    final selected = await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => SearchableSelect(
          title: 'Select Project',
          items: _projects,
          itemLabel: (item) => item['name']?.toString() ?? 'Project #${item['id']}',
          selectedItem: forCreate ? _createProject : _viewProject,
          onItemSelected: (_) {},
        ),
      ),
    );

    if (selected != null) {
      setState(() {
        if (forCreate) {
          _createProject = selected;
        } else {
          _viewProject = selected;
        }
      });
    }
  }

  Future<void> _submitReport() async {
    final note = _noteController.text.trim();
    if (_createProject == null) {
      _showSnackBar('Please select a project.');
      return;
    }
    if (note.isEmpty) {
      _showSnackBar('Please enter a note for the visit.');
      return;
    }

    SharedPreferences prefs = await SharedPreferences.getInstance();
    final createdBy = prefs.getString('userId') ?? prefs.getString('user_id');
    if (createdBy == null) {
      _showSnackBar('Unable to find your user information.');
      return;
    }

    setState(() {
      _submitting = true;
    });

    try {
      final response = await http.post(
        Uri.parse('https://office.buildahome.in/api/site_visit_reports'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'created_by_user_id': int.tryParse(createdBy) ?? createdBy,
          'project_id': _createProject['id'],
          'note': note,
          'is_task': _isTask ? 1 : 0,
        }),
      );

      if (response.statusCode == 201) {
        final body = jsonDecode(response.body);
        _showSnackBar(body['message']?.toString() ?? 'Report created.');
        setState(() {
          _noteController.clear();
          _isTask = false;
        });
      } else {
        final error = _extractError(response);
        _showSnackBar(error ?? 'Unable to create report.');
      }
    } catch (e) {
      _showSnackBar('Network error. Please try again.');
    } finally {
      setState(() {
        _submitting = false;
      });
    }
  }

  Future<void> _fetchReports() async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    final currentUserId = prefs.getString('userId') ?? prefs.getString('user_id');

    final Map<String, String> query = {};
    if (_viewProject != null) {
      query['project_id'] = _viewProject['id'].toString();
    }

    if (_myReportsOnly && currentUserId != null) {
      query['created_by_user_id'] = currentUserId;
    } else if (!_myReportsOnly) {
      final manualUser = _userIdFilterController.text.trim();
      if (manualUser.isNotEmpty) {
        query['created_by_user_id'] = manualUser;
      }
    }

    if (query.isEmpty) {
      _showSnackBar('Select at least a project or supply a user filter.');
      return;
    }

    setState(() {
      _fetchingReports = true;
      _reportsError = null;
    });

    try {
      final uri = Uri.parse('https://office.buildahome.in/api/site_visit_reports/search')
          .replace(queryParameters: query);
      final response = await http.get(uri);

      if (response.statusCode == 200) {
        final body = jsonDecode(response.body);
        setState(() {
          _reports = (body['data'] as List<dynamic>? ?? []);
          _hasSearched = true;
        });
      } else {
        setState(() {
          _reports = [];
          _hasSearched = true;
          _reportsError = _extractError(response) ?? 'Unable to fetch reports.';
        });
      }
    } catch (e) {
      setState(() {
        _reports = [];
        _hasSearched = true;
        _reportsError = 'Network error. Please try again.';
      });
    } finally {
      setState(() {
        _fetchingReports = false;
      });
    }
  }

  String? _extractError(http.Response response) {
    try {
      final decoded = jsonDecode(response.body);
      if (decoded is Map<String, dynamic>) {
        return decoded['message']?.toString();
      }
    } catch (_) {}
    return null;
  }

  void _showSnackBar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        backgroundColor: AppTheme.backgroundPrimary,
        appBar: AppBar(
          title: Text('Site Visit Reports'),
          backgroundColor: AppTheme.backgroundSecondary,
          bottom: TabBar(
            indicatorColor: AppTheme.primaryColorConst,
            labelColor: AppTheme.textPrimary,
            tabs: const [
              Tab(text: 'Create'),
              Tab(text: 'View'),
            ],
          ),
        ),
        body: TabBarView(
          children: [
            _buildCreateTab(),
            _buildViewTab(),
          ],
        ),
      ),
    );
  }

  Widget _buildCreateTab() {
    return SingleChildScrollView(
      padding: EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _SectionHeader(title: 'Project'),
          _InputCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _createProject == null
                      ? 'No project selected'
                      : _createProject['name'] ?? 'Project #${_createProject['id']}',
                  style: TextStyle(
                    color: AppTheme.textPrimary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                SizedBox(height: 12),
                ElevatedButton.icon(
                  onPressed: _submitting ? null : () => _openProjectPicker(forCreate: true),
                  icon: Icon(Icons.search),
                  label: Text('Choose project'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.primaryColorConst,
                    foregroundColor: Colors.white,
                    padding: EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  ),
                ),
              ],
            ),
          ),
          SizedBox(height: 20),
          _SectionHeader(title: 'Visit notes'),
          _InputCard(
            child: TextField(
              controller: _noteController,
              minLines: 4,
              maxLines: 8,
              enabled: !_submitting,
              decoration: InputDecoration(
                hintText: 'Add visit summary, observations, follow-ups…',
                border: InputBorder.none,
              ),
            ),
          ),
          SizedBox(height: 20),
          _SectionHeader(title: 'Mark as task'),
          _InputCard(
            child: SwitchListTile(
              contentPadding: EdgeInsets.zero,
              activeColor: AppTheme.primaryColorConst,
              title: Text(
                'This note requires action',
                style: TextStyle(color: AppTheme.textPrimary),
              ),
              subtitle: Text(
                'Flag the visit note as a task for quick follow-up.',
                style: TextStyle(color: AppTheme.textSecondary),
              ),
              value: _isTask,
              onChanged: _submitting
                  ? null
                  : (value) {
                      setState(() {
                        _isTask = value;
                      });
                    },
            ),
          ),
          SizedBox(height: 30),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: _submitting ? null : _submitReport,
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.primaryColorConst,
                padding: EdgeInsets.symmetric(vertical: 16),
                textStyle: TextStyle(fontWeight: FontWeight.bold),
              ),
              child: _submitting
                  ? SizedBox(
                      height: 18,
                      width: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                      ),
                    )
                  : Text('Create site visit report'),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildViewTab() {
    return Column(
      children: [
        Expanded(
          child: ListView(
            padding: EdgeInsets.all(20),
            children: [
              _SectionHeader(title: 'Filters'),
              _InputCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Project',
                      style: TextStyle(
                        color: AppTheme.textSecondary,
                        fontSize: 12,
                        letterSpacing: 0.5,
                      ),
                    ),
                    SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            _viewProject == null
                                ? 'All projects'
                                : _viewProject['name'] ?? 'Project #${_viewProject['id']}',
                            style: TextStyle(
                              color: AppTheme.textPrimary,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                        TextButton(
                          onPressed: _fetchingReports ? null : () => _openProjectPicker(forCreate: false),
                          child: Text('Change'),
                        ),
                        if (_viewProject != null)
                          IconButton(
                            icon: Icon(Icons.close, color: AppTheme.textSecondary),
                            onPressed: _fetchingReports
                                ? null
                                : () {
                                    setState(() {
                                      _viewProject = null;
                                    });
                                  },
                          ),
                      ],
                    ),
                    Divider(height: 24),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text(
                        'Only my reports',
                        style: TextStyle(color: AppTheme.textPrimary),
                      ),
                      value: _myReportsOnly,
                      onChanged: _fetchingReports
                          ? null
                          : (value) {
                              setState(() {
                                _myReportsOnly = value;
                                if (value) {
                                  _userIdFilterController.clear();
                                }
                              });
                            },
                    ),
                    if (!_myReportsOnly)
                      TextField(
                        controller: _userIdFilterController,
                        keyboardType: TextInputType.number,
                        decoration: InputDecoration(
                          labelText: 'User ID',
                          hintText: 'Filter by another user',
                        ),
                      ),
                  ],
                ),
              ),
              SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: _fetchingReports ? null : _fetchReports,
                  icon: Icon(Icons.search),
                  label: Text('Search reports'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.primaryColorConst,
                    padding: EdgeInsets.symmetric(vertical: 14),
                  ),
                ),
              ),
              SizedBox(height: 24),
              if (_fetchingReports)
                Center(
                  child: Padding(
                    padding: EdgeInsets.only(top: 40),
                    child: CircularProgressIndicator(
                      valueColor: AlwaysStoppedAnimation<Color>(AppTheme.primaryColorConst),
                    ),
                  ),
                )
              else if (_reportsError != null)
                _EmptyState(
                  icon: Icons.error_outline,
                  message: _reportsError!,
                )
              else if (_reports.isEmpty && _hasSearched)
                _EmptyState(
                  icon: Icons.description_outlined,
                  message: 'No site visit reports found for the selected filters.',
                )
              else if (_reports.isEmpty)
                _EmptyState(
                  icon: Icons.travel_explore,
                  message: 'Search to view site visit reports.',
                )
              else
                ..._reports.map((report) => _ReportTile(report: report)).toList(),
            ],
          ),
        ),
      ],
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final String title;

  const _SectionHeader({required this.title});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 4,
          height: 22,
          decoration: BoxDecoration(
            color: AppTheme.primaryColorConst,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        SizedBox(width: 12),
        Text(
          title,
          style: TextStyle(
            fontWeight: FontWeight.bold,
            fontSize: 16,
            color: AppTheme.textPrimary,
          ),
        ),
      ],
    );
  }
}

class _InputCard extends StatelessWidget {
  final Widget child;

  const _InputCard({required this.child});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      margin: EdgeInsets.only(top: 12),
      padding: EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.backgroundSecondary,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppTheme.primaryColorConst.withOpacity(0.08)),
      ),
      child: child,
    );
  }
}

class _EmptyState extends StatelessWidget {
  final IconData icon;
  final String message;

  const _EmptyState({required this.icon, required this.message});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: EdgeInsets.symmetric(vertical: 40, horizontal: 20),
      decoration: BoxDecoration(
        color: AppTheme.backgroundSecondary.withOpacity(0.5),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppTheme.primaryColorConst.withOpacity(0.05)),
      ),
      child: Column(
        children: [
          Icon(icon, size: 40, color: AppTheme.textSecondary),
          SizedBox(height: 12),
          Text(
            message,
            textAlign: TextAlign.center,
            style: TextStyle(color: AppTheme.textSecondary),
          ),
        ],
      ),
    );
  }
}

class _ReportTile extends StatelessWidget {
  final Map<String, dynamic> report;

  const _ReportTile({required this.report});

  String _formatDate(String? value) {
    if (value == null) return '--';
    try {
      final date = DateTime.parse(value).toLocal();
      return DateFormat('d MMM yyyy • h:mm a').format(date);
    } catch (_) {
      return value;
    }
  }

  @override
  Widget build(BuildContext context) {
    final project = report['project'];
    final createdBy = report['created_by'];

    String projectLabel;
    if (project != null && project is Map<String, dynamic>) {
      projectLabel = project['name']?.toString() ?? 'Project #${project['id']}';
    } else {
      projectLabel = 'Project #${report['project_id']}';
    }

    final dateLabel = _formatDate(report['created_at']?.toString());
    final note = report['note']?.toString() ?? '';
    final isTask = report['is_task'] == true || report['is_task'] == 1 || report['is_task'] == '1';

    return Container(
      margin: EdgeInsets.only(bottom: 16),
      padding: EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.backgroundSecondary,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppTheme.primaryColorConst.withOpacity(0.06)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  projectLabel,
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    color: AppTheme.textPrimary,
                  ),
                ),
              ),
              if (isTask)
                Container(
                  padding: EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.orange.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    'Task',
                    style: TextStyle(
                      color: Colors.orange,
                      fontWeight: FontWeight.w600,
                      fontSize: 12,
                    ),
                  ),
                ),
            ],
          ),
          SizedBox(height: 8),
          Text(
            note,
            style: TextStyle(color: AppTheme.textPrimary.withOpacity(0.9)),
          ),
          SizedBox(height: 16),
          Row(
            children: [
              Icon(Icons.person_outline, size: 16, color: AppTheme.textSecondary),
              SizedBox(width: 6),
              Expanded(
                child: Text(
                  createdBy != null
                      ? (createdBy['name']?.toString() ?? 'User #${createdBy['id']}')
                      : 'User #${report['created_by_user_id'] ?? '--'}',
                  style: TextStyle(color: AppTheme.textSecondary, fontSize: 12),
                ),
              ),
            ],
          ),
          SizedBox(height: 6),
          Row(
            children: [
              Icon(Icons.calendar_today_outlined, size: 16, color: AppTheme.textSecondary),
              SizedBox(width: 6),
              Text(
                dateLabel,
                style: TextStyle(color: AppTheme.textSecondary, fontSize: 12),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

