import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'app_theme.dart';
import 'user_picker.dart';
import 'services/data_provider.dart';
import 'widgets/dark_mode_toggle.dart';

class TasksLayout extends StatefulWidget {
  final List<dynamic> initialTasks;
  final VoidCallback? onTaskUpdated;
  final Future<List<dynamic>> Function()? loadTasksCallback;
  final int initialTabIndex; // 0 for Create, 1 for View
  
  const TasksLayout({Key? key, required this.initialTasks, this.onTaskUpdated, this.loadTasksCallback, this.initialTabIndex = 0}) : super(key: key);

  @override
  _TasksLayoutState createState() => _TasksLayoutState();
}

class _TasksLayoutState extends State<TasksLayout> with SingleTickerProviderStateMixin {
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this, initialIndex: widget.initialTabIndex);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.getBackgroundPrimary(context),
      appBar: AppBar(
        automaticallyImplyLeading: true,
        backgroundColor: AppTheme.getBackgroundSecondary(context),
        elevation: 0,
        title: Text(
          'Tasks',
          style: TextStyle(
            color: AppTheme.getTextPrimary(context),
            fontSize: 18,
            fontWeight: FontWeight.w600,
          ),
        ),
        actions: [
          DarkModeToggle(showLabel: false),
          SizedBox(width: 8),
        ],
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: AppTheme.getPrimaryColor(context),
          labelColor: AppTheme.getTextPrimary(context),
          unselectedLabelColor: AppTheme.getTextSecondary(context),
          tabs: const [
            Tab(text: 'Create'),
            Tab(text: 'View'),
          ],
        ),
      ),
      body: SafeArea(
        child: TasksScreen(
          tabController: _tabController,
          initialTasks: widget.initialTasks,
          onTaskUpdated: widget.onTaskUpdated,
          loadTasksCallback: widget.loadTasksCallback,
        ),
      ),
    );
  }
}

class TasksScreen extends StatefulWidget {
  final TabController? tabController;
  final List<dynamic> initialTasks;
  final VoidCallback? onTaskUpdated;
  final Future<List<dynamic>> Function()? loadTasksCallback;
  
  TasksScreen({this.tabController, required this.initialTasks, this.onTaskUpdated, this.loadTasksCallback});

  @override
  TasksScreenState createState() => TasksScreenState();
}

class TasksScreenState extends State<TasksScreen> {
  TabController? get _tabController => widget.tabController;
  final GlobalKey<_ViewTasksPageState> _viewTasksPageKey = GlobalKey<_ViewTasksPageState>();
  List<dynamic> _currentTasks = [];

  @override
  void initState() {
    super.initState();
    _currentTasks = List.from(widget.initialTasks);
  }

  @override
  void didUpdateWidget(TasksScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.initialTasks != oldWidget.initialTasks) {
      _currentTasks = List.from(widget.initialTasks);
      _viewTasksPageKey.currentState?.updateTasks(_currentTasks);
    }
  }

  Future<void> _refreshTasks() async {
    if (widget.loadTasksCallback != null) {
      final updatedTasks = await widget.loadTasksCallback!();
      if (mounted) {
        setState(() {
          _currentTasks = updatedTasks;
        });
        _viewTasksPageKey.currentState?.updateTasks(_currentTasks);
      }
    } else {
      widget.onTaskUpdated?.call();
      // Wait a bit and then update if we have a callback
      await Future.delayed(Duration(milliseconds: 500));
      if (widget.loadTasksCallback != null && mounted) {
        final updatedTasks = await widget.loadTasksCallback!();
        setState(() {
          _currentTasks = updatedTasks;
        });
        _viewTasksPageKey.currentState?.updateTasks(_currentTasks);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return TabBarView(
      controller: _tabController,
      children: [
        CreateTaskPage(
          onTaskCreated: () async {
            await _refreshTasks();
            // Switch to View tab after creating
            Future.delayed(Duration(milliseconds: 500), () {
              _tabController?.animateTo(1);
            });
          },
        ),
        ViewTasksPage(
          key: _viewTasksPageKey,
          initialTasks: _currentTasks,
          onTaskUpdated: _refreshTasks,
        ),
      ],
    );
  }
}

// Create Task Page
class CreateTaskPage extends StatefulWidget {
  final VoidCallback? onTaskCreated;
  
  const CreateTaskPage({Key? key, this.onTaskCreated}) : super(key: key);

  @override
  _CreateTaskPageState createState() => _CreateTaskPageState();
}

class _CreateTaskPageState extends State<CreateTaskPage> {
  final _formKey = GlobalKey<FormState>();
  final noteController = TextEditingController();
  final _searchController = TextEditingController();
  String selectedStatus = 'pending';
  bool isLoading = false;
  int? selectedProjectId;
  String? selectedProjectName;
  int? selectedUserId;
  String? selectedUserName;
  List<dynamic> _projects = [];
  List<dynamic> _filteredProjects = [];

  @override
  void initState() {
    super.initState();
    _loadProjects();
    _searchController.addListener(_filterProjects);
  }

  @override
  void dispose() {
    noteController.dispose();
    _searchController.removeListener(_filterProjects);
    _searchController.dispose();
    super.dispose();
  }

  void _filterProjects() {
    final query = _searchController.text.toLowerCase().trim();
    setState(() {
      if (query.isEmpty) {
        _filteredProjects = List<dynamic>.from(_projects);
      } else {
        _filteredProjects = _projects.where((project) {
          final name = project['name']?.toString().toLowerCase() ?? '';
          final id = project['id']?.toString() ?? '';
          final client = project['client_name']?.toString().toLowerCase() ?? '';
          return name.contains(query) || id.contains(query) || client.contains(query);
        }).toList();
      }
    });
  }

  Future<void> _loadProjects() async {
    try {
      await DataProvider().reloadData(force: false);
      if (mounted) {
        setState(() {
          _projects = List<dynamic>.from(DataProvider().projects);
          _filteredProjects = List<dynamic>.from(_projects);
        });
      }
    } catch (e) {
      print('[CreateTaskPage] Error loading projects: $e');
    }
  }

  Future<void> _createTask() async {
    if (selectedProjectId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Please select a project'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    if (noteController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Task note cannot be empty'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    setState(() {
      isLoading = true;
    });

    try {
      SharedPreferences prefs = await SharedPreferences.getInstance();
      String? userId = prefs.getString('userId') ?? prefs.getString('user_id');
      String? apiToken = prefs.getString('api_token');

      if (userId == null || apiToken == null) {
        throw Exception('Missing credentials. Please log in again.');
      }

      final assignedToInt = selectedUserId ?? int.tryParse(userId);
      if (assignedToInt == null) {
        throw Exception('Invalid user ID');
      }

      final uri = Uri.parse("https://office.buildahome.in/API/create_task");
      final response = await http.post(
        uri,
        body: {
          'user_id': userId,
          'project_id': selectedProjectId.toString(),
          'assigned_to': assignedToInt.toString(),
          'status': selectedStatus,
          'note': noteController.text.trim(),
          'api_token': apiToken,
        },
      ).timeout(const Duration(seconds: 20));

      if (response.statusCode == 200 || response.statusCode == 201) {
        final decoded = jsonDecode(response.body);
        if (decoded is Map && decoded['success'] == true) {
          if (mounted) {
            // Reset form
            setState(() {
              selectedProjectId = null;
              selectedProjectName = null;
              selectedUserId = null;
              selectedUserName = null;
              selectedStatus = 'pending';
              noteController.clear();
              isLoading = false;
            });
            
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Row(
                  children: [
                    Icon(Icons.check_circle, color: Colors.white),
                    SizedBox(width: 8),
                    Text('Task created successfully'),
                  ],
                ),
                backgroundColor: Colors.green,
                duration: Duration(seconds: 2),
              ),
            );
            widget.onTaskCreated?.call();
          }
        } else {
          throw Exception(decoded['message'] ?? 'Failed to create task');
        }
      } else {
        throw Exception('Unable to create task (code ${response.statusCode})');
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                Icon(Icons.error, color: Colors.white),
                SizedBox(width: 8),
                Expanded(
                  child: Text(e.toString().replaceAll('Exception: ', '')),
                ),
              ],
            ),
            backgroundColor: Colors.red,
            duration: Duration(seconds: 3),
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          isLoading = false;
        });
      }
    }
  }

  void _showProjectPicker() {
    _searchController.clear();
    
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (context) => Container(
        height: MediaQuery.of(context).size.height * 0.8,
        decoration: BoxDecoration(
          color: AppTheme.getBackgroundSecondary(context),
          borderRadius: BorderRadius.only(
            topLeft: Radius.circular(20),
            topRight: Radius.circular(20),
          ),
        ),
        child: StatefulBuilder(
          builder: (context, setModalState) {
            final query = _searchController.text.toLowerCase().trim();
            final filtered = query.isEmpty
                ? _projects
                : _projects.where((project) {
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
                          _searchController.clear();
                          Navigator.pop(context);
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
                    controller: _searchController,
                    style: TextStyle(color: AppTheme.getTextPrimary(context), fontSize: 14),
                    onChanged: (value) {
                      setModalState(() {});
                      _filterProjects();
                    },
                    decoration: InputDecoration(
                      hintText: 'Search projects by name, ID, or client...',
                      hintStyle: TextStyle(color: AppTheme.getTextSecondary(context)),
                      prefixIcon: Icon(Icons.search, color: AppTheme.getPrimaryColor(context)),
                      suffixIcon: _searchController.text.isNotEmpty
                          ? IconButton(
                              icon: Icon(Icons.clear, color: AppTheme.getTextSecondary(context), size: 20),
                              onPressed: () {
                                _searchController.clear();
                                setModalState(() {});
                                _filterProjects();
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
                  child: _projects.isEmpty
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
                                final isSelected = selectedProjectId?.toString() == projectId;

                                return Container(
                                  margin: EdgeInsets.only(bottom: 8),
                                  decoration: BoxDecoration(
                                    color: isSelected
                                        ? AppTheme.getPrimaryColor(context).withOpacity(0.1)
                                        : AppTheme.getBackgroundPrimary(context),
                                    borderRadius: BorderRadius.circular(10),
                                    border: Border.all(
                                      color: isSelected
                                          ? AppTheme.getPrimaryColor(context)
                                          : AppTheme.getPrimaryColor(context).withOpacity(0.2),
                                      width: isSelected ? 1.5 : 1,
                                    ),
                                  ),
                                  child: Material(
                                    color: Colors.transparent,
                                    child: InkWell(
                                      onTap: () {
                                        final parsedId = int.tryParse(projectId ?? '');
                                        print('[CreateTaskPage] Project selected: id=$projectId, parsed=$parsedId, name=$projectName');
                                        setState(() {
                                          selectedProjectId = parsedId;
                                          selectedProjectName = projectName;
                                        });
                                        _searchController.clear();
                                        Navigator.pop(context);
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
                                            if (isSelected)
                                              Icon(
                                                Icons.check_circle,
                                                color: AppTheme.getPrimaryColor(context),
                                                size: 20,
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
  }

  void _showUserPicker() async {
    print('[CreateTaskPage] _showUserPicker called');
    print('[CreateTaskPage] selectedProjectId: $selectedProjectId');
    print('[CreateTaskPage] selectedProjectName: $selectedProjectName');
    
    if (selectedProjectId == null) {
      print('[CreateTaskPage] ERROR: No project selected');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Please select a project first')),
      );
      return;
    }
    
    print('[CreateTaskPage] Opening UserPickerScreen with projectId: $selectedProjectId');
    final result = await UserPickerScreen.show(context, projectId: selectedProjectId);

    if (result != null && mounted) {
      print('[CreateTaskPage] User selected result: $result');
      
      setState(() {
        // Try different possible ID field names
        final userIdStr = result['id']?.toString() ?? 
                         result['user_id']?.toString() ?? 
                         '';
        selectedUserId = userIdStr.isNotEmpty ? int.tryParse(userIdStr) : null;
        
        // Try different possible name field names
        selectedUserName = result['user_name']?.toString() ?? 
                          result['name']?.toString() ?? 
                          result['username']?.toString();
        
        print('[CreateTaskPage] Set selectedUserId: $selectedUserId');
        print('[CreateTaskPage] Set selectedUserName: $selectedUserName');
      });
    } else {
      print('[CreateTaskPage] No user selected or widget not mounted');
    }
  }

  Widget _buildStatusDropdownForForm() {
    final statuses = [
      {'value': 'pending', 'label': 'Pending', 'color': Color(0xFFD97706), 'icon': Icons.pending},
      {'value': 'in_progress', 'label': 'In Progress', 'color': AppTheme.primaryColorConst, 'icon': Icons.work},
      {'value': 'completed', 'label': 'Completed', 'color': Color(0xFF10B981), 'icon': Icons.check_circle},
      {'value': 'cancelled', 'label': 'Cancelled', 'color': Color(0xFFEF4444), 'icon': Icons.cancel},
    ];

    final currentStatusData = statuses.firstWhere(
      (s) => s['value'] == selectedStatus,
      orElse: () => statuses[0],
    );
    final currentColor = currentStatusData['color'] as Color;
    final currentIcon = currentStatusData['icon'] as IconData;

    return Container(
      decoration: BoxDecoration(
        color: AppTheme.getBackgroundPrimaryLight(context),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: AppTheme.getPrimaryColor(context).withOpacity(0.2),
          width: 1,
        ),
      ),
      child: DropdownButtonFormField<String>(
        value: selectedStatus,
        decoration: InputDecoration(
          contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          border: InputBorder.none,
          enabledBorder: InputBorder.none,
          focusedBorder: InputBorder.none,
        ),
        icon: Icon(Icons.arrow_drop_down, color: AppTheme.getTextSecondary(context)),
        dropdownColor: AppTheme.getBackgroundPrimaryLight(context),
        style: TextStyle(
          color: AppTheme.getTextPrimary(context),
          fontSize: 14,
        ),
        items: statuses.map((statusData) {
          final status = statusData['value'] as String;
          final label = statusData['label'] as String;
          final color = statusData['color'] as Color;
          final icon = statusData['icon'] as IconData;
          
          return DropdownMenuItem<String>(
            value: status,
            child: Row(
              children: [
                Icon(icon, size: 16, color: color),
                SizedBox(width: 8),
                Text(
                  label,
                  style: TextStyle(
                    color: AppTheme.getTextPrimary(context),
                    fontSize: 14,
                  ),
                ),
              ],
            ),
          );
        }).toList(),
        onChanged: (String? newStatus) {
          if (newStatus != null) {
            setState(() {
              selectedStatus = newStatus;
            });
          }
        },
        selectedItemBuilder: (BuildContext context) {
          return statuses.map((statusData) {
            final label = statusData['label'] as String;
            return Row(
              children: [
                Icon(currentIcon, size: 16, color: currentColor),
                SizedBox(width: 8),
                Text(
                  label,
                  style: TextStyle(
                    color: AppTheme.getTextPrimary(context),
                    fontSize: 14,
                  ),
                ),
              ],
            );
          }).toList();
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Form(
      key: _formKey,
      child: ListView(
        padding: EdgeInsets.all(20),
        children: [
          // Project Picker
          Text(
            'Project *',
            style: TextStyle(
              color: AppTheme.getTextPrimary(context),
              fontSize: 14,
              fontWeight: FontWeight.w600,
            ),
          ),
          SizedBox(height: 8),
          InkWell(
            onTap: () => _showProjectPicker(),
            borderRadius: BorderRadius.circular(12),
            child: Container(
              padding: EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: AppTheme.getBackgroundPrimaryLight(context),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: selectedProjectId == null 
                      ? AppTheme.getPrimaryColor(context).withOpacity(0.3)
                      : AppTheme.getPrimaryColor(context).withOpacity(0.5),
                  width: selectedProjectId == null ? 1 : 1.5,
                ),
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.folder_special,
                    color: AppTheme.getPrimaryColor(context),
                    size: 20,
                  ),
                  SizedBox(width: 12),
                  Expanded(
                    child: selectedProjectId == null
                        ? Text(
                            'Select a project',
                            style: TextStyle(
                              color: AppTheme.getTextSecondary(context),
                              fontSize: 14,
                            ),
                          )
                        : Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                selectedProjectName ?? 'Project',
                                style: TextStyle(
                                  color: AppTheme.getTextPrimary(context),
                                  fontSize: 14,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              if (selectedProjectId != null)
                                Text(
                                  'ID: $selectedProjectId',
                                  style: TextStyle(
                                    color: AppTheme.getTextSecondary(context),
                                    fontSize: 11,
                                  ),
                                ),
                            ],
                          ),
                  ),
                  Icon(
                    Icons.arrow_forward_ios,
                    size: 16,
                    color: AppTheme.getTextSecondary(context),
                  ),
                ],
              ),
            ),
          ),
          if (selectedProjectId == null)
            Padding(
              padding: EdgeInsets.only(top: 4, left: 4),
              child: Text(
                'Please select a project',
                style: TextStyle(
                  color: Colors.red,
                  fontSize: 11,
                ),
              ),
            ),
          SizedBox(height: 20),
          
          // User Picker (Assign To)
          Text(
            'Assign To',
            style: TextStyle(
              color: AppTheme.getTextPrimary(context),
              fontSize: 14,
              fontWeight: FontWeight.w600,
            ),
          ),
          SizedBox(height: 8),
          InkWell(
            onTap: () => _showUserPicker(),
            borderRadius: BorderRadius.circular(12),
            child: Container(
              padding: EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: AppTheme.getBackgroundPrimaryLight(context),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: selectedUserId == null 
                      ? AppTheme.getPrimaryColor(context).withOpacity(0.3)
                      : AppTheme.getPrimaryColor(context).withOpacity(0.5),
                  width: selectedUserId == null ? 1 : 1.5,
                ),
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.person,
                    color: AppTheme.getPrimaryColor(context),
                    size: 20,
                  ),
                  SizedBox(width: 12),
                  Expanded(
                    child: selectedUserId == null
                        ? Text(
                            'Select a user (optional)',
                            style: TextStyle(
                              color: AppTheme.getTextSecondary(context),
                              fontSize: 14,
                            ),
                          )
                        : Text(
                            selectedUserName ?? 'User',
                            style: TextStyle(
                              color: AppTheme.getTextPrimary(context),
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                  ),
                  Icon(
                    Icons.arrow_forward_ios,
                    size: 16,
                    color: AppTheme.getTextSecondary(context),
                  ),
                ],
              ),
            ),
          ),
          SizedBox(height: 20),
          
          // Status Dropdown
          Text(
            'Status',
            style: TextStyle(
              color: AppTheme.getTextPrimary(context),
              fontSize: 14,
              fontWeight: FontWeight.w600,
            ),
          ),
          SizedBox(height: 8),
          _buildStatusDropdownForForm(),
          SizedBox(height: 20),
          
          // Note
          Text(
            'Note / Description *',
            style: TextStyle(
              color: AppTheme.getTextPrimary(context),
              fontSize: 14,
              fontWeight: FontWeight.w600,
            ),
          ),
          SizedBox(height: 8),
          TextFormField(
            controller: noteController,
            maxLines: 4,
            style: TextStyle(color: AppTheme.getTextPrimary(context)),
            validator: (value) {
              if (value == null || value.trim().isEmpty) {
                return 'Task note cannot be empty';
              }
              return null;
            },
            decoration: InputDecoration(
              filled: true,
              fillColor: AppTheme.getBackgroundPrimaryLight(context),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(color: AppTheme.getPrimaryColor(context).withOpacity(0.3)),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(color: AppTheme.getPrimaryColor(context).withOpacity(0.3)),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(color: AppTheme.getPrimaryColor(context), width: 2),
              ),
              prefixIcon: Padding(
                padding: EdgeInsets.only(bottom: 40),
                child: Icon(Icons.note, color: AppTheme.getPrimaryColor(context)),
              ),
              hintText: 'Enter task description...',
              hintStyle: TextStyle(color: AppTheme.getTextSecondary(context)),
            ),
          ),
          SizedBox(height: 30),
          
          // Submit Button
          Container(
            decoration: BoxDecoration(
              color: Color(0xFF10B981),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: isLoading ? null : _createTask,
                borderRadius: BorderRadius.circular(12),
                child: Padding(
                  padding: EdgeInsets.symmetric(vertical: 16),
                  child: Center(
                    child: isLoading
                        ? SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                            ),
                          )
                        : Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.check, color: Colors.white, size: 18),
                              SizedBox(width: 8),
                              Text(
                                'Create Task',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 16,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// View Tasks Page with Filters
class ViewTasksPage extends StatefulWidget {
  final List<dynamic> initialTasks;
  final VoidCallback? onTaskUpdated;
  
  const ViewTasksPage({Key? key, required this.initialTasks, this.onTaskUpdated}) : super(key: key);

  @override
  _ViewTasksPageState createState() => _ViewTasksPageState();
}

class _ViewTasksPageState extends State<ViewTasksPage> {
  List<dynamic> _allTasks = [];
  List<dynamic> _filteredTasks = [];
  bool _isLoading = false;
  String? _currentUserId;
  
  // Filter states
  String? _selectedProjectId;
  String? _selectedProjectName;
  bool _showAssignedToMeOnly = false;
  bool _showCreatedByMeOnly = false;
  
  // Accordion state - track which tasks have status change expanded
  Set<String> _expandedTaskIds = Set<String>();

  @override
  void initState() {
    super.initState();
    _allTasks = List.from(widget.initialTasks);
    _filteredTasks = List.from(_allTasks);
    _loadCurrentUserId();
  }

  @override
  void didUpdateWidget(ViewTasksPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.initialTasks != oldWidget.initialTasks) {
      _allTasks = List.from(widget.initialTasks);
      _applyFilters();
    }
  }

  Future<void> _loadCurrentUserId() async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    setState(() {
      _currentUserId = prefs.getString('userId') ?? prefs.getString('user_id');
    });
  }

  void refreshTasks() {
    widget.onTaskUpdated?.call();
  }

  void updateTasks(List<dynamic> newTasks) {
    setState(() {
      _allTasks = List.from(newTasks);
      _applyFilters();
    });
  }

  void _applyFilters() {
    setState(() {
      _filteredTasks = _allTasks.where((task) {
        // Filter by project
        if (_selectedProjectId != null) {
          final taskProjectId = task['project_id']?.toString() ?? '';
          if (taskProjectId != _selectedProjectId) {
            return false;
          }
        }
        
        // Filter by assigned to me
        if (_showAssignedToMeOnly && _currentUserId != null) {
          final assignedTo = task['assigned_to']?.toString() ?? '';
          if (assignedTo != _currentUserId) {
            return false;
          }
        }
        
        // Filter by created by me (check user_id field)
        if (_showCreatedByMeOnly && _currentUserId != null) {
          // Tasks might have user_id or created_by field
          final userId = task['user_id']?.toString() ?? task['created_by']?.toString() ?? '';
          if (userId != _currentUserId) {
            return false;
          }
        }
        
        return true;
      }).toList();
    });
  }

  void _showProjectFilter() async {
    await DataProvider().reloadData(force: false);
    final projects = List<dynamic>.from(DataProvider().projects);
    
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (context) => Container(
        height: MediaQuery.of(context).size.height * 0.6,
        decoration: BoxDecoration(
          color: AppTheme.getBackgroundSecondary(context),
          borderRadius: BorderRadius.only(
            topLeft: Radius.circular(20),
            topRight: Radius.circular(20),
          ),
        ),
        child: Column(
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
                      'Filter by Project',
                      style: TextStyle(
                        color: AppTheme.getTextPrimary(context),
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  IconButton(
                    icon: Icon(Icons.close, color: AppTheme.getTextSecondary(context)),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
            ),
            ListView.builder(
              padding: EdgeInsets.all(16),
              shrinkWrap: true,
              itemCount: projects.length + 1,
              itemBuilder: (context, index) {
                if (index == 0) {
                  final isSelected = _selectedProjectId == null;
                  return Container(
                    margin: EdgeInsets.only(bottom: 8),
                    decoration: BoxDecoration(
                      color: isSelected
                          ? AppTheme.getPrimaryColor(context).withOpacity(0.1)
                          : AppTheme.getBackgroundPrimary(context),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                        color: isSelected
                            ? AppTheme.getPrimaryColor(context)
                            : AppTheme.getPrimaryColor(context).withOpacity(0.2),
                        width: isSelected ? 1.5 : 1,
                      ),
                    ),
                    child: Material(
                      color: Colors.transparent,
                      child: InkWell(
                        onTap: () {
                          setState(() {
                            _selectedProjectId = null;
                            _selectedProjectName = null;
                          });
                          _applyFilters();
                          Navigator.pop(context);
                        },
                        borderRadius: BorderRadius.circular(10),
                        child: Padding(
                          padding: EdgeInsets.all(12),
                          child: Row(
                            children: [
                              Icon(Icons.clear_all, color: AppTheme.getPrimaryColor(context), size: 20),
                              SizedBox(width: 12),
                              Expanded(
                                child: Text(
                                  'All Projects',
                                  style: TextStyle(
                                    color: AppTheme.getTextPrimary(context),
                                    fontSize: 14,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                              if (isSelected)
                                Icon(Icons.check_circle, color: AppTheme.getPrimaryColor(context), size: 20),
                            ],
                          ),
                        ),
                      ),
                    ),
                  );
                }
                
                final project = projects[index - 1];
                final projectId = project['id']?.toString();
                final projectName = project['name']?.toString() ?? 'Unnamed Project';
                final isSelected = _selectedProjectId == projectId;
                
                return Container(
                  margin: EdgeInsets.only(bottom: 8),
                  decoration: BoxDecoration(
                    color: isSelected
                        ? AppTheme.getPrimaryColor(context).withOpacity(0.1)
                        : AppTheme.getBackgroundPrimary(context),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: isSelected
                          ? AppTheme.getPrimaryColor(context)
                          : AppTheme.getPrimaryColor(context).withOpacity(0.2),
                      width: isSelected ? 1.5 : 1,
                    ),
                  ),
                  child: Material(
                    color: Colors.transparent,
                    child: InkWell(
                      onTap: () {
                        setState(() {
                          _selectedProjectId = projectId;
                          _selectedProjectName = projectName;
                        });
                        _applyFilters();
                        Navigator.pop(context);
                      },
                      borderRadius: BorderRadius.circular(10),
                      child: Padding(
                        padding: EdgeInsets.all(12),
                        child: Row(
                          children: [
                            Icon(Icons.folder_special, color: AppTheme.getPrimaryColor(context), size: 20),
                            SizedBox(width: 12),
                            Expanded(
                              child: Text(
                                projectName,
                                style: TextStyle(
                                  color: AppTheme.getTextPrimary(context),
                                  fontSize: 14,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                            if (isSelected)
                              Icon(Icons.check_circle, color: AppTheme.getPrimaryColor(context), size: 20),
                          ],
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // Filter Section
        Container(
          margin: EdgeInsets.only(top: 12),
          padding: EdgeInsets.all(16),
          width: MediaQuery.of(context).size.width * 0.9,
          decoration: BoxDecoration(
            color: AppTheme.getBackgroundSecondary(context),
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
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Filters',
                style: TextStyle(
                  color: AppTheme.getTextPrimary(context),
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
              ),
              SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  // Project Filter
                  InkWell(
                    onTap: _showProjectFilter,
                    borderRadius: BorderRadius.circular(20),
                    child: Container(
                      padding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      decoration: BoxDecoration(
                        color: _selectedProjectId != null
                            ? AppTheme.getPrimaryColor(context).withOpacity(0.2)
                            : AppTheme.getBackgroundPrimary(context),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(
                          color: _selectedProjectId != null
                              ? AppTheme.getPrimaryColor(context)
                              : AppTheme.getPrimaryColor(context).withOpacity(0.3),
                          width: 1,
                        ),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.folder_special,
                            size: 14,
                            color: _selectedProjectId != null
                                ? AppTheme.getPrimaryColor(context)
                                : AppTheme.getTextSecondary(context),
                          ),
                          SizedBox(width: 6),
                          Text(
                            _selectedProjectName ?? 'All Projects',
                            style: TextStyle(
                              color: _selectedProjectId != null
                                  ? AppTheme.getPrimaryColor(context)
                                  : AppTheme.getTextSecondary(context),
                              fontSize: 12,
                              fontWeight: _selectedProjectId != null
                                  ? FontWeight.w600
                                  : FontWeight.w500,
                            ),
                          ),
                          if (_selectedProjectId != null) ...[
                            SizedBox(width: 4),
                            InkWell(
                              onTap: () {
                                setState(() {
                                  _selectedProjectId = null;
                                  _selectedProjectName = null;
                                });
                                _applyFilters();
                              },
                              child: Icon(
                                Icons.close,
                                size: 14,
                                color: AppTheme.getPrimaryColor(context),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                  // Assigned to Me Filter
                  InkWell(
                    onTap: () {
                      setState(() {
                        _showAssignedToMeOnly = !_showAssignedToMeOnly;
                      });
                      _applyFilters();
                    },
                    borderRadius: BorderRadius.circular(20),
                    child: Container(
                      padding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      decoration: BoxDecoration(
                        color: _showAssignedToMeOnly
                            ? AppTheme.getPrimaryColor(context).withOpacity(0.2)
                            : AppTheme.getBackgroundPrimary(context),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(
                          color: _showAssignedToMeOnly
                              ? AppTheme.getPrimaryColor(context)
                              : AppTheme.getPrimaryColor(context).withOpacity(0.3),
                          width: 1,
                        ),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.person,
                            size: 14,
                            color: _showAssignedToMeOnly
                                ? AppTheme.getPrimaryColor(context)
                                : AppTheme.getTextSecondary(context),
                          ),
                          SizedBox(width: 6),
                          Text(
                            'Assigned to Me',
                            style: TextStyle(
                              color: _showAssignedToMeOnly
                                  ? AppTheme.getPrimaryColor(context)
                                  : AppTheme.getTextSecondary(context),
                              fontSize: 12,
                              fontWeight: _showAssignedToMeOnly
                                  ? FontWeight.w600
                                  : FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  // Created by Me Filter
                  InkWell(
                    onTap: () {
                      setState(() {
                        _showCreatedByMeOnly = !_showCreatedByMeOnly;
                      });
                      _applyFilters();
                    },
                    borderRadius: BorderRadius.circular(20),
                    child: Container(
                      padding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      decoration: BoxDecoration(
                        color: _showCreatedByMeOnly
                            ? AppTheme.getPrimaryColor(context).withOpacity(0.2)
                            : AppTheme.getBackgroundPrimary(context),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(
                          color: _showCreatedByMeOnly
                              ? AppTheme.getPrimaryColor(context)
                              : AppTheme.getPrimaryColor(context).withOpacity(0.3),
                          width: 1,
                        ),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.create,
                            size: 14,
                            color: _showCreatedByMeOnly
                                ? AppTheme.getPrimaryColor(context)
                                : AppTheme.getTextSecondary(context),
                          ),
                          SizedBox(width: 6),
                          Text(
                            'Created by Me',
                            style: TextStyle(
                              color: _showCreatedByMeOnly
                                  ? AppTheme.getPrimaryColor(context)
                                  : AppTheme.getTextSecondary(context),
                              fontSize: 12,
                              fontWeight: _showCreatedByMeOnly
                                  ? FontWeight.w600
                                  : FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        // Tasks List
        Expanded(
          child: _filteredTasks.isEmpty
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.task_alt, size: 56, color: AppTheme.getTextSecondary(context)),
                      SizedBox(height: 16),
                      Text(
                        'No tasks found',
                        style: TextStyle(
                          color: AppTheme.getTextPrimary(context),
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      SizedBox(height: 8),
                      Text(
                        'Try adjusting your filters',
                        style: TextStyle(
                          color: AppTheme.getTextSecondary(context),
                          fontSize: 14,
                        ),
                      ),
                    ],
                  ),
                )
              : RefreshIndicator(
                  onRefresh: () async {
                    if (widget.onTaskUpdated != null) {
                      widget.onTaskUpdated!();
                      // Wait a bit for tasks to reload
                      await Future.delayed(Duration(milliseconds: 800));
                      // Tasks will be updated via didUpdateWidget
                    }
                  },
                  color: AppTheme.getPrimaryColor(context),
                  child: ListView(
                    padding: EdgeInsets.all(20),
                    children: _filteredTasks.map((task) {
                      if (task is Map<String, dynamic>) {
                        return _buildTaskCard(task);
                      }
                      return SizedBox.shrink();
                    }).toList(),
                  ),
                ),
        ),
      ],
    );
  }

  String _formatDateTime(String dateTimeStr) {
    try {
      final dateTime = DateTime.parse(dateTimeStr);
      final formatter = DateFormat('MMM d, y • h:mm a');
      return formatter.format(dateTime);
    } catch (e) {
      return dateTimeStr;
    }
  }

  Color _getStatusColor(String status) {
    switch (status.toLowerCase()) {
      case 'completed':
        return Color(0xFF10B981);
      case 'in_progress':
        return AppTheme.primaryColorConst;
      case 'cancelled':
        return Color(0xFFEF4444);
      default:
        return Color(0xFFD97706);
    }
  }

  IconData _getStatusIcon(String status) {
    switch (status.toLowerCase()) {
      case 'completed':
        return Icons.check_circle;
      case 'in_progress':
        return Icons.work;
      case 'cancelled':
        return Icons.cancel;
      default:
        return Icons.pending;
    }
  }

  bool _isUpdating = false;
  bool _isDeleting = false;

  Future<void> _deleteTask(int taskId) async {
    if (_isDeleting) return;
    
    // Show confirmation dialog
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppTheme.getBackgroundSecondary(context),
        title: Text('Delete Task', style: TextStyle(color: AppTheme.getTextPrimary(context))),
        content: Text('Are you sure you want to delete this task? This action cannot be undone.', style: TextStyle(color: AppTheme.getTextPrimary(context))),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text('Cancel', style: TextStyle(color: AppTheme.getTextPrimary(context))),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: Text('Delete'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    setState(() {
      _isDeleting = true;
    });

    try {
      SharedPreferences prefs = await SharedPreferences.getInstance();
      String? apiToken = prefs.getString('api_token');

      if (apiToken == null) {
        throw Exception('Missing credentials. Please log in again.');
      }

      final uri = Uri.parse("https://office.buildahome.in/API/delete_task");
      final response = await http.post(
        uri,
        body: {
          'task_id': taskId.toString(),
          'api_token': apiToken,
        },
      ).timeout(const Duration(seconds: 20));

      if (response.statusCode == 200) {
        final decoded = jsonDecode(response.body);
        if (decoded is Map && decoded['success'] == true) {
          setState(() {
            _allTasks.removeWhere((t) => t['id']?.toString() == taskId.toString());
            _isDeleting = false;
          });
          _applyFilters();

          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Row(
                  children: [
                    Icon(Icons.check_circle, color: Colors.white),
                    SizedBox(width: 8),
                    Text('Task deleted successfully'),
                  ],
                ),
                backgroundColor: Colors.green,
                duration: Duration(seconds: 2),
              ),
            );
            widget.onTaskUpdated?.call();
          }
        } else {
          throw Exception(decoded['message'] ?? 'Failed to delete task');
        }
      } else {
        throw Exception('Unable to delete task (code ${response.statusCode})');
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isDeleting = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: [
              Icon(Icons.error, color: Colors.white),
              SizedBox(width: 8),
              Expanded(
                child: Text(e.toString().replaceAll('Exception: ', '')),
              ),
            ],
          ),
          backgroundColor: Colors.red,
          duration: Duration(seconds: 3),
        ),
      );
    }
  }

  Future<void> _updateTaskStatus(int taskId, String newStatus) async {
    if (_isUpdating) return;
    
    setState(() {
      _isUpdating = true;
    });

    try {
      SharedPreferences prefs = await SharedPreferences.getInstance();
      String? apiToken = prefs.getString('api_token');

      if (apiToken == null) {
        throw Exception('Missing credentials. Please log in again.');
      }

      final uri = Uri.parse("https://office.buildahome.in/API/update_task_status");
      final response = await http.post(
        uri,
        body: {
          'task_id': taskId.toString(),
          'status': newStatus,
          'api_token': apiToken,
        },
      ).timeout(const Duration(seconds: 20));

      if (response.statusCode == 200) {
        final decoded = jsonDecode(response.body);
        if (decoded is Map && decoded['success'] == true) {
          // Update local task status
          setState(() {
            final taskIndex = _allTasks.indexWhere((t) => t['id']?.toString() == taskId.toString());
            if (taskIndex != -1) {
              _allTasks[taskIndex] = {..._allTasks[taskIndex], 'status': newStatus};
            }
            _isUpdating = false;
          });
          _applyFilters();

          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Row(
                  children: [
                    Icon(Icons.check_circle, color: Colors.white),
                    SizedBox(width: 8),
                    Text('Task status updated successfully'),
                  ],
                ),
                backgroundColor: Colors.green,
                duration: Duration(seconds: 2),
              ),
            );
            // Don't call onTaskUpdated here to avoid removing the task
            // The UI is already updated with the new status
          }
        } else {
          throw Exception(decoded['message'] ?? 'Failed to update task status');
        }
      } else {
        throw Exception('Unable to update task status (code ${response.statusCode})');
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isUpdating = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: [
              Icon(Icons.error, color: Colors.white),
              SizedBox(width: 8),
              Expanded(
                child: Text(e.toString().replaceAll('Exception: ', '')),
              ),
            ],
          ),
          backgroundColor: Colors.red,
          duration: Duration(seconds: 3),
        ),
      );
    }
  }

  Widget _buildStatusDropdown(String taskIdStr, String currentStatus) {
    final taskId = int.tryParse(taskIdStr) ?? 0;
    final statuses = [
      {'value': 'pending', 'label': 'Pending', 'color': Color(0xFFD97706), 'icon': Icons.pending}, // Darker amber/yellow
      {'value': 'in_progress', 'label': 'In Progress', 'color': Color(0xFF2196F3), 'icon': Icons.work}, // Blue
      {'value': 'completed', 'label': 'Completed', 'color': Color(0xFF10B981), 'icon': Icons.check_circle}, // Green
      {'value': 'cancelled', 'label': 'Cancelled', 'color': Color(0xFFEF4444), 'icon': Icons.cancel}, // Red
    ];

    final currentStatusData = statuses.firstWhere(
      (s) => s['value'] == currentStatus,
      orElse: () => statuses[0],
    );
    final currentColor = currentStatusData['color'] as Color;
    final currentIcon = currentStatusData['icon'] as IconData;

    return Container(
      decoration: BoxDecoration(
        color: AppTheme.getBackgroundPrimaryLight(context),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: AppTheme.getPrimaryColor(context).withOpacity(0.2),
          width: 1,
        ),
      ),
      child: DropdownButtonFormField<String>(
        value: currentStatus,
        decoration: InputDecoration(
          contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          border: InputBorder.none,
          enabledBorder: InputBorder.none,
          focusedBorder: InputBorder.none,
        ),
        icon: Icon(Icons.arrow_drop_down, color: AppTheme.getTextSecondary(context)),
        dropdownColor: AppTheme.getBackgroundPrimaryLight(context),
        style: TextStyle(
          color: AppTheme.getTextPrimary(context),
          fontSize: 14,
        ),
        items: statuses.map((statusData) {
          final status = statusData['value'] as String;
          final label = statusData['label'] as String;
          final color = statusData['color'] as Color;
          final icon = statusData['icon'] as IconData;
          
          return DropdownMenuItem<String>(
            value: status,
            child: Row(
              children: [
                Icon(icon, size: 16, color: color),
                SizedBox(width: 8),
                Text(
                  label,
                  style: TextStyle(
                    color: AppTheme.getTextPrimary(context),
                    fontSize: 14,
                  ),
                ),
              ],
            ),
          );
        }).toList(),
        onChanged: _isUpdating ? null : (String? newStatus) {
          if (newStatus != null && newStatus != currentStatus) {
            _updateTaskStatus(taskId, newStatus);
          }
        },
        selectedItemBuilder: (BuildContext context) {
          return statuses.map((statusData) {
            final label = statusData['label'] as String;
            return Row(
              children: [
                Icon(currentIcon, size: 16, color: currentColor),
                SizedBox(width: 8),
                Text(
                  label,
                  style: TextStyle(
                    color: AppTheme.getTextPrimary(context),
                    fontSize: 14,
                  ),
                ),
              ],
            );
          }).toList();
        },
      ),
    );
  }

  Widget _buildTaskCard(Map<String, dynamic> task) {
    final taskId = task['id']?.toString() ?? '';
    final taskUserId = task['user_id']?.toString() ?? '';
    final projectName = task['project_name']?.toString() ?? '';
    final assignedToName = task['assigned_to_name']?.toString() ?? '';
    final userName = task['user_name']?.toString() ?? '';
    final status = task['status']?.toString() ?? 'pending';
    final note = task['note']?.toString() ?? '';
    final createdAt = task['created_at']?.toString() ?? '';
    final statusColor = _getStatusColor(status);
    final statusIcon = _getStatusIcon(status);
    final isCreatedByMe = _currentUserId != null && taskUserId == _currentUserId;
    final isExpanded = _expandedTaskIds.contains(taskId);

    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0.0, end: 1.0),
      duration: Duration(milliseconds: 300),
      curve: Curves.easeOut,
      builder: (context, value, child) {
        return Opacity(
          opacity: value,
          child: Transform.translate(
            offset: Offset(0, 20 * (1 - value)),
            child: Container(
              margin: EdgeInsets.only(bottom: 16),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    AppTheme.getBackgroundSecondary(context),
                    AppTheme.getBackgroundPrimary(context),
                  ],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: statusColor.withOpacity(0.3),
                  width: 1.5,
                ),
                boxShadow: [
                  BoxShadow(
                    color: statusColor.withOpacity(0.15),
                    blurRadius: 8,
                    offset: Offset(0, 4),
                  ),
                  BoxShadow(
                    color: AppTheme.getPrimaryColor(context).withOpacity(0.1),
                    blurRadius: 4,
                    offset: Offset(0, 2),
                  ),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Header with status icon in box
                  Container(
                    padding: EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [
                          statusColor.withOpacity(0.1),
                          statusColor.withOpacity(0.05),
                        ],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      borderRadius: BorderRadius.only(
                        topLeft: Radius.circular(16),
                        topRight: Radius.circular(16),
                      ),
                    ),
                    child: Row(
                      children: [
                        Container(
                          width: 56,
                          height: 56,
                          decoration: BoxDecoration(
                            color: statusColor.withOpacity(0.2),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: statusColor.withOpacity(0.4),
                              width: 2,
                            ),
                            boxShadow: [
                              BoxShadow(
                                color: statusColor.withOpacity(0.2),
                                blurRadius: 8,
                                offset: Offset(0, 2),
                              ),
                            ],
                          ),
                          child: Icon(
                            statusIcon,
                            color: statusColor,
                            size: 28,
                          ),
                        ),
                        SizedBox(width: 16),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Task #$taskId',
                                style: TextStyle(
                                  color: AppTheme.getTextPrimary(context),
                                  fontSize: 16,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              SizedBox(height: 4),
                              Container(
                                padding: EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                decoration: BoxDecoration(
                                  color: statusColor.withOpacity(0.2),
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(
                                    color: statusColor.withOpacity(0.4),
                                    width: 1,
                                  ),
                                ),
                                child: Text(
                                  status.toUpperCase(),
                                  style: TextStyle(
                                    color: statusColor,
                                    fontSize: 11,
                                    fontWeight: FontWeight.w700,
                                    letterSpacing: 0.5,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                        // Dropdown menu
                        PopupMenuButton<String>(
                          icon: Icon(Icons.more_vert, color: AppTheme.getTextSecondary(context)),
                          onSelected: (value) {
                            if (value == 'delete') {
                              _deleteTask(int.tryParse(taskId) ?? 0);
                            } else if (value == 'change_status') {
                              setState(() {
                                if (_expandedTaskIds.contains(taskId)) {
                                  _expandedTaskIds.remove(taskId);
                                } else {
                                  _expandedTaskIds.add(taskId);
                                }
                              });
                            }
                          },
                          itemBuilder: (context) => [
                            PopupMenuItem(
                              value: 'change_status',
                              child: Row(
                                children: [
                                  Icon(Icons.edit, size: 18, color: AppTheme.getTextPrimary(context)),
                                  SizedBox(width: 8),
                                  Text('Change Status', style: TextStyle(color: AppTheme.getTextPrimary(context))),
                                ],
                              ),
                            ),
                            if (isCreatedByMe)
                              PopupMenuItem(
                                value: 'delete',
                                child: Row(
                                  children: [
                                    Icon(Icons.delete, size: 18, color: Colors.red),
                                    SizedBox(width: 8),
                                    Text('Delete Task', style: TextStyle(color: Colors.red)),
                                  ],
                                ),
                              ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  
                  // Note section
                  if (note.isNotEmpty) ...[
                    Padding(
                      padding: EdgeInsets.all(16),
                      child: Container(
                        padding: EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: AppTheme.getBackgroundPrimary(context),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: AppTheme.getPrimaryColor(context).withOpacity(0.2),
                            width: 1,
                          ),
                        ),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Container(
                              padding: EdgeInsets.all(8),
                              decoration: BoxDecoration(
                                color: AppTheme.getPrimaryColor(context).withOpacity(0.15),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Icon(
                                Icons.note_alt,
                                color: AppTheme.getPrimaryColor(context),
                                size: 20,
                              ),
                            ),
                            SizedBox(width: 12),
                            Expanded(
                              child: Text(
                                note,
                                style: TextStyle(
                                  color: AppTheme.getTextPrimary(context),
                                  fontSize: 14,
                                  fontWeight: FontWeight.w600,
                                  height: 1.4,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                  
                  // Task info section
                  if (projectName.isNotEmpty || assignedToName.isNotEmpty || userName.isNotEmpty || createdAt.isNotEmpty) ...[
                    Padding(
                      padding: EdgeInsets.symmetric(horizontal: 16),
                      child: Container(
                        padding: EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: AppTheme.getBackgroundPrimary(context).withOpacity(0.5),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Wrap(
                          spacing: 16,
                          runSpacing: 12,
                          children: [
                            if (projectName.isNotEmpty)
                              Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Container(
                                    padding: EdgeInsets.all(6),
                                    decoration: BoxDecoration(
                                      color: AppTheme.getPrimaryColor(context).withOpacity(0.15),
                                      borderRadius: BorderRadius.circular(6),
                                    ),
                                    child: Icon(Icons.folder_special, size: 14, color: AppTheme.getPrimaryColor(context)),
                                  ),
                                  SizedBox(width: 8),
                                  Text(
                                    projectName,
                                    style: TextStyle(
                                      color: AppTheme.getTextPrimary(context),
                                      fontSize: 13,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ],
                              ),
                            if (assignedToName.isNotEmpty)
                              Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Container(
                                    padding: EdgeInsets.all(6),
                                    decoration: BoxDecoration(
                                      color: AppTheme.getPrimaryColor(context).withOpacity(0.15),
                                      borderRadius: BorderRadius.circular(6),
                                    ),
                                    child: Icon(Icons.person, size: 14, color: AppTheme.getPrimaryColor(context)),
                                  ),
                                  SizedBox(width: 8),
                                  Text(
                                    assignedToName,
                                    style: TextStyle(
                                      color: AppTheme.getTextPrimary(context),
                                      fontSize: 13,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ],
                              ),
                            if (userName.isNotEmpty)
                              Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Container(
                                    padding: EdgeInsets.all(6),
                                    decoration: BoxDecoration(
                                      color: AppTheme.getPrimaryColor(context).withOpacity(0.15),
                                      borderRadius: BorderRadius.circular(6),
                                    ),
                                    child: Icon(Icons.account_circle, size: 14, color: AppTheme.getPrimaryColor(context)),
                                  ),
                                  SizedBox(width: 8),
                                  Text(
                                    'Created by: $userName',
                                    style: TextStyle(
                                      color: AppTheme.getTextSecondary(context),
                                      fontSize: 12,
                                    ),
                                  ),
                                ],
                              ),
                            if (createdAt.isNotEmpty)
                              Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Container(
                                    padding: EdgeInsets.all(6),
                                    decoration: BoxDecoration(
                                      color: AppTheme.getPrimaryColor(context).withOpacity(0.15),
                                      borderRadius: BorderRadius.circular(6),
                                    ),
                                    child: Icon(Icons.access_time, size: 14, color: AppTheme.getPrimaryColor(context)),
                                  ),
                                  SizedBox(width: 8),
                                  Text(
                                    _formatDateTime(createdAt),
                                    style: TextStyle(
                                      color: AppTheme.getTextSecondary(context),
                                      fontSize: 12,
                                    ),
                                  ),
                                ],
                              ),
                          ],
                        ),
                      ),
                    ),
                    SizedBox(height: 12),
                  ],
                  
                  // Status change section (Accordion)
                  Container(
                    decoration: BoxDecoration(
                      color: AppTheme.getBackgroundPrimary(context),
                      borderRadius: BorderRadius.only(
                        bottomLeft: Radius.circular(16),
                        bottomRight: Radius.circular(16),
                      ),
                      border: Border(
                        top: BorderSide(
                          color: AppTheme.getPrimaryColor(context).withOpacity(0.1),
                          width: 1,
                        ),
                      ),
                    ),
                    child: Column(
                      children: [
                        // Accordion header
                        InkWell(
                          onTap: () {
                            setState(() {
                              if (_expandedTaskIds.contains(taskId)) {
                                _expandedTaskIds.remove(taskId);
                              } else {
                                _expandedTaskIds.add(taskId);
                              }
                            });
                          },
                          child: Container(
                            padding: EdgeInsets.all(16),
                            child: Row(
                              children: [
                                Icon(Icons.edit, size: 16, color: AppTheme.getPrimaryColor(context)),
                                SizedBox(width: 8),
                                Text(
                                  'Change Status',
                                  style: TextStyle(
                                    color: AppTheme.getTextPrimary(context),
                                    fontSize: 14,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                Spacer(),
                                Icon(
                                  isExpanded ? Icons.expand_less : Icons.expand_more,
                                  color: AppTheme.getTextSecondary(context),
                                ),
                              ],
                            ),
                          ),
                        ),
                        // Accordion content
                        if (isExpanded)
                          Container(
                            padding: EdgeInsets.fromLTRB(16, 0, 16, 16),
                            child: _buildStatusDropdown(taskId, status),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

