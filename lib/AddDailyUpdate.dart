import 'package:flutter/material.dart';
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
import 'widgets/themed_scaffold.dart';
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
  Widget build(BuildContext context) {
    return ThemedScaffold(
      title: 'Photo',
      backgroundColor: Colors.black,
      body: ImageOnly(this.image),
    );
  }
}

class ImageOnly extends StatelessWidget {
  final image;

  ImageOnly(this.image);

  Widget build(BuildContext context) {
    return PhotoView(
      minScale: PhotoViewComputedScale.contained,
      backgroundDecoration: const BoxDecoration(color: Colors.black),
      imageProvider: this.image,
    );
  }
}

class AddDailyUpdate extends StatelessWidget {
  final bool returnToAdminDashboard;
  
  const AddDailyUpdate({Key? key, this.returnToAdminDashboard = false}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return ThemedScaffold(
      title: 'Add Daily Update',
      backgroundColor: const Color(0xFFF7F8FB),
      body: SafeArea(
        child: AddDailyUpdateForm(returnToAdminDashboard: returnToAdminDashboard),
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
  static const Color _navy = AppTheme.navy;
  static const Color _mutedGrey = AppTheme.mutedGrey;
  static const Color _cardBorder = AppTheme.border;
  static const Color _softShadow = AppTheme.softShadow;
  static const Color _pageBg = Color(0xFFF7F8FB);
  static const Color _success = Color(0xFF16A34A);
  static const Color _successBg = Color(0xFFDCFCE7);

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

  BoxDecoration _surfaceCard({Color? borderColor}) {
    return BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(18),
      border: Border.all(color: borderColor ?? _cardBorder),
      boxShadow: const [
        BoxShadow(
          color: _softShadow,
          blurRadius: 18,
          offset: Offset(0, 8),
        ),
      ],
    );
  }

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

  void _dismissKeyboard() {
    FocusManager.instance.primaryFocus?.unfocus();
  }

  void _nextStep() {
    if (_currentStep < _totalSteps - 1) {
      // Leaving the daily update text step → preview: close keyboard first
      if (_currentStep + 1 == _totalSteps - 1) {
        _dismissKeyboard();
      }
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

  /// Camera needs an explicit permission. Gallery uses the system photo picker
  /// (PHPicker / Android Photo Picker), so pre-checking Permission.photos is
  /// unnecessary and incorrectly blocks Limited Photo Access on iOS.
  Future<bool> checkPermissionStatus({required bool forCamera}) async {
    if (!forCamera) return true;

    try {
      var status = await Permission.camera.status;
      if (status.isGranted) return true;

      status = await Permission.camera.request();
      if (status.isGranted) return true;

      if (mounted) {
        await _showPermissionDeniedDialog(forCamera: true);
      }
      return false;
    } catch (e) {
      print('[AddDailyUpdate] Camera permission error: $e');
      // Let image_picker attempt the request itself.
      return true;
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
      builder: (BuildContext dialogContext) {
        return AlertDialog(
          backgroundColor: Colors.white,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: Row(
            children: [
              Icon(
                forCamera ? Icons.photo_camera_rounded : Icons.photo_library_rounded,
                color: const Color(0xFFEA580C),
                size: 24,
              ),
              const SizedBox(width: 12),
              const Expanded(
                child: Text(
                  'Permission Required',
                  style: TextStyle(
                    color: AppTheme.navy,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ],
          ),
          content: Text(
            forCamera
                ? 'Camera permission is required to take photos. ${isPermanentlyDenied ? 'Please enable it in your device settings.' : 'Please allow camera access when prompted.'}'
                : 'Photo access is needed to select images. ${isPermanentlyDenied ? 'Please enable it in your device settings.' : 'Please allow access when prompted.'}',
            style: const TextStyle(
              color: AppTheme.mutedGrey,
              fontWeight: FontWeight.w500,
              height: 1.4,
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text(
                'Cancel',
                style: TextStyle(
                  color: AppTheme.mutedGrey,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            if (!isPermanentlyDenied && forCamera)
              TextButton(
                onPressed: () async {
                  Navigator.of(dialogContext).pop();
                  final status = await Permission.camera.request();
                  if (status.isGranted && mounted) {
                    await _takePhotoFromCamera();
                  } else if (mounted) {
                    await openAppSettings();
                  }
                },
                child: const Text(
                  'Grant Permission',
                  style: TextStyle(
                    color: AppTheme.navy,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ElevatedButton(
              onPressed: () async {
                Navigator.of(dialogContext).pop();
                await openAppSettings();
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.navy,
                foregroundColor: Colors.white,
                elevation: 0,
                padding:
                    const EdgeInsets.symmetric(vertical: 10, horizontal: 16),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              child: const Text('Open Settings'),
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
          backgroundColor: Colors.white,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: const Text(
            'Select Image Source',
            style: TextStyle(
              color: _navy,
              fontWeight: FontWeight.w800,
              fontSize: 17,
            ),
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: const Color(0xFFEEF2FF),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(Icons.photo_camera_rounded, color: _navy, size: 20),
                ),
                title: const Text(
                  'Take Photo',
                  style: TextStyle(color: _navy, fontWeight: FontWeight.w700),
                ),
                onTap: () {
                  Navigator.pop(context);
                  _takePhotoFromCamera();
                },
              ),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: const Color(0xFFEEF2FF),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(Icons.photo_library_rounded, color: _navy, size: 20),
                ),
                title: const Text(
                  'Choose from Gallery',
                  style: TextStyle(color: _navy, fontWeight: FontWeight.w700),
                ),
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

      // Do not pre-check Permission.photos — the system gallery picker handles
      // access, and a strict photos check incorrectly fails for Limited Access.
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
    final progress = (_currentStep + 1) / _totalSteps;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 14),
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(bottom: BorderSide(color: _cardBorder)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                'Step ${_currentStep + 1} of $_totalSteps',
                style: const TextStyle(
                  color: _mutedGrey,
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.3,
                ),
              ),
              const Spacer(),
              Text(
                stepTitles[_currentStep],
                style: const TextStyle(
                  color: _navy,
                  fontSize: 13,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          ClipRRect(
            borderRadius: BorderRadius.circular(999),
            child: LinearProgressIndicator(
              value: progress,
              minHeight: 6,
              backgroundColor: const Color(0xFFEEF2F7),
              valueColor: const AlwaysStoppedAnimation<Color>(_navy),
            ),
          ),
          const SizedBox(height: 12),
          Text(
            stepInstructions[_currentStep],
            style: const TextStyle(
              color: _mutedGrey,
              fontSize: 13,
              fontWeight: FontWeight.w500,
              height: 1.35,
            ),
          ),
          const SizedBox(height: 14),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: List.generate(_totalSteps, (index) {
                final isActive = index == _currentStep;
                final isCompleted = _isStepCompleted(index);
                return Padding(
                  padding: EdgeInsets.only(right: index == _totalSteps - 1 ? 0 : 8),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    decoration: BoxDecoration(
                      color: isActive
                          ? _navy
                          : isCompleted
                              ? _successBg
                              : const Color(0xFFF1F4F8),
                      borderRadius: BorderRadius.circular(999),
                      border: Border.all(
                        color: isActive
                            ? _navy
                            : isCompleted
                                ? const Color(0xFFBBF7D0)
                                : _cardBorder,
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (isCompleted && !isActive) ...[
                          const Icon(Icons.check_rounded, size: 14, color: _success),
                          const SizedBox(width: 4),
                        ] else ...[
                          Text(
                            '${index + 1}',
                            style: TextStyle(
                              color: isActive ? Colors.white : _mutedGrey,
                              fontSize: 12,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          const SizedBox(width: 5),
                        ],
                        Text(
                          stepTitles[index],
                          style: TextStyle(
                            color: isActive
                                ? Colors.white
                                : isCompleted
                                    ? _success
                                    : _mutedGrey,
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              }),
            ),
          ),
        ],
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
              if (index == _totalSteps - 1) {
                _dismissKeyboard();
              }
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
      padding: const EdgeInsets.fromLTRB(20, 14, 20, 20),
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(top: BorderSide(color: _cardBorder)),
      ),
      child: Row(
        children: [
          if (_currentStep > 0)
            Expanded(
              child: OutlinedButton(
                onPressed: _previousStep,
                style: OutlinedButton.styleFrom(
                  foregroundColor: _navy,
                  side: const BorderSide(color: _cardBorder),
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
                child: const Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.arrow_back_rounded, size: 18),
                    SizedBox(width: 8),
                    Text(
                      'Back',
                      style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
                    ),
                  ],
                ),
              ),
            ),
          if (_currentStep > 0) const SizedBox(width: 12),
          Expanded(
            child: ElevatedButton(
              onPressed: isUploading
                  ? null
                  : (_currentStep == _totalSteps - 1
                      ? () async {
                          await _handleSubmit();
                        }
                      : _nextStep),
              style: ElevatedButton.styleFrom(
                backgroundColor: _navy,
                foregroundColor: Colors.white,
                disabledBackgroundColor: _navy.withValues(alpha: 0.55),
                elevation: 0,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  if (isUploading) ...[
                    const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                      ),
                    ),
                    const SizedBox(width: 10),
                    const Text(
                      'Uploading...',
                      style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800),
                    ),
                  ] else if (_currentStep == _totalSteps - 1) ...[
                    const Icon(Icons.cloud_upload_rounded, size: 18),
                    const SizedBox(width: 8),
                    const Text(
                      'Submit',
                      style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800),
                    ),
                  ] else ...[
                    const Text(
                      'Next',
                      style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800),
                    ),
                    const SizedBox(width: 8),
                    const Icon(Icons.arrow_forward_rounded, size: 18),
                  ],
                ],
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
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          _buildSectionHeader(
            'Select Project',
            Icons.folder_special_rounded,
            isCompleted: selectedProject != null,
            instruction: 'Choose the project for this daily update from the list below',
          ),
          const SizedBox(height: 18),
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
            borderRadius: BorderRadius.circular(18),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 18),
              decoration: _surfaceCard(
                borderColor: selectedProject != null
                    ? const Color(0xFFBBF7D0)
                    : _cardBorder,
              ),
              child: Row(
                children: [
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: const Color(0xFFEEF2FF),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(Icons.apartment_rounded, color: _navy),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          selectedProject != null ? 'Selected project' : 'Project',
                          style: const TextStyle(
                            color: _mutedGrey,
                            fontSize: 11.5,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 0.4,
                          ),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          selectedProject != null
                              ? (selectedProject['name'] ?? 'Unknown')
                              : 'Tap to select a project',
                          style: TextStyle(
                            color: selectedProject != null ? _navy : _mutedGrey,
                            fontSize: 15.5,
                            fontWeight: selectedProject != null
                                ? FontWeight.w800
                                : FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const Icon(Icons.chevron_right_rounded, color: _mutedGrey),
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
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          _buildSectionHeader(
            'Add Pictures',
            Icons.add_a_photo_rounded,
            isCompleted: selectedPictures.isNotEmpty,
            instruction:
                'Add photos of the work completed today. You can take new photos or select from your gallery',
          ),
          const SizedBox(height: 18),
          InkWell(
            onTap: () async => selectPicturesFromPhone(),
            borderRadius: BorderRadius.circular(18),
            child: Container(
              margin: const EdgeInsets.only(bottom: 20),
              decoration: _surfaceCard(),
              padding: const EdgeInsets.all(16),
              child: Row(
                children: <Widget>[
                  Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                      color: const Color(0xFFEEF2FF),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: const Icon(
                      Icons.add_a_photo_rounded,
                      size: 22,
                      color: _navy,
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          attachPictureButtonText,
                          style: const TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w800,
                            color: _navy,
                          ),
                        ),
                        const SizedBox(height: 3),
                        const Text(
                          'Camera or gallery',
                          style: TextStyle(
                            fontSize: 12.5,
                            fontWeight: FontWeight.w500,
                            color: _mutedGrey,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const Icon(Icons.chevron_right_rounded, color: _mutedGrey),
                ],
              ),
            ),
          ),
          if (selectedPictures.isNotEmpty)
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Selected images (${selectedPictures.length})',
                  style: const TextStyle(
                    fontSize: 14.5,
                    fontWeight: FontWeight.w800,
                    color: _navy,
                  ),
                ),
                const SizedBox(height: 12),
                SizedBox(
                  height: 148,
                  child: ListView.builder(
                    scrollDirection: Axis.horizontal,
                    itemCount: selectedPictures.length,
                    itemBuilder: (BuildContext ctxt, int index) {
                      return Container(
                        margin: const EdgeInsets.only(right: 12),
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
                              borderRadius: BorderRadius.circular(16),
                              child: Container(
                                height: 148,
                                width: 148,
                                decoration: BoxDecoration(
                                  image: DecorationImage(
                                    image: selectedPictures[index],
                                    fit: BoxFit.cover,
                                  ),
                                  border: Border.all(color: _cardBorder),
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
                                    if (selectedPictures.isEmpty) {
                                      attachPictureButtonText =
                                          'Add picture from phone';
                                    }
                                  });
                                },
                                child: Container(
                                  height: 30,
                                  width: 30,
                                  decoration: BoxDecoration(
                                    color: const Color(0xFFDC2626),
                                    shape: BoxShape.circle,
                                    border: Border.all(color: Colors.white, width: 2),
                                  ),
                                  child: const Icon(
                                    Icons.close_rounded,
                                    size: 16,
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
        ],
      ),
    );
  }

  Widget _buildStep3Tradesmen() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          _buildSectionHeader(
            'Select Tradesmen',
            Icons.groups_rounded,
            isCompleted: selectedTradesmen.isNotEmpty,
            instruction:
                'Select the tradesmen who worked today and specify the count for each',
          ),
          const SizedBox(height: 18),
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
            borderRadius: BorderRadius.circular(18),
            child: Container(
              margin: const EdgeInsets.only(bottom: 20),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 18),
              decoration: _surfaceCard(
                borderColor: selectedTradesmen.isNotEmpty
                    ? const Color(0xFFBBF7D0)
                    : _cardBorder,
              ),
              child: Row(
                children: [
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: const Color(0xFFEEF2FF),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(Icons.groups_rounded, color: _navy),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          selectedTradesmen.isEmpty
                              ? 'Tap to add tradesmen'
                              : '${selectedTradesmen.length} tradesmen selected',
                          style: TextStyle(
                            color: selectedTradesmen.isEmpty ? _mutedGrey : _navy,
                            fontSize: 15,
                            fontWeight: selectedTradesmen.isEmpty
                                ? FontWeight.w600
                                : FontWeight.w800,
                          ),
                        ),
                        if (selectedTradesmen.isNotEmpty) ...[
                          const SizedBox(height: 10),
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: selectedTradesmen.entries.map((entry) {
                              return Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 10, vertical: 6),
                                decoration: BoxDecoration(
                                  color: const Color(0xFFEEF2FF),
                                  borderRadius: BorderRadius.circular(999),
                                  border: Border.all(color: _cardBorder),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Text(
                                      entry.key,
                                      style: const TextStyle(
                                        color: _navy,
                                        fontSize: 12,
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                    const SizedBox(width: 6),
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 6, vertical: 2),
                                      decoration: BoxDecoration(
                                        color: _navy,
                                        borderRadius: BorderRadius.circular(999),
                                      ),
                                      child: Text(
                                        entry.value,
                                        style: const TextStyle(
                                          color: Colors.white,
                                          fontSize: 11,
                                          fontWeight: FontWeight.w800,
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 4),
                                    InkWell(
                                      onTap: () {
                                        setState(() {
                                          selectedTradesmen.remove(entry.key);
                                        });
                                      },
                                      child: const Icon(
                                        Icons.close_rounded,
                                        size: 15,
                                        color: _mutedGrey,
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
                  const SizedBox(width: 8),
                  const Icon(Icons.chevron_right_rounded, color: _mutedGrey),
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
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          _buildSectionHeader(
            'Daily Update',
            Icons.edit_note_rounded,
            isCompleted: dailyUpdateTextController.text.trim().isNotEmpty,
            instruction:
                'Write a detailed description of what was accomplished today. Be specific about the work done',
          ),
          const SizedBox(height: 18),
          Container(
            margin: const EdgeInsets.only(bottom: 20),
            padding: const EdgeInsets.all(16),
            decoration: _surfaceCard(
              borderColor: dailyUpdateTextController.text.trim().isNotEmpty
                  ? const Color(0xFFBBF7D0)
                  : _cardBorder,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF1F4F8),
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.calendar_today_rounded,
                              size: 14, color: _mutedGrey),
                          const SizedBox(width: 6),
                          Text(
                            DateFormat('dd MMMM yyyy').format(DateTime.now()),
                            style: const TextStyle(
                              fontSize: 12.5,
                              color: _mutedGrey,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                TextFormField(
                  autocorrect: true,
                  controller: dailyUpdateTextController,
                  keyboardType: TextInputType.multiline,
                  textCapitalization: TextCapitalization.sentences,
                  maxLines: 8,
                  style: const TextStyle(
                    fontSize: 15.5,
                    color: _navy,
                    fontWeight: FontWeight.w500,
                    height: 1.45,
                  ),
                  onChanged: (value) {
                    setState(() {});
                  },
                  decoration: InputDecoration(
                    floatingLabelBehavior: FloatingLabelBehavior.never,
                    errorBorder: OutlineInputBorder(
                      borderSide: const BorderSide(color: Color(0xFFDC2626)),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderSide: const BorderSide(color: _navy, width: 1.5),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderSide: const BorderSide(color: _cardBorder),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    filled: true,
                    hintText: "What's done today?",
                    hintStyle: const TextStyle(
                      color: _mutedGrey,
                      fontWeight: FontWeight.w500,
                    ),
                    alignLabelWithHint: true,
                    fillColor: _pageBg,
                    contentPadding: const EdgeInsets.all(16),
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
            Icons.preview_rounded,
            isCompleted: false,
            instruction: 'Review all information before submitting',
          ),
          const SizedBox(height: 20),
          _buildPreviewCard(
            icon: Icons.folder_special_rounded,
            title: 'Project',
            content: selectedProject != null
                ? (selectedProject['name'] ?? 'Unknown')
                : 'Not selected',
            isComplete: selectedProject != null,
          ),
          const SizedBox(height: 12),
          _buildPreviewCard(
            icon: Icons.add_a_photo_rounded,
            title: 'Pictures',
            content: selectedPictures.isEmpty
                ? 'No pictures added'
                : '${selectedPictures.length} picture${selectedPictures.length > 1 ? 's' : ''} selected',
            isComplete: selectedPictures.isNotEmpty,
            child: selectedPictures.isNotEmpty
                ? SizedBox(
                    height: 96,
                    child: ListView.builder(
                      scrollDirection: Axis.horizontal,
                      itemCount: selectedPictures.length,
                      itemBuilder: (context, index) {
                        return Container(
                          margin: const EdgeInsets.only(right: 8),
                          width: 96,
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: _cardBorder),
                          ),
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(12),
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
          const SizedBox(height: 12),
          _buildPreviewCard(
            icon: Icons.groups_rounded,
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
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 6),
                        decoration: BoxDecoration(
                          color: const Color(0xFFEEF2FF),
                          borderRadius: BorderRadius.circular(999),
                          border: Border.all(color: _cardBorder),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              entry.key,
                              style: const TextStyle(
                                color: _navy,
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            const SizedBox(width: 6),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                color: _navy,
                                borderRadius: BorderRadius.circular(999),
                              ),
                              child: Text(
                                entry.value,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 11,
                                  fontWeight: FontWeight.w800,
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
          const SizedBox(height: 12),
          _buildPreviewCard(
            icon: Icons.edit_note_rounded,
            title: 'Daily Update',
            content: dailyUpdateTextController.text.trim().isEmpty
                ? 'No update text entered'
                : dailyUpdateTextController.text.trim(),
            isComplete: dailyUpdateTextController.text.trim().isNotEmpty,
            isTextContent: true,
          ),
          const SizedBox(height: 12),
          _buildPreviewCard(
            icon: Icons.calendar_today_rounded,
            title: 'Date',
            content: DateFormat('dd MMMM yyyy').format(DateTime.now()),
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
      padding: const EdgeInsets.all(16),
      decoration: _surfaceCard(
        borderColor: isComplete ? const Color(0xFFBBF7D0) : _cardBorder,
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
                  color: isComplete ? _successBg : const Color(0xFFEEF2FF),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  icon,
                  size: 20,
                  color: isComplete ? _success : _navy,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                    color: _navy,
                  ),
                ),
              ),
              if (isComplete)
                const Icon(Icons.check_circle_rounded, color: _success, size: 20),
            ],
          ),
          const SizedBox(height: 12),
          if (isTextContent)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: _pageBg,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: _cardBorder),
              ),
              child: Text(
                content,
                style: const TextStyle(
                  fontSize: 14,
                  color: _navy,
                  height: 1.5,
                  fontWeight: FontWeight.w500,
                ),
              ),
            )
          else
            Text(
              content,
              style: TextStyle(
                fontSize: 14,
                color: isComplete ? _navy : _mutedGrey,
                fontWeight: isComplete ? FontWeight.w600 : FontWeight.w500,
              ),
            ),
          if (child != null) ...[
            const SizedBox(height: 12),
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
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                color: isCompleted ? _successBg : const Color(0xFFEEF2FF),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(
                isCompleted ? Icons.check_rounded : icon,
                size: 20,
                color: isCompleted ? _success : _navy,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                title,
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                  color: isCompleted ? _success : _navy,
                  letterSpacing: -0.2,
                ),
              ),
            ),
          ],
        ),
        if (instruction != null) ...[
          const SizedBox(height: 8),
          Padding(
            padding: const EdgeInsets.only(left: 54),
            child: Text(
              instruction,
              style: const TextStyle(
                fontSize: 13.5,
                color: _mutedGrey,
                height: 1.4,
                fontWeight: FontWeight.w500,
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
        builder: (context) => ThemedScaffold(
          title: 'Enter Count',
          backgroundColor: _pageBg,
          body: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  padding: const EdgeInsets.all(18),
                  decoration: _surfaceCard(),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Container(
                            width: 44,
                            height: 44,
                            decoration: BoxDecoration(
                              color: const Color(0xFFEEF2FF),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: const Icon(
                              Icons.groups_rounded,
                              color: _navy,
                              size: 22,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              tradesmenName,
                              style: const TextStyle(
                                color: _navy,
                                fontSize: 18,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 22),
                      const Text(
                        'Number of workers',
                        style: TextStyle(
                          color: _mutedGrey,
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 10),
                      TextField(
                        controller: countController,
                        keyboardType: TextInputType.number,
                        style: const TextStyle(
                          color: _navy,
                          fontSize: 18,
                          fontWeight: FontWeight.w700,
                        ),
                        decoration: InputDecoration(
                          hintText: 'Enter count',
                          hintStyle: const TextStyle(
                            color: _mutedGrey,
                            fontWeight: FontWeight.w500,
                          ),
                          filled: true,
                          fillColor: _pageBg,
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(14),
                            borderSide: const BorderSide(color: _cardBorder),
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(14),
                            borderSide: const BorderSide(color: _cardBorder),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(14),
                            borderSide: const BorderSide(color: _navy, width: 1.5),
                          ),
                          contentPadding: const EdgeInsets.symmetric(
                              horizontal: 16, vertical: 16),
                        ),
                        autofocus: true,
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 20),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: () {
                      if (countController.text.trim().isNotEmpty) {
                        setState(() {
                          selectedTradesmen[tradesmenName] =
                              countController.text.trim();
                        });
                        Navigator.pop(context);
                      }
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _navy,
                      foregroundColor: Colors.white,
                      elevation: 0,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                    child: const Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.check_rounded, size: 20),
                        SizedBox(width: 8),
                        Text(
                          'Add Tradesmen',
                          style: TextStyle(
                            fontSize: 15.5,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ],
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
