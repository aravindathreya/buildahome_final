import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:photo_view/photo_view.dart';
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
import 'package:provider/provider.dart';
import 'providers/theme_provider.dart';

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
    return Consumer<ThemeProvider>(
      builder: (context, themeProvider, child) {
        return MaterialApp(
          theme: AppTheme.getLightTheme(),
          darkTheme: AppTheme.getDarkTheme(),
          themeMode: themeProvider.isDarkMode ? ThemeMode.dark : ThemeMode.light,
          home: Scaffold(
            appBar: AppBar(
              automaticallyImplyLeading: true,
              title: Text(
                'buildAhome',
                style: TextStyle(color: AppTheme.getTextPrimary(context1)),
              ),
              leading: new IconButton(
                icon: new Icon(Icons.chevron_left),
                onPressed: () => {Navigator.pop(context1)},
              ),
              backgroundColor: AppTheme.getBackgroundSecondary(context1),
              iconTheme: IconThemeData(color: AppTheme.getTextPrimary(context1)),
            ),
            body: ImageOnly(this.image),
          ),
        );
      },
    );
  }
}

class ImageOnly extends StatelessWidget {
  final image;

  ImageOnly(this.image);

  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        border: Border.all(
          color: AppTheme.getTextSecondary(context).withOpacity(0.3),
        ),
      ),
      child: PhotoView(
        minScale: PhotoViewComputedScale.contained,
        imageProvider: this.image,
      ),
    );
  }
}

class AddDailyUpdate extends StatelessWidget {
  final bool returnToAdminDashboard;
  
  const AddDailyUpdate({Key? key, this.returnToAdminDashboard = false}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Consumer<ThemeProvider>(
      builder: (context, themeProvider, child) {
        return MaterialApp(
          title: 'buildAhome',
          theme: AppTheme.getLightTheme(),
          darkTheme: AppTheme.getDarkTheme(),
          themeMode: themeProvider.isDarkMode ? ThemeMode.dark : ThemeMode.light,
          home: Scaffold(
            backgroundColor: AppTheme.getBackgroundPrimary(context),
            appBar: AppBar(
              title: Text(
                'Add Daily Update',
                style: TextStyle(color: AppTheme.getTextPrimary(context)),
              ),
              automaticallyImplyLeading: true,
              backgroundColor: AppTheme.getBackgroundSecondary(context),
              iconTheme: IconThemeData(color: AppTheme.getTextPrimary(context)),
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
      },
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

  // PageView and step management
  late PageController _pageController;
  int _currentStep = 0;
  final int _totalSteps = 5;

  @override
  void initState() {
    super.initState();
    _pageController = PageController(initialPage: 0);
    setUserId();
    loadProjects();
  }

  @override
  void dispose() {
    _pageController.dispose();
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
        try {
          status = await Permission.camera.status;
          if (!status.isGranted) {
            status = await Permission.camera.request();
          }
        } catch (e) {
          print('[AddDailyUpdate] Camera permission error: $e');
          // If permission_handler fails, try to proceed anyway (image_picker might handle it)
          // Show dialog to inform user they may need to grant permission manually
          if (mounted) {
            await _showPermissionDeniedDialog(forCamera: true);
          }
          return false;
        }
      } else {
        // For gallery/photos - handle both Android storage and photos permissions
        try {
          // Try photos first (Android 13+)
          status = await Permission.photos.status;
          if (!status.isGranted) {
            status = await Permission.photos.request();
          }
          
          // If photos permission is not available (older Android), try storage
          if (!status.isGranted && Platform.isAndroid) {
            try {
              final storageStatus = await Permission.storage.status;
              if (!storageStatus.isGranted) {
                await Permission.storage.request();
              }
              // On Android, image_picker can work without explicit permission in some cases
              // Return true to let image_picker handle it
              return true;
            } catch (storageError) {
              print('[AddDailyUpdate] Storage permission error: $storageError');
              // If storage permission also fails, try to proceed anyway
              return true;
            }
          }
        } catch (e) {
          print('[AddDailyUpdate] Photos permission error: $e');
          // If permission_handler fails, try to proceed anyway (image_picker might handle it)
          // On Android, image_picker can work without explicit permission in some cases
          if (Platform.isAndroid) {
            return true;
          }
          if (mounted) {
            await _showPermissionDeniedDialog(forCamera: false);
          }
          return false;
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
      // For camera, show dialog since it's required
      if (mounted && forCamera) {
        await _showPermissionDeniedDialog(forCamera: true);
      }
      return false;
    }
  }

  Future<void> _showPermissionDeniedDialog({required bool forCamera}) async {
    if (!mounted) return;
    
    final permissionStatus = forCamera 
        ? await Permission.camera.status
        : await Permission.photos.status;
    
    final isPermanentlyDenied = permissionStatus.isPermanentlyDenied;
    
    await showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          backgroundColor: AppTheme.getBackgroundSecondary(context),
          title: Row(
            children: [
              Icon(Icons.camera_alt, color: Colors.orange, size: 24),
              SizedBox(width: 12),
              Expanded(
                child: Text(
                  'Permission Required',
                  style: TextStyle(
                    color: AppTheme.getTextPrimary(context),
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
          content: Text(
            forCamera
                ? 'Camera permission is required to take photos. ${isPermanentlyDenied ? 'Please enable it in your device settings.' : 'Would you like to grant permission?'}'
                : 'Photo library permission is required to select images. ${isPermanentlyDenied ? 'Please enable it in your device settings.' : 'Would you like to grant permission?'}',
            style: TextStyle(color: AppTheme.getTextSecondary(context)),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: Text(
                'Cancel',
                style: TextStyle(color: AppTheme.getTextSecondary(context)),
              ),
            ),
            if (!isPermanentlyDenied)
              TextButton(
                onPressed: () async {
                  Navigator.of(context).pop();
                  // Request permission again
                  if (forCamera) {
                    try {
                      final status = await Permission.camera.request();
                      if (status.isGranted && mounted) {
                        // Permission granted, proceed with camera action
                        await _takePhotoFromCamera();
                      } else if (mounted) {
                        // Permission still denied, show dialog again
                        await _showPermissionDeniedDialog(forCamera: true);
                      }
                    } catch (e) {
                      print('[AddDailyUpdate] Error requesting camera permission: $e');
                      // If permission request fails, try to open settings
                      if (mounted) {
                        await openAppSettings();
                      }
                    }
                  } else {
                    // For gallery, try photos permission first
                    try {
                      var status = await Permission.photos.request();
                      // If photos permission not available, try storage on Android
                      if (!status.isGranted && Platform.isAndroid) {
                        try {
                          status = await Permission.storage.request();
                        } catch (storageError) {
                          print('[AddDailyUpdate] Error requesting storage permission: $storageError');
                          // If storage permission also fails, try to proceed anyway
                          if (mounted) {
                            // On Android, image_picker might work without explicit permission
                            await _selectPicturesFromGallery();
                            return;
                          }
                        }
                      }
                      if (status.isGranted && mounted) {
                        // Permission granted, proceed with gallery action
                        await _selectPicturesFromGallery();
                      } else if (mounted) {
                        // Permission still denied or not granted, but on Android we can try anyway
                        if (Platform.isAndroid) {
                          // On Android, image_picker can work without explicit permission
                          await _selectPicturesFromGallery();
                        } else {
                          // On iOS, show dialog again
                          await _showPermissionDeniedDialog(forCamera: false);
                        }
                      }
                    } catch (e) {
                      print('[AddDailyUpdate] Error requesting photos permission: $e');
                      // If permission request fails, on Android try to proceed anyway
                      if (mounted) {
                        if (Platform.isAndroid) {
                          // On Android, image_picker might work without explicit permission
                          await _selectPicturesFromGallery();
                        } else {
                          // On iOS, open settings
                          await openAppSettings();
                        }
                      }
                    }
                  }
                },
                child: Text(
                  'Grant Permission',
                  style: TextStyle(
                    color: AppTheme.getPrimaryColor(context),
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              SizedBox(height: 10),
            ElevatedButton(
              onPressed: () async {
                Navigator.of(context).pop();
                // Open app settings
                await openAppSettings();
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.getPrimaryColor(context),
                padding: EdgeInsets.symmetric(vertical: 10, horizontal: 20),
                foregroundColor: AppTheme.getBackgroundPrimary(context),
              ),
              child: Text('Open Settings'),
            ),
          ],
        );
      },
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
          backgroundColor: AppTheme.getBackgroundSecondary(context),
          title: Text(
            'Select Image Source',
            style: TextStyle(color: AppTheme.getTextPrimary(context), fontWeight: FontWeight.bold),
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: Icon(Icons.camera_alt, color: AppTheme.getPrimaryColor(context)),
                title: Text('Take Photo', style: TextStyle(color: AppTheme.getTextPrimary(context))),
                onTap: () {
                  Navigator.pop(context);
                  _takePhotoFromCamera();
                },
              ),
              ListTile(
                leading: Icon(Icons.photo_library, color: AppTheme.getPrimaryColor(context)),
                title: Text('Choose from Gallery', style: TextStyle(color: AppTheme.getTextPrimary(context))),
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

  List<String> _getStepTitles() {
    return [
      'Select Project',
      'Add Pictures',
      'Select Tradesmen',
      'Daily Update',
      'Preview',
    ];
  }

  List<String> _getStepInstructions() {
    return [
      'Choose the project for this daily update',
      'Add photos of the work completed today',
      'Select the tradesmen and their count',
      'Write a detailed description of today\'s work',
      'Review all information before submitting',
    ];
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

  bool _isStepCompleted(int stepIndex) {
    switch (stepIndex) {
      case 0:
        return selectedProject != null;
      case 1:
        return selectedPictures.isNotEmpty;
      case 2:
        return selectedTradesmen.isNotEmpty;
      case 3:
        return dailyUpdateTextController.text.trim().isNotEmpty;
      case 4:
        // Preview step is completed if all previous steps are completed
        return selectedProject != null && 
               dailyUpdateTextController.text.trim().isNotEmpty;
      default:
        return false;
    }
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
              _buildStep2Pictures(),
              _buildStep3Tradesmen(),
              _buildStep4DailyUpdate(),
              _buildStep5Preview(),
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
                          'Uploading...',
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
      // Go back to step 1
      _pageController.animateToPage(
        0,
        duration: Duration(milliseconds: 300),
        curve: Curves.easeInOut,
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
      
      // Go back to step 4
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
          'date': new DateFormat('EEEE MMMM dd yyyy').format(DateTime.now()).toString(),
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
              'date': new DateFormat('EEEE MMMM dd yyyy').format(DateTime.now()).toString(),
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
              backgroundColor: AppTheme.getBackgroundSecondary(context),
              title: Text(
                "Error",
                style: TextStyle(color: Colors.red),
              ),
              content: Text(
                "An error occurred: ${e.toString()}",
                style: TextStyle(color: AppTheme.getTextPrimary(context)),
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
            instruction: 'Choose the project for this daily update from the list below',
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

  Widget _buildStep2Pictures() {
    return SingleChildScrollView(
      padding: EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          _buildSectionHeader(
            'Add Pictures',
            Icons.add_a_photo,
            isCompleted: selectedPictures.length > 0,
            instruction: 'Add photos of the work completed today. You can take new photos or select from your gallery',
          ),
          SizedBox(height: 20),
          Container(
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
                padding: EdgeInsets.all(18),
                child: Row(
                  children: <Widget>[
                    Container(
                      padding: EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: AppTheme.getPrimaryColor(context).withOpacity(0.2),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Icon(
                        Icons.add_a_photo,
                        size: 24,
                        color: AppTheme.getPrimaryColor(context),
                      ),
                    ),
                    SizedBox(width: 16),
                    Expanded(
                      child: Text(
                        attachPictureButtonText,
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                          color: AppTheme.getTextPrimary(context),
                        ),
                      ),
                    ),
                    Icon(
                      Icons.chevron_right,
                      color: AppTheme.getTextSecondary(context),
                    ),
                  ],
                ),
              ),
            ),
          ),

          //List of images stacked horizontally
          if (selectedPictures.length != 0)
            Container(
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
                        color: AppTheme.getTextPrimary(context),
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
                                      color: AppTheme.getPrimaryColor(context).withOpacity(0.3),
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
        ],
      ),
    );
  }

  Widget _buildStep3Tradesmen() {
    return SingleChildScrollView(
      padding: EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          _buildSectionHeader(
            'Select Tradesmen',
            Icons.people,
            isCompleted: selectedTradesmen.isNotEmpty,
            instruction: 'Select the tradesmen who worked today and specify the count for each',
          ),
          SizedBox(height: 20),
          InkWell(
            onTap: () async {
              final selectedTradesmenItem = await SearchableSelect.show(
                context: context,
                title: 'Select Tradesmen',
                items: availableResources,
                selectedItem: null,
              );
              if (selectedTradesmenItem != null) {
                _showTradesmenCountDialog(selectedTradesmenItem.toString());
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
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          selectedTradesmen.isEmpty
                              ? 'Select tradesmen'
                              : '${selectedTradesmen.length} tradesmen selected',
                          style: TextStyle(
                            color: selectedTradesmen.isEmpty
                                ? AppTheme.getTextSecondary(context)
                                : AppTheme.getTextPrimary(context),
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
                                  color: AppTheme.getPrimaryColor(context).withOpacity(0.2),
                                  borderRadius: BorderRadius.circular(20),
                                  border: Border.all(
                                    color: AppTheme.getPrimaryColor(context).withOpacity(0.5),
                                    width: 1,
                                  ),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Text(
                                      entry.key,
                                      style: TextStyle(
                                        color: AppTheme.getPrimaryColor(context),
                                        fontSize: 12,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                    SizedBox(width: 6),
                                    Container(
                                      padding: EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                      decoration: BoxDecoration(
                                        color: AppTheme.getPrimaryColor(context),
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
                                        color: AppTheme.getPrimaryColor(context),
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

  Widget _buildStep4DailyUpdate() {
    return SingleChildScrollView(
      padding: EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          _buildSectionHeader(
            'Daily Update',
            Icons.edit_note,
            isCompleted: dailyUpdateTextController.text.trim().isNotEmpty,
            instruction: 'Write a detailed description of what was accomplished today. Be specific about the work done',
          ),
          SizedBox(height: 20),
          Container(
            margin: EdgeInsets.only(bottom: 20),
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
                Row(
                  children: [
                    Icon(
                      Icons.calendar_today,
                      size: 16,
                      color: AppTheme.getTextSecondary(context),
                    ),
                    SizedBox(width: 8),
                    Text(
                      DateFormat("dd MMMM yyyy").format(DateTime.now()),
                      style: TextStyle(
                        fontSize: 13,
                        color: AppTheme.getTextSecondary(context),
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
                    color: AppTheme.getTextPrimary(context),
                  ),
                  onChanged: (value) {
                    setState(() {
                      // Update UI to show checkmark when text is entered
                    });
                  },
                  decoration: InputDecoration(
                    focusColor: AppTheme.getPrimaryColor(context),
                    floatingLabelBehavior: FloatingLabelBehavior.never,
                    errorBorder: OutlineInputBorder(
                      borderSide: BorderSide(color: Colors.red, width: 1.0),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderSide: BorderSide(color: AppTheme.getPrimaryColor(context), width: 2.0),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderSide: BorderSide(
                        color: AppTheme.getPrimaryColor(context).withOpacity(0.3),
                        width: 1.0,
                      ),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    filled: true,
                    hintText: "What's done today?",
                    hintStyle: TextStyle(color: AppTheme.getTextSecondary(context)),
                    alignLabelWithHint: true,
                    fillColor: AppTheme.getBackgroundPrimary(context),
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
        ],
      ),
    );
  }

  Widget _buildStep5Preview() {
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
          
          // Pictures Preview
          _buildPreviewCard(
            icon: Icons.add_a_photo,
            title: 'Pictures',
            content: selectedPictures.isEmpty
                ? 'No pictures added'
                : '${selectedPictures.length} picture${selectedPictures.length > 1 ? 's' : ''} selected',
            isComplete: selectedPictures.isNotEmpty,
            child: selectedPictures.isNotEmpty
                ? Container(
                    height: 100,
                    margin: EdgeInsets.only(top: 12),
                    child: ListView.builder(
                      scrollDirection: Axis.horizontal,
                      itemCount: selectedPictures.length,
                      itemBuilder: (context, index) {
                        return Container(
                          margin: EdgeInsets.only(right: 8),
                          width: 100,
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(
                              color: AppTheme.getPrimaryColor(context).withOpacity(0.3),
                              width: 1,
                            ),
                          ),
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(8),
                            child: Image(
                              image: selectedPictures[index],
                              fit: BoxFit.cover,
                            ),
                          ),
                        );
                      },
                    ),
                  )
                : null,
          ),
          SizedBox(height: 16),
          
          // Tradesmen Preview
          _buildPreviewCard(
            icon: Icons.people,
            title: 'Tradesmen',
            content: selectedTradesmen.isEmpty
                ? 'No tradesmen selected'
                : '${selectedTradesmen.length} tradesmen selected',
            isComplete: selectedTradesmen.isNotEmpty,
            child: selectedTradesmen.isNotEmpty
                ? Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: selectedTradesmen.entries.map((entry) {
                      return Container(
                        padding: EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                        decoration: BoxDecoration(
                          color: AppTheme.getPrimaryColor(context).withOpacity(0.1),
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(
                            color: AppTheme.getPrimaryColor(context).withOpacity(0.3),
                            width: 1,
                          ),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              entry.key,
                              style: TextStyle(
                                color: AppTheme.getPrimaryColor(context),
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            SizedBox(width: 6),
                            Container(
                              padding: EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                color: AppTheme.getPrimaryColor(context),
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
                          ],
                        ),
                      );
                    }).toList(),
                  )
                : null,
          ),
          SizedBox(height: 16),
          
          // Daily Update Preview
          _buildPreviewCard(
            icon: Icons.edit_note,
            title: 'Daily Update',
            content: dailyUpdateTextController.text.trim().isEmpty
                ? 'No update text entered'
                : dailyUpdateTextController.text.trim(),
            isComplete: dailyUpdateTextController.text.trim().isNotEmpty,
            isTextContent: true,
          ),
          SizedBox(height: 16),
          
          // Date Preview
          _buildPreviewCard(
            icon: Icons.calendar_today,
            title: 'Date',
            content: DateFormat("dd MMMM yyyy").format(DateTime.now()),
            isComplete: true,
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
    Widget? child,
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
          if (child != null) ...[
            SizedBox(height: 12),
            child,
          ],
        ],
      ),
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

  void _showTradesmenCountDialog(String tradesmenName) {
    final countController = TextEditingController();
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => Scaffold(
          backgroundColor: AppTheme.getBackgroundPrimary(context),
          appBar: AppBar(
            title: Text(
              'Enter Count',
              style: TextStyle(color: AppTheme.getTextPrimary(context)),
            ),
            backgroundColor: AppTheme.getBackgroundSecondary(context),
            iconTheme: IconThemeData(color: AppTheme.getTextPrimary(context)),
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
                      Row(
                        children: [
                          Container(
                            padding: EdgeInsets.all(10),
                            decoration: BoxDecoration(
                              color: AppTheme.getPrimaryColor(context).withOpacity(0.2),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Icon(
                              Icons.people,
                              color: AppTheme.getPrimaryColor(context),
                              size: 24,
                            ),
                          ),
                          SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              tradesmenName,
                              style: TextStyle(
                                color: AppTheme.getTextPrimary(context),
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
                          color: AppTheme.getTextSecondary(context),
                          fontSize: 14,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      SizedBox(height: 12),
                      TextField(
                        controller: countController,
                        keyboardType: TextInputType.number,
                        style: TextStyle(
                          color: AppTheme.getTextPrimary(context),
                          fontSize: 18,
                        ),
                        decoration: InputDecoration(
                          hintText: 'Enter count',
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
                            AppTheme.getPrimaryColor(context),
                            AppTheme.primaryColorConstDark,
                          ],
                        ),
                        borderRadius: BorderRadius.circular(16),
                        boxShadow: [
                          BoxShadow(
                            color: AppTheme.getPrimaryColor(context).withOpacity(0.3),
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
