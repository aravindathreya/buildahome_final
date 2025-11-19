import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:photo_view/photo_view.dart';
import 'main.dart';
import 'dart:async';
import 'dart:io';
import 'package:image_picker/image_picker.dart';
import 'package:permission_handler/permission_handler.dart';
import 'app_theme.dart';
import 'services/data_provider.dart';
import 'widgets/searchable_select.dart';
import 'widgets/full_screen_message.dart';
import 'widgets/full_screen_progress.dart';
import 'widgets/full_screen_error_summary.dart';
import 'AdminDashboard.dart';

class FullScreenImage extends StatefulWidget {
  final id;

  FullScreenImage(this.id);

  @override
  State<FullScreenImage> createState() => FullScreenFlutterImage(this.id);
}

class FullScreenFlutterImage extends State<FullScreenImage> {
  var image;

  FullScreenFlutterImage(this.image);

  @override
  Widget build(BuildContext context1) {
    return MaterialApp(
      theme: ThemeData(fontFamily: App().fontName),
      home: Scaffold(
        appBar: AppBar(
          automaticallyImplyLeading: true,
          title: Text('buildAhome'),
          leading: new IconButton(icon: new Icon(Icons.chevron_left), onPressed: () => {Navigator.pop(context)}),
          backgroundColor: Color(0xFF000055),
        ),
        body: ImageOnly(this.image),
      ),
    );
  }
}

class ImageOnly extends StatelessWidget {
  final image;

  ImageOnly(this.image);

  Widget build(BuildContext context) {
    return Container(decoration: BoxDecoration(border: Border.all(color: Colors.black)), child: PhotoView(minScale: PhotoViewComputedScale.contained, imageProvider: this.image));
  }
}

class AddDailyUpdate extends StatelessWidget {
  final bool returnToAdminDashboard;
  
  const AddDailyUpdate({Key? key, this.returnToAdminDashboard = false}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final appTitle = 'buildAhome';
    return MaterialApp(
      title: appTitle,
      theme: AppTheme.darkTheme,
      home: Scaffold(
        backgroundColor: AppTheme.backgroundPrimary,
        appBar: AppBar(
          title: Text('Add Daily Update'),
          automaticallyImplyLeading: true,
          leading: IconButton(
            icon: Icon(Icons.arrow_back),
            onPressed: () {
              Navigator.pop(context);
            },
          ),
        ),
        body: AddDailyUpdateForm(returnToAdminDashboard: returnToAdminDashboard),
      ),
    );
  }
}

class AddDailyUpdateForm extends StatefulWidget {
  final bool returnToAdminDashboard;
  
  const AddDailyUpdateForm({Key? key, this.returnToAdminDashboard = false}) : super(key: key);

  @override
  AddDailyUpdateState createState() {
    return AddDailyUpdateState();
  }
}

class AddDailyUpdateState extends State<AddDailyUpdateForm> {
  var textFieldFocused = false;
  var attachPictureButtonText = 'Add picture from phone';
  var dailyUpdateTextController = new TextEditingController();
  var quantityTextController = new TextEditingController();

  var selectedPictures = [];
  var selectedPictureFilenames = [];
  var selectedPictureFilePaths = [];

  final maxImageHeight = 1000;
  final maxImageWidth = 1000;

  var selectedProject;
  var projectId;
  var projects = [];
  var userId;
  var successfulImageUploadCount = 0;
  var availableResources = ['Mason', 'Helper', 'Carpenter', 'Bar bender', 'Painter', 'Electrician', 'Plumber', 'Tile mason', 'Granite mason', 'Fabricator', 'Other workers', 'Interior carpenter'];
  var selectedTradesmen = <String, String>{}; // Map of tradesmen name to count
  
  // Upload progress tracking
  double uploadProgress = 0.0;
  String? uploadError;
  String? uploadErrorMessage;
  bool isUploading = false;

  @override
  void initState() {
    super.initState();
    setUserId();
    loadProjects();
  }

  void loadProjects() async {
    await DataProvider().reloadData();
    setState(() {
      projects = DataProvider().projects;
    });
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
        // For gallery/photos - handle both Android storage and photos permissions
        // Try photos first (Android 13+)
        status = await Permission.photos.status;
        if (!status.isGranted) {
          status = await Permission.photos.request();
        }
        
        // If photos permission is not available (older Android), try storage
        if (!status.isGranted && Platform.isAndroid) {
          final storageStatus = await Permission.storage.status;
          if (!storageStatus.isGranted) {
            await Permission.storage.request();
          }
          // On Android, image_picker can work without explicit permission in some cases
          // Return true to let image_picker handle it
          return true;
        }
      }

      if (status.isGranted) {
        return true;
      } else if (status.isPermanentlyDenied) {
        if (mounted) {
          await _showPermissionDeniedDialog(forCamera: forCamera);
        }
        return false;
      } else {
        if (mounted) {
          await _showPermissionDeniedDialog(forCamera: forCamera);
        }
        return false;
      }
    } catch (e) {
      print('[AddDailyUpdate] Error checking permissions: $e');
      // On some platforms, permissions might not be required
      // Return true to let image_picker handle it
      if (Platform.isAndroid && !forCamera) {
        return true;
      }
      return false;
    }
  }

  Future<void> _showPermissionDeniedDialog({required bool forCamera}) async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => FullScreenMessage(
          title: 'Permission Required',
          message: forCamera
              ? 'Camera permission is required to take photos. Please enable it in your device settings.'
              : 'Photo library permission is required to select images. Please enable it in your device settings.',
          icon: Icons.error_outline,
          iconColor: Colors.orange,
          buttonText: 'OK',
          onButtonPressed: () => Navigator.pop(context),
        ),
      ),
    );
  }

  bool _uploadDialogShown = false;
  BuildContext? _uploadDialogContext;

  void showUploadProgressDialog(int currentIndex, int totalFiles, double progress, {String? error, String? errorMessage}) {
    if (!mounted) return;
    
    // Dismiss previous dialog if exists
    if (_uploadDialogShown && _uploadDialogContext != null) {
      try {
        if (Navigator.of(_uploadDialogContext!, rootNavigator: true).canPop()) {
          Navigator.of(_uploadDialogContext!, rootNavigator: true).pop();
        }
      } catch (e) {
        print('[AddDailyUpdate] Error dismissing previous dialog: $e');
      }
      _uploadDialogShown = false;
      _uploadDialogContext = null;
    }
    
    // Wait a bit before showing new dialog to prevent visual artifacts
    Future.delayed(Duration(milliseconds: 100), () {
      if (!mounted) return;
      _uploadDialogShown = true;
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (dialogContext) {
            _uploadDialogContext = dialogContext;
            return FullScreenProgress(
              title: 'Uploading',
              message: error == null ? "Uploading picture $currentIndex of $totalFiles" : "Upload Failed",
              progress: progress,
              error: error,
              errorMessage: errorMessage,
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
          print('[AddDailyUpdate] Error dismissing dialog: $e');
        }
        _uploadDialogContext = null;
      } else {
        // Fallback: try to pop from current context
        try {
          if (Navigator.of(context, rootNavigator: true).canPop()) {
            Navigator.of(context, rootNavigator: true).pop();
          }
        } catch (e) {
          print('[AddDailyUpdate] Error dismissing dialog (fallback): $e');
        }
      }
      _uploadDialogShown = false;
    }
  }

  setUserId() async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    userId = prefs.getString('user_id');
  }

  Future<bool> processSelectedPicture(XFile picture) async {
    try {
      // Process synchronously - FileImage is lazy-loaded anyway
      // Don't check file existence as it can hang on some devices
      // The file picker already ensures the file exists
      
      selectedPictures.insert(0, FileImage(File(picture.path)));
      selectedPictureFilenames.insert(0, picture.name);
      selectedPictureFilePaths.add(picture.path);
      return true;
    } catch (e) {
      print('[AddDailyUpdate] Error processing picture: $e');
      return false;
    }
  }

  Future<void> _showImageSourceDialog() async {
    if (!mounted) return;
    
    await showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          backgroundColor: AppTheme.backgroundSecondary,
          title: Text(
            'Select Image Source',
            style: TextStyle(color: AppTheme.textPrimary, fontWeight: FontWeight.bold),
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: Icon(Icons.camera_alt, color: AppTheme.primaryColorConst),
                title: Text('Take Photo', style: TextStyle(color: AppTheme.textPrimary)),
                onTap: () {
                  Navigator.pop(context);
                  _takePhotoFromCamera();
                },
              ),
              ListTile(
                leading: Icon(Icons.photo_library, color: AppTheme.primaryColorConst),
                title: Text('Choose from Gallery', style: TextStyle(color: AppTheme.textPrimary)),
                onTap: () {
                  Navigator.pop(context);
                  _selectPicturesFromGallery();
                },
              ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _takePhotoFromCamera() async {
    try {
      if (!mounted) return;
      
      // Check camera permission
      final hasPermission = await checkPermissionStatus(forCamera: true);
      if (!hasPermission) {
        return;
      }

      final picker = ImagePicker();
      final pickedFile = await picker.pickImage(
        source: ImageSource.camera,
        maxWidth: maxImageWidth.toDouble(),
        maxHeight: maxImageHeight.toDouble(),
        imageQuality: 85,
      );

      if (pickedFile == null) {
        // User cancelled
        return;
      }

      if (!mounted) return;

      // Process the image immediately (should be very fast)
      bool success = false;
      try {
        success = await processSelectedPicture(pickedFile).timeout(
          Duration(seconds: 5),
          onTimeout: () {
            print('[AddDailyUpdate] Image processing timeout');
            return false;
          },
        );
      } catch (e) {
        print('[AddDailyUpdate] Error processing image: $e');
        success = false;
      }

      if (!mounted) return;

      if (success) {
        if (mounted) {
          setState(() {
            attachPictureButtonText = "Add more pictures";
          });
        }
      } else {
        // Show error
        if (!mounted) return;
        await Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => FullScreenMessage(
              title: 'Error',
              message: 'Failed to process the image. Please try again.',
              icon: Icons.error_outline,
              iconColor: Colors.red,
              buttonText: 'OK',
              onButtonPressed: () => Navigator.pop(context),
            ),
          ),
        );
      }
    } catch (e) {
      print('[AddDailyUpdate] Error taking photo: $e');
      if (!mounted) return;
      
      await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => FullScreenMessage(
            title: 'Error',
            message: 'An error occurred while taking the photo: ${e.toString()}',
            icon: Icons.error_outline,
            iconColor: Colors.red,
            buttonText: 'OK',
            onButtonPressed: () => Navigator.pop(context),
          ),
        ),
      );
    }
  }

  Future<void> _selectPicturesFromGallery() async {
    try {
      if (!mounted) return;
      
      // Check gallery permission
      final hasPermission = await checkPermissionStatus(forCamera: false);
      if (!hasPermission) {
        return;
      }

      final picker = ImagePicker();
      final pickedFiles = await picker.pickMultiImage(
        maxWidth: maxImageWidth.toDouble(),
        maxHeight: maxImageHeight.toDouble(),
        imageQuality: 85,
      );

      if (pickedFiles.isEmpty) {
        // User cancelled or no files selected
        return;
      }

      if (!mounted) return;

      // Process all images (should be very fast)
      int successCount = 0;
      for (var i = 0; i < pickedFiles.length; i++) {
        try {
          final success = await processSelectedPicture(pickedFiles[i]).timeout(
            Duration(seconds: 5),
            onTimeout: () {
              print('[AddDailyUpdate] Image processing timeout for image ${i + 1}');
              return false;
            },
          );
          if (success) {
            successCount++;
          }
        } catch (e) {
          print('[AddDailyUpdate] Error processing image ${i + 1}: $e');
        }
      }

      if (!mounted) return;

      if (successCount > 0) {
        if (mounted) {
          setState(() {
            attachPictureButtonText = "Add more pictures";
          });
        }

        if (successCount < pickedFiles.length && mounted) {
          // Some images failed to process
          await Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => FullScreenMessage(
                title: 'Partial Success',
                message: '$successCount of ${pickedFiles.length} image(s) were added successfully.',
                icon: Icons.warning_amber_rounded,
                iconColor: Colors.orange,
                buttonText: 'OK',
                onButtonPressed: () => Navigator.pop(context),
              ),
            ),
          );
        }
      } else {
        if (!mounted) return;
        // All images failed
        await Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => FullScreenMessage(
              title: 'Error',
              message: 'Failed to process the images. Please try again.',
              icon: Icons.error_outline,
              iconColor: Colors.red,
              buttonText: 'OK',
              onButtonPressed: () => Navigator.pop(context),
            ),
          ),
        );
      }
    } catch (e) {
      print('[AddDailyUpdate] Error selecting pictures: $e');
      if (!mounted) return;
      
      await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => FullScreenMessage(
            title: 'Error',
            message: 'An error occurred while selecting images: ${e.toString()}',
            icon: Icons.error_outline,
            iconColor: Colors.red,
            buttonText: 'OK',
            onButtonPressed: () => Navigator.pop(context),
          ),
        ),
      );
    }
  }

  Future<void> selectPicturesFromPhone() async {
    await _showImageSourceDialog();
  }

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: EdgeInsets.all(20),
      children: <Widget>[
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
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
                          projectId = item['id'].toString();
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
            SizedBox(height: 20),

            // Section 2: Add Pictures
            _buildSectionHeader('2. Add Pictures', Icons.add_a_photo, isCompleted: selectedPictures.length > 0),
            SizedBox(height: 12),
            Visibility(
              visible: !textFieldFocused,
              child: Container(
                margin: EdgeInsets.only(bottom: 20),
                child: InkWell(
                  onTap: () async => selectPicturesFromPhone(),
                  borderRadius: BorderRadius.circular(16),
                  child: Container(
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
                    padding: EdgeInsets.all(18),
                    child: Row(
                      children: <Widget>[
                        Container(
                          padding: EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: AppTheme.primaryColorConst.withOpacity(0.2),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Icon(
                            Icons.add_a_photo,
                            size: 24,
                            color: AppTheme.primaryColorConst,
                          ),
                        ),
                        SizedBox(width: 16),
                        Expanded(
                          child: Text(
                            attachPictureButtonText,
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                              color: AppTheme.textPrimary,
                            ),
                          ),
                        ),
                        Icon(
                          Icons.chevron_right,
                          color: AppTheme.textSecondary,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),

            //List of images stacked horizontally
            if (selectedPictures.length != 0)
              Visibility(
                visible: !textFieldFocused,
                child: Container(
                  margin: EdgeInsets.only(bottom: 20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Padding(
                        padding: EdgeInsets.only(bottom: 12),
                        child: Text(
                          'Selected Images (${selectedPictures.length})',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                            color: AppTheme.textPrimary,
                          ),
                        ),
                      ),
                      Container(
                        height: 150,
                        child: ListView.builder(
                          shrinkWrap: true,
                          scrollDirection: Axis.horizontal,
                          itemCount: selectedPictures.length,
                          itemBuilder: (BuildContext ctxt, int index) {
                            return Container(
                              margin: EdgeInsets.only(right: 12),
                              child: Stack(
                                children: [
                                  InkWell(
                                    onTap: () async {
                                      Navigator.push(
                                        context,
                                        MaterialPageRoute(
                                          builder: (context) => FullScreenImage(
                                            selectedPictures[index],
                                          ),
                                        ),
                                      );
                                    },
                                    child: Container(
                                      height: 150,
                                      width: 150,
                                      decoration: BoxDecoration(
                                        image: DecorationImage(
                                          image: selectedPictures[index],
                                          fit: BoxFit.cover,
                                        ),
                                        border: Border.all(
                                          color: AppTheme.primaryColorConst.withOpacity(0.3),
                                          width: 2,
                                        ),
                                        borderRadius: BorderRadius.circular(16),
                                      ),
                                    ),
                                  ),
                                  Positioned(
                                    top: 8,
                                    right: 8,
                                    child: InkWell(
                                      onTap: () {
                                        setState(() {
                                          selectedPictures.removeAt(index);
                                          selectedPictureFilenames.removeAt(index);
                                          selectedPictureFilePaths.removeAt(index);
                                          if (selectedPictures.length == 0) {
                                            attachPictureButtonText = "Add picture from phone";
                                          }
                                        });
                                      },
                                      child: Container(
                                        height: 32,
                                        width: 32,
                                        decoration: BoxDecoration(
                                          color: Colors.red,
                                          shape: BoxShape.circle,
                                          boxShadow: [
                                            BoxShadow(
                                              color: Colors.black.withOpacity(0.3),
                                              blurRadius: 4,
                                              offset: Offset(0, 2),
                                            ),
                                          ],
                                        ),
                                        child: Icon(
                                          Icons.close,
                                          size: 18,
                                          color: Colors.white,
                                        ),
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
                  ),
                ),
              ),

            SizedBox(height: 10),       
            // Section 3: Tradesmen Selection
            _buildSectionHeader('3. Select Tradesmen', Icons.people, isCompleted: selectedTradesmen.isNotEmpty),
            SizedBox(height: 12),
            InkWell(
              onTap: () async {
                final selectedTradesmenItem = await Navigator.push<String>(
                  context,
                  MaterialPageRoute(
                    builder: (context) => SearchableSelect(
                      title: 'Select Tradesmen',
                      items: availableResources,
                      selectedItem: null,
                      onItemSelected: (item) {
                        // Navigation will be handled by SearchableSelect
                        // Return the item through Navigator.pop in the widget
                      },
                      defaultVisibleCount: 5,
                    ),
                  ),
                );
                if (selectedTradesmenItem != null) {
                  _showTradesmenCountDialog(selectedTradesmenItem);
                }
              },
              borderRadius: BorderRadius.circular(16),
              child: Container(
                margin: EdgeInsets.only(bottom: 20),
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
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            selectedTradesmen.isEmpty
                                ? 'Select tradesmen'
                                : '${selectedTradesmen.length} tradesmen selected',
                            style: TextStyle(
                              color: selectedTradesmen.isEmpty
                                  ? AppTheme.textSecondary
                                  : AppTheme.textPrimary,
                              fontSize: 16,
                              fontWeight: selectedTradesmen.isEmpty
                                  ? FontWeight.normal
                                  : FontWeight.w500,
                            ),
                          ),
                          if (selectedTradesmen.isNotEmpty) ...[
                            SizedBox(height: 8),
                            Wrap(
                              spacing: 8,
                              runSpacing: 8,
                              children: selectedTradesmen.entries.map((entry) {
                                return Container(
                                  padding: EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                                  decoration: BoxDecoration(
                                    color: AppTheme.primaryColorConst.withOpacity(0.2),
                                    borderRadius: BorderRadius.circular(20),
                                    border: Border.all(
                                      color: AppTheme.primaryColorConst.withOpacity(0.5),
                                      width: 1,
                                    ),
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Text(
                                        entry.key,
                                        style: TextStyle(
                                          color: AppTheme.primaryColorConst,
                                          fontSize: 12,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                      SizedBox(width: 6),
                                      Container(
                                        padding: EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                        decoration: BoxDecoration(
                                          color: AppTheme.primaryColorConst,
                                          borderRadius: BorderRadius.circular(10),
                                        ),
                                        child: Text(
                                          entry.value,
                                          style: TextStyle(
                                            color: Colors.white,
                                            fontSize: 11,
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                      ),
                                      SizedBox(width: 6),
                                      InkWell(
                                          onTap: () {
                                            setState(() {
                                              selectedTradesmen.remove(entry.key);
                                            });
                                          },
                                          child: Icon(
                                            Icons.close,
                                            size: 16,
                                            color: AppTheme.primaryColorConst,
                                          ),
                                        ),
                                    ],
                                  ),
                                );
                              }).toList(),
                            ),
                          ],
                        ],
                      ),
                    ),
                    SizedBox(width: 12),
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
            // Section 4: Daily Update Text
            _buildSectionHeader('4. Daily Update', Icons.edit_note, isCompleted: dailyUpdateTextController.text.trim().isNotEmpty),
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
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(
                        Icons.calendar_today,
                        size: 16,
                        color: AppTheme.textSecondary,
                      ),
                      SizedBox(width: 8),
                      Text(
                        DateFormat("dd MMMM yyyy").format(DateTime.now()),
                        style: TextStyle(
                          fontSize: 13,
                          color: AppTheme.textSecondary,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                  SizedBox(height: 16),
                  TextFormField(
                    autocorrect: true,
                    controller: dailyUpdateTextController,
                    keyboardType: TextInputType.multiline,
                    textCapitalization: TextCapitalization.sentences,
                    maxLines: 8,
                    style: TextStyle(
                      fontSize: 16,
                      color: AppTheme.textPrimary,
                    ),
                    onChanged: (value) {
                      setState(() {
                        // Update UI to show checkmark when text is entered
                      });
                    },
                    decoration: InputDecoration(
                      focusColor: AppTheme.primaryColorConst,
                      floatingLabelBehavior: FloatingLabelBehavior.never,
                      errorBorder: OutlineInputBorder(
                        borderSide: BorderSide(color: Colors.red, width: 1.0),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderSide: BorderSide(color: AppTheme.primaryColorConst, width: 2.0),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderSide: BorderSide(
                          color: AppTheme.primaryColorConst.withOpacity(0.3),
                          width: 1.0,
                        ),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      filled: true,
                      hintText: "What's done today?",
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
                ],
              ),
            ),

            // Submit Button
            Container(
              margin: EdgeInsets.only(bottom: 50),
              child: Material(
                color: Colors.transparent,
                child: InkWell(
                  onTap: isUploading ? null : () async {
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
                      return;
                    }

                    if (dailyUpdateTextController.text.trim() == "") {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) => FullScreenMessage(
                            title: 'Validation Error',
                            message: 'Update text field should not be empty',
                            icon: Icons.error_outline,
                            iconColor: Colors.red,
                            buttonText: 'OK',
                            onButtonPressed: () => Navigator.pop(context),
                          ),
                        ),
                      );
                      return;
                    }

                    if (!mounted) return;
                    setState(() {
                      isUploading = true;
                      successfulImageUploadCount = 0;
                      uploadProgress = 0.0;
                      uploadError = null;
                      uploadErrorMessage = null;
                    });

                    try {
                      var tradesmenMap = selectedTradesmen;

                      // Handle case with no images
                      if (selectedPictures.length == 0) {
                          var url = 'https://office.buildahome.in/API/add_daily_update';
                          var response = await http.post(Uri.parse(url), body: {
                            'pr_id': projectId.toString(),
                            'date': new DateFormat('EEEE MMMM dd').format(DateTime.now()).toString(),
                            'desc': dailyUpdateTextController.text,
                            'tradesmenMap': tradesmenMap.toString(),
                            'image': ''
                          });

                        if (response.statusCode == 200) {
                          if (!mounted) return;
                          setState(() {
                            selectedPictures.clear();
                            selectedPictureFilePaths.clear();
                            selectedPictureFilenames.clear();
                            dailyUpdateTextController.text = '';
                            selectedTradesmen.clear();
                            attachPictureButtonText = "Add picture from phone";
                            isUploading = false;
                            successfulImageUploadCount = 0;
                          });
                          if (!mounted) return;
                          await Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (context) => FullScreenMessage(
                                title: 'Success',
                                message: 'DPR added successfully',
                                icon: Icons.check_circle,
                                iconColor: Colors.green,
                                buttonText: 'OK',
                                onButtonPressed: () {
                                  Navigator.pop(context);
                                },
                              ),
                            ),
                          );
                          
                          // Navigate back to the screen that opened AddDailyUpdate
                          if (!mounted) return;
                          if (widget.returnToAdminDashboard) {
                            Navigator.pushAndRemoveUntil(
                              context,
                              MaterialPageRoute(builder: (context) => AdminDashboard()),
                              (route) => false,
                            );
                          } else {
                            Navigator.pop(context);
                          }
                        } else {
                          if (!mounted) return;
                          setState(() {
                            isUploading = false;
                          });
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (context) => FullScreenMessage(
                                title: 'Error',
                                message: 'Failed to add DPR. Please try again.',
                                icon: Icons.error_outline,
                                iconColor: Colors.red,
                                buttonText: 'OK',
                                onButtonPressed: () => Navigator.pop(context),
                              ),
                            ),
                          );
                        }
                        return;
                      }

                      // Upload images with progress tracking
                      List<String> failedUploads = [];
                      List<String> failedReasons = [];

                      for (int x = 0; x < selectedPictures.length; x++) {
                        try {
                          if (!mounted) break;
                          
                          // Show progress dialog
                          showUploadProgressDialog(
                            x + 1,
                            selectedPictures.length,
                            0.0,
                          );

                          var uri = Uri.parse("https://office.buildahome.in/API/dpr_image_upload");
                          var request = new http.MultipartRequest("POST", uri);

                          var pic = await http.MultipartFile.fromPath("image", selectedPictureFilePaths[x]);
                          request.files.add(pic);

                          // Track upload progress with timeout
                          var fileResponse = await request.send().timeout(
                            Duration(seconds: 60),
                            onTimeout: () {
                              throw TimeoutException('Image upload timeout after 60 seconds');
                            },
                          );
                          
                          if (!mounted) {
                            _dismissUploadDialog();
                            break;
                          }
                          
                          // Update progress while uploading
                          double progress = 0.5; // Approximate progress
                          showUploadProgressDialog(
                            x + 1,
                            selectedPictures.length,
                            progress,
                          );

                          // Read response with timeout
                          var responseData = await fileResponse.stream.toBytes().timeout(
                            Duration(seconds: 10),
                            onTimeout: () {
                              throw TimeoutException('Response read timeout');
                            },
                          );
                          var responseString = String.fromCharCodes(responseData);

                          if (!mounted) {
                            _dismissUploadDialog();
                            break;
                          }

                          if (fileResponse.statusCode == 200 && responseString.trim().toString() == "success") {
                            // Image uploaded successfully, now add daily update
                            var url = 'https://office.buildahome.in/API/add_daily_update';
                            var response = await http.post(Uri.parse(url), body: {
                              'pr_id': projectId.toString(),
                              'date': new DateFormat('EEEE MMMM dd').format(DateTime.now()).toString(),
                              'desc': dailyUpdateTextController.text,
                              'tradesmenMap': tradesmenMap.toString(),
                              'image': pic.filename
                            }).timeout(
                              Duration(seconds: 30),
                              onTimeout: () {
                                throw TimeoutException('Daily update save timeout');
                              },
                            );

                            if (response.statusCode == 200) {
                              successfulImageUploadCount += 1;
                              
                              // Update progress
                              double nextProgress = (x + 1) / selectedPictures.length;
                              
                              if (successfulImageUploadCount < selectedPictures.length) {
                                // Show next upload progress
                                showUploadProgressDialog(
                                  x + 2,
                                  selectedPictures.length,
                                  nextProgress,
                                );
                              } else {
                                // All uploads complete
                                _dismissUploadDialog();
                                if (!mounted) return;
                                setState(() {
                                  selectedPictures.clear();
                                  selectedPictureFilePaths.clear();
                                  selectedPictureFilenames.clear();
                                  dailyUpdateTextController.text = '';
                                  selectedTradesmen.clear();
                                  attachPictureButtonText = "Add picture from phone";
                                  isUploading = false;
                                  successfulImageUploadCount = 0;
                                });
                                if (!mounted) return;
                                
                                // Show success message and navigate back
                                await Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (context) => FullScreenMessage(
                                      title: 'Success',
                                      message: 'DPR added successfully',
                                      icon: Icons.check_circle,
                                      iconColor: Colors.green,
                                      buttonText: 'OK',
                                      onButtonPressed: () {
                                        Navigator.pop(context);
                                      },
                                    ),
                                  ),
                                );
                                
                                // Navigate back to the screen that opened AddDailyUpdate
                                if (!mounted) return;
                                if (widget.returnToAdminDashboard) {
                                  Navigator.pushAndRemoveUntil(
                                    context,
                                    MaterialPageRoute(builder: (context) => AdminDashboard()),
                                    (route) => false,
                                  );
                                } else {
                                  Navigator.pop(context);
                                }
                              }
                            } else {
                              // Failed to add daily update
                              failedUploads.add(selectedPictureFilenames[x]);
                              failedReasons.add("Failed to save update: HTTP ${response.statusCode}");
                              
                              if (x == selectedPictures.length - 1) {
                                // Last image, show error summary
                                _dismissUploadDialog();
                                if (mounted) {
                                  await _showUploadErrorSummary(failedUploads, failedReasons);
                                  setState(() {
                                    isUploading = false;
                                  });
                                }
                              } else {
                                // Continue with next upload
                                showUploadProgressDialog(
                                  x + 2,
                                  selectedPictures.length,
                                  (x + 1) / selectedPictures.length,
                                );
                              }
                            }
                          } else {
                            // Image upload failed
                            failedUploads.add(selectedPictureFilenames[x]);
                            String errorMsg = "Upload failed";
                            if (fileResponse.statusCode != 200) {
                              errorMsg = "HTTP ${fileResponse.statusCode}: ${responseString.isNotEmpty ? responseString : 'Server error'}";
                            } else {
                              errorMsg = responseString.trim().isEmpty ? "Unknown error" : responseString;
                            }
                            failedReasons.add(errorMsg);
                            
                                  // Show error for this specific file
                                  showUploadProgressDialog(
                                    x + 1,
                                    selectedPictures.length,
                                    (x) / selectedPictures.length,
                                    error: "failed",
                                    errorMessage: errorMsg,
                                  );

                                  // Wait a bit then continue or show summary
                                  await Future.delayed(Duration(seconds: 2));
                                  _dismissUploadDialog();
                            
                            if (x == selectedPictures.length - 1) {
                              if (mounted) {
                                await _showUploadErrorSummary(failedUploads, failedReasons);
                                setState(() {
                                  isUploading = false;
                                });
                              }
                            } else {
                              // Continue with next upload
                              if (mounted) {
                                showUploadProgressDialog(
                                  x + 2,
                                  selectedPictures.length,
                                  (x + 1) / selectedPictures.length,
                                );
                              }
                            }
                          }
                        } catch (e) {
                          print('[AddDailyUpdate] Upload error: $e');
                          _dismissUploadDialog();
                          failedUploads.add(selectedPictureFilenames[x]);
                          failedReasons.add("Exception: ${e.toString()}");
                          
                          if (x == selectedPictures.length - 1) {
                            if (mounted) {
                              await _showUploadErrorSummary(failedUploads, failedReasons);
                              setState(() {
                                isUploading = false;
                              });
                            }
                          } else {
                            // Continue with next upload
                            if (mounted) {
                              showUploadProgressDialog(
                                x + 2,
                                selectedPictures.length,
                                (x + 1) / selectedPictures.length,
                              );
                            }
                          }
                        }
                      }
                      
                      // Ensure dialog is dismissed after all uploads
                      _dismissUploadDialog();
                    } catch (e) {
                      print('[AddDailyUpdate] Upload loop error: $e');
                      _dismissUploadDialog();
                      if (mounted) {
                        setState(() {
                          isUploading = false;
                        });
                        await showDialog(
                          context: context,
                          builder: (BuildContext context) {
                            return AlertDialog(
                              backgroundColor: AppTheme.backgroundSecondary,
                              title: Text(
                                "Error",
                                style: TextStyle(color: Colors.red),
                              ),
                              content: Text(
                                "An error occurred: ${e.toString()}",
                                style: TextStyle(color: AppTheme.textPrimary),
                              ),
                              actions: [
                                TextButton(
                                  onPressed: () => Navigator.pop(context),
                                  child: Text('OK'),
                                ),
                              ],
                            );
                          },
                        );
                      }
                    }
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
                            "Uploading...",
                            style: TextStyle(
                              fontSize: 18,
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ] else ...[
                          Icon(
                            Icons.cloud_upload,
                            color: Colors.white,
                            size: 24,
                          ),
                          SizedBox(width: 12),
                          Text(
                            "Add Update",
                            style: TextStyle(
                              fontSize: 18,
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                            ),
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
      ],
    );
  }

  Future<void> _showUploadErrorSummary(List<String> failedUploads, List<String> failedReasons) async {
    if (failedUploads.isEmpty) return;

    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => FullScreenErrorSummary(
          failedUploads: failedUploads,
          failedReasons: failedReasons,
        ),
      ),
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

  void _showTradesmenCountDialog(String tradesmenName) {
    final countController = TextEditingController();
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => Scaffold(
          backgroundColor: AppTheme.backgroundPrimary,
          appBar: AppBar(
            title: Text('Enter Count'),
            backgroundColor: AppTheme.backgroundSecondary,
            leading: IconButton(
              icon: Icon(Icons.arrow_back),
              onPressed: () => Navigator.pop(context),
            ),
          ),
          body: Padding(
            padding: EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
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
                      Row(
                        children: [
                          Container(
                            padding: EdgeInsets.all(10),
                            decoration: BoxDecoration(
                              color: AppTheme.primaryColorConst.withOpacity(0.2),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Icon(
                              Icons.people,
                              color: AppTheme.primaryColorConst,
                              size: 24,
                            ),
                          ),
                          SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              tradesmenName,
                              style: TextStyle(
                                color: AppTheme.textPrimary,
                                fontSize: 20,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ],
                      ),
                      SizedBox(height: 24),
                      Text(
                        'Number of workers',
                        style: TextStyle(
                          color: AppTheme.textSecondary,
                          fontSize: 14,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      SizedBox(height: 12),
                      TextField(
                        controller: countController,
                        keyboardType: TextInputType.number,
                        style: TextStyle(
                          color: AppTheme.textPrimary,
                          fontSize: 18,
                        ),
                        decoration: InputDecoration(
                          hintText: 'Enter count',
                          hintStyle: TextStyle(color: AppTheme.textSecondary),
                          filled: true,
                          fillColor: AppTheme.backgroundPrimary,
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: BorderSide(
                              color: AppTheme.primaryColorConst.withOpacity(0.3),
                            ),
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: BorderSide(
                              color: AppTheme.primaryColorConst.withOpacity(0.3),
                            ),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: BorderSide(
                              color: AppTheme.primaryColorConst,
                              width: 2,
                            ),
                          ),
                          contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 18),
                        ),
                        autofocus: true,
                      ),
                    ],
                  ),
                ),
                SizedBox(height: 24),
                Material(
                  color: Colors.transparent,
                  child: InkWell(
                    onTap: () {
                      if (countController.text.trim().isNotEmpty) {
                        setState(() {
                          selectedTradesmen[tradesmenName] = countController.text.trim();
                        });
                        Navigator.pop(context);
                      }
                    },
                    borderRadius: BorderRadius.circular(16),
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
                            Icons.check,
                            color: Colors.white,
                            size: 24,
                          ),
                          SizedBox(width: 12),
                          Text(
                            'Add Tradesmen',
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
              ],
            ),
          ),
        ),
      ),
    );
  }
}
