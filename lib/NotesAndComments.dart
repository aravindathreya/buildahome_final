import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:cached_network_image/cached_network_image.dart';

import 'Gallery.dart';
import 'Scheduler.dart';
import 'ShowAlert.dart';
import 'app_theme.dart';
import 'services/data_provider.dart';
import 'widgets/dark_mode_toggle.dart';
import 'AddDailyUpdate.dart'; // For FullScreenImage if needed, or I can implement it here

class NotesAndComments extends StatefulWidget {
  const NotesAndComments({super.key});

  @override
  NotesAndCommentsState createState() {
    return NotesAndCommentsState();
  }
}

class NotesAndCommentsState extends State<NotesAndComments> {
  String? projectId;
  List<dynamic>? notes;
  bool showPostBtn = false;
  String? userId;
  var selectedPictures = [];
  var selectedPictureFilenames = [];
  var selectedPictureFilePaths = [];
  bool _isLoading = false;
  bool _isRefreshing = false;
  String? _errorMessage;
  int _loadRequestId = 0;
  static const Duration _requestTimeout = Duration(seconds: 20);

  final TextEditingController message = TextEditingController();

  @override
  void initState() {
    super.initState();
    getNotes();
  }

  Future<void> getNotes({bool showLoader = true}) async {
    final int requestId = ++_loadRequestId;

    if (showLoader) {
      if (!mounted) return;
      setState(() {
        _isLoading = true;
        _errorMessage = null;
      });
    } else {
      if (!mounted) return;
      setState(() {
        _isRefreshing = true;
        _errorMessage = null;
      });
    }

    try {
      final prefs = await SharedPreferences.getInstance();
      final currentProjectId = prefs.getString('project_id');
      userId = prefs.getString('user_id');

      if (currentProjectId == null) {
        throw Exception('Project not selected. Please reopen the project and try again.');
      }

      // Check cache for non-Client users
      final dataProvider = DataProvider();
      final role = prefs.getString('role');
      List<dynamic>? cachedData;
      if (role != null && role != 'Client' && dataProvider.cachedNotes != null) {
        cachedData = dataProvider.cachedNotes;
      }

      // Use cache if available and not initial load
      if (cachedData != null && !showLoader) {
        if (!mounted) return;
        setState(() {
          notes = cachedData;
          projectId = currentProjectId;
        });
        
        // Still refresh in background
        _fetchNotesFromApi(currentProjectId, dataProvider, role, requestId);
        return;
      }

      // Fetch from API
      await _fetchNotesFromApi(currentProjectId, dataProvider, role, requestId);
    } catch (e) {
      if (_shouldIgnoreLoad(requestId)) return;
      if (!mounted) return;
      setState(() {
        _errorMessage = e.toString().replaceAll('Exception: ', '');
      });
    } finally {
      if (_shouldIgnoreLoad(requestId)) return;
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _isRefreshing = false;
      });
    }
  }

  Future<void> _fetchNotesFromApi(String projectId, DataProvider dataProvider, String? userRole, int requestId) async {
    try {
      final url = 'https://office1.buildahome.in/API/get_notes?project_id=$projectId';
      final response = await http.get(Uri.parse(url)).timeout(_requestTimeout);
      
      if (response.statusCode != 200) {
        throw Exception('Unable to load notes right now. Please try again.');
      }

      final parsed = jsonDecode(response.body);
      
      // Update cache for non-Client users
      if (userRole != null && userRole != 'Client') {
        dataProvider.cachedNotes = parsed is List ? parsed : [];
        dataProvider.lastNotesLoad = DateTime.now();
      }

      if (_shouldIgnoreLoad(requestId)) return;
      if (!mounted) return;
      setState(() {
        notes = parsed;
        projectId = projectId; // Keep the existing projectId
      });
    } catch (e) {
      if (_shouldIgnoreLoad(requestId)) return;
      rethrow;
    }
  }

  bool _shouldIgnoreLoad(int requestId) => !mounted || requestId != _loadRequestId;

  Future<bool> checkPermissionStatus({required bool forCamera}) async {
    try {
      PermissionStatus status;
      if (forCamera) {
        status = await Permission.camera.status;
        if (!status.isGranted) {
          status = await Permission.camera.request();
        }
      } else {
        status = await Permission.photos.status;
        if (!status.isGranted) {
          status = await Permission.photos.request();
        }
        if (!status.isGranted && Platform.isAndroid) {
          final storageStatus = await Permission.storage.status;
          if (!storageStatus.isGranted) {
            await Permission.storage.request();
          }
          return true;
        }
      }
      return status.isGranted;
    } catch (e) {
      return !forCamera && Platform.isAndroid;
    }
  }

  Future<void> _showImageSourceDialog() async {
    await showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          backgroundColor: AppTheme.getBackgroundSecondary(context),
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
            ],
          ),
        );
      },
    );
  }

  Future<void> _takePhotoFromCamera() async {
    if (!await checkPermissionStatus(forCamera: true)) return;
    final picker = ImagePicker();
    final pickedFile = await picker.pickImage(source: ImageSource.camera, imageQuality: 85);
    if (pickedFile != null) _processImage(pickedFile);
  }

  Future<void> _selectPicturesFromGallery() async {
    if (!await checkPermissionStatus(forCamera: false)) return;
    final picker = ImagePicker();
    final pickedFiles = await picker.pickMultiImage(imageQuality: 85);
    for (var file in pickedFiles) {
      _processImage(file);
    }
  }

  void _processImage(XFile file) {
    setState(() {
      selectedPictures.insert(0, FileImage(File(file.path)));
      selectedPictureFilenames.insert(0, file.name);
      selectedPictureFilePaths.insert(0, file.path);
      showPostBtn = true;
    });
  }

  Future<void> _postNote() async {
    
    final prefs = await SharedPreferences.getInstance();
    final currentProjectId = prefs.getString('project_id');
    final userId = prefs.getString('user_id');
    if (currentProjectId == null || userId == null) return;
    showDialog(
      barrierDismissible: false,
      context: context,
      builder: (BuildContext context) {
        return ShowAlert("Hang in there. Submitting update", true);
      },
    );

    try {
      if (selectedPictureFilePaths.isEmpty) {
        await _submitSingleNote(null);
      } else {
        for (String filePath in selectedPictureFilePaths) {
          await _submitSingleNote(filePath);
        }
      }

      if (mounted) {
        Navigator.pop(context);
        await showDialog(
          context: context,
          builder: (BuildContext context) {
            return ShowAlert("Note added successfully", false);
          },
        );
        message.clear();
        showPostBtn = false;
        selectedPictures.clear();
        selectedPictureFilenames.clear();
        selectedPictureFilePaths.clear();
        setState(() {});
        await getNotes();
      }
    } catch (err) {
      if (mounted) {
        Navigator.pop(context);
        debugPrint('Failed to post note: $err');
        await showDialog(
          context: context,
          builder: (BuildContext context) {
            return ShowAlert("Something went wrong", false);
          },
        );
      }
    }
  }

  Future<void> _submitSingleNote(String? filePath) async {
    final prefs = await SharedPreferences.getInstance();
    final currentProjectId = prefs.getString('project_id');
    final userId = prefs.getString('user_id');
    print("projectId: $currentProjectId");
    print("userId: $userId");
    print("message: ${message.text}");
    final url = Uri.parse("https://office1.buildahome.in/API/post_comment");
    final response = await http.post(url, body: {'project_id': currentProjectId!, 'user_id': userId!, 'note': message.text});
    print("response: ${response.body}");
    if (response.statusCode != 200) {
      throw Exception('Server returned ${response.statusCode}');
    }

    print("post single note: ${response.body}");

    if (filePath != null) {
      try {
        final responseBody = jsonDecode(response.body);
        final noteId = responseBody['note_id'];
        
        if (noteId != null) {
          final uri = Uri.parse("https://office1.buildahome.in/API/notes_picture_uplpoad");
          final request = http.MultipartRequest("POST", uri);
          request.fields['note_id'] = noteId.toString();
          request.files.add(await http.MultipartFile.fromPath("file", filePath));
          await request.send();
        }
      } catch (e) {
        debugPrint('Failed to upload attachment: $e');
        // We don't throw here to allow the process to continue even if attachment fails
        // but since we are in a loop, maybe we should? The user said "it should post even without attachment".
      }
    }
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
      throw 'Could not launch $url';
    }
  }

  @override
  void dispose() {
    message.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final canPop = Navigator.of(context).canPop();
    return Scaffold(
      backgroundColor: AppTheme.getBackgroundPrimary(context),
      appBar: AppBar(
        backgroundColor: AppTheme.getBackgroundSecondary(context),
        automaticallyImplyLeading: canPop,
        leading: canPop
            ? IconButton(
                icon: const Icon(Icons.arrow_back_ios_new_rounded),
                onPressed: () => Navigator.of(context).maybePop(),
              )
            : null,
        title: Text(
          'ChatBox',
          style: theme.textTheme.headlineSmall?.copyWith(fontSize: 20),
        ),
        actions: [
          DarkModeToggle(showLabel: false),
          
        ],
      ),
      body: SafeArea(
        child: RefreshIndicator(
          color: AppTheme.getPrimaryColor(context),
          onRefresh: () => getNotes(showLoader: false),
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(16, 24, 16, 32),
            children: [
              _buildHeader(theme),
              const SizedBox(height: 20),
              _buildComposer(theme),
              if (showPostBtn)
                Align(
                  alignment: Alignment.centerRight,
                  child: Padding(
                    padding: const EdgeInsets.only(top: 12),
                    child: FilledButton(
                      onPressed: _postNote,
                      child: const Padding(
                        padding: EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                        child: Text('Post 1', style: TextStyle(fontWeight: FontWeight.w600, color: Colors.white)),
                      ),
                    ),
                  ),
                ),
              const SizedBox(height: 24),
              Text(
                'Previous messages',
                style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 12),
              if (_errorMessage != null && (notes == null || notes!.isEmpty))
                _buildErrorState()
              else if (_isLoading && (notes == null || notes!.isEmpty))
                ...List.generate(3, (_) => _buildNoteSkeleton())
              else if (notes == null || notes!.isEmpty)
                _buildEmptyState()
              else ...[
                if (_isRefreshing && notes!.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 16),
                    child: Center(
                      child: SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          valueColor: AlwaysStoppedAnimation<Color>(AppTheme.getPrimaryColor(context)),
                        ),
                      ),
                    ),
                  ),
                ...notes!.map((note) => _buildNoteCard(note)).toList(),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeader(ThemeData theme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Stay aligned with your site team',
          style: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 8),
        Text(
          'Share instructions, raise clarifications and review updates directly with buildAhome.',
          style: theme.textTheme.bodyMedium?.copyWith(color: AppTheme.getTextSecondary(context)),
        ),
      ],
    );
  }

  Widget _buildComposer(ThemeData theme) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.backgroundSecondary,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextField(
            controller: message,
            autocorrect: true,
            keyboardType: TextInputType.multiline,
            textCapitalization: TextCapitalization.sentences,
            maxLines: 4,
            onChanged: (value) {
              setState(() {
                showPostBtn = value.trim().isNotEmpty || selectedPictureFilePaths.isNotEmpty;
              });
            },
            decoration: const InputDecoration(
              hintText: "Add a note",
            ),
          ),
          const SizedBox(height: 16),
          InkWell(
            onTap: _showImageSourceDialog,
            borderRadius: BorderRadius.circular(12),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                color: AppTheme.getBackgroundPrimaryLight(context),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppTheme.getPrimaryColor(context).withOpacity(0.1)),
              ),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: AppTheme.getPrimaryColor(context).withOpacity(0.1),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Icon(Icons.add_a_photo, size: 20, color: AppTheme.getPrimaryColor(context)),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      selectedPictures.isEmpty ? 'Add pictures' : 'Add more pictures',
                      style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
                    ),
                  ),
                  Icon(Icons.chevron_right, size: 20, color: AppTheme.getTextSecondary(context)),
                ],
              ),
            ),
          ),
          if (selectedPictures.isNotEmpty) ...[
            const SizedBox(height: 16),
            SizedBox(
              height: 100,
              child: ListView.builder(
                scrollDirection: Axis.horizontal,
                itemCount: selectedPictures.length,
                itemBuilder: (context, index) {
                  return Container(
                    margin: const EdgeInsets.only(right: 12),
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
                            width: 100,
                            height: 100,
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
                            onTap: () {
                              setState(() {
                                selectedPictures.removeAt(index);
                                selectedPictureFilenames.removeAt(index);
                                selectedPictureFilePaths.removeAt(index);
                                showPostBtn = message.text.trim().isNotEmpty || selectedPictureFilePaths.isNotEmpty;
                              });
                            },
                            child: Container(
                              padding: const EdgeInsets.all(4),
                              decoration: const BoxDecoration(
                                color: Colors.red,
                                shape: BoxShape.circle,
                              ),
                              child: const Icon(Icons.close, size: 14, color: Colors.white),
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

  Widget _buildNoteSkeleton() {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.getBackgroundSecondary(context),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 140,
            height: 14,
            color: AppTheme.getBackgroundPrimaryLight(context),
          ),
          const SizedBox(height: 8),
          Container(
            width: double.infinity,
            height: 14,
            color: AppTheme.getBackgroundPrimaryLight(context),
          ),
          const SizedBox(height: 8),
          Container(
            width: 80,
            height: 12,
            color: AppTheme.getBackgroundPrimaryLight(context),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState() {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: AppTheme.getBackgroundSecondary(context),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        children: [
          Icon(Icons.chat_bubble_outline, size: 32, color: AppTheme.getPrimaryColor(context)),
          const SizedBox(height: 12),
          Text(
            'No tasks yet',
            style: TextStyle(fontWeight: FontWeight.w600, color: AppTheme.getTextPrimary(context)),
          ),
          const SizedBox(height: 4),
          Text(
            'Start the conversation by sharing your first task.',
            style: TextStyle(color: AppTheme.getTextSecondary(context)),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  Widget _buildErrorState() {
    return Container(
      padding: const EdgeInsets.all(32),
      decoration: BoxDecoration(
        color: AppTheme.getBackgroundSecondary(context),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        children: [
          Icon(Icons.error_outline, color: Colors.redAccent, size: 48),
          const SizedBox(height: 12),
          Text(
            'Something went wrong',
            style: TextStyle(fontWeight: FontWeight.w600, color: AppTheme.getTextPrimary(context)),
          ),
          const SizedBox(height: 8),
          Text(
            _errorMessage ?? 'Please try again later.',
            textAlign: TextAlign.center,
            style: TextStyle(color: AppTheme.getTextSecondary(context)),
          ),
          const SizedBox(height: 16),
          ElevatedButton(
            onPressed: () => getNotes(),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.getPrimaryColor(context),
              foregroundColor: Colors.white,
            ),
            child: const Text('Retry'),
          ),
        ],
      ),
    );
  }

  Widget _buildNoteCard(dynamic note) {
    final noteText = note[0].toString();
    final when = note[1].toString();
    final author = note[2].toString();
    final attachment = note[4].toString();
    final attachmentUrl = "https://office1.buildahome.in/files/$attachment";

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.getBackgroundSecondary(context),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppTheme.getPrimaryColor(context).withOpacity(0.08)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.account_circle, color: AppTheme.getPrimaryColor(context)),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  author,
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
              ),
              Text(
                when,
                style: TextStyle(color: AppTheme.getTextSecondary(context), fontSize: 12),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            noteText,
            style: const TextStyle(fontSize: 15),
          ),
          if (attachment != '0') ...[
            const SizedBox(height: 12),
            if (_isImage(attachment))
              GestureDetector(
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => FullScreenImage(NetworkImage(attachmentUrl)),
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
                onPressed: () => _launchURL(attachmentUrl),
                icon: const Icon(Icons.attach_file),
                label: const Text('View attachment'),
              ),
          ],
        ],
      ),
    );
  }
}
