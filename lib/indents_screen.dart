import 'package:buildahome/widgets/material_units.dart';
import 'package:buildahome/edit_indent.dart';
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
import 'app_theme.dart';
import 'widgets/searchable_select.dart';
import 'widgets/full_screen_message.dart';

class IndentsScreenLayout extends StatelessWidget {
  final int initialTab;

  const IndentsScreenLayout({Key? key, this.initialTab = 0}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final appTitle = 'buildAhome';
    return MaterialApp(
      title: appTitle,
      theme: AppTheme.darkTheme,
      home: Scaffold(
        backgroundColor: AppTheme.backgroundPrimary,
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
                          color: AppTheme.backgroundSecondary,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: AppTheme.primaryColorConst.withOpacity(0.3),
                            width: 1,
                          ),
                        ),
                        child: Icon(
                          Icons.arrow_back,
                          color: AppTheme.textPrimary,
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
                        color: AppTheme.textPrimary,
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

  @override
  void initState() {
    super.initState();
    final tab = widget.initialTab;
    selectedTab = (tab >= 0 && tab <= 2) ? tab : 0;
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
              CreateIndentTab(),
              ViewOpenIndentsTab(),
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
      selectedColor: AppTheme.primaryColorConst,
      checkmarkColor: Colors.white,
      backgroundColor: AppTheme.backgroundSecondary,
      labelStyle: TextStyle(
        color: isSelected ? Colors.white : AppTheme.textPrimary,
        fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
        fontSize: 14,
      ),
      padding: EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
          color: isSelected 
              ? AppTheme.primaryColorConst 
              : AppTheme.primaryColorConst.withOpacity(0.3),
          width: isSelected ? 2 : 1,
        ),
      ),
    );
  }
}

// Create Indent Tab
class CreateIndentTab extends StatefulWidget {
  @override
  CreateIndentTabState createState() {
    return CreateIndentTabState();
  }
}

class CreateIndentTabState extends State<CreateIndentTab> {
  var user_id;
  var selectedProject;
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

  @override
  void initState() {
    super.initState();
    _initializeData();
  }

  _initializeData() async {
    await call();
    await loadProjects();
    await loadMaterials();
  }

  call() async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    user_id = prefs.getString('user_id');
  }

  loadProjects() async {
    if (user_id == null) {
      print('User ID is null, cannot load projects');
      return;
    }
    var url = "https://office.buildahome.in/API/projects_access?id=${user_id}";
    try {
      var response = await http.get(Uri.parse(url));
      if (response.statusCode == 200) {
        var decodedResponse = jsonDecode(response.body);
        setState(() {
          projects = decodedResponse is List ? decodedResponse : [];
        });
        print('Loaded ${projects.length} projects');
      } else {
        print('Failed to load projects: ${response.statusCode}');
        setState(() {
          projects = [];
        });
      }
    } catch (e) {
      print('Error loading projects: $e');
      setState(() {
        projects = [];
      });
    }
  }

  loadMaterials() async {
    var url = "https://office.buildahome.in/API/get_materials";
    var response = await http.get(Uri.parse(url));
    if (response.statusCode == 200) {
      var res = jsonDecode(response.body);
      setState(() {
        materials = res['materials'] ?? [];
      });
    }
  }

  Future<void> checkPermissionStatus() async {
    final PermissionStatus cameraStatus = await Permission.camera.status;
    final PermissionStatus galleryStatus = await Permission.photos.status;

    if (cameraStatus.isGranted && galleryStatus.isGranted) {
      print("Camera and gallery permission is granted.");
    } else {
      print("Camera and gallery permission is NOT granted.");
      await _requestPermissions();
    }
  }

  Future<void> _requestPermissions() async {
    final List<Permission> permissions = [
      Permission.camera,
      Permission.photos,
    ];

    await permissions.request();
  }

  void getFile() async {
    await checkPermissionStatus();
    var res = await FilePicker.platform.pickFiles(allowMultiple: false);
    var file = res?.files.first;
    if (file != null) {
      setState(() {
        var fileSplit = file.path?.split('/');
        attachedFile = file;
        attachedFileName = 'Attached file: ' +
            (fileSplit![fileSplit.length - 1]);
      });
    } else {
      setState(() {
        attachedFileName = '';
      });
    }
  }

  bool _isNumeric(String str) {
    return double.tryParse(str) != null;
  }

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: EdgeInsets.all(20),
      children: [
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Section 1: Project Selection
            _buildSectionHeader('1. Select Project', Icons.folder_special, isCompleted: selectedProject != null),
            SizedBox(height: 12),
            InkWell(
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => SearchableSelect(
                      title: 'Select Project',
                      items: projects,
                      itemLabel: (item) => item['name'] ?? 'Unknown',
                      selectedItem: selectedProject,
                      onItemSelected: (item) {
                        setState(() {
                          selectedProject = item;
                        });
                      },
                      defaultVisibleCount: 5,
                    ),
                  ),
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
                      AppTheme.backgroundSecondary,
                      AppTheme.backgroundPrimaryLight,
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
                              ? AppTheme.textPrimary
                              : AppTheme.textSecondary,
                          fontSize: 16,
                          fontWeight: selectedProject != null
                              ? FontWeight.w500
                              : FontWeight.normal,
                        ),
                      ),
                    ),
                    Icon(
                      Icons.arrow_forward_ios,
                      color: AppTheme.primaryColorConst,
                      size: 18,
                    ),
                  ],
                ),
              ),
            ),
            SizedBox(height: 30),

            // Section 2: Material Selection
            _buildSectionHeader('2. Select Material', Icons.build, isCompleted: selectedMaterial != null),
            SizedBox(height: 12),
            InkWell(
              onTap: () async {
                final selectedMaterialItem = await Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => SearchableSelect(
                      title: 'Select Material',
                      items: materials,
                      selectedItem: selectedMaterial,
                      onItemSelected: (item) {
                        // Navigation will be handled by SearchableSelect
                      },
                      defaultVisibleCount: 5,
                    ),
                  ),
                );
                if (selectedMaterialItem != null) {
                  setState(() {
                    selectedMaterial = selectedMaterialItem.toString();
                  });
                }
              },
              borderRadius: BorderRadius.circular(16),
              child: Container(
                padding: EdgeInsets.symmetric(horizontal: 16, vertical: 18),
                margin: EdgeInsets.only(bottom: 20),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      AppTheme.backgroundSecondary,
                      AppTheme.backgroundPrimaryLight,
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
                        selectedMaterial != null
                            ? selectedMaterial
                            : 'Select a material',
                        style: TextStyle(
                          color: selectedMaterial != null
                              ? AppTheme.textPrimary
                              : AppTheme.textSecondary,
                          fontSize: 16,
                          fontWeight: selectedMaterial != null
                              ? FontWeight.w500
                              : FontWeight.normal,
                        ),
                      ),
                    ),
                    Icon(
                      Icons.arrow_forward_ios,
                      color: AppTheme.primaryColorConst,
                      size: 18,
                    ),
                  ],
                ),
              ),
            ),

            SizedBox(height: 20),

            // Section 3: Quantity and Unit
            _buildSectionHeader('3. Quantity & Unit', Icons.numbers, isCompleted: quantityTextController.text.isNotEmpty && unit != 'Unit'),
            SizedBox(height: 12),
            Container(
              margin: EdgeInsets.only(bottom: 20),
              child: Row(
                children: [
                  Expanded(
                    flex: 7,
                    child: Container(
                      margin: EdgeInsets.only(right: 12),
                      child: TextFormField(
                        controller: quantityTextController,
                        keyboardType: TextInputType.numberWithOptions(),
                        style: TextStyle(color: AppTheme.textPrimary),
                        decoration: InputDecoration(
                          contentPadding: EdgeInsets.symmetric(vertical: 16, horizontal: 16),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: BorderSide(color: AppTheme.primaryColorConst.withOpacity(0.3)),
                          ),
                          floatingLabelBehavior: FloatingLabelBehavior.never,
                          fillColor: AppTheme.backgroundPrimaryLight,
                          filled: true,
                          errorBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: BorderSide(color: Colors.red, width: 1.0),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: BorderSide(color: AppTheme.primaryColorConst, width: 2),
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: BorderSide(color: AppTheme.primaryColorConst.withOpacity(0.3), width: 1.0),
                          ),
                          hintText: "Quantity",
                          hintStyle: TextStyle(color: AppTheme.textSecondary),
                          labelText: "Quantity",
                          labelStyle: TextStyle(color: AppTheme.textSecondary),
                        ),
                      ),
                    ),
                  ),
                  Expanded(
                    flex: 3,
                    child: InkWell(
                      onTap: () async {
                        var unitDetails = await showDialog(
                            context: context,
                            builder: (BuildContext context) {
                              return MaterialUnits();
                            });
                        setState(() {
                          if (unitDetails != null) {
                            unit = unitDetails;
                          } else {
                            unit = 'Unit';
                          }
                        });
                      },
                      borderRadius: BorderRadius.circular(12),
                      child: Container(
                        padding: EdgeInsets.all(16),
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                            colors: [
                              AppTheme.backgroundSecondary,
                              AppTheme.backgroundPrimaryLight,
                            ],
                          ),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: AppTheme.primaryColorConst.withOpacity(0.3), width: 1.5),
                        ),
                        child: Text(unit, 
                            style: TextStyle(
                              color: AppTheme.textPrimary,
                              fontSize: 16,
                              fontWeight: FontWeight.w500,
                            )),
                      ),
                    ),
                  ),
                ],
              ),
            ),

            SizedBox(height: 20),

            // Section 4: Difference Cost
            _buildSectionHeader('4. Difference Cost', Icons.attach_money, isCompleted: diffCostTextController.text.isNotEmpty && diffCostTextController.text != '0'),
            SizedBox(height: 12),
            Container(
              margin: EdgeInsets.only(bottom: 20),
              child: TextFormField(
                controller: diffCostTextController,
                keyboardType: TextInputType.numberWithOptions(),
                style: TextStyle(color: AppTheme.textPrimary),
                decoration: InputDecoration(
                  contentPadding: EdgeInsets.symmetric(vertical: 16, horizontal: 16),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(color: AppTheme.primaryColorConst.withOpacity(0.3)),
                  ),
                  floatingLabelBehavior: FloatingLabelBehavior.never,
                  fillColor: AppTheme.backgroundPrimaryLight,
                  filled: true,
                  errorBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(color: Colors.red, width: 1.0),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(color: AppTheme.primaryColorConst, width: 2),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(color: AppTheme.primaryColorConst.withOpacity(0.3), width: 1.0),
                  ),
                  hintText: "Difference cost",
                  hintStyle: TextStyle(color: AppTheme.textSecondary),
                  labelText: "Difference cost",
                  labelStyle: TextStyle(color: AppTheme.textSecondary),
                ),
              ),
            ),

            SizedBox(height: 20),

            // Section 5: Approval Taken
            _buildSectionHeader('5. Approval Taken', Icons.check_circle, isCompleted: approvalTaken),
            SizedBox(height: 12),
            Container(
              margin: EdgeInsets.only(bottom: 20),
              padding: EdgeInsets.all(16),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    AppTheme.backgroundSecondary,
                    AppTheme.backgroundPrimaryLight,
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
                    activeColor: AppTheme.primaryColorConst,
                    value: approvalTaken,
                    onChanged: (value) {
                      setState(() {
                        approvalTaken = value!;
                      });
                    },
                  ),
                  SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Approval taken',
                      style: TextStyle(
                        fontSize: 16,
                        color: AppTheme.textPrimary,
                      ),
                    ),
                  )
                ],
              ),
            ),

            SizedBox(height: 20),

            // Section 6: Purpose
            _buildSectionHeader('6. Purpose', Icons.edit_note, isCompleted: purposeTextController.text.trim().isNotEmpty),
            SizedBox(height: 12),
            Container(
              margin: EdgeInsets.only(bottom: 20),
              padding: EdgeInsets.all(16),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    AppTheme.backgroundSecondary,
                    AppTheme.backgroundPrimaryLight,
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
                autocorrect: true,
                controller: purposeTextController,
                keyboardType: TextInputType.multiline,
                textCapitalization: TextCapitalization.sentences,
                maxLines: 4,
                style: TextStyle(
                  fontSize: 16,
                  color: AppTheme.textPrimary,
                ),
                decoration: InputDecoration(
                  focusColor: AppTheme.primaryColorConst,
                  floatingLabelBehavior: FloatingLabelBehavior.never,
                  errorBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(color: Colors.red, width: 1.0),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(color: AppTheme.primaryColorConst, width: 2),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(color: AppTheme.primaryColorConst.withOpacity(0.3), width: 1.0),
                  ),
                  filled: true,
                  hintText: "Purpose for indent",
                  hintStyle: TextStyle(color: AppTheme.textSecondary),
                  alignLabelWithHint: true,
                  fillColor: AppTheme.backgroundPrimary,
                  contentPadding: EdgeInsets.all(16),
                ),
                validator: (value) {
                  if (value!.isEmpty) {
                    return 'This field cannot be empty';
                  }
                  return null;
                },
              ),
            ),

            SizedBox(height: 20),

            // Section 7: Attachment
            _buildSectionHeader('7. Attachment (Optional)', Icons.attach_file, isCompleted: attachedFileName.isNotEmpty),
            SizedBox(height: 12),
            InkWell(
              onTap: () async => getFile(),
              borderRadius: BorderRadius.circular(16),
              child: Container(
                margin: EdgeInsets.only(bottom: 20),
                padding: EdgeInsets.all(18),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      AppTheme.backgroundSecondary,
                      AppTheme.backgroundPrimaryLight,
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
                        color: AppTheme.primaryColorConst.withOpacity(0.2),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Icon(Icons.file_upload,
                          size: 24, color: AppTheme.primaryColorConst),
                    ),
                    SizedBox(width: 16),
                    Expanded(
                      child: Text(
                        attachedFileName.isNotEmpty ? attachedFileName.replaceAll('Attached file: ', '') : 'Add attachment (Optional)',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: attachedFileName.isNotEmpty ? FontWeight.w600 : FontWeight.normal,
                          color: AppTheme.textPrimary,
                        ),
                      ),
                    ),
                    if (attachedFileName.isNotEmpty)
                      InkWell(
                        onTap: () {
                          setState(() {
                            attachedFileName = '';
                            attachedFile = null;
                          });
                        },
                        child: Icon(
                          Icons.close,
                          color: AppTheme.textSecondary,
                          size: 20,
                        ),
                      ),
                  ],
                ),
              ),
            ),

            // Submit Button
            Container(
              margin: EdgeInsets.only(bottom: 50),
              child: Material(
                color: Colors.transparent,
                child: InkWell(
                  onTap: () async {
                    showDialog(
                        barrierDismissible: false,
                        context: context,
                        builder: (BuildContext context) {
                          return ShowAlert(
                              "Hang in there. We're adding this user to our records",
                              true);
                        });

                    if (selectedProject == null) {
                      Navigator.of(context, rootNavigator: true).pop();
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
                      return;
                    }

                    if (selectedMaterial == null) {
                      Navigator.of(context, rootNavigator: true).pop();
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
                      return;
                    }

                    if (quantityTextController.text.trim() == '') {
                      Navigator.of(context, rootNavigator: true).pop();
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
                      return;
                    }

                    if (!_isNumeric(quantityTextController.text.trim())) {
                      Navigator.of(context, rootNavigator: true).pop();
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
                      Navigator.of(context, rootNavigator: true).pop();
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
                      return;
                    }

                    if (!_isNumeric(diffCostTextController.text.trim())) {
                      Navigator.of(context, rootNavigator: true).pop();
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
                      Navigator.of(context, rootNavigator: true).pop();
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
                      return;
                    }

                    DateTime now = DateTime.now();
                    String formattedDate = DateFormat('EEEE d MMMM H:m').format(now);
                    var url = 'https://office.buildahome.in/API/create_indent';
                    var response = await http.post(Uri.parse(url), body: {
                      'project_id': selectedProject['id'].toString(),
                      'material': selectedMaterial,
                      'quantity': quantityTextController.text.trim(),
                      'unit': unit,
                      'differenceCost': diffCostTextController.text.trim(),
                      'purpose': purposeTextController.text.trim(),
                      'approvalTaken': approvalTaken ? '1' : '0',
                      'user_id': user_id,
                      'timestamp': formattedDate,
                    });
                    print(response.body);
                    var responseBody = jsonDecode(response.body);
                    if (responseBody['message'] == 'failure') {
                      Navigator.of(context, rootNavigator: true).pop();
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) => FullScreenMessage(
                            title: 'Error',
                            message: "Indent failed. " + responseBody['reason'],
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
                    if (attachedFileName != '') {
                      var uri = Uri.parse(
                          "https://office.buildahome.in/API/indent_file_uplpoad");
                      var request = new http.MultipartRequest("POST", uri);

                      var pic =
                          await http.MultipartFile.fromPath("file", attachedFile.path);

                      request.files.add(pic);
                      request.fields['indent_id'] = indentId.toString();
                      var fileResponse = await request.send();
                      var responseData = await fileResponse.stream.toBytes();
                      var responseString = String.fromCharCodes(responseData);
                      print(responseString);
                    }
                    Navigator.of(context, rootNavigator: true).pop();
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => FullScreenMessage(
                          title: 'Success',
                          message: 'Indent added successfully',
                          icon: Icons.check_circle,
                          iconColor: Colors.green,
                          buttonText: 'OK',
                          onButtonPressed: () => Navigator.pop(context),
                        ),
                      ),
                    );

                    setState(() {
                      selectedProject = null;
                      selectedMaterial = null;
                      unit = 'Unit';
                      quantityTextController.text = '';
                      purposeTextController.text = '';
                      diffCostTextController.text = '0';
                      approvalTaken = false;
                      attachedFileName = '';
                      attachedFile = null;
                    });
                  },
                  child: Container(
                    width: double.infinity,
                    padding: EdgeInsets.symmetric(vertical: 18),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [
                          AppTheme.primaryColorConst,
                          AppTheme.primaryColorConstDark,
                        ],
                      ),
                      borderRadius: BorderRadius.circular(16),
                      boxShadow: [
                        BoxShadow(
                          color: AppTheme.primaryColorConst.withOpacity(0.3),
                          blurRadius: 12,
                          offset: Offset(0, 4),
                        ),
                      ],
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.check_circle,
                          color: Colors.white,
                          size: 24,
                        ),
                        SizedBox(width: 12),
                        Text(
                          "Submit",
                          style: TextStyle(
                            fontSize: 18,
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildSectionHeader(String title, IconData icon, {bool isCompleted = false}) {
    return Row(
      children: [
        if (isCompleted) ...[
          Container(
            padding: EdgeInsets.all(6),
            decoration: BoxDecoration(
              color: Colors.green.withOpacity(0.2),
              shape: BoxShape.circle,
            ),
            child: Icon(
              Icons.check,
              size: 16,
              color: Colors.green,
            ),
          ),
          SizedBox(width: 8),
        ],
        Text(
          title,
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.bold,
            color: isCompleted ? AppTheme.primaryColorConst : AppTheme.textPrimary,
            letterSpacing: 0.5,
          ),
        ),
      ],
    );
  }
}

// View Open Indents Tab
class ViewOpenIndentsTab extends StatefulWidget {
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
    setState(() {
      indents = jsonDecode(response.body);
      role = prefs.get('role');
    });
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
                      color: AppTheme.textPrimary,
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
                              AppTheme.backgroundSecondary,
                              AppTheme.backgroundPrimaryLight,
                            ],
                          ),
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(
                            color: AppTheme.primaryColorConst.withOpacity(0.2),
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
                                color: AppTheme.primaryColorConst.withOpacity(0.1),
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
                                      color: AppTheme.primaryColorConst.withOpacity(0.2),
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                    child: Icon(
                                      Icons.folder_special,
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
                                          '${indents[Index]['project_name']}',
                                          style: TextStyle(
                                            fontSize: 18,
                                            fontWeight: FontWeight.bold,
                                            color: AppTheme.textPrimary,
                                          ),
                                        ),
                                        SizedBox(height: 4),
                                        Text(
                                          'Created by ${indents[Index]['created_by_user']}',
                                          style: TextStyle(
                                            color: AppTheme.onSurfaceColorConst,
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
                                      color: AppTheme.backgroundPrimary,
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Icon(
                                          Icons.access_time,
                                          size: 14,
                                          color: AppTheme.onSurfaceColorConst,
                                        ),
                                        SizedBox(width: 6),
                                        Text(
                                          '${indents[Index]['timestamp']}',
                                          style: TextStyle(
                                            color: AppTheme.onSurfaceColorConst,
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
                                  color: AppTheme.backgroundPrimary,
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
                                            color: AppTheme.primaryColorConst,
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
            color: AppTheme.primaryColorConst.withOpacity(0.1),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(
            icon,
            size: 18,
            color: AppTheme.primaryColorConst,
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
                  color: AppTheme.textSecondary,
                  fontWeight: FontWeight.w500,
                ),
              ),
              SizedBox(height: 4),
              Text(
                value,
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: AppTheme.textPrimary,
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
                      color: AppTheme.textPrimary,
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
                              AppTheme.backgroundSecondary,
                              AppTheme.backgroundPrimaryLight,
                            ],
                          ),
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(
                            color: AppTheme.primaryColorConst.withOpacity(0.2),
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
                                color: AppTheme.primaryColorConst.withOpacity(0.1),
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
                                      color: AppTheme.primaryColorConst.withOpacity(0.2),
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                    child: Icon(
                                      Icons.folder_special,
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
                                          '${indents[Index]['project_name']}',
                                          style: TextStyle(
                                            fontSize: 18,
                                            fontWeight: FontWeight.bold,
                                            color: AppTheme.textPrimary,
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
                                          color: AppTheme.primaryColorConst.withOpacity(0.1),
                                          borderRadius: BorderRadius.circular(8),
                                        ),
                                        child: Icon(
                                          Icons.check_circle,
                                          size: 18,
                                          color: indents[Index]['approval_taken'].toString() == '1'
                                              ? Colors.green
                                              : AppTheme.textSecondary,
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
                                                color: AppTheme.textSecondary,
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
                                                    : AppTheme.textPrimary,
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
                                      color: AppTheme.backgroundPrimary,
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Icon(
                                          Icons.access_time,
                                          size: 14,
                                          color: AppTheme.onSurfaceColorConst,
                                        ),
                                        SizedBox(width: 6),
                                        Text(
                                          'Created on ${indents[Index]['timestamp']}',
                                          style: TextStyle(
                                            color: AppTheme.onSurfaceColorConst,
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
            color: AppTheme.primaryColorConst.withOpacity(0.1),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(
            icon,
            size: 18,
            color: AppTheme.primaryColorConst,
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
                  color: AppTheme.textSecondary,
                  fontWeight: FontWeight.w500,
                ),
              ),
              SizedBox(height: 4),
              Text(
                value,
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: AppTheme.textPrimary,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

