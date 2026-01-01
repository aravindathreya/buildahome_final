import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'widgets/material.dart';
import 'package:intl/intl.dart';
import 'app_theme.dart';
import 'widgets/searchable_select.dart';
import 'widgets/full_screen_message.dart';
import 'widgets/full_screen_progress.dart';
import 'services/data_provider.dart';
import 'package:provider/provider.dart';
import 'providers/theme_provider.dart';

class StockReportLayout extends StatelessWidget {
  const StockReportLayout({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.getBackgroundPrimary(context),
      appBar: AppBar(
        automaticallyImplyLeading: true,
        backgroundColor: AppTheme.getBackgroundSecondary(context),
        title: Text(
          'Stock Report',
          style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600),
        ),
      ),
      body: const SafeArea(child: StockReport()),
    );
  }
}

class StockReport extends StatefulWidget {
  const StockReport({super.key});

  @override
  StockReportState createState() => StockReportState();
}

class StockReportState extends State<StockReport> {
  String? userId;
  String? userName;
  String projectName = 'Select project';
  String? projectId;
  dynamic selectedProject;
  List<TextEditingController> materialsTextController = [TextEditingController()];
  List<TextEditingController> quantitiesTextController = [TextEditingController()];
  List<String> selectedMaterials = ['']; // Track selected material names
  
  // PageView and step management
  late PageController _pageController;
  int _currentStep = 0;
  final int _totalSteps = 3;
  List<dynamic> projects = [];
  bool _isSubmitting = false;

  @override
  void initState() {
    super.initState();
    _pageController = PageController(initialPage: 0);
    _loadUser();
    _loadProjects();
  }

  @override
  void dispose() {
    _pageController.dispose();
    for (final controller in materialsTextController) {
      controller.dispose();
    }
    for (final controller in quantitiesTextController) {
      controller.dispose();
    }
    super.dispose();
  }

  Future<void> _loadUser() async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    userId = prefs.getString('user_id');
    userName = prefs.getString('username');
  }
  
  Future<void> _loadProjects() async {
    await DataProvider().reloadData(force: false);
    setState(() {
      projects = List<dynamic>.from(DataProvider().projects);
    });
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
  
  List<String> _getStepTitles() {
    return [
      'Project',
      'Materials',
      'Preview',
    ];
  }

  List<String> _getStepInstructions() {
    return [
      'Select project',
      'Add materials',
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
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: List.generate(_totalSteps, (index) {
              final isActive = _currentStep == index;
              final isCompleted = _isStepCompleted(index);
              final isLast = index == _totalSteps - 1;
              final stepTitles = _getStepTitles();
              final stepInstructions = _getStepInstructions();

              return Row(
                children: [
                  Container(
                    width: MediaQuery.of(context).size.width / _totalSteps - 40,
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
        );
      },
    );
  }

  bool _isStepCompleted(int stepIndex) {
    switch (stepIndex) {
      case 0:
        return selectedProject != null || projectId != null;
      case 1:
        return materialsTextController.isNotEmpty &&
               materialsTextController.every((c) => c.text.trim().isNotEmpty) &&
               quantitiesTextController.every((c) => c.text.trim().isNotEmpty);
      case 2:
        return selectedProject != null && 
               materialsTextController.isNotEmpty &&
               materialsTextController.every((c) => c.text.trim().isNotEmpty) &&
               quantitiesTextController.every((c) => c.text.trim().isNotEmpty);
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
                  _buildStep2Materials(),
                  _buildStep3Preview(),
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
            isCompleted: selectedProject != null || projectId != null,
            instruction: 'Choose the project for this stock report',
          ),
          SizedBox(height: 24),
          InkWell(
            onTap: () async {
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
                  projectId = result['id']?.toString();
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
                              ? projectName
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
  
  Widget _buildStep2Materials() {
    return SingleChildScrollView(
      padding: EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildSectionHeader(
            'Add Materials',
            Icons.inventory_2,
            isCompleted: materialsTextController.isNotEmpty &&
                         materialsTextController.every((c) => c.text.trim().isNotEmpty) &&
                         quantitiesTextController.every((c) => c.text.trim().isNotEmpty),
            instruction: 'Add materials and their quantities',
          ),
          SizedBox(height: 24),
          ...List.generate(materialsTextController.length, (index) => _buildEntryCard(context, index)),
          SizedBox(height: 12),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: _addEntry,
              icon: Icon(Icons.add, color: AppTheme.getPrimaryColor(context)),
              label: Text(
                'Add another material',
                style: TextStyle(color: AppTheme.getPrimaryColor(context)),
              ),
            ),
          ),
        ],
      ),
    );
  }
  
  Widget _buildStep3Preview() {
    return SingleChildScrollView(
      padding: EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildSectionHeader(
            'Preview',
            Icons.preview,
            instruction: 'Review your stock report before submitting',
          ),
          SizedBox(height: 24),
          _buildPreviewCard('Project', selectedProject != null ? (selectedProject['name']?.toString() ?? 'Project') : projectName, Icons.folder_special),
          SizedBox(height: 12),
          ...List.generate(materialsTextController.length, (index) {
            if (materialsTextController[index].text.trim().isEmpty ||
                quantitiesTextController[index].text.trim().isEmpty) {
              return SizedBox.shrink();
            }
            return Padding(
              padding: EdgeInsets.only(bottom: 12),
              child: _buildPreviewCard(
                'Entry ${index + 1}',
                '${materialsTextController[index].text} - ${quantitiesTextController[index].text}',
                Icons.inventory_2,
              ),
            );
          }),
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


  Widget _buildEntryCard(BuildContext context, int index) {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            AppTheme.getBackgroundSecondary(context),
            AppTheme.getBackgroundPrimaryLight(context),
          ],
        ),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: AppTheme.getPrimaryColor(context).withOpacity(0.15),
          width: materialsTextController[index].text.trim().isNotEmpty &&
                 quantitiesTextController[index].text.trim().isNotEmpty ? 2 : 1,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 8,
            offset: Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: AppTheme.getPrimaryColor(context).withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  '${index + 1}',
                  style: TextStyle(
                    color: AppTheme.getPrimaryColor(context),
                    fontWeight: FontWeight.bold,
                    fontSize: 14,
                  ),
                ),
              ),
              SizedBox(width: 12),
              Expanded(
                child: Text(
                  'Entry ${index + 1}',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: AppTheme.getTextPrimary(context),
                  ),
                ),
              ),
              if (materialsTextController.length > 1)
                IconButton(
                  tooltip: 'Remove entry',
                  icon: Icon(Icons.delete_outline, color: Colors.red),
                  onPressed: () => _removeEntry(index),
                ),
            ],
          ),
          const SizedBox(height: 16),
          _buildMaterialPicker(context, index),
          const SizedBox(height: 16),
          TextField(
            controller: quantitiesTextController[index],
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            style: TextStyle(color: AppTheme.getTextPrimary(context)),
            decoration: InputDecoration(
              labelText: 'Quantity',
              hintText: 'Enter quantity',
              labelStyle: TextStyle(color: AppTheme.getTextSecondary(context)),
              hintStyle: TextStyle(color: AppTheme.getTextSecondary(context)),
              filled: true,
              fillColor: AppTheme.getBackgroundPrimary(context),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(
                  color: AppTheme.getPrimaryColor(context).withOpacity(0.3),
                ),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(
                  color: AppTheme.getPrimaryColor(context).withOpacity(0.3),
                ),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(
                  color: AppTheme.getPrimaryColor(context),
                  width: 2,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMaterialPicker(BuildContext context, int index) {
    final currentValue = materialsTextController[index].text;
    final isPlaceholder = currentValue.isEmpty;
    final displayValue = isPlaceholder ? 'Tap to select material' : currentValue;

    return InkWell(
      onTap: () async {
        final materialDetails = await showDialog<String>(
          context: context,
          builder: (BuildContext context) => Materials(),
        );
        if (!mounted) return;
        if (materialDetails != null) {
          setState(() {
            materialsTextController[index].text = materialDetails;
            if (selectedMaterials.length > index) {
              selectedMaterials[index] = materialDetails;
            }
          });
        }
      },
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        decoration: BoxDecoration(
          color: AppTheme.getBackgroundPrimary(context),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isPlaceholder
                ? AppTheme.getPrimaryColor(context).withOpacity(0.3)
                : AppTheme.getPrimaryColor(context).withOpacity(0.5),
            width: isPlaceholder ? 1 : 2,
          ),
        ),
        child: Row(
          children: [
            Icon(Icons.inventory_2_outlined, color: AppTheme.getPrimaryColor(context)),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                displayValue,
                style: TextStyle(
                  color: isPlaceholder ? AppTheme.getTextSecondary(context) : AppTheme.getTextPrimary(context),
                  fontWeight: isPlaceholder ? FontWeight.w500 : FontWeight.w600,
                  fontSize: 16,
                ),
              ),
            ),
            Icon(Icons.search, color: AppTheme.getTextSecondary(context)),
          ],
        ),
      ),
    );
  }

  void _addEntry() {
    setState(() {
      materialsTextController.add(TextEditingController());
      quantitiesTextController.add(TextEditingController());
      selectedMaterials.add('');
    });
  }

  void _removeEntry(int index) {
    if (materialsTextController.length <= 1) return;
    setState(() {
      final materialController = materialsTextController.removeAt(index);
      final quantityController = quantitiesTextController.removeAt(index);
      selectedMaterials.removeAt(index);
      materialController.dispose();
      quantityController.dispose();
    });
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

    if (materialsTextController.isEmpty) {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => FullScreenMessage(
            title: 'Validation Error',
            message: 'Please add at least one material entry',
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

    final List<String> stockReportEntries = [];
    for (var i = 0; i < materialsTextController.length; i++) {
      if (materialsTextController[i].text.trim().isEmpty) {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => FullScreenMessage(
              title: 'Validation Error',
              message: 'Material cannot be empty for entry ${i + 1}',
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
      if (quantitiesTextController[i].text.trim().isEmpty) {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => FullScreenMessage(
              title: 'Validation Error',
              message: 'Quantity cannot be empty for entry ${i + 1}',
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
      stockReportEntries.add('${materialsTextController[i].text}|${quantitiesTextController[i].text}');
    }

    if (!mounted) return;
    setState(() {
      _isSubmitting = true;
    });

    try {
      // Show progress
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => FullScreenProgress(
            title: 'Submitting',
            message: 'Submitting your stock report...',
            progress: 0.5,
          ),
        ),
      );

      final formattedDate = DateFormat('EEEE d MMMM yyyy H:m').format(DateTime.now());
      final response = await http.post(
        Uri.parse('https://office.buildahome.in/API/update_stock_report'),
        body: {
          'project_id': (selectedProject != null ? selectedProject['id'] : projectId!).toString(),
          'timestamp': formattedDate,
          'stock_report_entries': stockReportEntries.join('^'),
          'user_id': userId,
          'user_name': userName ?? '',
        },
      );

      Navigator.of(context, rootNavigator: true).pop(); // Close progress

      if (!mounted) return;

      if (response.statusCode != 200) {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => FullScreenMessage(
              title: 'Error',
              message: 'Something went wrong. Please try again.',
              icon: Icons.error_outline,
              iconColor: Colors.red,
              buttonText: 'OK',
              onButtonPressed: () => Navigator.pop(context),
            ),
          ),
        );
        return;
      }

      // Reset form
      setState(() {
        projectName = 'Select project';
        projectId = null;
        selectedProject = null;
        _resetEntries();
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
            message: 'Stock report submitted successfully',
            icon: Icons.check_circle,
            iconColor: Colors.green,
            buttonText: 'OK',
            onButtonPressed: () => Navigator.pop(context),
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => FullScreenMessage(
            title: 'Error',
            message: 'Error: ${e.toString()}',
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

  void _resetEntries() {
    for (final controller in materialsTextController) {
      controller.dispose();
    }
    for (final controller in quantitiesTextController) {
      controller.dispose();
    }
    materialsTextController = [TextEditingController()];
    quantitiesTextController = [TextEditingController()];
  }

}
