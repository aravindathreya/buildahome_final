import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:intl/intl.dart';
import 'dart:convert';
import 'package:file_picker/file_picker.dart';
import 'package:image_picker/image_picker.dart';
import 'ShowAlert.dart';
import 'app_theme.dart';
import 'user_picker.dart';
import 'services/data_provider.dart';
import 'services/rbac_service.dart';
import 'widgets/dark_mode_toggle.dart';
import 'widgets/searchable_select.dart';
import 'widgets/full_screen_message.dart';
import 'widgets/full_screen_progress.dart';
import 'package:provider/provider.dart';
import 'providers/theme_provider.dart';

class InspectionRequestLayout extends StatefulWidget {
  final String? fixedProjectId;
  final bool projectFixed;
  
  const InspectionRequestLayout({
    Key? key,
    this.fixedProjectId,
    this.projectFixed = false,
  }) : super(key: key);

  @override
  _InspectionRequestLayoutState createState() => _InspectionRequestLayoutState();
}

class _InspectionRequestLayoutState extends State<InspectionRequestLayout> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  bool _canCreate = false;
  bool _canView = false;
  bool _isLoadingPermissions = true;
  String? _userRole;

  @override
  void initState() {
    super.initState();
    _loadPermissions();
    _loadUserRole();
  }

  Future<void> _loadUserRole() async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    setState(() {
      _userRole = prefs.getString('role');
    });
  }

  Future<void> _loadPermissions() async {
    final rbac = RBACService();
    final canCreate = await rbac.canUpload(RBACService.inspectionRequest);
    final canView = await rbac.canView(RBACService.inspectionRequest);
    setState(() {
      _canCreate = canCreate;
      _canView = canView;
      _isLoadingPermissions = false;
      // Initialize tab controller based on permissions
      // Show Create tab if user can create, View tab if user can view
      final tabCount = (canCreate ? 1 : 0) + (canView ? 1 : 0);
      _tabController = TabController(length: tabCount, vsync: this, initialIndex: 0);
    });
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Hide inspection requests from clients
    if (_userRole != null && _userRole!.toLowerCase() == 'client') {
      return Scaffold(
        backgroundColor: AppTheme.getBackgroundPrimary(context),
        appBar: AppBar(
          automaticallyImplyLeading: true,
          backgroundColor: AppTheme.getBackgroundSecondary(context),
          elevation: 0,
          title: Text(
            'Inspection Requests',
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
        ),
        body: Center(
          child: Padding(
            padding: EdgeInsets.all(40),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  Icons.fact_check_outlined,
                  size: 64,
                  color: AppTheme.getTextSecondary(context),
                ),
                SizedBox(height: 16),
                Text(
                  'Inspection Requests',
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: AppTheme.getTextPrimary(context),
                  ),
                ),
                SizedBox(height: 8),
                Text(
                  'This feature is not available for clients.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 14,
                    color: AppTheme.getTextSecondary(context),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    if (_isLoadingPermissions) {
      return Scaffold(
        backgroundColor: Theme.of(context).scaffoldBackgroundColor,
        body: Center(
          child: CircularProgressIndicator(
            valueColor: AlwaysStoppedAnimation<Color>(AppTheme.getPrimaryColor(context)),
          ),
        ),
      );
    }

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        automaticallyImplyLeading: true,
        backgroundColor: Theme.of(context).colorScheme.surface,
        elevation: 0,
        title: Text(
          'Inspection Requests',
          style: TextStyle(
            color: AppTheme.getTextPrimary(context),
            fontSize: 18,
            fontWeight: FontWeight.w600,
          ),
        ),
        bottom: (_canCreate || _canView)
            ? TabBar(
                controller: _tabController,
                indicatorColor: AppTheme.getPrimaryColor(context),
                labelColor: AppTheme.getTextPrimary(context),
                unselectedLabelColor: AppTheme.getTextSecondary(context),
                tabs: [
                  if (_canCreate) const Tab(text: 'Create'),
                  if (_canView) const Tab(text: 'View'),
                ],
              )
            : null,
      ),
      body: SafeArea(
        child: InspectionRequestScreen(
          tabController: _tabController,
          canCreate: _canCreate,
          canView: _canView,
          fixedProjectId: widget.fixedProjectId,
          projectFixed: widget.projectFixed,
        ),
      ),
    );
  }
}

class InspectionRequestScreen extends StatefulWidget {
  final TabController? tabController;
  final bool canCreate;
  final bool canView;
  final String? fixedProjectId;
  final bool projectFixed;
  
  InspectionRequestScreen({
    this.tabController, 
    this.canCreate = false, 
    this.canView = false,
    this.fixedProjectId,
    this.projectFixed = false,
  });

  @override
  InspectionRequestScreenState createState() => InspectionRequestScreenState();
}

class InspectionRequestScreenState extends State<InspectionRequestScreen> {
  TabController? get _tabController => widget.tabController;
  final GlobalKey<_ViewInspectionRequestsPageState> _viewPageKey = GlobalKey<_ViewInspectionRequestsPageState>();

  Future<void> _refreshRequests() async {
    _viewPageKey.currentState?.refreshRequests();
  }

  @override
  Widget build(BuildContext context) {
    // Build list of tabs based on permissions
    List<Widget> tabs = [];
    
    // Determine View tab index before building tabs
    int viewTabIndex = widget.canCreate ? 1 : 0;
    
    if (widget.canCreate) {
      tabs.add(
        CreateInspectionRequestPage(
          fixedProjectId: widget.fixedProjectId,
          projectFixed: widget.projectFixed,
          onRequestCreated: () async {
            await _refreshRequests();
            // Switch to View tab after creating if user can view
            if (widget.canView && _tabController != null) {
              Future.delayed(Duration(milliseconds: 500), () {
                _tabController?.animateTo(viewTabIndex);
              });
            }
          },
        ),
      );
    }
    
    if (widget.canView) {
      tabs.add(
        ViewInspectionRequestsPage(
          key: _viewPageKey,
        ),
      );
    }

    // If no tabs, show empty state
    if (tabs.isEmpty) {
      return Center(
        child: Padding(
          padding: EdgeInsets.all(40),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.fact_check_outlined,
                size: 64,
                color: AppTheme.textSecondary,
              ),
              SizedBox(height: 16),
              Text(
                'No Access',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: AppTheme.textPrimary,
                ),
              ),
              SizedBox(height: 8),
              Text(
                'You do not have permission to access inspection requests.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 14,
                  color: AppTheme.textSecondary,
                ),
              ),
            ],
          ),
        ),
      );
    }

    // If only one tab, show it directly without TabBarView
    if (tabs.length == 1) {
      return tabs[0];
    }

    return TabBarView(
      controller: _tabController,
      children: tabs,
    );
  }
}

// Create Inspection Request Page
class CreateInspectionRequestPage extends StatefulWidget {
  final VoidCallback? onRequestCreated;
  final String? fixedProjectId;
  final bool projectFixed;
  
  const CreateInspectionRequestPage({
    Key? key, 
    this.onRequestCreated,
    this.fixedProjectId,
    this.projectFixed = false,
  }) : super(key: key);

  @override
  _CreateInspectionRequestPageState createState() => _CreateInspectionRequestPageState();
}

class _CreateInspectionRequestPageState extends State<CreateInspectionRequestPage> {
  final List<String> categories = ['MEP', 'Safety', 'AMC', 'QC', 'Structural', 'Architectural'];
  String selectedCategory = 'Select category';
  bool _isSubmitting = false;
  String? userId;
  int? projectId;
  String? projectName;
  dynamic selectedProject;
  String? apiToken;
  String? userName;
  DateTime? requestDate;
  int? assignedToUserId;
  String? assignedToUserName;
  final TextEditingController _commentsController = TextEditingController();
  
  // PageView and step management
  late PageController _pageController;
  int _currentStep = 0;
  final int _totalSteps = 6;
  List<dynamic> projects = [];

  @override
  void initState() {
    super.initState();
    _pageController = PageController(initialPage: 0);
    _loadDefaults();
    _loadProjects();
  }

  @override
  void dispose() {
    _pageController.dispose();
    _commentsController.dispose();
    super.dispose();
  }
  
  void _nextStep() {
    if (_currentStep < _totalSteps - 1) {
      _pageController.nextPage(
        duration: Duration(milliseconds: 300),
        curve: Curves.easeInOut,
      );
    }
  }

  void _previousStep() {
    if (_currentStep > 0) {
      _pageController.previousPage(
        duration: Duration(milliseconds: 300),
        curve: Curves.easeInOut,
      );
    }
  }
  
  Future<void> _loadProjects() async {
    await DataProvider().reloadData(force: false);
    setState(() {
      projects = List<dynamic>.from(DataProvider().projects);
    });
  }

  Future<void> _loadDefaults() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      userId = prefs.getString('userId') ?? prefs.getString('user_id');
      final projectIdStr = prefs.getString('project_id');
      if (projectIdStr != null) {
        projectId = int.tryParse(projectIdStr);
      }
      apiToken = prefs.getString('api_token');
      projectName = prefs.getString('client_name') ?? prefs.getString('username') ?? 'Project';
      userName = prefs.getString('username') ?? 'User';
    });
    
    // Try to get project from projects list if available
    if (projectId != null || widget.fixedProjectId != null) {
      try {
        await _loadProjects();
        final targetProjectId = widget.fixedProjectId ?? projectId.toString();
        try {
          final project = projects.firstWhere(
            (p) => p['id']?.toString() == targetProjectId,
          );
          if (project != null) {
            setState(() {
              selectedProject = project;
              if (project['name'] != null) {
                projectName = project['name'].toString();
              }
              if (widget.fixedProjectId != null) {
                projectId = int.tryParse(widget.fixedProjectId!);
              }
            });
          }
        } catch (e) {
          // Project not found in list, use name from preferences
        }
      } catch (e) {
        print('[CreateInspectionRequestPage] Error loading project: $e');
      }
    }
  }

  Future<void> _selectRequestDate() async {
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: requestDate ?? DateTime.now(),
      firstDate: DateTime.now(),
      lastDate: DateTime.now().add(const Duration(days: 365 * 2)),
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: ColorScheme.light(
              primary: AppTheme.primaryColorConst,
              onPrimary: Colors.white,
              onSurface: AppTheme.textPrimary,
            ),
          ),
          child: child!,
        );
      },
    );
    if (picked != null && picked != requestDate) {
      setState(() {
        requestDate = picked;
      });
    }
  }


  void _showUserPicker() async {
    final currentProjectId = selectedProject != null ? selectedProject['id'] : projectId;
    if (currentProjectId == null) {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => FullScreenMessage(
            title: 'Project Required',
            message: 'Please select a project first',
            icon: Icons.error_outline,
            iconColor: Colors.orange,
            buttonText: 'OK',
            onButtonPressed: () {
              Navigator.pop(context);
              _pageController.animateToPage(
                0,
                duration: Duration(milliseconds: 300),
                curve: Curves.easeInOut,
              );
            },
          ),
        ),
      );
      return;
    }
    
    final result = await UserPickerScreen.show(
      context,
      projectId: int.tryParse(currentProjectId.toString()),
    );

    if (result != null && mounted) {
      setState(() {
        // Try different possible ID field names
        final userIdStr = result['user_id']?.toString() ?? 
                         result['id']?.toString() ?? 
                         result['userId']?.toString() ?? '';
        assignedToUserId = userIdStr.isNotEmpty ? int.tryParse(userIdStr) : null;
        
        // Try different possible name field names
        assignedToUserName = result['user_name']?.toString() ?? 
                            result['name']?.toString() ?? 
                            result['username']?.toString();
      });
    }
  }

  Future<void> _handleSubmit() async {
    // Validation
    if (selectedProject == null && projectId == null) {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => FullScreenMessage(
            title: 'Validation Error',
            message: 'Please select a project',
            icon: Icons.error_outline,
            iconColor: Colors.red,
            buttonText: 'OK',
            onButtonPressed: () {
              Navigator.pop(context);
              _pageController.animateToPage(
                0,
                duration: Duration(milliseconds: 300),
                curve: Curves.easeInOut,
              );
            },
          ),
        ),
      );
      return;
    }

    if (selectedCategory == 'Select category') {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => FullScreenMessage(
            title: 'Validation Error',
            message: 'Please select a category',
            icon: Icons.error_outline,
            iconColor: Colors.red,
            buttonText: 'OK',
            onButtonPressed: () {
              Navigator.pop(context);
              _pageController.animateToPage(
                1,
                duration: Duration(milliseconds: 300),
                curve: Curves.easeInOut,
              );
            },
          ),
        ),
      );
      return;
    }

    if (requestDate == null) {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => FullScreenMessage(
            title: 'Validation Error',
            message: 'Please select a request date',
            icon: Icons.error_outline,
            iconColor: Colors.red,
            buttonText: 'OK',
            onButtonPressed: () {
              Navigator.pop(context);
              _pageController.animateToPage(
                2,
                duration: Duration(milliseconds: 300),
                curve: Curves.easeInOut,
              );
            },
          ),
        ),
      );
      return;
    }

    if (!mounted) return;
    setState(() {
      _isSubmitting = true;
    });

    try {
      final formattedRequestDate = DateFormat('yyyy-MM-dd').format(requestDate!);
      final createdByInt = int.tryParse(userId ?? '');
      
      if (createdByInt == null) {
        throw Exception('Invalid user ID');
      }

      final Map<String, String> requestBody = {
        'created_by': createdByInt.toString(),
        'requested_on_date': formattedRequestDate,
        'project_id': (selectedProject != null ? selectedProject['id'] : projectId).toString(),
        'category': selectedCategory,
      };

      if (_commentsController.text.trim().isNotEmpty) {
        requestBody['comments'] = _commentsController.text.trim();
      }

      if (assignedToUserId != null) {
        requestBody['assigned_to'] = assignedToUserId.toString();
      }

      // Show progress
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => FullScreenProgress(
            title: 'Submitting',
            message: 'Submitting inspection request...',
            progress: 0.5,
          ),
        ),
      );

      final response = await http.post(
        Uri.parse("https://office1\.buildahome.in/API/create_inspection_request"),
        body: requestBody,
      ).timeout(const Duration(seconds: 20));

      Navigator.of(context, rootNavigator: true).pop(); // Close progress

      if (response.statusCode == 200 || response.statusCode == 201) {
        final decoded = jsonDecode(response.body);
        if (decoded['success'] == true) {
          // Reset form
          setState(() {
            selectedCategory = 'Select category';
            selectedProject = null;
            requestDate = null;
            assignedToUserId = null;
            assignedToUserName = null;
            _commentsController.clear();
            _isSubmitting = false;
            _currentStep = 0;
          });
          _pageController.jumpToPage(0);

          if (!mounted) return;
          await Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => FullScreenMessage(
                title: 'Success',
                message: 'Inspection request submitted successfully',
                icon: Icons.check_circle,
                iconColor: Colors.green,
                buttonText: 'OK',
                onButtonPressed: () {
                  Navigator.pop(context);
                  widget.onRequestCreated?.call();
                },
              ),
            ),
          );
        } else {
          throw Exception(decoded['message'] ?? 'Failed to submit request');
        }
      } else {
        final decoded = jsonDecode(response.body);
        throw Exception(decoded['message'] ?? 'Server error: ${response.statusCode}');
      }
    } catch (e) {
      if (!mounted) return;
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => FullScreenMessage(
            title: 'Error',
            message: 'Error: ${e.toString().replaceAll('Exception: ', '')}',
            icon: Icons.error_outline,
            iconColor: Colors.red,
            buttonText: 'OK',
            onButtonPressed: () => Navigator.pop(context),
          ),
        ),
      );
    } finally {
      if (mounted) {
        setState(() {
          _isSubmitting = false;
        });
      }
    }
  }

  List<String> _getStepTitles() {
    return [
      'Project',
      'Category',
      'Date',
      'Assign To',
      'Comments',
      'Preview',
    ];
  }

  List<String> _getStepInstructions() {
    return [
      'Select project',
      'Choose category',
      'Select date',
      'Assign user',
      'Add comments',
      'Review & submit',
    ];
  }

  Widget _buildStepIndicator() {
    return Consumer<ThemeProvider>(
      builder: (context, themeProvider, child) {
        return Container(
          padding: EdgeInsets.symmetric(vertical: 16, horizontal: 12),
          decoration: BoxDecoration(
            color: AppTheme.getBackgroundSecondary(context),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.05),
                blurRadius: 4,
                offset: Offset(0, 2),
              ),
            ],
          ),
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: List.generate(_totalSteps, (index) {
                final isActive = _currentStep == index;
                final isCompleted = _isStepCompleted(index);
                final isLast = index == _totalSteps - 1;
                final stepTitles = _getStepTitles();
                final stepInstructions = _getStepInstructions();

                return Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: 100,
                      constraints: BoxConstraints(minWidth: 80, maxWidth: 120),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                        Container(
                          width: 36,
                          height: 36,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: isCompleted
                                ? Colors.green
                                : isActive
                                    ? AppTheme.getPrimaryColor(context)
                                    : AppTheme.getBackgroundSecondary(context),
                            border: Border.all(
                              color: isCompleted
                                  ? Colors.green
                                  : isActive
                                      ? AppTheme.getPrimaryColor(context)
                                      : AppTheme.getTextSecondary(context).withOpacity(0.3),
                              width: 2.5,
                            ),
                          ),
                          child: Center(
                            child: isCompleted
                                ? Icon(Icons.check, color: Colors.white, size: 18)
                                : Text(
                                    '${index + 1}',
                                    style: TextStyle(
                                      color: isActive
                                          ? Colors.white
                                          : AppTheme.getTextSecondary(context),
                                      fontSize: 14,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                          ),
                        ),
                        SizedBox(height: 6),
                        Text(
                          stepTitles[index],
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: isActive ? FontWeight.bold : FontWeight.w500,
                            color: isCompleted
                                ? Colors.green
                                : isActive
                                    ? AppTheme.getPrimaryColor(context)
                                    : AppTheme.getTextSecondary(context),
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        SizedBox(height: 3),
                        Text(
                          stepInstructions[index],
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 9,
                            color: AppTheme.getTextSecondary(context),
                            height: 1.2,
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                  if (!isLast)
                    Container(
                      width: 20,
                      height: 2,
                      margin: EdgeInsets.only(top: 17, left: 4, right: 4),
                      decoration: BoxDecoration(
                        color: isCompleted
                            ? Colors.green
                            : AppTheme.getTextSecondary(context).withOpacity(0.2),
                    ),
                  ),
                ],
                );
              }),
            ),
          ),
        );
      },
    );
  }

  bool _isStepCompleted(int stepIndex) {
    switch (stepIndex) {
      case 0:
        return selectedProject != null || projectId != null;
      case 1:
        return selectedCategory != 'Select category';
      case 2:
        return requestDate != null;
      case 3:
        return true; // Optional step
      case 4:
        return true; // Optional step
      case 5:
        return selectedProject != null && 
               selectedCategory != 'Select category' && 
               requestDate != null;
      default:
        return false;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<ThemeProvider>(
      builder: (context, themeProvider, child) {
        return Column(
          children: [
            _buildStepIndicator(),
            Expanded(
              child: PageView(
                controller: _pageController,
                onPageChanged: (index) {
                  setState(() {
                    _currentStep = index;
                  });
                },
                children: [
                  _buildStep1Project(),
                  _buildStep2Category(),
                  _buildStep3Date(),
                  _buildStep4AssignTo(),
                  _buildStep5Comments(),
                  _buildStep6Preview(),
                ],
              ),
            ),
            _buildNavigationButtons(),
          ],
        );
      },
    );
  }

  Widget _buildSectionHeader(String title, IconData icon, {bool isCompleted = false, String? instruction}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(
              padding: EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: isCompleted
                    ? Colors.green.withOpacity(0.1)
                    : AppTheme.getPrimaryColor(context).withOpacity(0.1),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(
                icon,
                color: isCompleted
                    ? Colors.green
                    : AppTheme.getPrimaryColor(context),
                size: 24,
              ),
            ),
            SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: AppTheme.getTextPrimary(context),
                    ),
                  ),
                  if (instruction != null) ...[
                    SizedBox(height: 4),
                    Text(
                      instruction,
                      style: TextStyle(
                        fontSize: 13,
                        color: AppTheme.getTextSecondary(context),
                      ),
                    ),
                  ],
                ],
              ),
            ),
            if (isCompleted)
              Icon(
                Icons.check_circle,
                color: Colors.green,
                size: 24,
              ),
          ],
        ),
      ],
    );
  }
  
  Widget _buildStep1Project() {
    return SingleChildScrollView(
      padding: EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildSectionHeader(
            'Select Project',
            Icons.folder_special,
            isCompleted: selectedProject != null || projectId != null,
            instruction: 'Choose the project for this inspection request',
          ),
          SizedBox(height: 24),
          InkWell(
            onTap: widget.projectFixed ? null : () async {
              await _loadProjects();
              if (projects.isEmpty) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('No projects available')),
                );
                return;
              }
              final result = await SearchableSelect.show(
                context: context,
                title: 'Select Project',
                items: projects,
                itemLabel: (item) => item['name']?.toString() ?? 'Project #${item['id']}',
                selectedItem: selectedProject,
              );
              if (result != null) {
                setState(() {
                  selectedProject = result;
                  projectId = int.tryParse(result['id'].toString());
                  projectName = result['name']?.toString() ?? 'Project';
                });
              }
            },
            borderRadius: BorderRadius.circular(16),
            child: Container(
              padding: EdgeInsets.symmetric(horizontal: 16, vertical: 18),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    AppTheme.getBackgroundSecondary(context),
                    AppTheme.getBackgroundPrimaryLight(context),
                  ],
                ),
                borderRadius: BorderRadius.circular(16),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.1),
                    blurRadius: 8,
                    offset: Offset(0, 4),
                  ),
                ],
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      selectedProject != null
                          ? (selectedProject['name']?.toString() ?? 'Project')
                          : projectId != null
                              ? (projectName ?? 'Project')
                              : 'Select a project',
                      style: TextStyle(
                        color: (selectedProject != null || projectId != null)
                            ? AppTheme.getTextPrimary(context)
                            : AppTheme.getTextSecondary(context),
                        fontSize: 16,
                        fontWeight: (selectedProject != null || projectId != null)
                            ? FontWeight.w600
                            : FontWeight.normal,
                      ),
                    ),
                  ),
                  if (!widget.projectFixed)
                    Icon(
                      Icons.arrow_forward_ios,
                      color: AppTheme.getPrimaryColor(context),
                      size: 18,
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
  
  Widget _buildStep2Category() {
    return SingleChildScrollView(
      padding: EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildSectionHeader(
            'Select Category',
            Icons.category,
            isCompleted: selectedCategory != 'Select category',
            instruction: 'Choose the type of inspection you need',
          ),
          SizedBox(height: 24),
          Container(
            padding: EdgeInsets.symmetric(horizontal: 16),
            decoration: BoxDecoration(
              color: AppTheme.getBackgroundSecondary(context),
              borderRadius: BorderRadius.circular(18),
              border: Border.all(
                color: selectedCategory != 'Select category'
                    ? AppTheme.getPrimaryColor(context).withOpacity(0.5)
                    : AppTheme.getPrimaryColor(context).withOpacity(0.15),
                width: selectedCategory != 'Select category' ? 2 : 1,
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.05),
                  blurRadius: 10,
                  offset: Offset(0, 4),
                ),
              ],
            ),
            child: DropdownButtonHideUnderline(
              child: DropdownButton<String>(
                isExpanded: true,
                value: selectedCategory == 'Select category' ? null : selectedCategory,
                hint: Text('Select category', style: TextStyle(color: AppTheme.getTextSecondary(context))),
                icon: Icon(Icons.keyboard_arrow_down, color: AppTheme.getPrimaryColor(context)),
                items: categories.map((String category) {
                  return DropdownMenuItem<String>(
                    value: category,
                    child: Text(category, style: TextStyle(color: AppTheme.getTextPrimary(context), fontWeight: FontWeight.w600)),
                  );
                }).toList(),
                onChanged: (String? newValue) {
                  if (newValue != null) {
                    setState(() {
                      selectedCategory = newValue;
                    });
                  }
                },
              ),
            ),
          ),
        ],
      ),
    );
  }
  
  Widget _buildStep3Date() {
    return SingleChildScrollView(
      padding: EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildSectionHeader(
            'Request Date',
            Icons.calendar_today,
            isCompleted: requestDate != null,
            instruction: 'Select when this inspection is requested',
          ),
          SizedBox(height: 24),
          InkWell(
            onTap: _selectRequestDate,
            borderRadius: BorderRadius.circular(16),
            child: Container(
              padding: EdgeInsets.symmetric(horizontal: 16, vertical: 18),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    AppTheme.getBackgroundSecondary(context),
                    AppTheme.getBackgroundPrimaryLight(context),
                  ],
                ),
                borderRadius: BorderRadius.circular(16),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.1),
                    blurRadius: 8,
                    offset: Offset(0, 4),
                  ),
                ],
              ),
              child: Row(
                children: [
                  Icon(Icons.calendar_month, color: AppTheme.getPrimaryColor(context), size: 24),
                  SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      requestDate == null
                          ? 'Select request date'
                          : DateFormat('d MMM yyyy').format(requestDate!),
                      style: TextStyle(
                        color: requestDate == null ? AppTheme.getTextSecondary(context) : AppTheme.getTextPrimary(context),
                        fontWeight: requestDate == null ? FontWeight.normal : FontWeight.w600,
                        fontSize: 16,
                      ),
                    ),
                  ),
                  Icon(Icons.chevron_right, color: AppTheme.getTextSecondary(context), size: 20),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
  
  Widget _buildStep4AssignTo() {
    return SingleChildScrollView(
      padding: EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildSectionHeader(
            'Assign To',
            Icons.person,
            isCompleted: assignedToUserId != null,
            instruction: 'Select a user to assign this request to (optional)',
          ),
          SizedBox(height: 24),
          InkWell(
            onTap: () => _showUserPicker(),
            borderRadius: BorderRadius.circular(16),
            child: Container(
              padding: EdgeInsets.symmetric(horizontal: 16, vertical: 18),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    AppTheme.getBackgroundSecondary(context),
                    AppTheme.getBackgroundPrimaryLight(context),
                  ],
                ),
                borderRadius: BorderRadius.circular(16),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.1),
                    blurRadius: 8,
                    offset: Offset(0, 4),
                  ),
                ],
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.person,
                    color: AppTheme.getPrimaryColor(context),
                    size: 24,
                  ),
                  SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      assignedToUserId == null
                          ? 'Select a user (optional)'
                          : assignedToUserName ?? 'User',
                      style: TextStyle(
                        color: assignedToUserId == null ? AppTheme.getTextSecondary(context) : AppTheme.getTextPrimary(context),
                        fontWeight: assignedToUserId == null ? FontWeight.normal : FontWeight.w600,
                        fontSize: 16,
                      ),
                    ),
                  ),
                  Icon(
                    Icons.arrow_forward_ios,
                    color: AppTheme.getPrimaryColor(context),
                    size: 18,
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
  
  Widget _buildStep5Comments() {
    return SingleChildScrollView(
      padding: EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildSectionHeader(
            'Comments',
            Icons.comment,
            isCompleted: _commentsController.text.trim().isNotEmpty,
            instruction: 'Add any additional details or comments (optional)',
          ),
          SizedBox(height: 24),
          Container(
            padding: EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppTheme.getBackgroundSecondary(context),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: AppTheme.getPrimaryColor(context).withOpacity(0.15),
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.05),
                  blurRadius: 10,
                  offset: Offset(0, 4),
                ),
              ],
            ),
            child: TextFormField(
              controller: _commentsController,
              maxLines: 8,
              textCapitalization: TextCapitalization.sentences,
              keyboardType: TextInputType.multiline,
              style: TextStyle(
                fontSize: 16,
                color: AppTheme.getTextPrimary(context),
              ),
              onChanged: (value) {
                setState(() {});
              },
              decoration: InputDecoration(
                hintText: 'Add any additional details or comments about the inspection request...',
                hintStyle: TextStyle(color: AppTheme.getTextSecondary(context)),
                border: InputBorder.none,
              ),
            ),
          ),
        ],
      ),
    );
  }
  
  Widget _buildStep6Preview() {
    return SingleChildScrollView(
      padding: EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildSectionHeader(
            'Preview',
            Icons.preview,
            instruction: 'Review your inspection request before submitting',
          ),
          SizedBox(height: 24),
          _buildPreviewCard('Project', selectedProject != null ? (selectedProject['name']?.toString() ?? 'Project') : (projectName ?? 'Not selected'), Icons.folder_special),
          SizedBox(height: 12),
          _buildPreviewCard('Category', selectedCategory != 'Select category' ? selectedCategory : 'Not selected', Icons.category),
          SizedBox(height: 12),
          _buildPreviewCard('Request Date', requestDate != null ? DateFormat('d MMM yyyy').format(requestDate!) : 'Not selected', Icons.calendar_today),
          if (assignedToUserId != null) ...[
            SizedBox(height: 12),
            _buildPreviewCard('Assigned To', assignedToUserName ?? 'User', Icons.person),
          ],
          if (_commentsController.text.trim().isNotEmpty) ...[
            SizedBox(height: 12),
            _buildPreviewCard('Comments', _commentsController.text.trim(), Icons.comment),
          ],
        ],
      ),
    );
  }
  
  Widget _buildPreviewCard(String label, String value, IconData icon) {
    return Container(
      padding: EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            AppTheme.getBackgroundSecondary(context),
            AppTheme.getBackgroundPrimaryLight(context),
          ],
        ),
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 8,
            offset: Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: AppTheme.getPrimaryColor(context).withOpacity(0.1),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, color: AppTheme.getPrimaryColor(context), size: 20),
          ),
          SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 12,
                    color: AppTheme.getTextSecondary(context),
                    fontWeight: FontWeight.w500,
                  ),
                ),
                SizedBox(height: 4),
                Text(
                  value,
                  style: TextStyle(
                    fontSize: 15,
                    color: AppTheme.getTextPrimary(context),
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
  
  Widget _buildNavigationButtons() {
    return Container(
      padding: EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppTheme.getBackgroundSecondary(context),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.1),
            blurRadius: 8,
            offset: Offset(0, -2),
          ),
        ],
      ),
      child: Row(
        children: [
          if (_currentStep > 0)
            Expanded(
              child: Material(
                color: Colors.transparent,
                child: InkWell(
                  onTap: _previousStep,
                  borderRadius: BorderRadius.circular(12),
                  child: Container(
                    padding: EdgeInsets.symmetric(vertical: 14),
                    decoration: BoxDecoration(
                      color: AppTheme.getBackgroundPrimary(context),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: AppTheme.getPrimaryColor(context).withOpacity(0.3),
                      ),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.arrow_back,
                          color: AppTheme.getPrimaryColor(context),
                          size: 20,
                        ),
                        SizedBox(width: 8),
                        Text(
                          'Back',
                          style: TextStyle(
                            color: AppTheme.getPrimaryColor(context),
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
          if (_currentStep > 0) SizedBox(width: 12),
          Expanded(
            flex: _currentStep == 0 ? 1 : 1,
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: _isSubmitting
                    ? null
                    : (_currentStep == _totalSteps - 1
                        ? () async {
                            await _handleSubmit();
                          }
                        : _nextStep),
                borderRadius: BorderRadius.circular(12),
                child: Container(
                  padding: EdgeInsets.symmetric(vertical: 14),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [
                        AppTheme.getPrimaryColor(context),
                        AppTheme.primaryColorConstDark,
                      ],
                    ),
                    borderRadius: BorderRadius.circular(12),
                    boxShadow: [
                      BoxShadow(
                        color: AppTheme.getPrimaryColor(context).withOpacity(0.3),
                        blurRadius: 8,
                        offset: Offset(0, 4),
                      ),
                    ],
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      if (_isSubmitting) ...[
                        SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                          ),
                        ),
                        SizedBox(width: 12),
                        Text(
                          'Submitting...',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ] else if (_currentStep == _totalSteps - 1) ...[
                        Icon(
                          Icons.send,
                          color: Colors.white,
                          size: 20,
                        ),
                        SizedBox(width: 8),
                        Text(
                          'Submit',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ] else ...[
                        Text(
                          'Next',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        SizedBox(width: 8),
                        Icon(
                          Icons.arrow_forward,
                          color: Colors.white,
                          size: 20,
                        ),
                      ],
                    ],
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

// View Inspection Requests Page
class ViewInspectionRequestsPage extends StatefulWidget {
  const ViewInspectionRequestsPage({Key? key}) : super(key: key);

  @override
  _ViewInspectionRequestsPageState createState() => _ViewInspectionRequestsPageState();
}

class _ViewInspectionRequestsPageState extends State<ViewInspectionRequestsPage> {
  List<dynamic> _requests = [];
  bool _isLoading = false;
  bool _isDeleting = false;
  bool _isCompleting = false;
  String? _currentUserId;
  bool _canDelete = false;
  String? _userRole;
  
  // Filter states
  String? _selectedProjectId;
  String? _selectedProjectName;
  String? _selectedCategory;
  bool _showCreatedByMeOnly = false;
  bool _showAssignedToMeOnly = false;
  
  // Expanded cards tracking
  Set<String> _expandedCardIds = Set<String>();

  @override
  void initState() {
    super.initState();
    _loadCurrentUser();
    _loadPermissions();
    _loadUserRole();
    _loadRequests();
  }

  Future<void> _loadCurrentUser() async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    setState(() {
      _currentUserId = prefs.getString('userId') ?? prefs.getString('user_id');
    });
  }

  Future<void> _loadUserRole() async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    setState(() {
      _userRole = prefs.getString('role');
    });
  }

  Future<void> _loadPermissions() async {
    final rbac = RBACService();
    final canDelete = await rbac.canDelete(RBACService.inspectionRequest);
    setState(() {
      _canDelete = canDelete;
    });
  }

  void refreshRequests() {
    _loadRequests();
  }

  Future<void> _loadRequests() async {
    if (_isLoading) return;
    
    setState(() {
      _isLoading = true;
    });

    try {
      SharedPreferences prefs = await SharedPreferences.getInstance();
      String? userId = prefs.getString('userId') ?? prefs.getString('user_id');
      String? projectId = prefs.getString('project_id');
      String? role = prefs.getString('role');
      
      // Build query parameters based on filters
      Map<String, String> queryParams = {};
      
      if (_selectedProjectId != null) {
        queryParams['project_id'] = _selectedProjectId!;
      } else if (projectId != null && _selectedProjectId == null) {
        // If no filter selected, use current project if available
        queryParams['project_id'] = projectId;
      }
      
      // Role-based filtering
      // Client can only see tasks created by client
      if (role == 'Client' && userId != null) {
        queryParams['created_by'] = userId;
      }
      
      if (_showCreatedByMeOnly && userId != null) {
        queryParams['created_by'] = userId;
      }
      
      if (_showAssignedToMeOnly && userId != null) {
        queryParams['assigned_to'] = userId;
      }
      
      if (_selectedCategory != null && _selectedCategory!.isNotEmpty) {
        queryParams['category'] = _selectedCategory!;
      }

      final uri = Uri.parse("https://office1\.buildahome.in/API/get_inspection_requests").replace(
        queryParameters: queryParams.isEmpty ? {} : queryParams,
      );
      
      final response = await http.get(uri).timeout(const Duration(seconds: 20));

      if (response.statusCode == 200) {
        final decoded = jsonDecode(response.body);
        if (decoded['success'] == true && decoded['inspection_requests'] != null) {
          List<dynamic> allRequests = decoded['inspection_requests'] is List 
              ? decoded['inspection_requests'] 
              : [];
          
          // Filter requests based on role permissions
          // For roles that can only view assigned items, filter server-side or client-side
          // Note: This is a basic implementation - server-side filtering is preferred
          setState(() {
            _requests = allRequests;
            _isLoading = false;
          });
        } else {
          setState(() {
            _requests = [];
            _isLoading = false;
          });
        }
      } else {
        throw Exception('Failed to load inspection requests');
      }
    } catch (e) {
      print('[ViewInspectionRequestsPage] Error loading requests: $e');
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error loading inspection requests: ${e.toString()}'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _deleteRequest(int requestId) async {
    if (_isDeleting) return;
    
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Delete Inspection Request'),
        content: Text('Are you sure you want to delete this inspection request? This action cannot be undone.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text('Cancel'),
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
      final response = await http.post(
        Uri.parse("https://office1\.buildahome.in/API/delete_inspection_request"),
        body: {
          'id': requestId.toString(),
        },
      ).timeout(const Duration(seconds: 20));

      if (response.statusCode == 200) {
        final decoded = jsonDecode(response.body);
        if (decoded['success'] == true) {
          setState(() {
            _requests.removeWhere((r) => r['id']?.toString() == requestId.toString());
            _isDeleting = false;
          });

          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Row(
                  children: [
                    Icon(Icons.check_circle, color: Colors.white),
                    SizedBox(width: 8),
                    Text('Inspection request deleted successfully'),
                  ],
                ),
                backgroundColor: Colors.green,
                duration: Duration(seconds: 2),
              ),
            );
          }
        } else {
          throw Exception(decoded['message'] ?? 'Failed to delete request');
        }
      } else {
        throw Exception('Unable to delete request (code ${response.statusCode})');
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

  void _showCompleteDialog(Map<String, dynamic> request) async {
    final requestId = request['id']?.toString() ?? '';
    final projectId = request['project_id']?.toString();
    String? selectedFilePath;
    String? selectedFileName;

    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          backgroundColor: Theme.of(context).colorScheme.surface,
          title: Row(
            children: [
              Icon(Icons.check_circle, color: AppTheme.primaryColorConst),
              SizedBox(width: 8),
              Text('Mark as Complete'),
            ],
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Please upload an inspection report to complete this request.',
                  style: TextStyle(
                    color: AppTheme.textPrimary,
                    fontSize: 14,
                  ),
                ),
                SizedBox(height: 20),
                // File selection button
                InkWell(
                  onTap: () async {
                    await _showFileSourceDialog((filePath, fileName) {
                      setDialogState(() {
                        selectedFilePath = filePath;
                        selectedFileName = fileName;
                      });
                    });
                  },
                  borderRadius: BorderRadius.circular(12),
                  child: Container(
                    padding: EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: AppTheme.backgroundPrimary,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: selectedFilePath != null
                            ? AppTheme.primaryColorConst
                            : AppTheme.primaryColorConst.withOpacity(0.3),
                        width: selectedFilePath != null ? 2 : 1,
                      ),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          Icons.attach_file,
                          color: selectedFilePath != null
                              ? AppTheme.primaryColorConst
                              : AppTheme.textSecondary,
                        ),
                        SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                selectedFileName ?? 'Select Report File',
                                style: TextStyle(
                                  color: selectedFilePath != null
                                      ? AppTheme.textPrimary
                                      : AppTheme.textSecondary,
                                  fontWeight: selectedFilePath != null
                                      ? FontWeight.w600
                                      : FontWeight.normal,
                                  fontSize: 14,
                                ),
                              ),
                              if (selectedFileName != null)
                                Text(
                                  'Tap to change',
                                  style: TextStyle(
                                    color: AppTheme.textSecondary,
                                    fontSize: 11,
                                  ),
                                ),
                            ],
                          ),
                        ),
                        Icon(
                          Icons.arrow_forward_ios,
                          size: 16,
                          color: AppTheme.textSecondary,
                        ),
                      ],
                    ),
                  ),
                ),
                if (selectedFilePath == null) ...[
                  SizedBox(height: 8),
                  Text(
                    '* Report file is required',
                    style: TextStyle(
                      color: Colors.red,
                      fontSize: 12,
                    ),
                  ),
                ],
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: selectedFilePath == null
                  ? null
                  : () {
                      Navigator.pop(context, {
                        'filePath': selectedFilePath,
                        'fileName': selectedFileName,
                      });
                    },
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.primaryColorConst,
                foregroundColor: Colors.white,
              ),
              child: Text('Complete & Upload'),
            ),
          ],
        ),
      ),
    );

    if (result != null && result['filePath'] != null) {
      await _markAsComplete(
        int.tryParse(requestId) ?? 0,
        projectId ?? '',
        result['filePath'] as String,
        request,
      );
    }
  }

  Future<void> _showFileSourceDialog(Function(String?, String?) onFileSelected) async {
    await showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppTheme.backgroundSecondary,
        title: Text('Select File Source', style: TextStyle(fontWeight: FontWeight.bold)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: Icon(Icons.camera_alt, color: AppTheme.primaryColorConst),
              title: Text('Take Photo'),
              onTap: () async {
                Navigator.pop(context);
                final picker = ImagePicker();
                final pickedFile = await picker.pickImage(
                  source: ImageSource.camera,
                  imageQuality: 85,
                );
                if (pickedFile != null) {
                  onFileSelected(pickedFile.path, pickedFile.name);
                }
              },
            ),
            ListTile(
              leading: Icon(Icons.photo_library, color: AppTheme.primaryColorConst),
              title: Text('Choose from Gallery'),
              onTap: () async {
                Navigator.pop(context);
                final picker = ImagePicker();
                final pickedFile = await picker.pickImage(
                  source: ImageSource.gallery,
                  imageQuality: 85,
                );
                if (pickedFile != null) {
                  onFileSelected(pickedFile.path, pickedFile.name);
                }
              },
            ),
            ListTile(
              leading: Icon(Icons.attach_file, color: AppTheme.primaryColorConst),
              title: Text('Other Files'),
              onTap: () async {
                Navigator.pop(context);
                try {
                  final result = await FilePicker.platform.pickFiles(
                    allowMultiple: false,
                    type: FileType.any,
                  );
                  if (result != null && result.files.single.path != null) {
                    final file = result.files.single;
                    onFileSelected(file.path, file.name);
                  }
                } catch (e) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('Error picking file: $e')),
                  );
                }
              },
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _markAsComplete(int requestId, String projectId, String filePath, Map<String, dynamic> request) async {
    if (_isCompleting) return;

    setState(() {
      _isCompleting = true;
    });

    showDialog(
      barrierDismissible: false,
      context: context,
      builder: (BuildContext context) {
        return ShowAlert("Uploading inspection report...", true);
      },
    );

    try {
      SharedPreferences prefs = await SharedPreferences.getInstance();
      String? userId = prefs.getString('userId') ?? prefs.getString('user_id');
      
      if (userId == null) {
        throw Exception('User ID not found');
      }

      // Upload report to site inspection reports API
      final uri = Uri.parse('https://office1.buildahome.in/api/site_visit_reports');
      final uploadRequest = http.MultipartRequest('POST', uri);
      
      uploadRequest.fields['created_by_user_id'] = (int.tryParse(userId) ?? userId).toString();
      uploadRequest.fields['project_id'] = projectId;
      uploadRequest.fields['note'] = 'Inspection Report for Request #$requestId - ${request['category'] ?? ''}';
      uploadRequest.fields['is_task'] = '0';
      uploadRequest.fields['inspection_request_id'] = requestId.toString();
      
      uploadRequest.files.add(await http.MultipartFile.fromPath('attachment', filePath));
      
      final streamedResponse = await uploadRequest.send();
      final response = await http.Response.fromStream(streamedResponse);

      Navigator.of(context, rootNavigator: true).pop(); // Close loader

      if (response.statusCode == 200 || response.statusCode == 201) {
        // Update request status to completed
        await _updateRequestStatus(requestId, 'completed');
        
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Row(
                children: [
                  Icon(Icons.check_circle, color: Colors.white),
                  SizedBox(width: 8),
                  Text('Inspection request marked as complete and report uploaded successfully'),
                ],
              ),
              backgroundColor: Colors.green,
              duration: Duration(seconds: 3),
            ),
          );
        }
      } else {
        final decoded = jsonDecode(response.body);
        throw Exception(decoded['message'] ?? 'Failed to upload report');
      }
    } catch (e) {
      Navigator.of(context, rootNavigator: true).pop(); // Close loader if still open
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
          _isCompleting = false;
        });
        _loadRequests(); // Refresh the list
      }
    }
  }

  Future<void> _updateRequestStatus(int requestId, String status) async {
    try {
      final response = await http.post(
        Uri.parse("https://office1.buildahome.in/API/update_inspection_request_status"),
        body: {
          'id': requestId.toString(),
          'status': status,
        },
      ).timeout(const Duration(seconds: 20));

      if (response.statusCode == 200) {
        final decoded = jsonDecode(response.body);
        if (decoded['success'] != true) {
          print('[InspectionRequest] Warning: Status update may have failed: ${decoded['message']}');
        }
      } else {
        print('[InspectionRequest] Warning: Status update failed with code ${response.statusCode}');
      }
    } catch (e) {
      print('[InspectionRequest] Error updating status: $e');
      // Don't throw - we still want to show success if report upload succeeded
    }
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
          color: AppTheme.backgroundSecondary,
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
                color: AppTheme.backgroundPrimary,
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
                      color: AppTheme.primaryColorConst,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'Filter by Project',
                      style: TextStyle(
                        color: AppTheme.textPrimary,
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  IconButton(
                    icon: Icon(Icons.close, color: AppTheme.textSecondary),
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
                          ? AppTheme.primaryColorConst.withOpacity(0.1)
                          : AppTheme.backgroundPrimary,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                        color: isSelected
                            ? AppTheme.primaryColorConst
                            : AppTheme.primaryColorConst.withOpacity(0.2),
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
                          _loadRequests();
                          Navigator.pop(context);
                        },
                        borderRadius: BorderRadius.circular(10),
                        child: Padding(
                          padding: EdgeInsets.all(12),
                          child: Row(
                            children: [
                              Icon(Icons.clear_all, color: AppTheme.primaryColorConst, size: 20),
                              SizedBox(width: 12),
                              Expanded(
                                child: Text(
                                  'All Projects',
                                  style: TextStyle(
                                    color: AppTheme.textPrimary,
                                    fontSize: 14,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                              if (isSelected)
                                Icon(Icons.check_circle, color: AppTheme.primaryColorConst, size: 20),
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
                        ? AppTheme.primaryColorConst.withOpacity(0.1)
                        : AppTheme.backgroundPrimary,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: isSelected
                          ? AppTheme.primaryColorConst
                          : AppTheme.primaryColorConst.withOpacity(0.2),
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
                        _loadRequests();
                        Navigator.pop(context);
                      },
                      borderRadius: BorderRadius.circular(10),
                      child: Padding(
                        padding: EdgeInsets.all(12),
                        child: Row(
                          children: [
                            Icon(Icons.folder_special, color: AppTheme.primaryColorConst, size: 20),
                            SizedBox(width: 12),
                            Expanded(
                              child: Text(
                                projectName,
                                style: TextStyle(
                                  color: AppTheme.textPrimary,
                                  fontSize: 14,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                            if (isSelected)
                              Icon(Icons.check_circle, color: AppTheme.primaryColorConst, size: 20),
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

  void _showCategoryFilter() {
    final categories = ['MEP', 'Safety', 'AMC', 'QC', 'Structural', 'Foundation'];
    
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) => Container(
        decoration: BoxDecoration(
          color: AppTheme.backgroundSecondary,
          borderRadius: BorderRadius.only(
            topLeft: Radius.circular(20),
            topRight: Radius.circular(20),
          ),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: AppTheme.backgroundPrimary,
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
                      color: AppTheme.primaryColorConst,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'Filter by Category',
                      style: TextStyle(
                        color: AppTheme.textPrimary,
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  IconButton(
                    icon: Icon(Icons.close, color: AppTheme.textSecondary),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
            ),
            ListView.builder(
              padding: EdgeInsets.all(16),
              shrinkWrap: true,
              itemCount: categories.length + 1,
              itemBuilder: (context, index) {
                if (index == 0) {
                  final isSelected = _selectedCategory == null;
                  return Container(
                    margin: EdgeInsets.only(bottom: 8),
                    decoration: BoxDecoration(
                      color: isSelected
                          ? AppTheme.primaryColorConst.withOpacity(0.1)
                          : AppTheme.backgroundPrimary,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                        color: isSelected
                            ? AppTheme.primaryColorConst
                            : AppTheme.primaryColorConst.withOpacity(0.2),
                        width: isSelected ? 1.5 : 1,
                      ),
                    ),
                    child: Material(
                      color: Colors.transparent,
                      child: InkWell(
                        onTap: () {
                          setState(() {
                            _selectedCategory = null;
                          });
                          _loadRequests();
                          Navigator.pop(context);
                        },
                        borderRadius: BorderRadius.circular(10),
                        child: Padding(
                          padding: EdgeInsets.all(12),
                          child: Row(
                            children: [
                              Icon(Icons.clear_all, color: AppTheme.primaryColorConst, size: 20),
                              SizedBox(width: 12),
                              Expanded(
                                child: Text(
                                  'All Categories',
                                  style: TextStyle(
                                    color: AppTheme.textPrimary,
                                    fontSize: 14,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                              if (isSelected)
                                Icon(Icons.check_circle, color: AppTheme.primaryColorConst, size: 20),
                            ],
                          ),
                        ),
                      ),
                    ),
                  );
                }
                
                final category = categories[index - 1];
                final isSelected = _selectedCategory == category;
                
                return Container(
                  margin: EdgeInsets.only(bottom: 8),
                  decoration: BoxDecoration(
                    color: isSelected
                        ? AppTheme.primaryColorConst.withOpacity(0.1)
                        : AppTheme.backgroundPrimary,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: isSelected
                          ? AppTheme.primaryColorConst
                          : AppTheme.primaryColorConst.withOpacity(0.2),
                      width: isSelected ? 1.5 : 1,
                    ),
                  ),
                  child: Material(
                    color: Colors.transparent,
                    child: InkWell(
                      onTap: () {
                        setState(() {
                          _selectedCategory = category;
                        });
                        _loadRequests();
                        Navigator.pop(context);
                      },
                      borderRadius: BorderRadius.circular(10),
                      child: Padding(
                        padding: EdgeInsets.all(12),
                        child: Row(
                          children: [
                            Icon(Icons.category, color: AppTheme.primaryColorConst, size: 20),
                            SizedBox(width: 12),
                            Expanded(
                              child: Text(
                                category,
                                style: TextStyle(
                                  color: AppTheme.textPrimary,
                                  fontSize: 14,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                            if (isSelected)
                              Icon(Icons.check_circle, color: AppTheme.primaryColorConst, size: 20),
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

  String _formatDateTime(String dateTimeStr) {
    try {
      final dateTime = DateTime.parse(dateTimeStr);
      final formatter = DateFormat('MMM d, y • h:mm a');
      return formatter.format(dateTime);
    } catch (e) {
      return dateTimeStr;
    }
  }

  String _formatDate(String dateStr) {
    try {
      final date = DateTime.parse(dateStr);
      final formatter = DateFormat('MMM d, y');
      return formatter.format(date);
    } catch (e) {
      return dateStr;
    }
  }

  Widget _buildRequestCard(Map<String, dynamic> request) {
    final requestId = request['id']?.toString() ?? '';
    final createdBy = request['created_by']?.toString() ?? '';
    final projectName = request['project_name']?.toString() ?? '';
    final category = request['category']?.toString() ?? '';
    final comments = request['comments']?.toString() ?? '';
    final requestedOnDate = request['requested_on_date']?.toString() ?? '';
    final createdOn = request['created_on']?.toString() ?? '';
    final createdByName = request['created_by_name']?.toString() ?? '';
    final assignedToName = request['assigned_to_name']?.toString();
    final isCreatedByMe = _currentUserId != null && createdBy == _currentUserId;
    final isExpanded = _expandedCardIds.contains(requestId);

    return Container(
      margin: EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: AppTheme.backgroundSecondary,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: AppTheme.primaryColorConst.withOpacity(0.15),
          width: 1,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.03),
            blurRadius: 4,
            offset: Offset(0, 2),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () {
            setState(() {
              if (isExpanded) {
                _expandedCardIds.remove(requestId);
              } else {
                _expandedCardIds.add(requestId);
              }
            });
          },
          borderRadius: BorderRadius.circular(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Collapsed Header - Always visible
              Padding(
                padding: EdgeInsets.all(16),
                child: Row(
                  children: [
                    // Category badge
                    if (category.isNotEmpty)
                      Container(
                        padding: EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                        decoration: BoxDecoration(
                          color: AppTheme.primaryColorConst.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          category.toUpperCase(),
                          style: TextStyle(
                            color: AppTheme.primaryColorConst,
                            fontSize: 10,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 0.5,
                          ),
                        ),
                      ),
                    if (category.isNotEmpty) SizedBox(width: 12),
                    // Request ID and Project
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Request #$requestId',
                            style: TextStyle(
                              color: AppTheme.textPrimary,
                              fontSize: 15,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          if (projectName.isNotEmpty) ...[
                            SizedBox(height: 4),
                            Text(
                              projectName,
                              style: TextStyle(
                                color: AppTheme.textSecondary,
                                fontSize: 12,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                        ],
                      ),
                    ),
                    // Expand/Collapse icon
                    Icon(
                      isExpanded ? Icons.expand_less : Icons.expand_more,
                      color: AppTheme.textSecondary,
                      size: 20,
                    ),
                    SizedBox(width: 8),
                    // Menu button - only show if user has delete permission
                    if (_canDelete && isCreatedByMe)
                      PopupMenuButton<String>(
                        icon: Icon(Icons.more_vert, color: AppTheme.textSecondary, size: 20),
                        onSelected: (value) {
                          if (value == 'delete') {
                            _deleteRequest(int.tryParse(requestId) ?? 0);
                          }
                        },
                        itemBuilder: (context) => [
                          PopupMenuItem(
                            value: 'delete',
                            child: Row(
                              children: [
                                Icon(Icons.delete, size: 18, color: Colors.red),
                                SizedBox(width: 8),
                                Text('Delete', style: TextStyle(color: Colors.red)),
                              ],
                            ),
                          ),
                        ],
                      ),
                  ],
                ),
              ),
              
              // Expanded Content - Only shown when expanded
              if (isExpanded) ...[
                Divider(height: 1, thickness: 1, color: AppTheme.primaryColorConst.withOpacity(0.1)),
                Padding(
                  padding: EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Comments
                      if (comments.isNotEmpty) ...[
                        Container(
                          padding: EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: AppTheme.backgroundPrimary,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Icon(Icons.comment_outlined, size: 16, color: AppTheme.primaryColorConst),
                              SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  comments,
                                  style: TextStyle(
                                    color: AppTheme.textPrimary,
                                    fontSize: 13,
                                    height: 1.4,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                        SizedBox(height: 12),
                      ],
                      
                      // Details in compact format
                      Wrap(
                        spacing: 12,
                        runSpacing: 8,
                        children: [
                          if (createdByName.isNotEmpty)
                            _buildDetailChip(Icons.person_outline, 'Created by $createdByName'),
                          if (assignedToName != null && assignedToName.isNotEmpty)
                            _buildDetailChip(Icons.assignment_ind, 'Assigned to $assignedToName'),
                          if (requestedOnDate.isNotEmpty)
                            _buildDetailChip(Icons.calendar_today, _formatDate(requestedOnDate)),
                          if (createdOn.isNotEmpty)
                            _buildDetailChip(Icons.access_time, _formatDateTime(createdOn)),
                        ],
                      ),
                      SizedBox(height: 16),
                      // Mark as Complete button
                      if (request['status']?.toString().toLowerCase() != 'completed')
                        SizedBox(
                          width: double.infinity,
                          child: ElevatedButton.icon(
                            onPressed: _isCompleting ? null : () => _showCompleteDialog(request),
                            icon: Icon(Icons.check_circle, size: 18),
                            label: Text('Mark as Complete'),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: AppTheme.primaryColorConst,
                              foregroundColor: Colors.white,
                              padding: EdgeInsets.symmetric(vertical: 12),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                            ),
                          ),
                        ),
                      // Status indicator if completed
                      if (request['status']?.toString().toLowerCase() == 'completed')
                        Container(
                          padding: EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: Colors.green.withOpacity(0.1),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: Colors.green.withOpacity(0.3)),
                          ),
                          child: Row(
                            children: [
                              Icon(Icons.check_circle, color: Colors.green, size: 20),
                              SizedBox(width: 8),
                              Text(
                                'Completed',
                                style: TextStyle(
                                  color: Colors.green,
                                  fontWeight: FontWeight.w600,
                                  fontSize: 14,
                                ),
                              ),
                            ],
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildDetailChip(IconData icon, String text) {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: AppTheme.backgroundPrimary,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: AppTheme.textSecondary),
          SizedBox(width: 6),
          Text(
            text,
            style: TextStyle(
              color: AppTheme.textSecondary,
              fontSize: 11,
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // Hide inspection requests from clients
    if (_userRole != null && _userRole!.toLowerCase() == 'client') {
      return Center(
        child: Padding(
          padding: EdgeInsets.all(40),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.fact_check_outlined,
                size: 64,
                color: AppTheme.textSecondary,
              ),
              SizedBox(height: 16),
              Text(
                'Inspection Requests',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: AppTheme.textPrimary,
                ),
              ),
              SizedBox(height: 8),
              Text(
                'This feature is not available for clients.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 14,
                  color: AppTheme.textSecondary,
                ),
              ),
            ],
          ),
        ),
      );
    }

    return Column(
      children: [
        // Filter Section
        Container(
          margin: EdgeInsets.only(top: 12),
          padding: EdgeInsets.all(16),
          width: MediaQuery.of(context).size.width * 0.9,
          decoration: BoxDecoration(
            color: AppTheme.backgroundSecondary,
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.05),
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
                  color: AppTheme.textPrimary,
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
                            ? AppTheme.primaryColorConst.withOpacity(0.2)
                            : AppTheme.backgroundPrimary,
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(
                          color: _selectedProjectId != null
                              ? AppTheme.primaryColorConst
                              : AppTheme.primaryColorConst.withOpacity(0.3),
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
                                ? AppTheme.primaryColorConst
                                : AppTheme.textSecondary,
                          ),
                          SizedBox(width: 6),
                          Text(
                            _selectedProjectName ?? 'All Projects',
                            style: TextStyle(
                              color: _selectedProjectId != null
                                  ? AppTheme.primaryColorConst
                                  : AppTheme.textSecondary,
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
                                _loadRequests();
                              },
                              child: Icon(
                                Icons.close,
                                size: 14,
                                color: AppTheme.primaryColorConst,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                  // Category Filter
                  InkWell(
                    onTap: _showCategoryFilter,
                    borderRadius: BorderRadius.circular(20),
                    child: Container(
                      padding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      decoration: BoxDecoration(
                        color: _selectedCategory != null
                            ? AppTheme.primaryColorConst.withOpacity(0.2)
                            : AppTheme.backgroundPrimary,
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(
                          color: _selectedCategory != null
                              ? AppTheme.primaryColorConst
                              : AppTheme.primaryColorConst.withOpacity(0.3),
                          width: 1,
                        ),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.category,
                            size: 14,
                            color: _selectedCategory != null
                                ? AppTheme.primaryColorConst
                                : AppTheme.textSecondary,
                          ),
                          SizedBox(width: 6),
                          Text(
                            _selectedCategory ?? 'All Categories',
                            style: TextStyle(
                              color: _selectedCategory != null
                                  ? AppTheme.primaryColorConst
                                  : AppTheme.textSecondary,
                              fontSize: 12,
                              fontWeight: _selectedCategory != null
                                  ? FontWeight.w600
                                  : FontWeight.w500,
                            ),
                          ),
                          if (_selectedCategory != null) ...[
                            SizedBox(width: 4),
                            InkWell(
                              onTap: () {
                                setState(() {
                                  _selectedCategory = null;
                                });
                                _loadRequests();
                              },
                              child: Icon(
                                Icons.close,
                                size: 14,
                                color: AppTheme.primaryColorConst,
                              ),
                            ),
                          ],
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
                      _loadRequests();
                    },
                    borderRadius: BorderRadius.circular(20),
                    child: Container(
                      padding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      decoration: BoxDecoration(
                        color: _showCreatedByMeOnly
                            ? AppTheme.primaryColorConst.withOpacity(0.2)
                            : AppTheme.backgroundPrimary,
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(
                          color: _showCreatedByMeOnly
                              ? AppTheme.primaryColorConst
                              : AppTheme.primaryColorConst.withOpacity(0.3),
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
                                ? AppTheme.primaryColorConst
                                : AppTheme.textSecondary,
                          ),
                          SizedBox(width: 6),
                          Text(
                            'Created by Me',
                            style: TextStyle(
                              color: _showCreatedByMeOnly
                                  ? AppTheme.primaryColorConst
                                  : AppTheme.textSecondary,
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
                  // Assigned to Me Filter
                  InkWell(
                    onTap: () {
                      setState(() {
                        _showAssignedToMeOnly = !_showAssignedToMeOnly;
                      });
                      _loadRequests();
                    },
                    borderRadius: BorderRadius.circular(20),
                    child: Container(
                      padding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      decoration: BoxDecoration(
                        color: _showAssignedToMeOnly
                            ? AppTheme.primaryColorConst.withOpacity(0.2)
                            : AppTheme.backgroundPrimary,
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(
                          color: _showAssignedToMeOnly
                              ? AppTheme.primaryColorConst
                              : AppTheme.primaryColorConst.withOpacity(0.3),
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
                                ? AppTheme.primaryColorConst
                                : AppTheme.textSecondary,
                          ),
                          SizedBox(width: 6),
                          Text(
                            'Assigned to Me',
                            style: TextStyle(
                              color: _showAssignedToMeOnly
                                  ? AppTheme.primaryColorConst
                                  : AppTheme.textSecondary,
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
                ],
              ),
            ],
          ),
        ),
        // Requests List
        Expanded(
          child: _isLoading && _requests.isEmpty
              ? Center(
                  child: CircularProgressIndicator(
                    valueColor: AlwaysStoppedAnimation<Color>(AppTheme.primaryColorConst),
                  ),
                )
              : _requests.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.fact_check_outlined, size: 56, color: AppTheme.textSecondary),
                          SizedBox(height: 16),
                          Text(
                            'No inspection requests found',
                            style: TextStyle(
                              color: AppTheme.textPrimary,
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          SizedBox(height: 8),
                          Text(
                            'Try adjusting your filters',
                            style: TextStyle(
                              color: AppTheme.textSecondary,
                              fontSize: 14,
                            ),
                          ),
                        ],
                      ),
                    )
                  : RefreshIndicator(
                      onRefresh: () async {
                        await _loadRequests();
                      },
                      color: AppTheme.primaryColorConst,
                      child: ListView(
                        padding: EdgeInsets.all(20),
                        children: _requests.map((request) {
                          if (request is Map<String, dynamic>) {
                            return _buildRequestCard(request);
                          }
                          return SizedBox.shrink();
                        }).toList(),
                      ),
                    ),
        ),
      ],
    );
  }
}

