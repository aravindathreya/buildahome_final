import 'dart:async';
import 'dart:convert';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

import 'Gallery.dart';
import 'Scheduler.dart';
import 'ShowAlert.dart';
import 'app_theme.dart';
import 'services/data_provider.dart';

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
  String attachedFileName = '';
  PlatformFile? attachedFile;
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
      final url = 'https://office.buildahome.in/API/get_notes?project_id=$projectId';
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

  Future<void> getFile() async {
    final res = await FilePicker.platform.pickFiles(allowMultiple: false);
    final file = res?.files.first;

    if (!mounted) return;

    if (file != null) {
      setState(() {
        attachedFile = file;
        attachedFileName = 'Attached file: ${file.name}';
      });
    } else {
      setState(() {
        attachedFile = null;
        attachedFileName = '';
      });
    }
  }

  Future<void> _postNote() async {
    if (projectId == null || userId == null) return;
    showDialog(
      barrierDismissible: false,
      context: context,
      builder: (BuildContext context) {
        return ShowAlert("Hang in there. Submitting update", true);
      },
    );

    try {
      final url = Uri.parse("https://office.buildahome.in/API/post_comment");
      final response = await http.post(url, body: {'project_id': projectId!, 'user_id': userId!, 'note': message.text});
      final responseBody = jsonDecode(response.body);
      final noteId = responseBody['note_id'];

      if (attachedFile != null && attachedFile!.path != null) {
        final uri = Uri.parse("https://office.buildahome.in/API/notes_picture_uplpoad");
        final request = http.MultipartRequest("POST", uri);
        request.fields['note_id'] = noteId.toString();
        request.files.add(await http.MultipartFile.fromPath("file", attachedFile!.path!));
        await request.send();
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
        attachedFile = null;
        attachedFileName = '';
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

  Future<void> _launchURL(String url) async {
    if (await canLaunch(url)) {
      await launch(url);
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
      backgroundColor: AppTheme.backgroundPrimary,
      appBar: AppBar(
        backgroundColor: AppTheme.backgroundSecondary,
        automaticallyImplyLeading: canPop,
        leading: canPop
            ? IconButton(
                icon: const Icon(Icons.arrow_back_ios_new_rounded),
                onPressed: () => Navigator.of(context).maybePop(),
              )
            : null,
        title: Text(
          'Notes & comments',
          style: theme.textTheme.headlineSmall?.copyWith(fontSize: 20),
        ),
        actions: [
          IconButton(
            tooltip: 'Gallery',
            icon: const Icon(Icons.photo_library_outlined),
            onPressed: () {
              Navigator.of(context).push(MaterialPageRoute(builder: (_) => const Gallery()));
            },
          ),
          IconButton(
            tooltip: 'Scheduler',
            icon: const Icon(Icons.event_note_outlined),
            onPressed: () {
              Navigator.of(context).push(MaterialPageRoute(builder: (_) => const TaskWidget()));
            },
          ),
        ],
      ),
      body: SafeArea(
        child: RefreshIndicator(
          color: AppTheme.primaryColorConst,
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
                        child: Text('Post'),
                      ),
                    ),
                  ),
                ),
              const SizedBox(height: 24),
              Text(
                'Previous notes',
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
                          valueColor: AlwaysStoppedAnimation<Color>(AppTheme.primaryColorConst),
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
          style: theme.textTheme.bodyMedium?.copyWith(color: AppTheme.textSecondary),
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
                showPostBtn = value.trim().isNotEmpty;
              });
            },
            decoration: const InputDecoration(
              hintText: "Add a note",
            ),
          ),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            style: OutlinedButton.styleFrom(
              foregroundColor: AppTheme.primaryColorConst,
              side: BorderSide(color: AppTheme.primaryColorConst.withOpacity(0.4)),
            ),
            onPressed: getFile,
            icon: const Icon(Icons.attach_file),
            label: const Text('Add attachment'),
          ),
          if (attachedFileName.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              attachedFileName,
              style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
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
        color: AppTheme.backgroundSecondary,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 140,
            height: 14,
            color: AppTheme.backgroundPrimaryLight,
          ),
          const SizedBox(height: 8),
          Container(
            width: double.infinity,
            height: 14,
            color: AppTheme.backgroundPrimaryLight,
          ),
          const SizedBox(height: 8),
          Container(
            width: 80,
            height: 12,
            color: AppTheme.backgroundPrimaryLight,
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState() {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: AppTheme.backgroundSecondary,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        children: [
          Icon(Icons.chat_bubble_outline, size: 32, color: AppTheme.primaryColorConst),
          const SizedBox(height: 12),
          Text(
            'No notes yet',
            style: TextStyle(fontWeight: FontWeight.w600, color: AppTheme.textPrimary),
          ),
          const SizedBox(height: 4),
          Text(
            'Start the conversation by sharing your first note.',
            style: TextStyle(color: AppTheme.textSecondary),
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
        color: AppTheme.backgroundSecondary,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        children: [
          Icon(Icons.error_outline, color: Colors.redAccent, size: 48),
          const SizedBox(height: 12),
          Text(
            'Something went wrong',
            style: TextStyle(fontWeight: FontWeight.w600, color: AppTheme.textPrimary),
          ),
          const SizedBox(height: 8),
          Text(
            _errorMessage ?? 'Please try again later.',
            textAlign: TextAlign.center,
            style: TextStyle(color: AppTheme.textSecondary),
          ),
          const SizedBox(height: 16),
          ElevatedButton(
            onPressed: () => getNotes(),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.primaryColorConst,
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

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.backgroundSecondary,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppTheme.primaryColorConst.withOpacity(0.08)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.account_circle, color: AppTheme.primaryColorConst),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  author,
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
              ),
              Text(
                when,
                style: TextStyle(color: AppTheme.textSecondary, fontSize: 12),
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
            OutlinedButton.icon(
              onPressed: () => _launchURL("https://app.buildahome.in/files/$attachment"),
              icon: const Icon(Icons.attach_file),
              label: const Text('View attachment'),
            ),
          ],
        ],
      ),
    );
  }
}
