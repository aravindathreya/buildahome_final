import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:intl/intl.dart';
import 'NavMenu.dart';
import 'ShowAlert.dart';
import 'app_theme.dart';
import 'projects.dart';

class RequestDrawingLayout extends StatelessWidget {
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      key: _scaffoldKey,
      backgroundColor: AppTheme.backgroundPrimary,
      appBar: AppBar(
        automaticallyImplyLeading: true,
        backgroundColor: AppTheme.backgroundSecondary,
        elevation: 0,
        title: Text(
          'Request Drawings',
          style: TextStyle(
            color: AppTheme.textPrimary,
            fontWeight: FontWeight.w600,
          ),
        ),
        
      ),
      body: SafeArea(child: RequestDrawing()),
    );
  }
}

class RequestDrawing extends StatefulWidget {
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

    final hasProject = projectId != null && (projectName?.trim().isNotEmpty ?? false);

    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            AppTheme.backgroundSecondary,
            AppTheme.backgroundPrimary,
          ],
        ),
      ),
      child: SafeArea(
        child: SingleChildScrollView(
          padding: EdgeInsets.symmetric(horizontal: 20, vertical: 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildHeroSection(hasProject),
              // SizedBox(height: 20),
              // if (hasProject) _buildInfoHighlights(),
              SizedBox(height: 24),
              if (!hasProject) _buildMissingProjectCard(context),
              if (hasProject) _buildProjectCard(),
              SizedBox(height: 26),
              _buildSectionHeader('What do you need?', 'Pick a category and drawing set'),
              SizedBox(height: 12),
              _buildQuickCategoryChips(),
              SizedBox(height: 18),
              _buildSelectionTile(
                context: context,
                label: 'Category',
                value: category,
                icon: Icons.category_outlined,
                onTap: () => _openCategorySelector(context),
              ),
              if (category != 'Select category') ...[
                SizedBox(height: 16),
                _buildSelectionTile(
                  context: context,
                  label: 'Drawing',
                  value: drawing,
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
              _buildSubmitButton(context),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeroSection(bool hasProject) {
    return AnimatedContainer(
      duration: Duration(milliseconds: 300),
      padding: EdgeInsets.all(22),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            AppTheme.primaryColorConst.withOpacity(0.85),
            AppTheme.primaryColorConstDark,
          ],
        ),
        boxShadow: [
          BoxShadow(
            color: AppTheme.primaryColorConst.withOpacity(0.35),
            blurRadius: 16,
            offset: Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Icon(Icons.draw, color: Colors.white, size: 30),
              ),
              SizedBox(width: 14),
              Expanded(
                child: Text(
                  hasProject ? 'Submit a drawing request' : 'Link a project to continue',
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w700,
                    fontSize: 18,
                  ),
                ),
              ),
            ],
          ),
          SizedBox(height: 18),
          Text(
            hasProject
                ? 'We\'ll share the requested drawings with you as soon as they’re ready.'
                : 'Pick a project so we can route your drawing requests to the right team.',
            style: TextStyle(
              color: Colors.white.withOpacity(0.95),
              fontSize: 15,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInfoHighlights() {
    final highlights = [
      _HighlightData('Average turnaround', '2-4 business days', Icons.schedule),
      _HighlightData('Priority requests', 'Call your coordinator', Icons.support_agent),
      _HighlightData('Status updates', 'Sent to your app notifications', Icons.notifications),
    ];

    return Row(
      children: highlights
          .map(
            (item) => Expanded(
              child: Container(
                margin: EdgeInsets.only(right: item == highlights.last ? 0 : 10),
                padding: EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.85),
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(color: AppTheme.primaryColorConst.withOpacity(0.1)),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.04),
                      blurRadius: 10,
                      offset: Offset(0, 6),
                    ),
                  ],
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(item.icon, size: 20, color: AppTheme.primaryColorConstDark),
                    SizedBox(height: 10),
                    Text(
                      item.title,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: AppTheme.textSecondary,
                      ),
                    ),
                    SizedBox(height: 4),
                    Text(
                      item.subtitle,
                      style: TextStyle(
                        fontSize: 13,
                        color: AppTheme.textPrimary,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          )
          .toList(),
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

  Widget _buildQuickCategoryChips() {
    final quickCategories = ['Architectural', 'Structural', 'Electrical', 'Plumbing'];
    return Wrap(
      spacing: 10,
      runSpacing: 10,
      children: quickCategories.map((item) {
        final isSelected = category == item;
        return ChoiceChip(
          label: Text(item),
          selected: isSelected,
          onSelected: (_) {
            setState(() {
              category = item;
              drawing = 'Select drawing';
            });
          },
          selectedColor: AppTheme.primaryColorConst.withOpacity(0.85),
          labelStyle: TextStyle(
            color: isSelected ? Colors.white : AppTheme.textPrimary,
            fontWeight: FontWeight.w600,
          ),
          backgroundColor: Colors.white,
          shape: StadiumBorder(
            side: BorderSide(color: AppTheme.primaryColorConst.withOpacity(0.2)),
          ),
        );
      }).toList(),
    );
  }

  Widget _buildCommentField() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
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
        controller: purposeTextController,
        maxLines: 5,
        textCapitalization: TextCapitalization.sentences,
        decoration: InputDecoration(
          hintText: 'Example: Need the updated staircase detail for floor 2...',
          border: InputBorder.none,
          contentPadding: EdgeInsets.symmetric(horizontal: 18, vertical: 18),
        ),
      ),
    );
  }

  Widget _buildTimelineCard() {
    final steps = [
      _TimelineStep('Request submitted', 'We log your requirement instantly'),
      _TimelineStep('Team notified', 'Our architects receive the brief'),
      _TimelineStep('Delivery update', 'You’ll be notified when it’s ready'),
    ];

    return Container(
      width: double.infinity,
      padding: EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
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

  Widget _buildSubmitButton(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      child: ElevatedButton(
        onPressed: _isSubmitting ? null : () => _submitRequest(context),
        style: ElevatedButton.styleFrom(
          backgroundColor: AppTheme.primaryColorConst,
          padding: EdgeInsets.symmetric(vertical: 18),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18),
          ),
          elevation: 6,
        ),
        child: _isSubmitting
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

  Widget _buildProjectCard() {
    return Container(
      width: double.infinity,
      padding: EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            AppTheme.backgroundSecondary,
            AppTheme.backgroundPrimaryLight,
          ],
        ),
        borderRadius: BorderRadius.circular(18),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.08),
            blurRadius: 12,
            offset: Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Linked Project',
            style: TextStyle(
              fontSize: 13,
              color: AppTheme.textSecondary,
            ),
          ),
          SizedBox(height: 8),
          Text(
            projectName ?? 'Selected project',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w700,
              color: AppTheme.textPrimary,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMissingProjectCard(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppTheme.primaryColorConst.withOpacity(0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'No project linked',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: AppTheme.textPrimary,
            ),
          ),
          SizedBox(height: 6),
          Text(
            'Select a project from your dashboard to submit drawing requests.',
            style: TextStyle(
              fontSize: 13,
              color: AppTheme.textSecondary,
            ),
          ),
          SizedBox(height: 14),
          OutlinedButton(
            onPressed: () => _openProjectPicker(context),
            style: OutlinedButton.styleFrom(
              foregroundColor: AppTheme.primaryColorConst,
              side: BorderSide(color: AppTheme.primaryColorConst),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
            ),
            child: Text('Select Project'),
          ),
        ],
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
            color: Colors.white,
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
    final selectedCategory = await _openSelectionDialog(
      context,
      title: 'Select category',
      items: drawingsSet.keys.toList(),
    );

    if (selectedCategory != null) {
      setState(() {
        category = selectedCategory;
        drawing = 'Select drawing';
      });
    }
  }

  Future<void> _openDrawingSelector(BuildContext context) async {
    final drawings = drawingsSet[category] ?? [];
    final selectedDrawing = await _openSelectionDialog(
      context,
      title: 'Select drawing',
      items: drawings,
    );

    if (selectedDrawing != null) {
      setState(() {
        drawing = selectedDrawing;
      });
    }
  }

  Future<String?> _openSelectionDialog(
    BuildContext context, {
    required String title,
    required List<String> items,
  }) {
    return showDialog<String>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Text(title),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          content: Container(
            width: double.maxFinite,
            height: MediaQuery.of(context).size.height * 0.5,
            child: ListView.separated(
              itemCount: items.length,
              separatorBuilder: (_, __) => Divider(height: 1),
              itemBuilder: (context, index) {
                final value = items[index];
                return ListTile(
                  title: Text(
                    value,
                    style: TextStyle(fontWeight: FontWeight.w600),
                  ),
                  onTap: () => Navigator.of(context).pop(value),
                );
              },
            ),
          ),
        );
      },
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
      _showSnack(context, 'Please select a drawing.');
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
        Uri.parse('https://office.buildahome.in/API/create_drawing_request'),
        body: {
          'project_id': projectId,
          'category': category,
          'drawing': drawing,
          'purpose': purposeTextController.text.trim(),
          'user_id': userId,
          'timestamp': formattedDate,
        },
      );

      Navigator.of(context, rootNavigator: true).pop(); // Close loader

      if (response.statusCode >= 200 && response.statusCode < 300) {
        showDialog(
          context: context,
          builder: (BuildContext context) {
            return ShowAlert("Request created successfully", false);
          },
        );

        setState(() {
          category = 'Select category';
          drawing = 'Select drawing';
          purposeTextController.clear();
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

class _HighlightData {
  final String title;
  final String subtitle;
  final IconData icon;

  _HighlightData(this.title, this.subtitle, this.icon);
}

class _TimelineStep {
  final String title;
  final String subtitle;

  _TimelineStep(this.title, this.subtitle);
}
