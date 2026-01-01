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

class TestReportsScreen extends StatefulWidget {
  final String? fixedProjectId;
  final bool projectFixed;
  
  const TestReportsScreen({
    Key? key,
    this.fixedProjectId,
    this.projectFixed = false,
  }) : super(key: key);

  @override
  State<TestReportsScreen> createState() => _TestReportsScreenState();
}

class _TestReportsScreenState extends State<TestReportsScreen> with SingleTickerProviderStateMixin {
  final TextEditingController _commentController = TextEditingController();
  TabController? _tabController;

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

  var selectedPictures = [];
  var selectedPictureFilenames = [];
  var selectedPictureFilePaths = [];
  String attachPictureButtonText = "Add files";
  
  final int maxImageWidth = 1920;
  final int maxImageHeight = 1080;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _tabController!.addListener(_handleTabSelection);
    _primeProjects();
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
      print('[TestReports] Project not found: ${widget.fixedProjectId}');
    }
  }

  @override
  void dispose() {
    _tabController?.removeListener(_handleTabSelection);
    _tabController?.dispose();
    _commentController.dispose();
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
      print('[TestReports] Permission error: $e');
      return Platform.isAndroid && !forCamera; // Default true for gallery on Android
    }
  }

  Future<void> _showImageSourceDialog() async {
    await showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          backgroundColor: Theme.of(context).colorScheme.surface,
          title: const Text('Select File Source', style: TextStyle(fontWeight: FontWeight.bold)),
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
      attachPictureButtonText = "Add more files";
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
              // For non-image files, we'll still try to display them
              try {
                selectedPictures.insert(0, FileImage(File(file.path!)));
              } catch (e) {
                // If it's not an image, we'll handle it differently
                selectedPictures.insert(0, FileImage(File(file.path!)));
              }
              selectedPictureFilenames.insert(0, file.name);
              selectedPictureFilePaths.insert(0, file.path!);
              attachPictureButtonText = "Add more files";
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
        attachPictureButtonText = "Add files";
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

  Future<void> _submitReport() async {
    final comment = _commentController.text.trim();
    if (_createProject == null) {
      _showSnackBar('Please select a project.');
      return;
    }
    if (comment.isEmpty) {
      _showSnackBar('Please enter a comment.');
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
      if (selectedPictureFilePaths.isEmpty) {
        await _submitSingleReport(createdBy, comment, null);
      } else {
        for (String filePath in selectedPictureFilePaths) {
          await _submitSingleReport(createdBy, comment, filePath);
        }
      }

      _showSnackBar('Test report(s) created successfully.');
      setState(() {
        _commentController.clear();
        selectedPictures.clear();
        selectedPictureFilenames.clear();
        selectedPictureFilePaths.clear();
        attachPictureButtonText = "Add files";
      });
    } catch (e) {
      print('Error submitting report: $e');
      _showSnackBar('Error: $e');
    } finally {
      setState(() {
        _submitting = false;
      });
    }
  }

  Future<void> _submitSingleReport(String createdBy, String comment, String? filePath) async {
    http.Response response;
    
    if (filePath != null) {
      final uri = Uri.parse('https://office1.buildahome.in/api/test_reports');
      final request = http.MultipartRequest('POST', uri);
      
      request.fields['created_by_user_id'] = (int.tryParse(createdBy) ?? createdBy).toString();
      request.fields['project_id'] = _createProject['id'].toString();
      request.fields['comment'] = comment;
      
      request.files.add(await http.MultipartFile.fromPath('attachment', filePath));
      
      final streamedResponse = await request.send();
      response = await http.Response.fromStream(streamedResponse);
    } else {
      response = await http.post(
        Uri.parse('https://office1.buildahome.in/api/test_reports'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'created_by_user_id': int.tryParse(createdBy) ?? createdBy,
          'project_id': _createProject['id'],
          'comment': comment,
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
      final uri = Uri.parse('https://office1.buildahome.in/api/test_reports/search')
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
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        title: Text('Test Reports / QC Reports'),
        backgroundColor: Theme.of(context).colorScheme.surface,
        actions: [
          DarkModeToggle(showLabel: false),
          SizedBox(width: 8),
        ],
        bottom: _tabController != null
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
      body: _tabController != null
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
                    color: AppTheme.getTextPrimary(context),
                    fontWeight: FontWeight.w600,
                  ),
                ),
                SizedBox(height: 12),
                if (!widget.projectFixed)
                  ElevatedButton.icon(
                    onPressed: _submitting ? null : () => _openProjectPicker(forCreate: true),
                    icon: Icon(Icons.search),
                    label: Text('Choose project'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppTheme.getPrimaryColor(context),
                      foregroundColor: Colors.white,
                      padding: EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    ),
                  ),
                
              ],
            ),
          ),
          SizedBox(height: 20),
          _SectionHeader(title: 'Comments'),
          _InputCard(
            child: TextField(
              controller: _commentController,
              minLines: 4,
              maxLines: 8,
              enabled: !_submitting,
              decoration: InputDecoration(
                hintText: 'Add your comments, observations, or test results…',
                border: InputBorder.none,
              ),
            ),
          ),
          SizedBox(height: 20),
          _SectionHeader(title: 'Attachments (Optional)'),
          _InputCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                InkWell(
                  onTap: _submitting ? null : _showImageSourceDialog,
                  child: Container(
                    padding: EdgeInsets.symmetric(vertical: 12, horizontal: 16),
                    decoration: BoxDecoration(
                      color: Theme.of(context).scaffoldBackgroundColor,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: AppTheme.getPrimaryColor(context).withOpacity(0.2)),
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.attach_file, color: AppTheme.getPrimaryColor(context)),
                        SizedBox(width: 12),
                        Text(
                          attachPictureButtonText,
                          style: TextStyle(
                            color: AppTheme.getTextPrimary(context),
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        Spacer(),
                        Icon(Icons.chevron_right, color: AppTheme.getTextSecondary(context)),
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
          ),
          SizedBox(height: 30),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: _submitting ? null : _submitReport,
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.getPrimaryColor(context),
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
                  : Text('Create Test Report'),
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
                  message: 'No test reports found for the selected filters.',
                )
              else if (_reports.isEmpty)
                _EmptyState(
                  icon: Icons.travel_explore,
                  message: _viewProject == null 
                      ? 'Click "View All Projects" to see all test reports.'
                      : 'Search to view test reports.',
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
    final comment = report['comment']?.toString() ?? '';
    
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
            ],
          ),
          SizedBox(height: 8),
          Text(
            comment,
            style: TextStyle(color: AppTheme.getTextPrimary(context).withOpacity(0.9)),
          ),
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
                style: TextStyle(color: AppTheme.textSecondary, fontSize: 12),
              ),
            ],
          ),
        ],
      ),
    );
  }
}



