import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:intl/intl.dart';
import 'package:shimmer/shimmer.dart';
import 'package:file_picker/file_picker.dart';
import 'package:image_picker/image_picker.dart';
import 'dart:convert';
import 'ShowAlert.dart';
import 'app_theme.dart';
import 'projects.dart';
import 'widgets/dark_mode_toggle.dart';

class RequestDrawingLayout extends StatefulWidget {
  @override
  _RequestDrawingLayoutState createState() => _RequestDrawingLayoutState();
}

class _RequestDrawingLayoutState extends State<RequestDrawingLayout> with SingleTickerProviderStateMixin {
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      key: _scaffoldKey,
      backgroundColor: AppTheme.getBackgroundPrimary(context),
      appBar: AppBar(
        automaticallyImplyLeading: true,
        backgroundColor: AppTheme.getBackgroundSecondary(context),
        elevation: 0,
        title: Text('Request Drawings'),
        actions: [
          DarkModeToggle(showLabel: false),
          SizedBox(width: 8),
        ],
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: AppTheme.getPrimaryColor(context),
          labelColor: AppTheme.getTextPrimary(context),
          tabs: const [
            Tab(text: 'Create'),
            Tab(text: 'View'),
          ],
        ),
      ),
      body: SafeArea(child: RequestDrawing(tabController: _tabController)),
    );
  }
}

class RequestDrawing extends StatefulWidget {
  final TabController? tabController;
  
  RequestDrawing({this.tabController});

  @override
  RequestDrawingState createState() => RequestDrawingState();
}

class RequestDrawingState extends State<RequestDrawing> {
  String? userId;
  String? projectName;
  String? projectId;
  String category = 'Select category';
  String drawing = 'Select drawing';
  bool _isSubmitting = false;
  bool _isLoadingPrefs = true;
  final GlobalKey<_ViewRequestsPageState> _viewRequestsPageKey = GlobalKey<_ViewRequestsPageState>();
  TabController? get _tabController => widget.tabController;

  final Map<String, List<String>> drawingsSet = {
    'Architectural': [
      'Working Drawings',
      'Misc Details',
      'Filter slab layout',
      'Sections',
      '2D elevation',
      'Door window details, Window grill details',
      'Flooring layout details',
      'Toilet kitchen dadoing details',
      'Compound wall details',
      'Fabrication details',
      'Sky light details',
      'External and internal paint shades',
      'Isometric views',
      '3D drawings'
    ],
    'Structural': [
      'Column marking',
      'Footing layout',
      'UG sump details',
      'Plinth beam layout',
      'Staircase details',
      'Floor form work beam and slab reinforcement details',
      'OHT slab details',
      'Lintel details'
    ],
    'Electrical': ['Electrical drawing', 'Conduit drawing'],
    'Plumbing': ['Water line drawing', 'Drainage line drawing', 'RWH details']
  };

  final TextEditingController purposeTextController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _loadDefaults();
  }

  Future<void> _loadDefaults() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      userId = prefs.getString('user_id');
      projectId = prefs.getString('project_id');
      projectName = prefs.getString('client_name');
      _isLoadingPrefs = false;
    });
  }

  @override
  void dispose() {
    purposeTextController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoadingPrefs) {
      return Center(
        child: CircularProgressIndicator(
          valueColor: AlwaysStoppedAnimation<Color>(AppTheme.primaryColorConst),
        ),
      );
    }

    return TabBarView(
      controller: _tabController,
      children: [
        CreateRequestPage(
          userId: userId,
          projectId: projectId,
          projectName: projectName,
          category: category,
          drawing: drawing,
          purposeTextController: purposeTextController,
          isSubmitting: _isSubmitting,
          drawingsSet: drawingsSet,
          onCategoryChanged: (value) => setState(() => category = value),
          onDrawingChanged: (value) => setState(() => drawing = value),
          onSubmit: () => _submitRequest(context),
          onProjectPicker: () => _openProjectPicker(context),
          onRefresh: () {
            _loadDefaults();
          },
        ),
        ViewRequestsPage(
          key: _viewRequestsPageKey,
          projectId: projectId,
          projectName: projectName,
          userId: userId,
        ),
      ],
    );
  }


  Future<void> _openProjectPicker(BuildContext context) async {
    final projectDetails = await showDialog(
      context: context,
      builder: (BuildContext context) {
        return ProjectsModal(userId ?? '');
      },
    );

    if (projectDetails != null) {
      final details = projectDetails.split("|");
      if (details.length >= 2) {
        setState(() {
          projectName = details[0];
          projectId = details[1];
        });
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString('client_name', projectName ?? '');
        await prefs.setString('project_id', projectId ?? '');
      }
    }
  }

  Future<void> _submitRequest(BuildContext context) async {
    if (projectId == null) {
      _showSnack(context, 'Please link a project to continue.');
      return;
    }

    if (userId == null) {
      _showSnack(context, 'We could not find your account. Please sign in again.');
      return;
    }

    if (category == 'Select category') {
      _showSnack(context, 'Please select a category.');
      return;
    }

    if (drawing == 'Select drawing') {
      if (category == 'Custom') {
        _showSnack(context, 'Please enter a custom drawing name.');
      } else {
        _showSnack(context, 'Please select a drawing.');
      }
      return;
    }

    setState(() {
      _isSubmitting = true;
    });

    showDialog(
      barrierDismissible: false,
      context: context,
      builder: (BuildContext context) {
        return ShowAlert("Submitting your request...", true);
      },
    );

    try {
      final formattedDate = DateFormat('EEEE d MMMM HH:mm').format(DateTime.now());
      final response = await http.post(
        Uri.parse('https://office1\.buildahome.in/API/create_drawing_request'),
        body: {
          'project_id': projectId,
          'category': category,
          'drawing': drawing,
          'purpose': purposeTextController.text.trim(),
          'user_id': userId,
          'timestamp': formattedDate,
        },
      );

      print("create drawing request: ${response.body}");

      Navigator.of(context, rootNavigator: true).pop(); // Close loader

      if (response.statusCode >= 200 && response.statusCode < 300) {
        // Reset form
        setState(() {
          category = 'Select category';
          drawing = 'Select drawing';
          purposeTextController.clear();
        });

        // Show success dialog and then switch to View page
        showDialog(
          context: context,
          builder: (BuildContext context) {
            return ShowAlert("Request created successfully", false);
          },
        ).then((_) {
          // Switch to View page after dialog closes
          if (_tabController != null) {
            _tabController!.animateTo(1);
            // Refresh the view page after switching
            Future.delayed(Duration(milliseconds: 400), () {
              _viewRequestsPageKey.currentState?.refreshRequests();
            });
          } else {
            // Refresh the view page even if we can't switch tabs
            _viewRequestsPageKey.currentState?.refreshRequests();
          }
        });
      } else {
        _showSnack(context, 'Unable to submit request. Please try again.');
      }
    } catch (e) {
      Navigator.of(context, rootNavigator: true).pop();
      _showSnack(context, 'Something went wrong. Please try again.');
    } finally {
      if (mounted) {
        setState(() {
          _isSubmitting = false;
        });
      }
    }
  }

  void _showSnack(BuildContext context, String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }
}

class _TimelineStep {
  final String title;
  final String subtitle;

  _TimelineStep(this.title, this.subtitle);
}

// Create Request Page Widget
class CreateRequestPage extends StatefulWidget {
  final String? userId;
  final String? projectId;
  final String? projectName;
  final String category;
  final String drawing;
  final TextEditingController purposeTextController;
  final bool isSubmitting;
  final Map<String, List<String>> drawingsSet;
  final ValueChanged<String> onCategoryChanged;
  final ValueChanged<String> onDrawingChanged;
  final VoidCallback onSubmit;
  final VoidCallback onProjectPicker;
  final VoidCallback onRefresh;

  const CreateRequestPage({
    Key? key,
    required this.userId,
    required this.projectId,
    required this.projectName,
    required this.category,
    required this.drawing,
    required this.purposeTextController,
    required this.isSubmitting,
    required this.drawingsSet,
    required this.onCategoryChanged,
    required this.onDrawingChanged,
    required this.onSubmit,
    required this.onProjectPicker,
    required this.onRefresh,
  }) : super(key: key);

  @override
  State<CreateRequestPage> createState() => _CreateRequestPageState();
}

class _CreateRequestPageState extends State<CreateRequestPage> {
  late TextEditingController _customDrawingController;

  @override
  void initState() {
    super.initState();
    _customDrawingController = TextEditingController(
      text: widget.drawing != 'Select drawing' ? widget.drawing : '',
    );
  }

  @override
  void didUpdateWidget(CreateRequestPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Reset controller if category changed to Custom or from Custom
    if (widget.category != oldWidget.category) {
      if (widget.category == 'Custom') {
        _customDrawingController.text = '';
        widget.onDrawingChanged('Select drawing');
      }
    }
    // Update controller text if drawing changed externally (but not if it's being reset)
    if (widget.drawing != oldWidget.drawing && widget.drawing != 'Select drawing') {
      if (widget.category == 'Custom') {
        _customDrawingController.text = widget.drawing;
      }
    }
  }

  @override
  void dispose() {
    _customDrawingController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
          padding: EdgeInsets.symmetric(horizontal: 20, vertical: 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildSectionHeader('What do you need?', 'Pick a category and drawing set'),
              SizedBox(height: 18),
              _buildSelectionTile(
                context: context,
                label: 'Category',
            value: widget.category,
                icon: Icons.category_outlined,
                onTap: () => _openCategorySelector(context),
              ),
          if (widget.category != 'Select category') ...[
                SizedBox(height: 16),
                // Show text input for Custom category, otherwise show drawing selector
                if (widget.category == 'Custom')
                  _buildCustomDrawingInput()
                else
                  _buildSelectionTile(
                    context: context,
                    label: 'Drawing',
                    value: widget.drawing,
                    icon: Icons.architecture,
                    onTap: () => _openDrawingSelector(context),
                  ),
              ],
              SizedBox(height: 28),
              _buildSectionHeader('Comments', 'Add context or instructions for our team'),
              SizedBox(height: 10),
              _buildCommentField(),
              SizedBox(height: 30),
              _buildTimelineCard(),
              SizedBox(height: 32),
          _buildSubmitButton(),
            ],
      ),
    );
  }

  Widget _buildSectionHeader(String title, String subtitle) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.bold,
            color: AppTheme.textPrimary,
          ),
        ),
        SizedBox(height: 4),
        Text(
          subtitle,
          style: TextStyle(
            fontSize: 13,
            color: AppTheme.textSecondary,
          ),
        ),
      ],
    );
  }

  Widget _buildCommentField() {
    return Container(
      decoration: BoxDecoration(
        color: AppTheme.getBackgroundSecondary(context),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppTheme.primaryColorConst.withOpacity(0.15)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 12,
            offset: Offset(0, 6),
          ),
        ],
      ),
      child: TextFormField(
        controller: widget.purposeTextController,
        maxLines: 5,
        textCapitalization: TextCapitalization.sentences,
        style: TextStyle(color: AppTheme.getTextPrimary(context)),
        decoration: InputDecoration(
          hintText: 'Example: Need the updated staircase detail for floor 2...',
          hintStyle: TextStyle(color: AppTheme.getTextSecondary(context)),
          border: InputBorder.none,
          contentPadding: EdgeInsets.symmetric(horizontal: 18, vertical: 18),
        ),
      ),
    );
  }

  Widget _buildCustomDrawingInput() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Custom Drawing Name',
          style: TextStyle(
            fontSize: 12,
            color: AppTheme.textSecondary,
            fontWeight: FontWeight.w500,
          ),
        ),
        SizedBox(height: 8),
        Container(
          decoration: BoxDecoration(
            color: AppTheme.getBackgroundSecondary(context),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: AppTheme.primaryColorConst.withOpacity(0.15)),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.04),
                blurRadius: 12,
                offset: Offset(0, 6),
              ),
            ],
          ),
          child: TextFormField(
            controller: _customDrawingController,
            textCapitalization: TextCapitalization.sentences,
            style: TextStyle(color: AppTheme.getTextPrimary(context)),
            decoration: InputDecoration(
              hintText: 'Enter custom drawing name...',
              hintStyle: TextStyle(color: AppTheme.getTextSecondary(context)),
              border: InputBorder.none,
              contentPadding: EdgeInsets.symmetric(horizontal: 18, vertical: 18),
              prefixIcon: Icon(
                Icons.architecture,
                color: AppTheme.primaryColorConst,
              ),
            ),
            onChanged: (value) {
              widget.onDrawingChanged(value.trim().isEmpty ? 'Select drawing' : value.trim());
            },
          ),
        ),
      ],
    );
  }

  Widget _buildTimelineCard() {
    final steps = [
      _TimelineStep('Request submitted', 'We log your requirement instantly'),
      _TimelineStep('Team notified', 'Our architects receive the brief'),
      _TimelineStep('Delivery update', 'You\'ll be notified when it\'s ready'),
    ];

    return Container(
      width: double.infinity,
      padding: EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppTheme.getBackgroundSecondary(context),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppTheme.primaryColorConst.withOpacity(0.12)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 14,
            offset: Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'What happens next?',
            style: TextStyle(
              fontWeight: FontWeight.bold,
              color: AppTheme.textPrimary,
            ),
          ),
          SizedBox(height: 16),
          ...steps.map((step) {
            final isLast = step == steps.last;
            return Padding(
              padding: EdgeInsets.only(bottom: isLast ? 0 : 16),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Column(
                    children: [
                      Container(
                        height: 12,
                        width: 12,
                        decoration: BoxDecoration(
                          color: AppTheme.primaryColorConst,
                          shape: BoxShape.circle,
                        ),
                      ),
                      if (!isLast)
                        Container(
                          width: 2,
                          height: 28,
                          color: AppTheme.primaryColorConst.withOpacity(0.3),
                        ),
                    ],
                  ),
                  SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          step.title,
                          style: TextStyle(
                            fontWeight: FontWeight.w600,
                            color: AppTheme.textPrimary,
                          ),
                        ),
                        SizedBox(height: 4),
                        Text(
                          step.subtitle,
                          style: TextStyle(
                            color: AppTheme.textSecondary,
                            fontSize: 13,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            );
          }).toList(),
        ],
      ),
    );
  }

  Widget _buildSubmitButton() {
    return SizedBox(
      width: double.infinity,
      child: ElevatedButton(
        onPressed: widget.isSubmitting ? null : widget.onSubmit,
        style: ElevatedButton.styleFrom(
          backgroundColor: AppTheme.primaryColorConst,
          padding: EdgeInsets.symmetric(vertical: 18),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18),
          ),
          elevation: 6,
        ),
        child: widget.isSubmitting
            ? SizedBox(
                height: 22,
                width: 22,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                ),
              )
            : Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    'Submit Request',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  SizedBox(width: 8),
                  Icon(Icons.arrow_forward_rounded),
                ],
              ),
      ),
    );
  }

  Widget _buildSelectionTile({
    required BuildContext context,
    required String label,
    required String value,
    required IconData icon,
    required VoidCallback onTap,
  }) {
    final isPlaceholder = value.startsWith('Select');
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(18),
          child: Container(
            padding: EdgeInsets.symmetric(horizontal: 16, vertical: 18),
            decoration: BoxDecoration(
              color: AppTheme.getBackgroundSecondary(context),
              borderRadius: BorderRadius.circular(18),
              border: Border.all(
                color: AppTheme.primaryColorConst.withOpacity(0.15),
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.05),
                  blurRadius: 10,
                  offset: Offset(0, 4),
                ),
              ],
            ),
          child: Row(
            children: [
              Container(
                padding: EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: AppTheme.primaryColorConst.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(icon, color: AppTheme.primaryColorConst),
              ),
              SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      label,
                      style: TextStyle(
                        fontSize: 12,
                        color: AppTheme.textSecondary,
                      ),
                    ),
                    SizedBox(height: 4),
                    Text(
                      value,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: isPlaceholder ? AppTheme.textSecondary : AppTheme.textPrimary,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(Icons.chevron_right, color: AppTheme.textSecondary),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _openCategorySelector(BuildContext context) async {
    // Add "Custom" to the category list
    final categoryList = List<String>.from(widget.drawingsSet.keys.toList())..add('Custom');
    final selectedCategory = await _openSelectionDialog(
      context,
      title: 'Select category',
      items: categoryList,
    );

    if (selectedCategory != null) {
      widget.onCategoryChanged(selectedCategory);
      widget.onDrawingChanged('Select drawing');
    }
  }

  Future<void> _openDrawingSelector(BuildContext context) async {
    final drawings = widget.drawingsSet[widget.category] ?? [];
    final selectedDrawing = await _openDrawingSelectionDialog(
      context,
      drawings: drawings,
    );

    if (selectedDrawing != null && selectedDrawing.isNotEmpty) {
      widget.onDrawingChanged(selectedDrawing);
    }
  }

  Future<String?> _openDrawingSelectionDialog(
    BuildContext context, {
    required List<String> drawings,
  }) {
    final TextEditingController searchController = TextEditingController();
    String searchQuery = '';
    
    return showDialog<String>(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            final filteredDrawings = drawings.where((item) {
              return item.toLowerCase().contains(searchQuery.toLowerCase());
            }).toList();

            return Dialog(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(24),
              ),
              backgroundColor: Colors.transparent,
              child: Container(
                constraints: BoxConstraints(
                  maxHeight: MediaQuery.of(context).size.height * 0.75,
                  maxWidth: 500,
                ),
                decoration: BoxDecoration(
                  color: AppTheme.backgroundSecondary,
                  borderRadius: BorderRadius.circular(24),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.2),
                      blurRadius: 20,
                      offset: Offset(0, 10),
                    ),
                  ],
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Header
                    Container(
                      padding: EdgeInsets.all(24),
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: [
                            AppTheme.primaryColorConst.withOpacity(0.9),
                            AppTheme.primaryColorConstDark,
                          ],
                        ),
                        borderRadius: BorderRadius.only(
                          topLeft: Radius.circular(24),
                          topRight: Radius.circular(24),
                        ),
                      ),
                      child: Row(
                        children: [
                          Container(
                            padding: EdgeInsets.all(10),
                            decoration: BoxDecoration(
                              color: Colors.white.withOpacity(0.2),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Icon(
                              Icons.architecture,
                              color: Colors.white,
                              size: 24,
                            ),
                          ),
                          SizedBox(width: 16),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Select Drawing',
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontSize: 20,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                SizedBox(height: 4),
                                Text(
                                  'Choose from the list or add custom',
                                  style: TextStyle(
                                    color: Colors.white.withOpacity(0.9),
                                    fontSize: 13,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          IconButton(
                            icon: Icon(Icons.close, color: Colors.white),
                            onPressed: () => Navigator.of(context).pop(),
                          ),
                        ],
                      ),
                    ),
                    // Search field
                    Padding(
                      padding: EdgeInsets.all(20),
                      child: Container(
                        decoration: BoxDecoration(
                          color: AppTheme.getBackgroundSecondary(context),
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(
                            color: AppTheme.primaryColorConst.withOpacity(0.2),
                          ),
                        ),
                        child: TextField(
                          controller: searchController,
                          style: TextStyle(color: AppTheme.getTextPrimary(context)),
                          onChanged: (value) {
                            setDialogState(() {
                              searchQuery = value;
                            });
                          },
                          decoration: InputDecoration(
                            hintText: 'Search drawings...',
                            hintStyle: TextStyle(color: AppTheme.getTextSecondary(context)),
                            prefixIcon: Icon(
                              Icons.search,
                              color: AppTheme.getTextSecondary(context),
                            ),
                            suffixIcon: searchQuery.isNotEmpty
                                ? IconButton(
                                    icon: Icon(Icons.clear, color: AppTheme.textSecondary),
                                    onPressed: () {
                                      searchController.clear();
                                      setDialogState(() {
                                        searchQuery = '';
                                      });
                                    },
                                  )
                                : null,
                            border: InputBorder.none,
                            contentPadding: EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 14,
                            ),
                          ),
                        ),
                      ),
                    ),
                    // List of drawings
                    Flexible(
                      child: Container(
                        constraints: BoxConstraints(
                          maxHeight: MediaQuery.of(context).size.height * 0.4,
                        ),
                        child: filteredDrawings.isEmpty
                            ? Padding(
                                padding: EdgeInsets.all(40),
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(
                                      Icons.search_off,
                                      size: 48,
                                      color: AppTheme.textSecondary,
                                    ),
                                    SizedBox(height: 16),
                                    Text(
                                      'No drawings found',
                                      style: TextStyle(
                                        color: AppTheme.textPrimary,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                    SizedBox(height: 8),
                                    Text(
                                      'Try a different search term',
                                      style: TextStyle(
                                        color: AppTheme.textSecondary,
                                        fontSize: 13,
                                      ),
                                    ),
                                  ],
                                ),
                              )
                            : ListView.separated(
                                shrinkWrap: true,
                                padding: EdgeInsets.symmetric(horizontal: 20),
                                itemCount: filteredDrawings.length + 1,
                                separatorBuilder: (_, __) => SizedBox(height: 8),
                                itemBuilder: (context, index) {
                                  if (index == filteredDrawings.length) {
                                    return Material(
                                      color: Colors.transparent,
                                      child: InkWell(
                                        onTap: () async {
                                          Navigator.of(context).pop();
                                          final customDrawing =
                                              await _showOtherDrawingDialog(context);
                                          if (customDrawing != null &&
                                              customDrawing.isNotEmpty) {
                                            Navigator.of(context).pop(customDrawing);
                                          }
                                        },
                                        borderRadius: BorderRadius.circular(14),
                                        child: Container(
                                          padding: EdgeInsets.all(16),
                                          decoration: BoxDecoration(
                                            gradient: LinearGradient(
                                              colors: [
                                                AppTheme.primaryColorConst
                                                    .withOpacity(0.1),
                                                AppTheme.primaryColorConst
                                                    .withOpacity(0.05),
                                              ],
                                            ),
                                            borderRadius: BorderRadius.circular(14),
                                            border: Border.all(
                                              color: AppTheme.primaryColorConst
                                                  .withOpacity(0.3),
                                              width: 2,
                                            ),
                                          ),
                                          child: Row(
                                            children: [
                                              Container(
                                                padding: EdgeInsets.all(10),
                                                decoration: BoxDecoration(
                                                  color: AppTheme.primaryColorConst
                                                      .withOpacity(0.15),
                                                  borderRadius: BorderRadius.circular(10),
                                                ),
                                                child: Icon(
                                                  Icons.add_circle_outline,
                                                  color: AppTheme.primaryColorConst,
                                                  size: 22,
                                                ),
                                              ),
                                              SizedBox(width: 16),
                                              Expanded(
                                                child: Column(
                                                  crossAxisAlignment:
                                                      CrossAxisAlignment.start,
                                                  children: [
                                                    Text(
                                                      'Other',
                                                      style: TextStyle(
                                                        fontWeight: FontWeight.bold,
                                                        fontSize: 16,
                                                        color: AppTheme.textPrimary,
                                                      ),
                                                    ),
                                                    SizedBox(height: 2),
                                                    Text(
                                                      'Enter custom drawing name',
                                                      style: TextStyle(
                                                        fontSize: 12,
                                                        color: AppTheme.textSecondary,
                                                      ),
                                                    ),
                                                  ],
                                                ),
                                              ),
                                              Icon(
                                                Icons.chevron_right,
                                                color: AppTheme.primaryColorConst,
                                              ),
                                            ],
                                          ),
                                        ),
                                      ),
                                    );
                                  }

                                  final value = filteredDrawings[index];
                                  return Material(
                                    color: Colors.transparent,
                                    child: InkWell(
                                      onTap: () => Navigator.of(context).pop(value),
                                      borderRadius: BorderRadius.circular(14),
                                      child: Container(
                                        padding: EdgeInsets.all(16),
                                        decoration: BoxDecoration(
                                          color: Colors.white,
                                          borderRadius: BorderRadius.circular(14),
                                          border: Border.all(
                                            color: AppTheme.primaryColorConst
                                                .withOpacity(0.1),
                                          ),
                                        ),
                                        child: Row(
                                          children: [
                                            Container(
                                              padding: EdgeInsets.all(8),
                                              decoration: BoxDecoration(
                                                color: AppTheme.primaryColorConst
                                                    .withOpacity(0.1),
                                                borderRadius: BorderRadius.circular(10),
                                              ),
                                              child: Icon(
                                                Icons.description_outlined,
                                                color: AppTheme.primaryColorConst,
                                                size: 20,
                                              ),
                                            ),
                                            SizedBox(width: 16),
                                            Expanded(
                                              child: Text(
                                                value,
                                                style: TextStyle(
                                                  fontWeight: FontWeight.w600,
                                                  fontSize: 15,
                                                  color: AppTheme.textPrimary,
                                                ),
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ),
                                  );
                                },
                              ),
                      ),
                    ),
                    SizedBox(height: 20),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  Future<String?> _showOtherDrawingDialog(BuildContext context) {
    final TextEditingController otherController = TextEditingController();
    
    return showDialog<String>(
      context: context,
      builder: (context) {
        return Dialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(24),
          ),
          backgroundColor: Colors.transparent,
          child: Container(
            constraints: BoxConstraints(maxWidth: 400),
            decoration: BoxDecoration(
              color: AppTheme.backgroundSecondary,
              borderRadius: BorderRadius.circular(24),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.2),
                  blurRadius: 20,
                  offset: Offset(0, 10),
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Header
                Container(
                  padding: EdgeInsets.all(24),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [
                        AppTheme.primaryColorConst.withOpacity(0.9),
                        AppTheme.primaryColorConstDark,
                      ],
                    ),
                    borderRadius: BorderRadius.only(
                      topLeft: Radius.circular(24),
                      topRight: Radius.circular(24),
                    ),
                  ),
                  child: Row(
                    children: [
                      Container(
                        padding: EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.2),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Icon(
                          Icons.edit_outlined,
                          color: Colors.white,
                          size: 24,
                        ),
                      ),
                      SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Custom Drawing',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 20,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            SizedBox(height: 4),
                            Text(
                              'Enter the drawing name',
                              style: TextStyle(
                                color: Colors.white.withOpacity(0.9),
                                fontSize: 13,
                              ),
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        icon: Icon(Icons.close, color: Colors.white),
                        onPressed: () => Navigator.of(context).pop(),
                      ),
                    ],
                  ),
                ),
                // Content
                Padding(
                  padding: EdgeInsets.all(24),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Drawing Name',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: AppTheme.textPrimary,
                        ),
                      ),
                      SizedBox(height: 12),
                      Container(
                        decoration: BoxDecoration(
                          color: AppTheme.getBackgroundSecondary(context),
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(
                            color: AppTheme.primaryColorConst.withOpacity(0.2),
                          ),
                        ),
                        child: TextField(
                          controller: otherController,
                          autofocus: true,
                          textCapitalization: TextCapitalization.sentences,
                          maxLines: 2,
                          style: TextStyle(color: AppTheme.getTextPrimary(context)),
                          decoration: InputDecoration(
                            hintText:
                                'e.g., Custom staircase detail, Special railing design...',
                            hintStyle: TextStyle(color: AppTheme.getTextSecondary(context)),
                            border: InputBorder.none,
                            contentPadding: EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 14,
                            ),
                          ),
                        ),
                      ),
                      SizedBox(height: 24),
                      Row(
                        children: [
                          Expanded(
                            child: OutlinedButton(
                              onPressed: () => Navigator.of(context).pop(),
                              style: OutlinedButton.styleFrom(
                                foregroundColor: AppTheme.textPrimary,
                                side: BorderSide(
                                    color: AppTheme.primaryColorConst.withOpacity(0.3)),
                                padding: EdgeInsets.symmetric(vertical: 16),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(14),
                                ),
                              ),
                              child: Text('Cancel'),
                            ),
                          ),
                          SizedBox(width: 12),
                          Expanded(
                            flex: 2,
                            child: ElevatedButton(
                              onPressed: () {
                                final value = otherController.text.trim();
                                if (value.isNotEmpty) {
                                  Navigator.of(context).pop(value);
                                }
                              },
                              style: ElevatedButton.styleFrom(
                                backgroundColor: AppTheme.primaryColorConst,
                                foregroundColor: Colors.white,
                                padding: EdgeInsets.symmetric(vertical: 16),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(14),
                                ),
                                elevation: 0,
                              ),
                              child: Text(
                                'Add',
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<String?> _openSelectionDialog(
    BuildContext context, {
    required String title,
    required List<String> items,
  }) {
    final TextEditingController searchController = TextEditingController();
    String searchQuery = '';

    return showDialog<String>(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            final filteredItems = items.where((item) {
              return item.toLowerCase().contains(searchQuery.toLowerCase());
            }).toList();

            return Dialog(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(24),
              ),
              backgroundColor: Colors.transparent,
              child: Container(
                constraints: BoxConstraints(
                  maxHeight: MediaQuery.of(context).size.height * 0.75,
                  maxWidth: 500,
                ),
                decoration: BoxDecoration(
                  color: AppTheme.backgroundSecondary,
                  borderRadius: BorderRadius.circular(24),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.2),
                      blurRadius: 20,
                      offset: Offset(0, 10),
                    ),
                  ],
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Header
                    Container(
                      padding: EdgeInsets.all(24),
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: [
                            AppTheme.primaryColorConst.withOpacity(0.9),
                            AppTheme.primaryColorConstDark,
                          ],
                        ),
                        borderRadius: BorderRadius.only(
                          topLeft: Radius.circular(24),
                          topRight: Radius.circular(24),
                        ),
                      ),
                      child: Row(
                        children: [
                          Container(
                            padding: EdgeInsets.all(10),
                            decoration: BoxDecoration(
                              color: Colors.white.withOpacity(0.2),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Icon(
                              Icons.category_outlined,
                              color: Colors.white,
                              size: 24,
                            ),
                          ),
                          SizedBox(width: 16),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  title,
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontSize: 20,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                SizedBox(height: 4),
                                Text(
                                  'Choose a category',
                                  style: TextStyle(
                                    color: Colors.white.withOpacity(0.9),
                                    fontSize: 13,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          IconButton(
                            icon: Icon(Icons.close, color: Colors.white),
                            onPressed: () => Navigator.of(context).pop(),
                          ),
                        ],
                      ),
                    ),
                    // Search field
                    Padding(
                      padding: EdgeInsets.all(20),
                      child: Container(
                        decoration: BoxDecoration(
                          color: AppTheme.getBackgroundSecondary(context),
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(
                            color: AppTheme.primaryColorConst.withOpacity(0.2),
                          ),
                        ),
                        child: TextField(
                          controller: searchController,
                          style: TextStyle(color: AppTheme.getTextPrimary(context)),
                          onChanged: (value) {
                            setDialogState(() {
                              searchQuery = value;
                            });
                          },
                          decoration: InputDecoration(
                            hintText: 'Search categories...',
                            hintStyle: TextStyle(color: AppTheme.getTextSecondary(context)),
                            prefixIcon: Icon(
                              Icons.search,
                              color: AppTheme.getTextSecondary(context),
                            ),
                            suffixIcon: searchQuery.isNotEmpty
                                ? IconButton(
                                    icon: Icon(Icons.clear, color: AppTheme.textSecondary),
                                    onPressed: () {
                                      searchController.clear();
                                      setDialogState(() {
                                        searchQuery = '';
                                      });
                                    },
                                  )
                                : null,
                            border: InputBorder.none,
                            contentPadding: EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 14,
                            ),
                          ),
                        ),
                      ),
                    ),
                    // List of categories
                    Flexible(
                      child: Container(
                        constraints: BoxConstraints(
                          maxHeight: MediaQuery.of(context).size.height * 0.4,
                        ),
                        child: filteredItems.isEmpty
                            ? Padding(
                                padding: EdgeInsets.all(40),
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(
                                      Icons.search_off,
                                      size: 48,
                                      color: AppTheme.textSecondary,
                                    ),
                                    SizedBox(height: 16),
                                    Text(
                                      'No categories found',
                                      style: TextStyle(
                                        color: AppTheme.textPrimary,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                    SizedBox(height: 8),
                                    Text(
                                      'Try a different search term',
                                      style: TextStyle(
                                        color: AppTheme.textSecondary,
                                        fontSize: 13,
                                      ),
                                    ),
                                  ],
                                ),
                              )
                            : ListView.separated(
                                shrinkWrap: true,
                                padding: EdgeInsets.symmetric(horizontal: 20),
                                itemCount: filteredItems.length,
                                separatorBuilder: (_, __) => SizedBox(height: 8),
              itemBuilder: (context, index) {
                                  final value = filteredItems[index];
                                  return Material(
                                    color: Colors.transparent,
                                    child: InkWell(
                                      onTap: () => Navigator.of(context).pop(value),
                                      borderRadius: BorderRadius.circular(14),
                                      child: Container(
                                        padding: EdgeInsets.all(16),
                                        decoration: BoxDecoration(
                                          color: AppTheme.getBackgroundSecondary(context),
                                          borderRadius: BorderRadius.circular(14),
                                          border: Border.all(
                                            color: AppTheme.primaryColorConst.withOpacity(0.1),
                                          ),
                                        ),
                                        child: Row(
                                          children: [
                                            Container(
                                              padding: EdgeInsets.all(8),
                                              decoration: BoxDecoration(
                                                color: AppTheme.primaryColorConst.withOpacity(0.1),
                                                borderRadius: BorderRadius.circular(10),
                                              ),
                                              child: Icon(
                                                Icons.category_outlined,
                                                color: AppTheme.primaryColorConst,
                                                size: 20,
                                              ),
                                            ),
                                            SizedBox(width: 16),
                                            Expanded(
                                              child: Text(
                    value,
                                                style: TextStyle(
                                                  fontWeight: FontWeight.w600,
                                                  fontSize: 15,
                                                  color: AppTheme.getTextPrimary(context),
                                                ),
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ),
                                  );
                                },
                              ),
                      ),
                    ),
                    SizedBox(height: 20),
                  ],
            ),
          ),
        );
      },
    );
      },
    );
  }
}

// View Requests Page Widget
class ViewRequestsPage extends StatefulWidget {
  final String? projectId;
  final String? projectName;
  final String? userId;

  const ViewRequestsPage({
    Key? key,
    required this.projectId,
    required this.projectName,
    required this.userId,
  }) : super(key: key);

  @override
  State<ViewRequestsPage> createState() => _ViewRequestsPageState();
}

class _ViewRequestsPageState extends State<ViewRequestsPage> {
  List<dynamic> _requests = [];
  bool _isLoading = true;
  bool _isRefreshing = false;
  String? _errorMessage;
  int _loadRequestId = 0;
  String? _userRole;
  bool _isUploading = false;

  @override
  void initState() {
    super.initState();
    _loadUserRole();
    _loadRequests();
  }

  Future<void> _loadUserRole() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _userRole = prefs.getString('role');
    });
  }

  void refreshRequests() {
    _loadRequests(isRefresh: true);
  }

  Future<void> _loadRequests({bool isRefresh = false}) async {
    // Require project_id to be selected
    if (widget.projectId == null || widget.projectId!.isEmpty) {
      setState(() {
        _isLoading = false;
        _errorMessage = 'No project selected. Please select a project first.';
      });
      return;
    }

    final requestId = ++_loadRequestId;
    setState(() {
      if (isRefresh) {
        _isRefreshing = true;
      } else {
        _isLoading = true;
      }
      _errorMessage = null;
    });

    try {
      // Build query parameters - only send project_id
      final uri = Uri.parse('https://office1\.buildahome.in/API/view_drawings_requests?project_id=${widget.projectId}');
      final response = await http.get(uri).timeout(
            Duration(seconds: 10),
          );

        print(uri.toString());

      print("drawing requests: ${response.body}");

      if (!mounted || requestId != _loadRequestId) return;

      if (response.statusCode != 200) {
        throw Exception('Unable to load drawing requests. Please try again.');
      }

      final data = jsonDecode(response.body);
      if (!mounted || requestId != _loadRequestId) return;

    setState(() {
        _requests = data is List ? data : [];
        _isLoading = false;
        _isRefreshing = false;
        _errorMessage = null;
      });
    } catch (e) {
      if (!mounted || requestId != _loadRequestId) return;
      setState(() {
        _errorMessage = e.toString().replaceAll('Exception: ', '');
        _isLoading = false;
        _isRefreshing = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (widget.projectId == null || widget.projectId!.isEmpty) {
      return _buildEmptyState(
        icon: Icons.assignment_outlined,
        title: 'No Project Selected',
        message: 'Select a project from the Create page to view drawing requests.',
      );
    }

    if (_isLoading) {
      return _buildSkeletonLoader();
    }

    if (_errorMessage != null) {
      return _buildErrorState();
    }

    return RefreshIndicator(
      onRefresh: () => _loadRequests(isRefresh: true),
      color: AppTheme.primaryColorConst,
      child: CustomScrollView(
        slivers: [
          SliverToBoxAdapter(
            child: Padding(
              padding: EdgeInsets.fromLTRB(20, 20, 20, 16),
              child: _buildHeader(),
            ),
          ),
          if (_requests.isEmpty)
            SliverFillRemaining(
              hasScrollBody: false,
              child: Padding(
                padding: EdgeInsets.symmetric(horizontal: 20),
                child: _buildEmptyState(
                  icon: Icons.description_outlined,
                  title: 'No Drawing Requests',
                  message: 'You haven\'t submitted any drawing requests yet.\nCreate one from the Create tab!',
                ),
              ),
            )
          else ...[
            if (_isRefreshing)
              SliverToBoxAdapter(
                child: Padding(
                  padding: EdgeInsets.symmetric(vertical: 8),
                  child: Center(
                    child: SizedBox(
                      height: 20,
                      width: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        valueColor:
                            AlwaysStoppedAnimation<Color>(AppTheme.primaryColorConst),
                      ),
                    ),
                  ),
                ),
              ),
            SliverPadding(
              padding: EdgeInsets.symmetric(horizontal: 20),
              sliver: SliverList(
                delegate: SliverChildBuilderDelegate(
                  (context, index) {
                    final request = _requests[index];
                    return Padding(
                      padding: EdgeInsets.only(bottom: 16),
                      child: _buildRequestCard(request),
                    );
                  },
                  childCount: _requests.length,
                ),
              ),
            ),
          ],
          SliverToBoxAdapter(
            child: SizedBox(height: 20),
          ),
        ],
      ),
    );
  }

  Widget _buildHeader() {
    return Row(
      children: [
        Container(
          padding: EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: AppTheme.primaryColorConst.withOpacity(0.1),
            borderRadius: BorderRadius.circular(14),
          ),
          child: Icon(
            Icons.description_outlined,
            color: AppTheme.primaryColorConst,
            size: 24,
          ),
        ),
        SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Drawing Requests',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: AppTheme.textPrimary,
                ),
              ),
              SizedBox(height: 4),
              Text(
                '${_requests.length} request${_requests.length != 1 ? 's' : ''}',
                style: TextStyle(
                  fontSize: 14,
                  color: AppTheme.textSecondary,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildRequestCard(List<dynamic> request) {
    // Array structure: [project_name, project_id, category, drawing, user_name, timestamp, purpose, request_id, user_id]
    final category = request.length > 2 ? request[2]?.toString() ?? 'N/A' : 'N/A';
    final drawing = request.length > 3 ? request[3]?.toString() ?? 'N/A' : 'N/A';
    final userName = request.length > 4 ? request[4]?.toString() ?? '' : '';
    final timestamp = request.length > 5 ? request[5]?.toString() ?? '' : '';
    final purpose = request.length > 6 ? request[6]?.toString() ?? '' : '';
    final requestId = request.length > 7 ? request[7]?.toString() : null;
    final projectIdFromRequest = request.length > 1 ? request[1]?.toString() : null;
    final projectId = projectIdFromRequest ?? widget.projectId ?? '';
    
    // Status is not in the array, defaulting to pending
    final status = 'pending';
    
    // Check if user can upload drawings: Admin or roles containing "architect", "Head", or "design"
    final canUploadDrawing = _userRole != null && (
      _userRole!.toLowerCase() == 'admin' ||
      _userRole!.toLowerCase().contains('architect') ||
      _userRole!.toLowerCase().contains('head') ||
      _userRole!.toLowerCase().contains('design')
    );

    return Container(
      padding: EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppTheme.backgroundSecondary,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: AppTheme.primaryColorConst.withOpacity(0.1),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: _getCategoryColor(category).withOpacity(0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  Icons.architecture,
                  color: AppTheme.textPrimary,
                  size: 20,
                ),
              ),
              SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            category,
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                              color: AppTheme.textPrimary,
                            ),
                          ),
                        ),
                        _buildStatusChip(status),
                      ],
                    ),
                    SizedBox(height: 6),
                    Text(
                      drawing,
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: AppTheme.textPrimary,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          if (purpose.isNotEmpty) ...[
            SizedBox(height: 16),
            Container(
              padding: EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: AppTheme.backgroundPrimaryLight,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    Icons.comment_outlined,
                    size: 18,
                    color: AppTheme.textSecondary,
                  ),
                  SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      purpose,
                      style: TextStyle(
                        fontSize: 14,
                        color: AppTheme.textPrimary,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
          SizedBox(height: 16),
          Row(
            children: [
              Icon(
                Icons.access_time,
                size: 16,
                color: AppTheme.textSecondary,
              ),
              SizedBox(width: 6),
              Expanded(
                child: Text(
                  timestamp.isNotEmpty ? timestamp : 'Date not available',
                  style: TextStyle(
                    fontSize: 12,
                    color: AppTheme.textSecondary,
                  ),
                ),
              ),
              if (userName.isNotEmpty) ...[
                SizedBox(width: 12),
                Icon(
                  Icons.person_outline,
                  size: 16,
                  color: AppTheme.textSecondary,
                ),
                SizedBox(width: 6),
                Text(
                  userName,
                  style: TextStyle(
                    fontSize: 12,
                    color: AppTheme.textSecondary,
                  ),
                ),
              ],
            ],
          ),
          // Upload Drawing button - only for Admin or roles with "architect", "Head", or "design"
          if (canUploadDrawing && requestId != null && requestId.isNotEmpty) ...[
            SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: _isUploading ? null : () => _showUploadDrawingDialog(requestId, projectId, request),
                icon: Icon(Icons.upload_file, size: 18),
                label: Text('Upload Drawing'),
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
          ],
        ],
      ),
    );
  }

  Color _getCategoryColor(String category) {
    switch (category.toLowerCase()) {
      case 'architectural':
        return Colors.blue;
      case 'structural':
        return Colors.orange;
      case 'electrical':
        return Colors.amber;
      case 'plumbing':
        return Colors.teal;
      case 'custom':
        return Colors.purple;
      default:
        return AppTheme.primaryColorConst;
    }
  }

  Widget _buildStatusChip(String status) {
    Color statusColor;
    String statusText;

    switch (status.toLowerCase()) {
      case 'completed':
      case 'done':
        statusColor = Colors.green;
        statusText = 'Completed';
        break;
      case 'in_progress':
      case 'processing':
        statusColor = Colors.blue;
        statusText = 'In Progress';
        break;
      default:
        statusColor = Colors.orange;
        statusText = 'Pending';
    }

    return Container(
      padding: EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: statusColor.withOpacity(0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: statusColor.withOpacity(0.3),
        ),
      ),
      child: Text(
        statusText,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w600,
          color: statusColor,
        ),
      ),
    );
  }

  Widget _buildSkeletonLoader() {
    return ListView(
      padding: EdgeInsets.symmetric(horizontal: 20, vertical: 20),
      children: [
        _buildSkeletonHeader(),
        SizedBox(height: 20),
        ...List.generate(3, (_) => _buildSkeletonCard()),
      ],
    );
  }

  Widget _buildSkeletonHeader() {
    return Shimmer.fromColors(
      baseColor: AppTheme.backgroundSecondary.withOpacity(0.4),
      highlightColor: AppTheme.getBackgroundSecondary(context).withOpacity(0.35),
      child: Container(
        padding: EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: AppTheme.backgroundSecondary.withOpacity(0.4),
          borderRadius: BorderRadius.circular(18),
        ),
        child: Row(
          children: [
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: AppTheme.getBackgroundSecondary(context),
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    height: 16,
                    width: 150,
                    decoration: BoxDecoration(
                      color: AppTheme.getBackgroundSecondary(context),
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                  SizedBox(height: 8),
                  Container(
                    height: 12,
                    width: 100,
                    decoration: BoxDecoration(
                      color: AppTheme.getBackgroundSecondary(context),
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSkeletonCard() {
    return Shimmer.fromColors(
      baseColor: AppTheme.backgroundSecondary.withOpacity(0.4),
      highlightColor: AppTheme.getBackgroundSecondary(context).withOpacity(0.35),
      child: Container(
        margin: EdgeInsets.only(bottom: 16),
        padding: EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: AppTheme.backgroundSecondary.withOpacity(0.4),
          borderRadius: BorderRadius.circular(18),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: AppTheme.getBackgroundSecondary(context),
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        height: 14,
                        width: double.infinity,
                        decoration: BoxDecoration(
                          color: AppTheme.getBackgroundSecondary(context),
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                      SizedBox(height: 8),
                      Container(
                        height: 16,
                        width: double.infinity,
                        decoration: BoxDecoration(
                          color: AppTheme.getBackgroundSecondary(context),
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            SizedBox(height: 16),
            Container(
              height: 60,
              width: double.infinity,
              decoration: BoxDecoration(
                color: AppTheme.getBackgroundSecondary(context),
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            SizedBox(height: 16),
            Container(
              height: 12,
              width: 150,
              decoration: BoxDecoration(
                color: AppTheme.getBackgroundSecondary(context),
                borderRadius: BorderRadius.circular(8),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildErrorState() {
    return Center(
      child: Padding(
        padding: EdgeInsets.all(40),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: Colors.red.withOpacity(0.1),
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.error_outline,
                size: 48,
                color: Colors.red,
              ),
            ),
            SizedBox(height: 20),
            Text(
              'Error Loading Requests',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: AppTheme.textPrimary,
              ),
            ),
            SizedBox(height: 8),
            Text(
              _errorMessage ?? 'Something went wrong',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 14,
                color: AppTheme.textSecondary,
              ),
            ),
            SizedBox(height: 24),
            ElevatedButton.icon(
              onPressed: () => _loadRequests(),
              icon: Icon(Icons.refresh),
              label: Text('Retry'),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.primaryColorConst,
                padding: EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyState({
    required IconData icon,
    required String title,
    required String message,
  }) {
    return Center(
      child: Padding(
        padding: EdgeInsets.all(40),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: AppTheme.primaryColorConst.withOpacity(0.1),
                shape: BoxShape.circle,
              ),
              child: Icon(
                icon,
                size: 64,
                color: AppTheme.primaryColorConst,
              ),
            ),
            SizedBox(height: 24),
            Text(
              title,
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: AppTheme.textPrimary,
              ),
            ),
            SizedBox(height: 12),
            Text(
              message,
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

  Future<void> _showUploadDrawingDialog(String requestId, String projectId, List<dynamic> request) async {
    String? selectedFilePath;
    String? selectedFileName;

    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          backgroundColor: Theme.of(context).colorScheme.surface,
          title: Row(
            children: [
              Icon(Icons.upload_file, color: AppTheme.primaryColorConst),
              SizedBox(width: 8),
              Text('Upload Drawing'),
            ],
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Please select a drawing file to upload for this request.',
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
                                selectedFileName ?? 'Select Drawing File',
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
                    '* Drawing file is required',
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
              child: Text('Upload'),
            ),
          ],
        ),
      ),
    );

    if (result != null && result['filePath'] != null) {
      await _uploadDrawing(
        requestId,
        projectId,
        result['filePath'] as String,
        request,
      );
    }
  }

  Future<void> _showFileSourceDialog(Function(String?, String?) onFileSelected) async {
    await showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: Theme.of(context).colorScheme.surface,
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

  Future<void> _uploadDrawing(String requestId, String projectId, String filePath, List<dynamic> request) async {
    if (_isUploading) return;

    setState(() {
      _isUploading = true;
    });

    showDialog(
      barrierDismissible: false,
      context: context,
      builder: (BuildContext context) {
        return ShowAlert("Uploading drawing...", true);
      },
    );

    try {
      SharedPreferences prefs = await SharedPreferences.getInstance();
      String? userId = prefs.getString('userId') ?? prefs.getString('user_id');
      
      if (userId == null) {
        throw Exception('User ID not found');
      }

      // Upload drawing file
      final uri = Uri.parse('https://office1\.buildahome.in/API/upload_drawing_for_request');
      final uploadRequest = http.MultipartRequest('POST', uri);
      
      uploadRequest.fields['request_id'] = requestId;
      uploadRequest.fields['project_id'] = projectId;
      uploadRequest.fields['uploaded_by'] = userId;
      
      uploadRequest.files.add(await http.MultipartFile.fromPath('drawing_file', filePath));
      
      final streamedResponse = await uploadRequest.send();
      final response = await http.Response.fromStream(streamedResponse);

      Navigator.of(context, rootNavigator: true).pop(); // Close loader

      if (response.statusCode == 200 || response.statusCode == 201) {
        final decoded = jsonDecode(response.body);
        if (decoded['success'] == true) {
          // Update request status to completed
          await _updateRequestStatus(requestId, 'completed');
          
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Row(
                  children: [
                    Icon(Icons.check_circle, color: Colors.white),
                    SizedBox(width: 8),
                    Text('Drawing uploaded successfully and request marked as completed'),
                  ],
                ),
                backgroundColor: Colors.green,
                duration: Duration(seconds: 3),
              ),
            );
          }
        } else {
          throw Exception(decoded['message'] ?? 'Failed to upload drawing');
        }
      } else {
        final decoded = jsonDecode(response.body);
        throw Exception(decoded['message'] ?? 'Failed to upload drawing');
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
          _isUploading = false;
        });
        _loadRequests(); // Refresh the list
      }
    }
  }

  Future<void> _updateRequestStatus(String requestId, String status) async {
    try {
      final response = await http.post(
        Uri.parse("https://office1\.buildahome.in/API/update_drawing_request_status"),
        body: {
          'request_id': requestId,
          'status': status,
        },
      ).timeout(const Duration(seconds: 20));

      if (response.statusCode == 200) {
        final decoded = jsonDecode(response.body);
        if (decoded['success'] != true) {
          print('[RequestDrawing] Warning: Status update may have failed: ${decoded['message']}');
        }
      } else {
        print('[RequestDrawing] Warning: Status update failed with code ${response.statusCode}');
      }
    } catch (e) {
      print('[RequestDrawing] Error updating status: $e');
      // Don't throw - we still want to show success if upload succeeded
    }
  }
}
