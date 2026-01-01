import 'package:buildAhome/edit_indent.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'widgets/confirmation.dart';
import 'providers/apis.dart';
import "ShowAlert.dart";
import 'package:intl/intl.dart';
import 'package:file_picker/file_picker.dart';
import 'package:permission_handler/permission_handler.dart';
import 'dart:async';
import 'app_theme.dart';
import 'widgets/searchable_select.dart';
import 'widgets/full_screen_message.dart';
import 'widgets/full_screen_progress.dart';
import 'services/data_provider.dart';

class IndentsScreenLayout extends StatelessWidget {
  final int initialTab;

  const IndentsScreenLayout({Key? key, this.initialTab = 0}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final appTitle = 'buildAhome';
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return MaterialApp(
      title: appTitle,
      theme: AppTheme.getLightTheme(),
      darkTheme: AppTheme.getDarkTheme(),
      themeMode: isDark ? ThemeMode.dark : ThemeMode.light,
      home: Scaffold(
        backgroundColor: AppTheme.getBackgroundPrimary(context),
        body: SafeArea(
          child: Column(
            children: [
              // Back button header
              Container(
                padding: EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                child: Row(
                  children: [
                    InkWell(
                      onTap: () => Navigator.pop(context),
                      borderRadius: BorderRadius.circular(12),
                      child: Container(
                        padding: EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: AppTheme.getBackgroundSecondary(context),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: AppTheme.getPrimaryColor(context).withOpacity(0.3),
                            width: 1,
                          ),
                        ),
                        child: Icon(
                          Icons.arrow_back,
                          color: AppTheme.getTextPrimary(context),
                          size: 20,
                        ),
                      ),
                    ),
                    SizedBox(width: 16),
                    Text(
                      'Indents',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        color: AppTheme.getTextPrimary(context),
                      ),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: IndentsScreen(initialTab: initialTab),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class IndentsScreen extends StatefulWidget {
  final int initialTab;

  const IndentsScreen({Key? key, this.initialTab = 0}) : super(key: key);

  @override
  IndentsScreenState createState() {
    return IndentsScreenState();
  }
}

class IndentsScreenState extends State<IndentsScreen> {
  late int selectedTab; // 0: Create, 1: View Open, 2: My Indents
  final GlobalKey<ViewOpenIndentsTabState> _viewOpenIndentsKey = GlobalKey<ViewOpenIndentsTabState>();

  @override
  void initState() {
    super.initState();
    final tab = widget.initialTab;
    selectedTab = (tab >= 0 && tab <= 2) ? tab : 0;
  }

  void _refreshViewOpenIndents() {
    _viewOpenIndentsKey.currentState?.call();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // Filter chip tabs
        Container(
          height: 100,
          padding: EdgeInsets.symmetric(horizontal: 15, vertical: 15),
          child: ListView(
            scrollDirection: Axis.horizontal,
            children: [
              _buildFilterChip('Create', 0),
              SizedBox(width: 10),
              _buildFilterChip('View Open', 1),
              SizedBox(width: 10),
              _buildFilterChip('My Indents', 2),
            ],
          ),
        ),
        // Content based on selected tab
        Expanded(
          child: IndexedStack(
            index: selectedTab,
            children: [
              CreateIndentTab(onIndentCreated: _refreshViewOpenIndents),
              ViewOpenIndentsTab(key: _viewOpenIndentsKey),
              MyIndentsTab(),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildFilterChip(String label, int index) {
    final isSelected = selectedTab == index;
    return FilterChip(
      label: Text(label),
      selected: isSelected,
      onSelected: (selected) {
        setState(() {
          selectedTab = index;
        });
      },
      // Set width to 100%
      selectedColor: AppTheme.getPrimaryColor(context),
      checkmarkColor: Colors.white,
      backgroundColor: Theme.of(context).colorScheme.surface,
      labelStyle: TextStyle(
        color: isSelected ? Colors.white : AppTheme.getTextPrimary(context),
        fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
        fontSize: 14,
      ),
      padding: EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
          color: isSelected 
              ? AppTheme.getPrimaryColor(context) 
              : AppTheme.getPrimaryColor(context).withOpacity(0.3),
          width: isSelected ? 2 : 1,
        ),
      ),
    );
  }
}

// Create Indent Tab
class CreateIndentTab extends StatefulWidget {
  final VoidCallback? onIndentCreated;

  const CreateIndentTab({Key? key, this.onIndentCreated}) : super(key: key);

  @override
  CreateIndentTabState createState() {
    return CreateIndentTabState();
  }
}

class CreateIndentTabState extends State<CreateIndentTab> {
  var user_id;
  var selectedProject;
  var projectId;
  var selectedMaterial;
  var unit = 'Unit';
  var quantityTextController = new TextEditingController();
  var purposeTextController = new TextEditingController();
  var diffCostTextController = new TextEditingController(text: '0');
  var approvalTaken = false;
  var attachedFileName = '';
  var attachedFile;
  var projects = [];
  var materials = [];

  // Upload progress tracking
  double uploadProgress = 0.0;
  String? uploadError;
  String? uploadErrorMessage;
  bool isUploading = false;

  // PageView and step management
  late PageController _pageController;
  int _currentStep = 0;
  final int _totalSteps = 6;

  // Material units list
  final materialUnits = [
    'Bags',
    'CFT',
    'CUM',
    'Load',
    'Kg',
    'MT',
    'Nos',
    'Box',
    'Others',
  ];

  @override
  void initState() {
    super.initState();
    _pageController = PageController(initialPage: 0);
    call();
    loadProjects();
    loadMaterials();
  }

  @override
  void dispose() {
    _pageController.dispose();
    quantityTextController.dispose();
    purposeTextController.dispose();
    diffCostTextController.dispose();
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

  call() async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    user_id = prefs.getString('user_id');
  }

  void loadProjects() async {
    await DataProvider().loadProjects(force: false);
    setState(() {
      projects = DataProvider().projects;
    });
  }

  void loadMaterials() async {
    try {
      var url = "https://office.buildahome.in/API/get_materials";
      var response = await http.get(Uri.parse(url));
      if (response.statusCode == 200) {
        var res = jsonDecode(response.body);
        setState(() {
          materials = res['materials'] ?? [];
        });
      }
    } catch (e) {
      print('[CreateIndentTab] Error loading materials: $e');
    }
  }

  Future<void> checkPermissionStatus() async {
    try {
      final PermissionStatus storageStatus = await Permission.storage.status;
      if (!storageStatus.isGranted) {
        await Permission.storage.request();
      }
    } catch (e) {
      print('[CreateIndentTab] Permission error: $e');
    }
  }

  void getFile() async {
    await checkPermissionStatus();
    try {
      var res = await FilePicker.platform.pickFiles(allowMultiple: false);
      var file = res?.files.first;
      if (file != null && file.path != null) {
        setState(() {
          attachedFile = file;
          var fileSplit = file.path?.split('/');
          attachedFileName = fileSplit != null && fileSplit.isNotEmpty
              ? fileSplit[fileSplit.length - 1]
              : 'Unknown file';
        });
      } else {
        setState(() {
          attachedFileName = '';
          attachedFile = null;
        });
      }
    } catch (e) {
      print('[CreateIndentTab] Error picking file: $e');
      if (mounted) {
        await Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => FullScreenMessage(
              title: 'Error',
              message: 'Failed to pick file: ${e.toString()}',
              icon: Icons.error_outline,
              iconColor: Colors.red,
              buttonText: 'OK',
              onButtonPressed: () => Navigator.pop(context),
            ),
          ),
        );
      }
    }
  }

  bool _isNumeric(String str) {
    return double.tryParse(str) != null;
  }

  List<String> _getStepTitles() {
    return [
      'Select Project',
      'Select Material',
      'Quantity & Unit',
      'Details',
      'Attachment',
      'Preview',
    ];
  }

  List<String> _getStepInstructions() {
    return [
      'Choose the project for this indent',
      'Select the material you need',
      'Enter quantity and select unit',
      'Enter difference cost, approval status, and purpose',
      'Add an attachment file (optional)',
      'Review all information before submitting',
    ];
  }

  bool _isStepCompleted(int stepIndex) {
    switch (stepIndex) {
      case 0:
        return selectedProject != null;
      case 1:
        return selectedMaterial != null && selectedMaterial.isNotEmpty;
      case 2:
        return quantityTextController.text.trim().isNotEmpty && unit != 'Unit';
      case 3:
        return purposeTextController.text.trim().isNotEmpty;
      case 4:
        // Attachment is optional, so always completed
        return true;
      case 5:
        // Preview step is completed if all required steps are completed
        return selectedProject != null && 
               selectedMaterial != null &&
               quantityTextController.text.trim().isNotEmpty &&
               unit != 'Unit' &&
               purposeTextController.text.trim().isNotEmpty;
      default:
        return false;
    }
  }

  Widget _buildStepIndicator() {
    final stepTitles = _getStepTitles();
    final stepInstructions = _getStepInstructions();
    
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 12, vertical: 16),
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
            final isActive = index == _currentStep;
            final isCompleted = _isStepCompleted(index);
            final isLast = index == _totalSteps - 1;
            
            return Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Step circle and text
                Container(
                  width: MediaQuery.of(context).size.width / _totalSteps - 20,
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
                      // Step title
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
                      // Step instruction
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
                // Connector line
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
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // Horizontal step indicator at top
        _buildStepIndicator(),
        // PageView content
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
              _buildStep2Material(),
              _buildStep3QuantityUnit(),
              _buildStep4Details(),
              _buildStep5Attachment(),
              _buildStep6Preview(),
            ],
          ),
        ),
        // Navigation buttons
        _buildNavigationButtons(),
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
            flex: _currentStep == 0 ? 1 : 1,
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: isUploading
                    ? null
                    : (_currentStep == _totalSteps - 1
                        ? () async {
                            // Submit logic
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
                      if (isUploading) ...[
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
                          Icons.cloud_upload,
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

  Future<void> _handleSubmit() async {
    // Validation
    if (selectedProject == null) {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => FullScreenMessage(
            title: 'Validation Error',
            message: 'Please select a project',
            icon: Icons.error_outline,
            iconColor: Colors.red,
            buttonText: 'OK',
            onButtonPressed: () => Navigator.pop(context),
          ),
        ),
      );
      _pageController.animateToPage(
        0,
        duration: Duration(milliseconds: 300),
        curve: Curves.easeInOut,
      );
      return;
    }

    if (selectedMaterial == null || selectedMaterial.isEmpty) {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => FullScreenMessage(
            title: 'Validation Error',
            message: 'Please select a material',
            icon: Icons.error_outline,
            iconColor: Colors.red,
            buttonText: 'OK',
            onButtonPressed: () => Navigator.pop(context),
          ),
        ),
      );
      _pageController.animateToPage(
        1,
        duration: Duration(milliseconds: 300),
        curve: Curves.easeInOut,
      );
      return;
    }

    if (quantityTextController.text.trim() == '') {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => FullScreenMessage(
            title: 'Validation Error',
            message: 'Please enter quantity',
            icon: Icons.error_outline,
            iconColor: Colors.red,
            buttonText: 'OK',
            onButtonPressed: () => Navigator.pop(context),
          ),
        ),
      );
      _pageController.animateToPage(
        2,
        duration: Duration(milliseconds: 300),
        curve: Curves.easeInOut,
      );
      return;
    }

    if (!_isNumeric(quantityTextController.text.trim())) {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => FullScreenMessage(
            title: 'Validation Error',
            message: 'Please enter valid data for quantity',
            icon: Icons.error_outline,
            iconColor: Colors.red,
            buttonText: 'OK',
            onButtonPressed: () => Navigator.pop(context),
          ),
        ),
      );
      return;
    }

    if (unit == 'Unit') {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => FullScreenMessage(
            title: 'Validation Error',
            message: 'Please select a unit',
            icon: Icons.error_outline,
            iconColor: Colors.red,
            buttonText: 'OK',
            onButtonPressed: () => Navigator.pop(context),
          ),
        ),
      );
      _pageController.animateToPage(
        2,
        duration: Duration(milliseconds: 300),
        curve: Curves.easeInOut,
      );
      return;
    }

    if (!_isNumeric(diffCostTextController.text.trim())) {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => FullScreenMessage(
            title: 'Validation Error',
            message: 'Please enter valid data for difference cost',
            icon: Icons.error_outline,
            iconColor: Colors.red,
            buttonText: 'OK',
            onButtonPressed: () => Navigator.pop(context),
          ),
        ),
      );
      return;
    }

    if (purposeTextController.text.trim() == '') {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => FullScreenMessage(
            title: 'Validation Error',
            message: 'Please enter purpose for indent',
            icon: Icons.error_outline,
            iconColor: Colors.red,
            buttonText: 'OK',
            onButtonPressed: () => Navigator.pop(context),
          ),
        ),
      );
      _pageController.animateToPage(
        3,
        duration: Duration(milliseconds: 300),
        curve: Curves.easeInOut,
      );
      return;
    }

    if (!mounted) return;
    setState(() {
      isUploading = true;
      uploadProgress = 0.0;
      uploadError = null;
      uploadErrorMessage = null;
    });

    try {
      // Show progress dialog
      showUploadProgressDialog(0.0);

      DateTime now = DateTime.now();
      String formattedDate = DateFormat('EEEE d MMMM H:m').format(now);
      var url = 'https://office.buildahome.in/API/create_indent';
      var response = await http.post(Uri.parse(url), body: {
        'project_id': projectId.toString(),
        'material': selectedMaterial,
        'quantity': quantityTextController.text.trim(),
        'unit': unit,
        'differenceCost': diffCostTextController.text.trim(),
        'purpose': purposeTextController.text.trim(),
        'approvalTaken': approvalTaken ? '1' : '0',
        'user_id': user_id,
        'timestamp': formattedDate,
      }).timeout(
        Duration(seconds: 30),
        onTimeout: () {
          throw TimeoutException('Request timeout');
        },
      );

      print(response.body);
      var responseBody = jsonDecode(response.body);
      
      if (responseBody['message'] == 'failure') {
        _dismissUploadDialog();
        if (!mounted) return;
        setState(() {
          isUploading = false;
        });
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => FullScreenMessage(
              title: 'Error',
              message: 'Indent failed. ${responseBody['reason'] ?? 'Unknown error'}',
              icon: Icons.error_outline,
              iconColor: Colors.red,
              buttonText: 'OK',
              onButtonPressed: () => Navigator.pop(context),
            ),
          ),
        );
        return;
      }

      var indentId = responseBody['indent_id'];
      
      // Upload file if attached
      if (attachedFileName != '' && attachedFile != null && attachedFile.path != null) {
        showUploadProgressDialog(0.5);
        
        try {
          var uri = Uri.parse("https://office.buildahome.in/API/indent_file_uplpoad");
          var request = new http.MultipartRequest("POST", uri);
          var pic = await http.MultipartFile.fromPath("file", attachedFile.path);
          request.files.add(pic);
          request.fields['indent_id'] = indentId.toString();
          
          var fileResponse = await request.send().timeout(
            Duration(seconds: 60),
            onTimeout: () {
              throw TimeoutException('File upload timeout');
            },
          );
          
          var responseData = await fileResponse.stream.toBytes();
          var responseString = String.fromCharCodes(responseData);
          print(responseString);
        } catch (e) {
          print('[CreateIndentTab] File upload error: $e');
          // Continue even if file upload fails
        }
      }

      _dismissUploadDialog();
      if (!mounted) return;
      
      setState(() {
        isUploading = false;
        // Reset form
        selectedProject = null;
        projectId = null;
        selectedMaterial = null;
        unit = 'Unit';
        quantityTextController.text = '';
        purposeTextController.text = '';
        diffCostTextController.text = '0';
        approvalTaken = false;
        attachedFileName = '';
        attachedFile = null;
        _currentStep = 0;
      });
      
      // Reset to first page
      _pageController.jumpToPage(0);

      // Show success message
      await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => FullScreenMessage(
            title: 'Success',
            message: 'Indent added successfully',
            icon: Icons.check_circle,
            iconColor: Colors.green,
            buttonText: 'OK',
            onButtonPressed: () {
              Navigator.pop(context);
            },
          ),
        ),
      );

      // Refresh the View Open Indents tab
      if (widget.onIndentCreated != null) {
        widget.onIndentCreated!();
      }
    } catch (e) {
      print('[CreateIndentTab] Submit error: $e');
      _dismissUploadDialog();
      if (!mounted) return;
      setState(() {
        isUploading = false;
      });
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => FullScreenMessage(
            title: 'Error',
            message: 'An error occurred: ${e.toString()}',
            icon: Icons.error_outline,
            iconColor: Colors.red,
            buttonText: 'OK',
            onButtonPressed: () => Navigator.pop(context),
          ),
        ),
      );
    }
  }

  bool _uploadDialogShown = false;
  BuildContext? _uploadDialogContext;

  void showUploadProgressDialog(double progress) {
    if (!mounted) return;
    
    if (_uploadDialogShown && _uploadDialogContext != null) {
      try {
        if (Navigator.of(_uploadDialogContext!, rootNavigator: true).canPop()) {
          Navigator.of(_uploadDialogContext!, rootNavigator: true).pop();
        }
      } catch (e) {
        print('[CreateIndentTab] Error dismissing previous dialog: $e');
      }
      _uploadDialogShown = false;
      _uploadDialogContext = null;
    }
    
    Future.delayed(Duration(milliseconds: 100), () {
      if (!mounted) return;
      _uploadDialogShown = true;
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (dialogContext) {
            _uploadDialogContext = dialogContext;
            return FullScreenProgress(
              title: 'Submitting',
              message: progress < 0.5 ? 'Creating indent...' : 'Uploading file...',
              progress: progress,
            );
          },
        ),
      );
    });
  }

  void _dismissUploadDialog() {
    if (!mounted) return;
    if (_uploadDialogShown) {
      if (_uploadDialogContext != null) {
        try {
          if (Navigator.of(_uploadDialogContext!, rootNavigator: true).canPop()) {
            Navigator.of(_uploadDialogContext!, rootNavigator: true).pop();
          }
        } catch (e) {
          print('[CreateIndentTab] Error dismissing dialog: $e');
        }
        _uploadDialogContext = null;
      } else {
        try {
          if (Navigator.of(context, rootNavigator: true).canPop()) {
            Navigator.of(context, rootNavigator: true).pop();
          }
        } catch (e) {
          print('[CreateIndentTab] Error dismissing dialog (fallback): $e');
        }
      }
      _uploadDialogShown = false;
    }
  }

  Widget _buildStep1Project() {
    return SingleChildScrollView(
      padding: EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          _buildSectionHeader(
            'Select Project',
            Icons.folder_special,
            isCompleted: selectedProject != null,
            instruction: 'Choose the project for this indent from the list below',
          ),
          SizedBox(height: 20),

          
          InkWell(
            onTap: () async {
              final result = await SearchableSelect.show(
                context: context,
                title: 'Select Project',
                items: projects,
                itemLabel: (item) => item['name'] ?? 'Unknown',
                selectedItem: selectedProject,
              );
              if (result != null) {
                setState(() {
                  selectedProject = result;
                  projectId = result['id'].toString();
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
                    color: Colors.black.withOpacity(0.2),
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
                          ? (selectedProject['name'] ?? 'Unknown')
                          : 'Select a project',
                      style: TextStyle(
                        color: selectedProject != null
                            ? AppTheme.getTextPrimary(context)
                            : AppTheme.getTextSecondary(context),
                        fontSize: 16,
                        fontWeight: selectedProject != null
                            ? FontWeight.w500
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

  Widget _buildStep2Material() {
    return SingleChildScrollView(
      padding: EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          _buildSectionHeader(
            'Select Material',
            Icons.inventory_2,
            isCompleted: selectedMaterial != null && selectedMaterial.isNotEmpty,
            instruction: 'Choose the material you need from the list below',
          ),
          SizedBox(height: 20),
          InkWell(
            onTap: () async {
              final result = await SearchableSelect.show(
                context: context,
                title: 'Select Material',
                items: materials,
                selectedItem: selectedMaterial,
              );
              if (result != null) {
                setState(() {
                  selectedMaterial = result.toString();
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
                    color: Colors.black.withOpacity(0.2),
                    blurRadius: 8,
                    offset: Offset(0, 4),
                  ),
                ],
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      selectedMaterial != null && selectedMaterial.isNotEmpty
                          ? selectedMaterial
                          : 'Select a material',
                      style: TextStyle(
                        color: selectedMaterial != null && selectedMaterial.isNotEmpty
                            ? AppTheme.getTextPrimary(context)
                            : AppTheme.getTextSecondary(context),
                        fontSize: 16,
                        fontWeight: selectedMaterial != null && selectedMaterial.isNotEmpty
                            ? FontWeight.w500
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

  Widget _buildStep3QuantityUnit() {
    return SingleChildScrollView(
      padding: EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          _buildSectionHeader(
            'Quantity & Unit',
            Icons.scale,
            isCompleted: quantityTextController.text.trim().isNotEmpty && unit != 'Unit',
            instruction: 'Enter the quantity and select the unit of measurement',
          ),
          SizedBox(height: 20),
          Row(
            children: [
              Expanded(
                flex: 2,
                child: Container(
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
                        color: Colors.black.withOpacity(0.2),
                        blurRadius: 8,
                        offset: Offset(0, 4),
                      ),
                    ],
                  ),
                  child: TextFormField(
                    controller: quantityTextController,
                    keyboardType: TextInputType.numberWithOptions(decimal: true),
                    style: TextStyle(
                      fontSize: 16,
                      color: AppTheme.getTextPrimary(context),
                    ),
                    onChanged: (value) {
                      setState(() {});
                    },
                    decoration: InputDecoration(
                      hintText: 'Quantity',
                      hintStyle: TextStyle(color: AppTheme.getTextSecondary(context)),
                      border: InputBorder.none,
                      contentPadding: EdgeInsets.symmetric(horizontal: 0, vertical: 0),
                    ),
                  ),
                ),
              ),
              SizedBox(width: 12),
              Expanded(
                flex: 1,
                child: InkWell(
                  onTap: () {
                    showDialog(
                      context: context,
                      builder: (BuildContext context) {
                        return AlertDialog(
                          backgroundColor: AppTheme.getBackgroundSecondary(context),
                          title: Text(
                            'Select Unit',
                            style: TextStyle(color: AppTheme.getTextPrimary(context)),
                          ),
                          content: Container(
                            width: double.maxFinite,
                            child: ListView.builder(
                              shrinkWrap: true,
                              itemCount: materialUnits.length,
                              itemBuilder: (context, index) {
                                return ListTile(
                                  title: Text(
                                    materialUnits[index],
                                    style: TextStyle(color: AppTheme.getTextPrimary(context)),
                                  ),
                                  onTap: () {
                                    setState(() {
                                      unit = materialUnits[index];
                                    });
                                    Navigator.pop(context);
                                  },
                                );
                              },
                            ),
                          ),
                        );
                      },
                    );
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
                          color: Colors.black.withOpacity(0.2),
                          blurRadius: 8,
                          offset: Offset(0, 4),
                        ),
                      ],
                    ),
                    child: Center(
                      child: Text(
                        unit,
                        style: TextStyle(
                          color: unit != 'Unit'
                              ? AppTheme.getTextPrimary(context)
                              : AppTheme.getTextSecondary(context),
                          fontSize: 16,
                          fontWeight: unit != 'Unit' ? FontWeight.w500 : FontWeight.normal,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildStep4Details() {
    return SingleChildScrollView(
      padding: EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          _buildSectionHeader(
            'Details',
            Icons.edit_note,
            isCompleted: purposeTextController.text.trim().isNotEmpty,
            instruction: 'Enter difference cost, approval status, and purpose for this indent',
          ),
          SizedBox(height: 20),
          Container(
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
                  color: Colors.black.withOpacity(0.2),
                  blurRadius: 8,
                  offset: Offset(0, 4),
                ),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TextFormField(
                  controller: diffCostTextController,
                  keyboardType: TextInputType.numberWithOptions(decimal: true),
                  style: TextStyle(
                    fontSize: 16,
                    color: AppTheme.getTextPrimary(context),
                  ),
                  decoration: InputDecoration(
                    hintText: 'Difference cost',
                    hintStyle: TextStyle(color: AppTheme.getTextSecondary(context)),
                    border: InputBorder.none,
                    contentPadding: EdgeInsets.symmetric(horizontal: 0, vertical: 0),
                  ),
                ),
              ],
            ),
          ),
          SizedBox(height: 16),
          Container(
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
                  color: Colors.black.withOpacity(0.2),
                  blurRadius: 8,
                  offset: Offset(0, 4),
                ),
              ],
            ),
            child: Row(
              children: [
                Checkbox(
                  activeColor: AppTheme.getPrimaryColor(context),
                  value: approvalTaken,
                  onChanged: (value) {
                    setState(() {
                      approvalTaken = value!;
                    });
                  },
                ),
                Expanded(
                  child: Text(
                    'Approval taken',
                    style: TextStyle(
                      fontSize: 16,
                      color: AppTheme.getTextPrimary(context),
                    ),
                  ),
                ),
              ],
            ),
          ),
          SizedBox(height: 16),
          Container(
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
                  color: Colors.black.withOpacity(0.2),
                  blurRadius: 8,
                  offset: Offset(0, 4),
                ),
              ],
            ),
            child: TextFormField(
              controller: purposeTextController,
              keyboardType: TextInputType.multiline,
              textCapitalization: TextCapitalization.sentences,
              maxLines: 4,
              style: TextStyle(
                fontSize: 16,
                color: AppTheme.getTextPrimary(context),
              ),
              onChanged: (value) {
                setState(() {});
              },
              decoration: InputDecoration(
                hintText: 'Purpose for indent',
                hintStyle: TextStyle(color: AppTheme.getTextSecondary(context)),
                border: InputBorder.none,
                contentPadding: EdgeInsets.symmetric(horizontal: 0, vertical: 0),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStep5Attachment() {
    return SingleChildScrollView(
      padding: EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          _buildSectionHeader(
            'Attachment',
            Icons.attach_file,
            isCompleted: true,
            instruction: 'Add an attachment file (optional). This step can be skipped',
          ),
          SizedBox(height: 20),
          InkWell(
            onTap: () async => getFile(),
            borderRadius: BorderRadius.circular(16),
            child: Container(
              padding: EdgeInsets.all(18),
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
                    color: Colors.black.withOpacity(0.2),
                    blurRadius: 8,
                    offset: Offset(0, 4),
                  ),
                ],
              ),
              child: Row(
                children: <Widget>[
                  Container(
                    padding: EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: AppTheme.getPrimaryColor(context).withOpacity(0.2),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(
                      Icons.attach_file,
                      size: 24,
                      color: AppTheme.getPrimaryColor(context),
                    ),
                  ),
                  SizedBox(width: 16),
                  Expanded(
                    child: Text(
                      attachedFileName.isNotEmpty
                          ? attachedFileName
                          : 'Add attachment (Optional)',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: attachedFileName.isNotEmpty
                            ? AppTheme.getTextPrimary(context)
                            : AppTheme.getTextSecondary(context),
                      ),
                    ),
                  ),
                  if (attachedFileName.isNotEmpty)
                    IconButton(
                      icon: Icon(Icons.close, color: Colors.red),
                      onPressed: () {
                        setState(() {
                          attachedFileName = '';
                          attachedFile = null;
                        });
                      },
                    ),
                ],
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
        children: <Widget>[
          _buildSectionHeader(
            'Preview',
            Icons.preview,
            isCompleted: false,
            instruction: 'Review all information before submitting',
          ),
          SizedBox(height: 24),
          
          // Project Preview
          _buildPreviewCard(
            icon: Icons.folder_special,
            title: 'Project',
            content: selectedProject != null
                ? (selectedProject['name'] ?? 'Unknown')
                : 'Not selected',
            isComplete: selectedProject != null,
          ),
          SizedBox(height: 16),
          
          // Material Preview
          _buildPreviewCard(
            icon: Icons.inventory_2,
            title: 'Material',
            content: selectedMaterial != null && selectedMaterial.isNotEmpty
                ? selectedMaterial
                : 'Not selected',
            isComplete: selectedMaterial != null && selectedMaterial.isNotEmpty,
          ),
          SizedBox(height: 16),
          
          // Quantity & Unit Preview
          _buildPreviewCard(
            icon: Icons.scale,
            title: 'Quantity & Unit',
            content: quantityTextController.text.trim().isNotEmpty && unit != 'Unit'
                ? '${quantityTextController.text.trim()} $unit'
                : 'Not entered',
            isComplete: quantityTextController.text.trim().isNotEmpty && unit != 'Unit',
          ),
          SizedBox(height: 16),
          
          // Details Preview
          _buildPreviewCard(
            icon: Icons.edit_note,
            title: 'Details',
            content: 'Difference Cost: ${diffCostTextController.text.trim()}\n'
                'Approval Taken: ${approvalTaken ? 'Yes' : 'No'}\n'
                'Purpose: ${purposeTextController.text.trim().isNotEmpty ? purposeTextController.text.trim() : 'Not entered'}',
            isComplete: purposeTextController.text.trim().isNotEmpty,
            isTextContent: true,
          ),
          SizedBox(height: 16),
          
          // Attachment Preview
          _buildPreviewCard(
            icon: Icons.attach_file,
            title: 'Attachment',
            content: attachedFileName.isNotEmpty
                ? attachedFileName
                : 'No attachment',
            isComplete: attachedFileName.isNotEmpty,
          ),
        ],
      ),
    );
  }

  Widget _buildPreviewCard({
    required IconData icon,
    required String title,
    required String content,
    required bool isComplete,
    bool isTextContent = false,
  }) {
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
        border: Border.all(
          color: isComplete
              ? Colors.green.withOpacity(0.3)
              : AppTheme.getPrimaryColor(context).withOpacity(0.2),
          width: 1.5,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.1),
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
                padding: EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: isComplete
                      ? Colors.green.withOpacity(0.2)
                      : AppTheme.getPrimaryColor(context).withOpacity(0.15),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(
                  icon,
                  size: 20,
                  color: isComplete
                      ? Colors.green
                      : AppTheme.getPrimaryColor(context),
                ),
              ),
              SizedBox(width: 12),
              Expanded(
                child: Text(
                  title,
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: AppTheme.getTextPrimary(context),
                  ),
                ),
              ),
              if (isComplete)
                Icon(
                  Icons.check_circle,
                  color: Colors.green,
                  size: 20,
                ),
            ],
          ),
          SizedBox(height: 12),
          if (isTextContent)
            Container(
              padding: EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppTheme.getBackgroundPrimary(context),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                content,
                style: TextStyle(
                  fontSize: 14,
                  color: AppTheme.getTextPrimary(context),
                  height: 1.5,
                ),
              ),
            )
          else
            Text(
              content,
              style: TextStyle(
                fontSize: 14,
                color: isComplete
                    ? AppTheme.getTextPrimary(context)
                    : AppTheme.getTextSecondary(context),
                fontWeight: isComplete ? FontWeight.w500 : FontWeight.normal,
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
                    ? Colors.green.withOpacity(0.2)
                    : AppTheme.getPrimaryColor(context).withOpacity(0.15),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(
                isCompleted ? Icons.check : icon,
                size: 20,
                color: isCompleted ? Colors.green : AppTheme.getPrimaryColor(context),
              ),
            ),
            SizedBox(width: 12),
            Expanded(
              child: Text(
                title,
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: isCompleted
                      ? Colors.green
                      : AppTheme.getTextPrimary(context),
                  letterSpacing: 0.5,
                ),
              ),
            ),
          ],
        ),
        if (instruction != null) ...[
          SizedBox(height: 8),
          Padding(
            padding: EdgeInsets.only(left: 44),
            child: Text(
              instruction,
              style: TextStyle(
                fontSize: 14,
                color: AppTheme.getTextSecondary(context),
                height: 1.4,
              ),
            ),
          ),
        ],
      ],
    );
  }
}

// View Open Indents Tab
class ViewOpenIndentsTab extends StatefulWidget {
  const ViewOpenIndentsTab({Key? key}) : super(key: key);

  @override
  ViewOpenIndentsTabState createState() {
    return ViewOpenIndentsTabState();
  }
}

class ViewOpenIndentsTabState extends State<ViewOpenIndentsTab> {
  var user_id;
  var indents = [];
  var current_user_name;
  var role;

  @override
  void initState() {
    super.initState();
    call();
  }

  call() async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    user_id = prefs.getString('user_id');
    current_user_name = prefs.get('username');

    var url =
        'https://office.buildahome.in/API/get_unapproved_indents?user_id=${user_id}';
    var response = await http.get(Uri.parse(url));
    print(response.body);
    if (mounted) {
      setState(() {
        indents = jsonDecode(response.body);
        role = prefs.get('role');
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
        height: MediaQuery.of(context).size.height,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
                margin: EdgeInsets.symmetric(horizontal: 10, vertical: 20),
                child: Text('Open indents (${indents.length})',
                    style: TextStyle(
                      color: AppTheme.getTextPrimary(context),
                      fontSize: 20,
                      fontWeight: FontWeight.w600,
                    ))),
            Expanded(
              child: ListView.builder(
                  shrinkWrap: true,
                  padding: EdgeInsets.all(15),
                  itemCount: indents.length,
                  itemBuilder: (BuildContext ctxt, int Index) {
                    return Container(
                        margin: EdgeInsets.only(bottom: 20),
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                            colors: [
                              Theme.of(context).colorScheme.surface,
                              AppTheme.getBackgroundPrimaryLight(context),
                            ],
                          ),
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(
                            color: AppTheme.getPrimaryColor(context).withOpacity(0.2),
                            width: 1.5,
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withOpacity(0.15),
                              blurRadius: 10,
                              spreadRadius: 2,
                              offset: Offset(0, 4),
                            ),
                          ],
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // Header with project name
                            Container(
                              padding: EdgeInsets.all(20),
                              decoration: BoxDecoration(
                                color: AppTheme.getPrimaryColor(context).withOpacity(0.1),
                                borderRadius: BorderRadius.only(
                                  topLeft: Radius.circular(20),
                                  topRight: Radius.circular(20),
                                ),
                              ),
                              child: Row(
                                children: [
                                  Container(
                                    padding: EdgeInsets.all(10),
                                    decoration: BoxDecoration(
                                      color: AppTheme.getPrimaryColor(context).withOpacity(0.2),
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                    child: Icon(
                                      Icons.folder_special,
                                      color: AppTheme.getPrimaryColor(context),
                                      size: 24,
                                    ),
                                  ),
                                  SizedBox(width: 12),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          '${indents[Index]['project_name']}',
                                          style: TextStyle(
                                            fontSize: 18,
                                            fontWeight: FontWeight.bold,
                                            color: AppTheme.getTextPrimary(context),
                                          ),
                                        ),
                                        SizedBox(height: 4),
                                        Text(
                                          'Created by ${indents[Index]['created_by_user']}',
                                          style: TextStyle(
                                            color: AppTheme.getTextSecondary(context),
                                            fontSize: 12,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            
                            // Content
                            Padding(
                              padding: EdgeInsets.all(20),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  // Material Row
                                  _buildInfoRow(
                                    Icons.build,
                                    'Material',
                                    '${indents[Index]['material']}',
                                  ),
                                  SizedBox(height: 16),
                                  
                                  // Quantity Row
                                  _buildInfoRow(
                                    Icons.numbers,
                                    'Quantity',
                                    '${indents[Index]['quantity']} ${indents[Index]['unit']}',
                                  ),
                                  SizedBox(height: 16),
                                  
                                  // Purpose Row
                                  _buildInfoRow(
                                    Icons.description,
                                    'Purpose',
                                    '${indents[Index]['purpose']}',
                                  ),
                                  SizedBox(height: 20),
                                  
                                  // Timestamp
                                  Container(
                                    padding: EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                                    decoration: BoxDecoration(
                                      color: Theme.of(context).scaffoldBackgroundColor,
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Icon(
                                          Icons.access_time,
                                          size: 14,
                                          color: AppTheme.getTextSecondary(context),
                                        ),
                                        SizedBox(width: 6),
                                        Text(
                                          '${indents[Index]['timestamp']}',
                                          style: TextStyle(
                                            color: AppTheme.getTextSecondary(context),
                                            fontSize: 12,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            // Action Buttons
                            if (role != 'Site Engineer')
                              Container(
                                padding: EdgeInsets.all(20),
                                decoration: BoxDecoration(
                                      color: Theme.of(context).scaffoldBackgroundColor,
                                  borderRadius: BorderRadius.only(
                                    bottomLeft: Radius.circular(20),
                                    bottomRight: Radius.circular(20),
                                  ),
                                ),
                                child: Row(
                                  children: [
                                    Expanded(
                                      child: InkWell(
                                        onTap: () {
                                          Navigator.push(
                                            context,
                                            MaterialPageRoute(
                                                builder: (context) =>
                                                    EditIndentLayout(
                                                        indents[Index])),
                                          );
                                        },
                                        borderRadius: BorderRadius.circular(12),
                                        child: Container(
                                          padding: EdgeInsets.symmetric(vertical: 12),
                                          decoration: BoxDecoration(
                                            color: AppTheme.getPrimaryColor(context),
                                            borderRadius: BorderRadius.circular(12),
                                          ),
                                          child: Row(
                                            mainAxisAlignment: MainAxisAlignment.center,
                                            children: [
                                              Icon(Icons.edit, color: Colors.white, size: 18),
                                              SizedBox(width: 6),
                                              Text(
                                                "Edit",
                                                style: TextStyle(
                                                  color: Colors.white,
                                                  fontWeight: FontWeight.w600,
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                      ),
                                    ),
                                    SizedBox(width: 12),
                                    Expanded(
                                      child: InkWell(
                                        onTap: () async {
                                          var response_for_confirmation =
                                              await showDialog(
                                                  barrierDismissible: false,
                                                  context: context,
                                                  builder: (BuildContext context) {
                                                    return Confirmation(
                                                        'Are you sure you want to reject this indent?');
                                                  });
                                          if (response_for_confirmation ==
                                              'Confirm') {
                                            showDialog(
                                                barrierDismissible: false,
                                                context: context,
                                                builder: (BuildContext context) {
                                                  return ShowAlert(
                                                      "Hang in there. We're adding this user to our records",
                                                      true);
                                                });
                                            await update_indent_status(
                                                'rejected',
                                                indents[Index]['id'].toString(),
                                                indents[Index]
                                                    ['created_by_user_id'],
                                                user_id,
                                                '${indents[Index]['quantity']} ${indents[Index]['unit']} ${indents[Index]['material']} Indent for project ${indents[Index]['project_name']} has been rejected by ${current_user_name}');
                                            setState(() {
                                              indents.removeAt(Index);
                                            });
                                            Navigator.of(context,
                                                    rootNavigator: true)
                                                .pop();
                                          }
                                        },
                                        borderRadius: BorderRadius.circular(12),
                                        child: Container(
                                          padding: EdgeInsets.symmetric(vertical: 12),
                                          decoration: BoxDecoration(
                                            color: Colors.red[500],
                                            borderRadius: BorderRadius.circular(12),
                                          ),
                                          child: Row(
                                            mainAxisAlignment: MainAxisAlignment.center,
                                            children: [
                                              Icon(Icons.close, color: Colors.white, size: 18),
                                              SizedBox(width: 6),
                                              Text(
                                                "Reject",
                                                style: TextStyle(
                                                  color: Colors.white,
                                                  fontWeight: FontWeight.w600,
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                      ),
                                    ),
                                    SizedBox(width: 12),
                                    Expanded(
                                      child: InkWell(
                                        onTap: () async {
                                          var response_for_confirmation =
                                              await showDialog(
                                                  barrierDismissible: false,
                                                  context: context,
                                                  builder: (BuildContext context) {
                                                    return Confirmation(
                                                        'Are you sure you want to approve this indent?');
                                                  });
                                          if (response_for_confirmation ==
                                              'Confirm') {
                                            showDialog(
                                                barrierDismissible: false,
                                                context: context,
                                                builder: (BuildContext context) {
                                                  return ShowAlert(
                                                      "Hang in there. We're adding this user to our records",
                                                      true);
                                                });
                                            await update_indent_status(
                                                'approved',
                                                indents[Index]['id'].toString(),
                                                indents[Index]
                                                    ['created_by_user_id'],
                                                user_id,
                                                '${indents[Index]['quantity']} ${indents[Index]['unit']} ${indents[Index]['material']} Indent for project ${indents[Index]['project_name']} has been approved by ${current_user_name}');
                                            setState(() {
                                              indents.removeAt(Index);
                                            });
                                            Navigator.of(context,
                                                    rootNavigator: true)
                                                .pop();
                                          }
                                        },
                                        borderRadius: BorderRadius.circular(12),
                                        child: Container(
                                          padding: EdgeInsets.symmetric(vertical: 12),
                                          decoration: BoxDecoration(
                                            color: Colors.green[500],
                                            borderRadius: BorderRadius.circular(12),
                                          ),
                                          child: Row(
                                            mainAxisAlignment: MainAxisAlignment.center,
                                            children: [
                                              Icon(Icons.check, color: Colors.white, size: 18),
                                              SizedBox(width: 6),
                                              Text(
                                                "Approve",
                                                style: TextStyle(
                                                  color: Colors.white,
                                                  fontWeight: FontWeight.w600,
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              )
                          ],
                        ));
                  }),
            ),
          ],
        ));
  }

  Widget _buildInfoRow(IconData icon, String label, String value) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: EdgeInsets.all(8),
          decoration: BoxDecoration(
                                          color: AppTheme.getPrimaryColor(context).withOpacity(0.1),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(
            icon,
            size: 18,
            color: AppTheme.getPrimaryColor(context),
          ),
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
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: AppTheme.getTextPrimary(context),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

// My Indents Tab
class MyIndentsTab extends StatefulWidget {
  @override
  MyIndentsTabState createState() {
    return MyIndentsTabState();
  }
}

class MyIndentsTabState extends State<MyIndentsTab> {
  var user_id;
  var indents = [];
  var current_user_name;
  var role;

  @override
  void initState() {
    super.initState();
    call();
  }

  call() async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    user_id = prefs.getString('user_id');
    current_user_name = prefs.get('username');

    var url =
        'https://office.buildahome.in/API/get_my_indents?user_id=${user_id}';
    var response = await http.get(Uri.parse(url));
    print(response.body);
    setState(() {
      indents = jsonDecode(response.body);
      role = prefs.get('role');
    });
  }

  getIndentStatusColor(status) {
    if (status == 'Unapproved') {
      return Colors.yellow[900];
    } else if (status == 'Approved By Ph') {
      return Colors.green[600];
    } else {
      return Colors.blue[600];
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
        height: MediaQuery.of(context).size.height,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
                margin: EdgeInsets.symmetric(horizontal: 10, vertical: 20),
                child: Text('My indents (${indents.length})',
                    style: TextStyle(
                      color: AppTheme.getTextPrimary(context),
                      fontSize: 20,
                      fontWeight: FontWeight.w600,
                    ))),
            Expanded(
              child: ListView.builder(
                  shrinkWrap: true,
                  padding: EdgeInsets.all(15),
                  itemCount: indents.length,
                  itemBuilder: (BuildContext ctxt, int Index) {
                    return Container(
                        margin: EdgeInsets.only(bottom: 20),
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                            colors: [
                              Theme.of(context).colorScheme.surface,
                              AppTheme.getBackgroundPrimaryLight(context),
                            ],
                          ),
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(
                            color: AppTheme.getPrimaryColor(context).withOpacity(0.2),
                            width: 1.5,
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withOpacity(0.15),
                              blurRadius: 10,
                              spreadRadius: 2,
                              offset: Offset(0, 4),
                            ),
                          ],
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // Header with project name and status
                            Container(
                              padding: EdgeInsets.all(20),
                              decoration: BoxDecoration(
                                color: AppTheme.getPrimaryColor(context).withOpacity(0.1),
                                borderRadius: BorderRadius.only(
                                  topLeft: Radius.circular(20),
                                  topRight: Radius.circular(20),
                                ),
                              ),
                              child: Row(
                                children: [
                                  Container(
                                    padding: EdgeInsets.all(10),
                                    decoration: BoxDecoration(
                                      color: AppTheme.getPrimaryColor(context).withOpacity(0.2),
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                    child: Icon(
                                      Icons.folder_special,
                                      color: AppTheme.getPrimaryColor(context),
                                      size: 24,
                                    ),
                                  ),
                                  SizedBox(width: 12),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          '${indents[Index]['project_name']}',
                                          style: TextStyle(
                                            fontSize: 18,
                                            fontWeight: FontWeight.bold,
                                            color: AppTheme.getTextPrimary(context),
                                          ),
                                        ),
                                        SizedBox(height: 6),
                                        Container(
                                          padding: EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                          decoration: BoxDecoration(
                                            color: getIndentStatusColor(indents[Index]['status']).withOpacity(0.2),
                                            borderRadius: BorderRadius.circular(12),
                                            border: Border.all(
                                              color: getIndentStatusColor(indents[Index]['status']).withOpacity(0.5),
                                              width: 1,
                                            ),
                                          ),
                                          child: Text(
                                            '${indents[Index]['status']}',
                                            style: TextStyle(
                                              color: getIndentStatusColor(indents[Index]['status']),
                                              fontSize: 12,
                                              fontWeight: FontWeight.bold,
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            
                            // Content
                            Padding(
                              padding: EdgeInsets.all(20),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  // Material Row
                                  _buildInfoRow(
                                    Icons.build,
                                    'Material',
                                    '${indents[Index]['material']}',
                                  ),
                                  SizedBox(height: 16),
                                  
                                  // Quantity Row
                                  _buildInfoRow(
                                    Icons.numbers,
                                    'Quantity',
                                    '${indents[Index]['quantity']} ${indents[Index]['unit']}',
                                  ),
                                  SizedBox(height: 16),
                                  
                                  // Purpose Row
                                  _buildInfoRow(
                                    Icons.description,
                                    'Purpose',
                                    '${indents[Index]['purpose']}',
                                  ),
                                  SizedBox(height: 16),
                                  
                                  // Difference Cost Row
                                  _buildInfoRow(
                                    Icons.attach_money,
                                    'Difference Cost',
                                    '${indents[Index]['difference_cost']}',
                                  ),
                                  SizedBox(height: 16),
                                  
                                  // Approval Taken Row
                                  Row(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Container(
                                        padding: EdgeInsets.all(8),
                                        decoration: BoxDecoration(
                                          color: AppTheme.getPrimaryColor(context).withOpacity(0.1),
                                          borderRadius: BorderRadius.circular(8),
                                        ),
                                        child: Icon(
                                          Icons.check_circle,
                                          size: 18,
                                          color: indents[Index]['approval_taken'].toString() == '1'
                                              ? Colors.green
                                              : AppTheme.getTextSecondary(context),
                                        ),
                                      ),
                                      SizedBox(width: 12),
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              'Approval Taken',
                                              style: TextStyle(
                                                fontSize: 12,
                                                color: AppTheme.getTextSecondary(context),
                                                fontWeight: FontWeight.w500,
                                              ),
                                            ),
                                            SizedBox(height: 4),
                                            Text(
                                              indents[Index]['approval_taken'].toString() == '1' ? 'Yes' : 'No',
                                              style: TextStyle(
                                                fontSize: 16,
                                                fontWeight: FontWeight.w600,
                                                color: indents[Index]['approval_taken'].toString() == '1'
                                                    ? Colors.green
                                                    : AppTheme.getTextPrimary(context),
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ],
                                  ),
                                  SizedBox(height: 20),
                                  
                                  // Timestamp
                                  Container(
                                    padding: EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                                    decoration: BoxDecoration(
                                      color: Theme.of(context).scaffoldBackgroundColor,
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Icon(
                                          Icons.access_time,
                                          size: 14,
                                          color: AppTheme.getTextSecondary(context),
                                        ),
                                        SizedBox(width: 6),
                                        Text(
                                          'Created on ${indents[Index]['timestamp']}',
                                          style: TextStyle(
                                            color: AppTheme.getTextSecondary(context),
                                            fontSize: 12,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ));
                  }),
            ),
          ],
        ));
  }

  Widget _buildInfoRow(IconData icon, String label, String value) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: EdgeInsets.all(8),
          decoration: BoxDecoration(
                                          color: AppTheme.getPrimaryColor(context).withOpacity(0.1),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(
            icon,
            size: 18,
            color: AppTheme.getPrimaryColor(context),
          ),
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
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: AppTheme.getTextPrimary(context),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

