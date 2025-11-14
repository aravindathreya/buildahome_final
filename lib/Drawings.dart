import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

import 'app_theme.dart';

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
      margin: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
      decoration: BoxDecoration(
        color: AppTheme.backgroundSecondary,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppTheme.primaryColorConst.withOpacity(0.08)),
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
              borderRadius: BorderRadius.circular(16),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: <Widget>[
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: AppTheme.primaryColorConst.withOpacity(0.12),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: const Icon(
                            Icons.folder,
                            size: 20,
                            color: AppTheme.primaryColorConst,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Text(
                          parent.toString(),
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                            color: AppTheme.textPrimary,
                          ),
                        ),
                      ],
                    ),
                    AnimatedRotation(
                      turns: vis ? 0.5 : 0.0,
                      duration: const Duration(milliseconds: 250),
                      child: const Icon(
                        Icons.expand_more,
                        color: AppTheme.textPrimary,
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
                                      _launchURL("https://app.buildahome.in/team/Drawings/${children[x]}");
                                    },
                                    child: Container(
                                      padding: const EdgeInsets.all(16),
                                      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                                      decoration: BoxDecoration(
                                        color: AppTheme.backgroundPrimary,
                                        borderRadius: BorderRadius.circular(12),
                                      ),
                                      child: Row(
                                        children: [
                                          const Icon(
                                            Icons.description,
                                            size: 20,
                                            color: AppTheme.primaryColorConst,
                                          ),
                                          const SizedBox(width: 12),
                                          Expanded(
                                            child: Text(
                                              children[x].toString(),
                                              style: const TextStyle(
                                                color: AppTheme.textPrimary,
                                                fontWeight: FontWeight.w600,
                                                fontSize: 14,
                                              ),
                                            ),
                                          ),
                                          const Icon(
                                            Icons.open_in_new,
                                            size: 18,
                                            color: AppTheme.primaryColorConst,
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

  Future<void> call() async {
    setState(() {
      _isLoading = true;
    });
    try {
      SharedPreferences prefs = await SharedPreferences.getInstance();
      var id = prefs.getString('project_id');
      if (id == null) {
        if (!mounted) return;
        setState(() {
          folders = [];
          subfolders = {};
          drawing_ids = {};
        });
        return;
      }
      var response = await http.get(Uri.parse('https://office.buildahome.in/API/view_all_documents?id=$id'));
      var _role = prefs.getString('role');

      final localFolders = <String>[];
      final localSubFolders = <String, List<dynamic>>{};
      final localDrawingIds = <String, List<dynamic>>{};

      if (response.body.isNotEmpty) {
        entries = jsonDecode(response.body);
        for (int i = 0; i < entries.length; i++) {
          final folder = entries[i]['folder']?.toString() ?? '';
          if (folder.trim().isEmpty) continue;
          if (!localFolders.contains(folder)) {
            localFolders.add(folder);
          }
          localSubFolders.putIfAbsent(folder, () => []);
          localDrawingIds.putIfAbsent(folder, () => []);
          localSubFolders[folder]!.add(entries[i]["name"]);
          localDrawingIds[folder]!.add(entries[i]["doc_id"]);
        }
      }

      if (!mounted) return;
      setState(() {
        role = _role;
        folders = localFolders;
        subfolders = localSubFolders;
        drawing_ids = localDrawingIds;
      });
    } catch (err) {
      debugPrint('Failed to load documents: $err');
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  @override
  void initState() {
    super.initState();
    call();
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
          'Documents',
          style: theme.textTheme.headlineSmall?.copyWith(fontSize: 20),
        ),
      ),
      body: SafeArea(
        child: RefreshIndicator(
          color: AppTheme.primaryColorConst,
          onRefresh: call,
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(16, 24, 16, 32),
            children: [
              Text(
                "Project documents",
                style: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 8),
              Text(
                'Access sanctioned drawings, approvals and shared files in one place.',
                style: theme.textTheme.bodyMedium?.copyWith(color: AppTheme.textSecondary),
              ),
              const SizedBox(height: 24),
              if (_isLoading && folders.isEmpty)
                ...List.generate(3, (_) => _buildSkeletonCard())
              else if (folders.isEmpty)
                _buildEmptyState()
              else
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
        color: AppTheme.backgroundSecondary,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 160,
            height: 16,
            color: AppTheme.backgroundPrimaryLight,
          ),
          const SizedBox(height: 12),
          Container(
            width: double.infinity,
            height: 14,
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
          Icon(Icons.inventory_2_outlined, color: AppTheme.primaryColorConst, size: 32),
          const SizedBox(height: 12),
          Text(
            'No documents shared yet',
            style: const TextStyle(fontWeight: FontWeight.w600, color: AppTheme.textPrimary),
          ),
          const SizedBox(height: 4),
          Text(
            'Project files uploaded by the team will appear here automatically.',
            textAlign: TextAlign.center,
            style: TextStyle(color: AppTheme.textSecondary),
          ),
        ],
      ),
    );
  }
}
