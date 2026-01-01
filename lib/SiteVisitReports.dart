import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:cached_network_image/cached_network_image.dart';

import 'app_theme.dart';
import 'widgets/dark_mode_toggle.dart';
import 'AddDailyUpdate.dart'; // For FullScreenImage
import 'services/data_provider.dart';
import 'widgets/searchable_select.dart';
import 'package:provider/provider.dart';
import 'providers/theme_provider.dart';

class SiteVisitReportsScreen extends StatefulWidget {
  final String? fixedProjectId;
  final bool projectFixed;
  
  const SiteVisitReportsScreen({
    Key? key,
    this.fixedProjectId,
    this.projectFixed = false,
  }) : super(key: key);

  @override
  State<SiteVisitReportsScreen> createState() => _SiteVisitReportsScreenState();
}

class _SiteVisitReportsScreenState extends State<SiteVisitReportsScreen> with SingleTickerProviderStateMixin {
  final TextEditingController _noteController = TextEditingController();
  TabController? _tabController;

  bool _isTask = false;
  bool _submitting = false;
  bool _fetchingReports = false;
  bool _myReportsOnly = true;
  bool _isClient = false;

  List<dynamic> _projects = [];
  bool _projectsLoading = false;
  dynamic _createProject;
  dynamic _viewProject;

  List<dynamic> _reports = [];
  bool _hasSearched = false;
  String? _reportsError;

  DateTime? _dueDate;

  var selectedPictures = [];
  var selectedPictureFilenames = [];
  var selectedPictureFilePaths = [];
  String attachPictureButtonText = "Add pictures";
  
  final int maxImageWidth = 1920;
  final int maxImageHeight = 1080;
  
  // PageView and step management
  late PageController _pageController;
  int _currentStep = 0;
  int get _totalSteps => widget.projectFixed ? 3 : 4; // Project (if not fixed), Notes, Attachments, Task/Preview

  @override
  void initState() {
    super.initState();
    _pageController = PageController(initialPage: 0);
    _initializeRoleAndTabs();
    _primeProjects();
  }
  
  void _nextStep() {
    // Validate current step before moving forward
    if (widget.projectFixed) {
      // Fixed project flow: Step 0 = Notes, Step 1 = Attachments, Step 2 = Task/Preview
      if (_currentStep == 0) {
        // Notes step
        if (_noteController.text.trim().isEmpty) {
          _showSnackBar('Please enter a note for the visit.');
          return;
        }
      } else if (_currentStep == 1) {
        // Attachments step
        if (selectedPictures.isEmpty) {
          _showSnackBar('Please add at least one photo or attachment.');
          return;
        }
      }
    } else {
      // Non-fixed project flow: Step 0 = Project, Step 1 = Notes, Step 2 = Attachments, Step 3 = Task/Preview
      if (_currentStep == 1) {
        // Notes step
        if (_noteController.text.trim().isEmpty) {
          _showSnackBar('Please enter a note for the visit.');
          return;
        }
      } else if (_currentStep == 2) {
        // Attachments step
        if (selectedPictures.isEmpty) {
          _showSnackBar('Please add at least one photo or attachment.');
          return;
        }
      }
    }
    
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

  Future<void> _initializeRoleAndTabs() async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    final role = prefs.getString('role');
    final isClient = role == 'Client';
    
    if (mounted) {
      setState(() {
        _isClient = isClient;
        if (!isClient) {
          _tabController = TabController(length: 2, vsync: this);
          _tabController!.addListener(_handleTabSelection);
        }
      });
    }
  }

  void _handleTabSelection() {
    if (_tabController == null || _tabController!.indexIsChanging) return;
    if (_tabController!.index == 1) {
      _fetchReports();
    }
  }
  
  Future<void> _setFixedProject() async {
    if (widget.fixedProjectId == null || !widget.projectFixed) return;
    
    // Find the project in the list
    await _ensureProjectsLoaded();
    try {
      final project = _projects.firstWhere(
        (p) => p['id'].toString() == widget.fixedProjectId,
      );
      
      if (project != null && mounted) {
        setState(() {
          _createProject = project;
          _viewProject = project;
        });
        // Auto-fetch reports for the fixed project
        if (_viewProject != null) {
          _fetchReports();
        }
      }
    } catch (e) {
      print('[SiteVisitReports] Project not found: ${widget.fixedProjectId}');
    }
  }

  @override
  void dispose() {
    _tabController?.removeListener(_handleTabSelection);
    _tabController?.dispose();
    _noteController.dispose();
    _pageController.dispose();
    super.dispose();
  }

  Future<bool> checkPermissionStatus({required bool forCamera}) async {
    try {
      PermissionStatus status;
      if (forCamera) {
        status = await Permission.camera.status;
        if (!status.isGranted) {
          status = await Permission.camera.request();
        }
      } else {
        // For gallery/photos
        if (Platform.isAndroid) {
          // On Android 13+ (SDK 33+), use photos permission
          // For older versions, use storage
          status = await Permission.photos.status;
          if (!status.isGranted) {
            status = await Permission.photos.request();
          }
          if (!status.isGranted) {
            final storageStatus = await Permission.storage.status;
            if (!storageStatus.isGranted) {
              await Permission.storage.request();
            }
            return true; // Often storage is enough on Android
          }
        } else {
          status = await Permission.photos.status;
          if (!status.isGranted) {
            status = await Permission.photos.request();
          }
        }
      }
      return status.isGranted;
    } catch (e) {
      print('[SiteVisitReports] Permission error: $e');
      return Platform.isAndroid && !forCamera; // Default true for gallery on Android
    }
  }

  Future<void> _showImageSourceDialog() async {
    await showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          backgroundColor: Theme.of(context).colorScheme.surface,
          title: const Text('Select Image Source', style: TextStyle(fontWeight: FontWeight.bold)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: Icon(Icons.camera_alt, color: AppTheme.getPrimaryColor(context)),
                title: const Text('Take Photo'),
                onTap: () {
                  Navigator.pop(context);
                  _takePhotoFromCamera();
                },
              ),
              ListTile(
                leading: Icon(Icons.photo_library, color: AppTheme.getPrimaryColor(context)),
                title: const Text('Choose from Gallery'),
                onTap: () {
                  Navigator.pop(context);
                  _selectPicturesFromGallery();
                },
              ),
              ListTile(
                leading: Icon(Icons.attach_file, color: AppTheme.getPrimaryColor(context)),
                title: const Text('Other Files'),
                onTap: () {
                  Navigator.pop(context);
                  _pickFile();
                },
              ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _takePhotoFromCamera() async {
    if (!await checkPermissionStatus(forCamera: true)) return;
    
    final picker = ImagePicker();
    final pickedFile = await picker.pickImage(
      source: ImageSource.camera,
      maxWidth: maxImageWidth.toDouble(),
      maxHeight: maxImageHeight.toDouble(),
      imageQuality: 85,
    );
    
    if (pickedFile != null) {
      _processImage(pickedFile);
    }
  }

  Future<void> _selectPicturesFromGallery() async {
    if (!await checkPermissionStatus(forCamera: false)) return;
    
    final picker = ImagePicker();
    final pickedFiles = await picker.pickMultiImage(
      maxWidth: maxImageWidth.toDouble(),
      maxHeight: maxImageHeight.toDouble(),
      imageQuality: 85,
    );
    
    for (var file in pickedFiles) {
      _processImage(file);
    }
  }

  void _processImage(XFile file) {
    setState(() {
      selectedPictures.insert(0, FileImage(File(file.path)));
      selectedPictureFilenames.insert(0, file.name);
      selectedPictureFilePaths.insert(0, file.path);
      attachPictureButtonText = "Add more pictures";
    });
  }

  Future<void> _pickFile() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        allowMultiple: true,
        type: FileType.any,
      );

      if (result != null && result.files.isNotEmpty) {
        for (var file in result.files) {
          if (file.path != null) {
            setState(() {
              // We'll treat other files similarly if they are images, or just add them to the list
              // For simplicity, we'll just add them to the paths
              selectedPictures.insert(0, FileImage(File(file.path!)));
              selectedPictureFilenames.insert(0, file.name);
              selectedPictureFilePaths.insert(0, file.path!);
              attachPictureButtonText = "Add more pictures";
            });
          }
        }
      }
    } catch (e) {
      _showSnackBar('Error picking file: $e');
    }
  }

  void _removeAttachment(int index) {
    setState(() {
      selectedPictures.removeAt(index);
      selectedPictureFilenames.removeAt(index);
      selectedPictureFilePaths.removeAt(index);
      if (selectedPictures.isEmpty) {
        attachPictureButtonText = "Add pictures";
      }
    });
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
    
    // If fixed project ID is provided, set it after projects are loaded
    if (widget.projectFixed && widget.fixedProjectId != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _setFixedProject();
      });
    }
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

    final selected = await SearchableSelect.show(
      context: context,
      title: 'Select Project',
      items: _projects,
      itemLabel: (item) => item['name']?.toString() ?? 'Project #${item['id']}',
      selectedItem: forCreate ? _createProject : _viewProject,
    );

    if (selected != null) {
      setState(() {
        if (forCreate) {
          _createProject = selected;
        } else {
          _viewProject = selected;
        }
      });
      // Auto-trigger search when project is selected in view tab
      if (!forCreate && _viewProject != null) {
        _fetchReports();
      }
    }
  }

  Future<void> _selectDueDate() async {
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: _dueDate ?? DateTime.now(),
      firstDate: DateTime.now(),
      lastDate: DateTime.now().add(const Duration(days: 365 * 2)), // 2 years out
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: ColorScheme.light(
              primary: AppTheme.getPrimaryColor(context),
              onPrimary: Colors.white,
              onSurface: AppTheme.getTextPrimary(context),
            ),
          ),
          child: child!,
        );
      },
    );
    if (picked != null && picked != _dueDate) {
      setState(() {
        _dueDate = picked;
      });
    }
  }

  Future<void> _submitReport() async {
    // Prevent clients from creating reports
    if (_isClient) {
      _showSnackBar('Clients cannot create site visit reports.');
      return;
    }

    final note = _noteController.text.trim();
    if (_createProject == null) {
      _showSnackBar('Please select a project.');
      return;
    }
    if (note.isEmpty) {
      _showSnackBar('Please enter a note for the visit.');
      return;
    }
    if (selectedPictureFilePaths.isEmpty) {
      _showSnackBar('Please add at least one photo or attachment.');
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
      final String? formattedDueDate = _dueDate != null ? DateFormat('yyyy-MM-dd').format(_dueDate!) : null;

      if (selectedPictureFilePaths.isEmpty) {
        await _submitSingleReport(createdBy, note, null, formattedDueDate);
      } else {
        for (String filePath in selectedPictureFilePaths) {
          await _submitSingleReport(createdBy, note, filePath, formattedDueDate);
        }
      }

      _showSnackBar('Report(s) created successfully.');
      setState(() {
        _noteController.clear();
        _isTask = false;
        _dueDate = null;
        selectedPictures.clear();
        selectedPictureFilenames.clear();
        selectedPictureFilePaths.clear();
        attachPictureButtonText = "Add pictures";
        _currentStep = 0;
      });
      _pageController.jumpToPage(0);
    } catch (e) {
      print('Error submitting report: $e');
      _showSnackBar('Error: $e');
    } finally {
      setState(() {
        _submitting = false;
      });
    }
  }

  Future<void> _submitSingleReport(String createdBy, String note, String? filePath, String? dueDate) async {
    http.Response response;
    
    if (filePath != null) {
      final uri = Uri.parse('https://office1.buildahome.in/api/site_visit_reports');
      final request = http.MultipartRequest('POST', uri);
      
      request.fields['created_by_user_id'] = (int.tryParse(createdBy) ?? createdBy).toString();
      request.fields['project_id'] = _createProject['id'].toString();
      request.fields['note'] = note;
      request.fields['is_task'] = (_isTask ? 1 : 0).toString();
      if (dueDate != null) {
        request.fields['due_date'] = dueDate;
      }
      
      request.files.add(await http.MultipartFile.fromPath('attachment', filePath));
      
      final streamedResponse = await request.send();
      response = await http.Response.fromStream(streamedResponse);
    } else {
      response = await http.post(
        Uri.parse('https://office1.buildahome.in/api/site_visit_reports'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'created_by_user_id': int.tryParse(createdBy) ?? createdBy,
          'project_id': _createProject['id'],
          'note': note,
          'is_task': _isTask ? 1 : 0,
          if (dueDate != null) 'due_date': dueDate,
        }),
      );
    }
    
    if (response.statusCode != 201 && response.statusCode != 200) {
      final error = _extractError(response);
      throw Exception(error ?? 'Server returned ${response.statusCode}');
    }
  }

  Future<void> _fetchReports() async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    final currentUserId = prefs.getString('userId') ?? prefs.getString('user_id');

    final Map<String, String> query = {};

    // Only add project_id if a specific project is selected
    if (_viewProject != null) {
      query['project_id'] = _viewProject!['id'].toString();
    }

    if (_myReportsOnly && currentUserId != null) {
      query['created_by_user_id'] = currentUserId;
    }

    setState(() {
      _fetchingReports = true;
      _reportsError = null;
    });

    try {
      final uri = Uri.parse('https://office1.buildahome.in/api/site_visit_reports/search')
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

  bool _isImage(String filename) {
    final imageExtensions = ['.jpg', '.jpeg', '.png', '.gif', '.webp', '.bmp'];
    final lowerCaseFilename = filename.toLowerCase();
    return imageExtensions.any((ext) => lowerCaseFilename.endsWith(ext));
  }

  Future<void> _launchURL(String url) async {
    final Uri uri = Uri.parse(url);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } else {
      _showSnackBar('Could not launch $url');
    }
  }

  @override
  Widget build(BuildContext context) {
    // Show loading if tab controller is not initialized yet
    if (_tabController == null && !_isClient) {
      return Scaffold(
        backgroundColor: Theme.of(context).scaffoldBackgroundColor,
        appBar: AppBar(
          title: Text('Site Visit Reports'),
          backgroundColor: Theme.of(context).colorScheme.surface,
        ),
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
        title: Text('Site Visit Reports'),
        backgroundColor: Theme.of(context).colorScheme.surface,
        actions: [
          DarkModeToggle(showLabel: false),
          SizedBox(width: 8),
        ],
        bottom: _isClient
            ? null
            : _tabController != null
                ? TabBar(
                    controller: _tabController!,
                    indicatorColor: AppTheme.getPrimaryColor(context),
                    labelColor: AppTheme.getTextPrimary(context),
                    tabs: const [
                      Tab(text: 'Create'),
                      Tab(text: 'View'),
                    ],
                  )
                : null,
      ),
      body: _isClient
          ? _buildViewTab()
          : _tabController != null
              ? TabBarView(
                  controller: _tabController!,
                  children: [
                    _buildCreateTab(),
                    _buildViewTab(),
                  ],
                )
              : Center(
                  child: CircularProgressIndicator(
                    valueColor: AlwaysStoppedAnimation<Color>(AppTheme.getPrimaryColor(context)),
                  ),
                ),
    );
  }

  List<String> _getStepTitles() {
    if (widget.projectFixed) {
      return ['Notes', 'Attachments', 'Task & Preview'];
    }
    return ['Project', 'Notes', 'Attachments', 'Task & Preview'];
  }

  List<String> _getStepInstructions() {
    if (widget.projectFixed) {
      return ['Add visit notes', 'Add attachments', 'Set task & review'];
    }
    return ['Select project', 'Add visit notes', 'Add attachments', 'Set task & review'];
  }

  bool _isStepCompleted(int stepIndex) {
    final adjustedIndex = widget.projectFixed ? stepIndex : stepIndex;
    switch (adjustedIndex) {
      case 0:
        return widget.projectFixed ? true : _createProject != null;
      case 1:
        return _noteController.text.trim().isNotEmpty;
      case 2:
        return selectedPictures.isNotEmpty; // Attachments are mandatory
      case 3:
        return _createProject != null && _noteController.text.trim().isNotEmpty && selectedPictures.isNotEmpty;
      default:
        return false;
    }
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

  Widget _buildCreateTab() {
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
                children: widget.projectFixed
                    ? [
                        _buildStep1Notes(),
                        _buildStep2Attachments(),
                        _buildStep3TaskPreview(),
                      ]
                    : [
                        _buildStep1Project(),
                        _buildStep2Notes(),
                        _buildStep3Attachments(),
                        _buildStep4TaskPreview(),
                      ],
              ),
            ),
            _buildNavigationButtons(),
          ],
        );
      },
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
            isCompleted: _createProject != null,
            instruction: 'Choose the project for this site visit report',
          ),
          SizedBox(height: 24),
          InkWell(
            onTap: widget.projectFixed ? null : () async {
              await _openProjectPicker(forCreate: true);
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
                      _createProject != null
                          ? (_createProject['name']?.toString() ?? 'Project')
                          : 'Select a project',
                      style: TextStyle(
                        color: _createProject != null
                            ? AppTheme.getTextPrimary(context)
                            : AppTheme.getTextSecondary(context),
                        fontSize: 16,
                        fontWeight: _createProject != null
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

  Widget _buildStep1Notes() {
    return SingleChildScrollView(
      padding: EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildSectionHeader(
            'Visit Notes',
            Icons.note,
            isCompleted: _noteController.text.trim().isNotEmpty,
            instruction: 'Add visit summary, observations, follow-ups',
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
            child: TextField(
              controller: _noteController,
              minLines: 4,
              maxLines: 8,
              enabled: !_submitting,
              style: TextStyle(color: AppTheme.getTextPrimary(context)),
              onChanged: (value) {
                setState(() {});
              },
              decoration: InputDecoration(
                hintText: 'Add visit summary, observations, follow-ups…',
                hintStyle: TextStyle(color: AppTheme.getTextSecondary(context)),
                border: InputBorder.none,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStep2Notes() {
    return _buildStep1Notes();
  }

  Widget _buildStep2Attachments() {
    return SingleChildScrollView(
      padding: EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildSectionHeader(
            'Attachments',
            Icons.attach_file,
            isCompleted: selectedPictures.isNotEmpty,
            instruction: 'Add photos or files (required)',
          ),
          SizedBox(height: 24),
          InkWell(
            onTap: _submitting ? null : _showImageSourceDialog,
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
                  Icon(Icons.add_a_photo, color: AppTheme.getPrimaryColor(context), size: 24),
                  SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      attachPictureButtonText,
                      style: TextStyle(
                        color: AppTheme.getTextPrimary(context),
                        fontWeight: FontWeight.w600,
                        fontSize: 16,
                      ),
                    ),
                  ),
                  Icon(Icons.chevron_right, color: AppTheme.getTextSecondary(context), size: 20),
                ],
              ),
            ),
          ),
          if (selectedPictures.isNotEmpty) ...[
            SizedBox(height: 16),
            SizedBox(
              height: 120,
              child: ListView.builder(
                scrollDirection: Axis.horizontal,
                itemCount: selectedPictures.length,
                itemBuilder: (context, index) {
                  return Container(
                    margin: EdgeInsets.only(right: 12),
                    child: Stack(
                      children: [
                        InkWell(
                          onTap: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (context) => FullScreenImage(selectedPictures[index]),
                              ),
                            );
                          },
                          child: Container(
                            width: 120,
                            height: 120,
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(12),
                              image: DecorationImage(
                                image: selectedPictures[index],
                                fit: BoxFit.cover,
                              ),
                              border: Border.all(color: AppTheme.getPrimaryColor(context).withOpacity(0.2)),
                            ),
                          ),
                        ),
                        Positioned(
                          top: 4,
                          right: 4,
                          child: GestureDetector(
                            onTap: () => _removeAttachment(index),
                            child: Container(
                              padding: EdgeInsets.all(4),
                              decoration: BoxDecoration(
                                color: Colors.red,
                                shape: BoxShape.circle,
                              ),
                              child: Icon(Icons.close, size: 16, color: Colors.white),
                            ),
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildStep3Attachments() {
    return _buildStep2Attachments();
  }

  Widget _buildStep3TaskPreview() {
    return _buildStep4TaskPreview();
  }

  Widget _buildStep4TaskPreview() {
    return SingleChildScrollView(
      padding: EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildSectionHeader(
            'Task Settings',
            Icons.task,
            instruction: 'Mark as task and set due date (optional)',
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
            ),
            child: SwitchListTile(
              contentPadding: EdgeInsets.zero,
              activeColor: AppTheme.getPrimaryColor(context),
              title: Text(
                'This note requires action',
                style: TextStyle(color: AppTheme.getTextPrimary(context)),
              ),
              subtitle: Text(
                'Flag the visit note as a task for quick follow-up.',
                style: TextStyle(color: AppTheme.getTextSecondary(context)),
              ),
              value: _isTask,
              onChanged: _submitting
                  ? null
                  : (value) {
                      setState(() {
                        _isTask = value;
                        if (!value) _dueDate = null;
                      });
                    },
            ),
          ),
          if (_isTask) ...[
            SizedBox(height: 16),
            InkWell(
              onTap: _submitting ? null : _selectDueDate,
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
                        _dueDate == null
                            ? 'Select due date'
                            : DateFormat('d MMM yyyy').format(_dueDate!),
                        style: TextStyle(
                          color: _dueDate == null ? AppTheme.getTextSecondary(context) : AppTheme.getTextPrimary(context),
                          fontWeight: _dueDate == null ? FontWeight.normal : FontWeight.w600,
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
          SizedBox(height: 24),
          _buildSectionHeader(
            'Preview',
            Icons.preview,
            instruction: 'Review your site visit report before submitting',
          ),
          SizedBox(height: 16),
          _buildPreviewCard('Project', _createProject != null ? (_createProject['name']?.toString() ?? 'Project') : 'Not selected', Icons.folder_special),
          SizedBox(height: 12),
          _buildPreviewCard('Notes', _noteController.text.trim().isNotEmpty ? _noteController.text.trim() : 'No notes', Icons.note),
          SizedBox(height: 12),
          _buildPreviewCard('Attachments', selectedPictures.isNotEmpty ? '${selectedPictures.length} file(s)' : 'No attachments', Icons.attach_file),
          if (_isTask) ...[
            SizedBox(height: 12),
            _buildPreviewCard('Due Date', _dueDate != null ? DateFormat('d MMM yyyy').format(_dueDate!) : 'Not set', Icons.calendar_today),
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
                onTap: _submitting
                    ? null
                    : (_currentStep == _totalSteps - 1
                        ? () async {
                            await _submitReport();
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
                      if (_submitting) ...[
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
                        color: AppTheme.getTextSecondary(context),
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
                              color: AppTheme.getTextPrimary(context),
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                        if (!widget.projectFixed)
                          TextButton(
                            onPressed: _fetchingReports ? null : () => _openProjectPicker(forCreate: false),
                            child: Text('Change'),
                          ),
                        if (_viewProject != null && !widget.projectFixed)
                          IconButton(
                            icon: Icon(Icons.close, color: AppTheme.getTextSecondary(context)),
                            onPressed: _fetchingReports
                                ? null
                                : () {
                                    setState(() {
                                      _viewProject = null;
                                      _reports = [];
                                      _hasSearched = false;
                                      _reportsError = null;
                                    });
                                  },
                          ),
                        
                      ],
                    ),
                    Divider(height: 24),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      activeColor: AppTheme.getPrimaryColor(context),
                      thumbColor: MaterialStateProperty.all(Colors.white),
                      title: Text(
                        'Only my reports',
                        style: TextStyle(color: AppTheme.getTextPrimary(context)),
                      ),
                      value: _myReportsOnly,
                      onChanged: _fetchingReports
                          ? null
                          : (value) {
                              setState(() {
                                _myReportsOnly = value;
                              });
                              // Auto-trigger search when toggle changes
                              _fetchReports();
                            },
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
                  label: Text(_viewProject == null ? 'View All Projects' : 'Refresh Reports'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.getPrimaryColor(context),
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
                      valueColor: AlwaysStoppedAnimation<Color>(AppTheme.getPrimaryColor(context)),
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
                  message: _viewProject == null 
                      ? 'Click "View All Projects" to see all site visit reports.'
                      : 'Search to view site visit reports.',
                )
              else
                ..._reports.map((report) => _ReportTile(
                      report: report,
                      onLaunchUrl: _launchURL,
                      isImage: _isImage,
                    )).toList(),
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
            color: AppTheme.getPrimaryColor(context),
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        SizedBox(width: 12),
        Text(
          title,
          style: TextStyle(
            fontWeight: FontWeight.bold,
            fontSize: 16,
                            color: AppTheme.getTextPrimary(context),
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
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppTheme.getPrimaryColor(context).withOpacity(0.08)),
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
        color: Theme.of(context).colorScheme.surface.withOpacity(0.5),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppTheme.getPrimaryColor(context).withOpacity(0.05)),
      ),
      child: Column(
        children: [
          Icon(icon, size: 40, color: AppTheme.getTextSecondary(context)),
          SizedBox(height: 12),
          Text(
            message,
            textAlign: TextAlign.center,
            style: TextStyle(color: AppTheme.getTextSecondary(context)),
          ),
        ],
      ),
    );
  }
}

class _ReportTile extends StatelessWidget {
  final Map<String, dynamic> report;
  final Function(String) onLaunchUrl;
  final bool Function(String) isImage;

  const _ReportTile({
    required this.report,
    required this.onLaunchUrl,
    required this.isImage,
  });

  String _formatDate(String? value) {
    if (value == null) return '--';
    try {
      final date = DateTime.parse(value);
      // Add 5.5 hours (IST offset from UTC)
      final adjustedDate = date.add(Duration(hours: 5, minutes: 30));
      return DateFormat('d MMM yyyy • h:mm a').format(adjustedDate);
    } catch (_) {
      return value;
    }
  }

  String _formatDueDate(String value) {
    try {
      final date = DateTime.parse(value);
      return DateFormat('d MMM yyyy').format(date);
    } catch (_) {
      return value;
    }
  }

  @override
  Widget build(BuildContext context) {
    final createdBy = report['created_by'];

    String projectLabel;
    // Check for project_name from the API response first
    final projectData = report['project'];
    if (projectData != null && projectData is Map<String, dynamic>) {
      if (projectData['project_name'] != null && projectData['project_name'].toString().isNotEmpty) {
        projectLabel = projectData['project_name'].toString();
      } else if (projectData['name'] != null && projectData['name'].toString().isNotEmpty) {
        projectLabel = projectData['name'].toString();
      } else {
        projectLabel = 'Project #${projectData['id'] ?? projectData['project_id'] ?? '--'}';
      }
    } else if (report['project_name'] != null && report['project_name'].toString().isNotEmpty) {
      // Fallback: check if project_name is directly in report
      projectLabel = report['project_name'].toString();
    } else {
      projectLabel = 'Project #${report['project_id'] ?? '--'}';
    }

    final dateLabel = _formatDate(report['created_at']?.toString());
    final note = report['note']?.toString() ?? '';
    final isTask = report['is_task'] == true || report['is_task'] == 1 || report['is_task'] == '1';
    final dueDate = report['due_date']?.toString();
    
    // Support both 'attachment' and 'attachment_url' fields
    String? attachment = report['attachment']?.toString();
    String? attachmentUrl = report['attachment_url']?.toString();
    
    if (attachmentUrl == null && attachment != null && attachment != '0' && attachment.isNotEmpty) {
      attachmentUrl = "https://office1.buildahome.in/files/$attachment";
    }

    return Container(
      margin: EdgeInsets.only(bottom: 16),
      padding: EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppTheme.getPrimaryColor(context).withOpacity(0.06)),
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
                    color: AppTheme.getTextPrimary(context),
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
            style: TextStyle(color: AppTheme.getTextPrimary(context).withOpacity(0.9)),
          ),
          if (isTask && dueDate != null && dueDate.isNotEmpty && dueDate != 'null') ...[
            SizedBox(height: 8),
            Row(
              children: [
                Icon(Icons.calendar_month, size: 14, color: Colors.orange),
                SizedBox(width: 4),
                Text(
                  'Due: ${_formatDueDate(dueDate)}',
                  style: TextStyle(
                    color: Colors.orange[800],
                    fontWeight: FontWeight.w600,
                    fontSize: 13,
                  ),
                ),
              ],
            ),
          ],
          if (attachmentUrl != null && attachmentUrl.isNotEmpty) ...[
            SizedBox(height: 16),
            if (isImage(attachmentUrl))
              GestureDetector(
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => FullScreenImage(NetworkImage(attachmentUrl!)),
                    ),
                  );
                },
                child: Hero(
                  tag: attachmentUrl,
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: CachedNetworkImage(
                      imageUrl: attachmentUrl,
                      placeholder: (context, url) => Container(
                        width: 150,
                        height: 150,
                        decoration: BoxDecoration(
                          color: AppTheme.getBackgroundPrimaryLight(context),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Center(
                          child: SizedBox(
                            width: 24,
                            height: 24,
                            child: CircularProgressIndicator(strokeWidth: 2, color: AppTheme.getPrimaryColor(context)),
                          ),
                        ),
                      ),
                      errorWidget: (context, url, error) => Container(
                        width: 150,
                        height: 150,
                        decoration: BoxDecoration(
                          color: AppTheme.getBackgroundPrimaryLight(context),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: const Icon(Icons.error_outline, color: Colors.redAccent),
                      ),
                      width: 150,
                      height: 150,
                      fit: BoxFit.cover,
                    ),
                  ),
                ),
              )
            else
              OutlinedButton.icon(
                onPressed: () => onLaunchUrl(attachmentUrl!),
                icon: const Icon(Icons.attach_file),
                label: const Text('View attachment'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppTheme.getPrimaryColor(context),
                  side: BorderSide(color: AppTheme.getPrimaryColor(context).withOpacity(0.5)),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
              ),
          ],
          SizedBox(height: 16),
          Row(
            children: [
              Icon(Icons.person_outline, size: 16, color: AppTheme.getTextSecondary(context)),
              SizedBox(width: 6),
              Expanded(
                child: Text(
                  report['user_name']?.toString() ?? 
                  (createdBy != null
                      ? (createdBy['name']?.toString() ?? 'User #${createdBy['id']}')
                      : 'User #${report['created_by_user_id'] ?? '--'}'),
                  style: TextStyle(color: AppTheme.getTextSecondary(context), fontSize: 12),
                ),
              ),
            ],
          ),
          SizedBox(height: 6),
          Row(
            children: [
              Icon(Icons.calendar_today_outlined, size: 16, color: AppTheme.getTextSecondary(context)),
              SizedBox(width: 6),
              Text(
                dateLabel,
                style: TextStyle(color: AppTheme.getTextSecondary(context), fontSize: 12),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

