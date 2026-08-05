import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

import 'app_theme.dart';
import 'services/data_provider.dart';
import 'widgets/themed_scaffold.dart';

class Documents extends StatefulWidget {
  @override
  DocumentsState createState() {
    return DocumentsState();
  }
}

class DocumentObject extends StatefulWidget {
  final dynamic parent;
  final dynamic children;
  final dynamic drawing_id;

  const DocumentObject(this.parent, this.children, this.drawing_id, {super.key});

  @override
  DocumentObjectState createState() {
    return DocumentObjectState(this.parent, this.children, this.drawing_id);
  }
}

class DocumentObjectState extends State<DocumentObject> {
  var parent;
  var children;
  var drawing_id;
  bool vis = false;

  DocumentObjectState(this.parent, this.children, this.drawing_id);

  _launchURL(url) async {
    await launch(url);
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppTheme.border),
        boxShadow: const [
          BoxShadow(
            color: AppTheme.softShadow,
            blurRadius: 18,
            offset: Offset(0, 8),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: Column(
          children: <Widget>[
            InkWell(
              onTap: () {
                setState(() {
                  vis = !vis;
                });
              },
              borderRadius: BorderRadius.circular(18),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: <Widget>[
                    Row(
                      children: [
                        Container(
                          width: 42,
                          height: 42,
                          decoration: BoxDecoration(
                            color: const Color(0xFFEEF2FF),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: const Icon(
                            Icons.folder_rounded,
                            size: 22,
                            color: AppTheme.navy,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Text(
                          parent.toString(),
                          style: const TextStyle(
                            fontSize: 15.5,
                            fontWeight: FontWeight.w800,
                            color: AppTheme.navy,
                          ),
                        ),
                      ],
                    ),
                    AnimatedRotation(
                      turns: vis ? 0.5 : 0.0,
                      duration: const Duration(milliseconds: 250),
                      child: const Icon(
                        Icons.expand_more_rounded,
                        color: AppTheme.mutedGrey,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            AnimatedSize(
              duration: const Duration(milliseconds: 250),
              curve: Curves.easeInOut,
              child: vis
                  ? Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        for (int x = 0; x < children.length; x++)
                          TweenAnimationBuilder<double>(
                            tween: Tween(begin: 0.0, end: 1.0),
                            duration: Duration(milliseconds: 200 + (x * 60)),
                            curve: Curves.easeOut,
                            builder: (context, value, child) {
                              return Opacity(
                                opacity: value,
                                child: Material(
                                  color: Colors.transparent,
                                  child: InkWell(
                                    onTap: () {
                                      showDialog(
                                          context: context,
                                          builder: (BuildContext context) {
                                            return const AlertDialog(content: Text("Loading..."));
                                          });
                                      Navigator.of(context, rootNavigator: true).pop();
                                      _launchURL("https://office.buildahome.in/files/${children[x]['link']}");
                                    },
                                    child: Container(
                                      padding: const EdgeInsets.all(14),
                                      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                                      decoration: BoxDecoration(
                                        color: const Color(0xFFF7F8FB),
                                        borderRadius: BorderRadius.circular(12),
                                        border: Border.all(color: AppTheme.border),
                                      ),
                                      child: Row(
                                        children: [
                                          const Icon(
                                            Icons.description_outlined,
                                            color: AppTheme.navy,
                                            size: 20,
                                          ),
                                          const SizedBox(width: 12),
                                          Expanded(
                                            child: Text(
                                              children[x]['name'].toString() == 'null' ? children[x]['link'].toString() : children[x]['name'].toString(),
                                              style: const TextStyle(
                                                color: AppTheme.navy,
                                                fontWeight: FontWeight.w700,
                                                fontSize: 14,
                                              ),
                                            ),
                                          ),
                                          const Icon(
                                            Icons.open_in_new_rounded,
                                            size: 18,
                                            color: AppTheme.mutedGrey,
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                ),
                              );
                            },
                          ),
                      ],
                    )
                  : const SizedBox.shrink(),
            ),
          ],
        ),
      ),
    );
  }
}

class DocumentsState extends State<Documents> {
  var entries;
  var folders = [];
  var subfolders = {};
  var drawing_ids = {};
  var work_orders = [];
  var purchase_orders = [];
  var role;
  bool _isLoading = false;
  bool _isRefreshing = false;
  String? _errorMessage;
  int _loadRequestId = 0;
  static const Duration _requestTimeout = Duration(seconds: 20);

  Future<void> call({bool showLoader = true}) async {
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
      SharedPreferences prefs = await SharedPreferences.getInstance();
      var id = prefs.getString('project_id');
      if (id == null) {
        throw Exception('Project not selected. Please reopen the project and try again.');
      }
      var _role = prefs.getString('role');

      // Check cache for non-Client users
      final dataProvider = DataProvider();
      List<dynamic>? cachedData;
      if (_role != null && _role != 'Client' && dataProvider.cachedDocuments != null) {
        cachedData = dataProvider.cachedDocuments;
      }

      // Use cache if available and not initial load
      if (cachedData != null && !showLoader) {
        _processDocuments(cachedData, _role, requestId);
        
        // Still refresh in background
        _fetchDocumentsFromApi(id, dataProvider, _role, requestId);
        return;
      }

      // Fetch from API
      await _fetchDocumentsFromApi(id, dataProvider, _role, requestId);
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

  Future<void> _fetchDocumentsFromApi(String projectId, DataProvider dataProvider, String? userRole, int requestId) async {
    try {
      final response = await http.get(Uri.parse('https://office1.buildahome.in/API/view_all_documents?id=$projectId'))
          .timeout(_requestTimeout);
      
      if (response.statusCode != 200) {
        throw Exception('Unable to load documents right now. Please try again.');
      }

      if (response.body.isEmpty) {
        if (_shouldIgnoreLoad(requestId)) return;
        if (!mounted) return;
        setState(() {
          entries = [];
          folders = [];
          subfolders = {};
          drawing_ids = {};
        });
        return;
      }

      final data = jsonDecode(response.body);
      print('data: $data');
      
      // Update cache for non-Client users
      if (userRole != null && userRole != 'Client') {
        dataProvider.cachedDocuments = data is List ? data : [];
        dataProvider.lastDocumentsLoad = DateTime.now();
      }

      _processDocuments(data, userRole, requestId);
    } catch (e) {
      if (_shouldIgnoreLoad(requestId)) return;
      rethrow;
    }
  }

  void _processDocuments(dynamic data, String? userRole, int requestId) {
    if (_shouldIgnoreLoad(requestId)) return;
    if (!mounted) return;

    final localFolders = <String>[];
    final localSubFolders = <String, List<dynamic>>{};
    final localDrawingIds = <String, List<dynamic>>{};

    // Check if user is site engineer
    final isSiteEngineer = userRole != null && 
        userRole.toLowerCase().trim() == 'site engineer';

    if (data != null && data is List) {
      entries = data;
      for (int i = 0; i < entries.length; i++) {
        var folder = entries[i]['folder']?.toString() ?? '';
        if (folder.trim().isEmpty) continue;
        print('folder: $folder');
        
        // Normalize folder name: merge "Agreement" into "Agreements"
        if (folder.toLowerCase().trim() == 'agreement' || folder.toLowerCase() == 'agreements') {
          print('changed folder: $folder to Agreements');
          folder = 'Agreements';
        }
        
        // Filter out folders with "agreements" or "receipts" in name for site engineer
        if (isSiteEngineer) {
          final folderLower = folder.toLowerCase();
          if (folderLower.contains('agreement') || folderLower.contains('receipts')) {
            print('Filtered out folder for site engineer: $folder');
            continue;
          }
        }
        
        if (!localFolders.contains(folder)) {
          localFolders.add(folder);
        }
        localSubFolders.putIfAbsent(folder, () => []);
        localDrawingIds.putIfAbsent(folder, () => []);
        localSubFolders[folder]!.add({"name": entries[i]["pdf"] == 'null' ? entries[i]["name"] : entries[i]["pdf"], "link": entries[i]["name"]});
        localDrawingIds[folder]!.add(entries[i]["doc_id"]);
      }
    }

    setState(() {
      role = userRole;
      folders = localFolders;
      subfolders = localSubFolders;
      drawing_ids = localDrawingIds;
    });
  }

  bool _shouldIgnoreLoad(int requestId) => !mounted || requestId != _loadRequestId;

  @override
  void initState() {
    super.initState();
    call();
  }

  @override
  Widget build(BuildContext context) {
    return ThemedScaffold(
      title: 'Documents',
      body: SafeArea(
        child: RefreshIndicator(
          color: AppTheme.navy,
          onRefresh: () => call(showLoader: false),
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 32),
            children: [
              const Text(
                'Project documents',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                  color: AppTheme.navy,
                  letterSpacing: -0.2,
                ),
              ),
              const SizedBox(height: 6),
              const Text(
                'Access sanctioned drawings, approvals and shared files in one place.',
                style: TextStyle(
                  color: AppTheme.mutedGrey,
                  fontSize: 13.5,
                  fontWeight: FontWeight.w500,
                  height: 1.35,
                ),
              ),
              const SizedBox(height: 20),
              if (_errorMessage != null && folders.isEmpty)
                _buildErrorState()
              else if (_isLoading && folders.isEmpty)
                ...List.generate(3, (_) => _buildSkeletonCard())
              else if (folders.isEmpty)
                _buildEmptyState()
              else ...[
                if (_isRefreshing && folders.isNotEmpty)
                  const Padding(
                    padding: EdgeInsets.only(bottom: 16),
                    child: Center(
                      child: SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          valueColor: AlwaysStoppedAnimation<Color>(AppTheme.navy),
                        ),
                      ),
                    ),
                  ),
                ...List.generate(
                  folders.length,
                  (index) => TweenAnimationBuilder<double>(
                    tween: Tween(begin: 0.0, end: 1.0),
                    duration: Duration(milliseconds: 300 + (index * 80)),
                    curve: Curves.easeOut,
                    builder: (context, value, child) {
                      return Opacity(
                        opacity: value,
                        child: Transform.translate(
                          offset: Offset(0, 20 * (1 - value)),
                          child: DocumentObject(
                            folders[index].toString(),
                            subfolders[folders[index]],
                            drawing_ids[folders[index]],
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSkeletonCard() {
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
            width: 160,
            height: 16,
            color: AppTheme.getBackgroundPrimaryLight(context),
          ),
          const SizedBox(height: 12),
          Container(
            width: double.infinity,
            height: 14,
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
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppTheme.border),
      ),
      child: const Column(
        children: [
          Icon(Icons.inventory_2_outlined, color: AppTheme.navy, size: 32),
          SizedBox(height: 12),
          Text(
            'No documents shared yet',
            style: TextStyle(fontWeight: FontWeight.w800, color: AppTheme.navy),
          ),
          SizedBox(height: 4),
          Text(
            'Project files uploaded by the team will appear here automatically.',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: AppTheme.mutedGrey,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildErrorState() {
    return Container(
      padding: const EdgeInsets.all(32),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppTheme.border),
      ),
      child: Column(
        children: [
          const Icon(Icons.error_outline, color: Color(0xFFDC2626), size: 48),
          const SizedBox(height: 12),
          const Text(
            'Something went wrong',
            style: TextStyle(fontWeight: FontWeight.w800, color: AppTheme.navy),
          ),
          const SizedBox(height: 8),
          Text(
            _errorMessage ?? 'Please try again later.',
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: AppTheme.mutedGrey,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 16),
          ElevatedButton(
            onPressed: () => call(),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.navy,
              foregroundColor: Colors.white,
              elevation: 0,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
            ),
            child: const Text('Retry'),
          ),
        ],
      ),
    );
  }
}
