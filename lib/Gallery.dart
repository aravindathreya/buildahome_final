import 'dart:async';
import 'dart:convert';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

import 'FullScreenImage.dart';
import 'app_theme.dart';
import 'services/data_provider.dart';

const String _galleryApiBaseUrl = 'https://office.buildahome.in';

const List<String> _galleryDateFieldKeys = [
  'uploaded_at_display',
  'submitted_at_display',
  'completed_at_display',
  'created_at_display',
  'updated_at_display',
  'uploaded_at',
  'submitted_at',
  'completed_at',
  'created_at',
  'updated_at',
  'captured_at',
  'date',
  'timestamp',
];

const List<String> _galleryUploaderFieldKeys = [
  'uploaded_by',
  'uploaded_by_name',
  'submitted_by_name',
  'submitted_by',
  'user_name',
  'assigned_to_name',
];

String? _galleryStringValue(dynamic value) {
  final text = value?.toString().trim();
  if (text == null || text.isEmpty || text == 'null') return null;
  return text;
}

bool _isImageGalleryEntry(Map<String, dynamic> map, String candidate) {
  if (map['is_video'] == true) return false;
  if (map['is_image'] == true) return true;
  final mime = (_galleryStringValue(map['content_type']) ??
          _galleryStringValue(map['mime_type']) ??
          '')
      .toLowerCase();
  if (mime.startsWith('image/')) return true;
  if (mime.startsWith('video/')) return false;

  final lower = candidate.toLowerCase().split('?').first;
  return lower.endsWith('.jpg') ||
      lower.endsWith('.jpeg') ||
      lower.endsWith('.png') ||
      lower.endsWith('.webp') ||
      lower.endsWith('.heic') ||
      lower.endsWith('.gif');
}

bool _isVideoEntry(Map<String, dynamic> map, String candidate) {
  if (map['is_video'] == true) return true;
  final mime = (_galleryStringValue(map['content_type']) ??
          _galleryStringValue(map['mime_type']) ??
          '')
      .toLowerCase();
  if (mime.startsWith('video/')) return true;

  final type = _galleryStringValue(map['type'])?.toLowerCase();
  if (type == 'video') return true;

  final lower = candidate.toLowerCase().split('?').first;
  return lower.endsWith('.mp4') ||
      lower.endsWith('.mov') ||
      lower.endsWith('.avi') ||
      lower.endsWith('.webm') ||
      lower.endsWith('.mkv') ||
      lower.endsWith('.m4v') ||
      lower.endsWith('.3gp');
}

Future<void> _openGalleryMediaItem(
  BuildContext context,
  _GalleryImage item,
) async {
  if (item.isVideo) {
    final uri = Uri.tryParse(item.imageUrl);
    if (uri == null) return;
    final opened = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!opened && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not open video.')),
      );
    }
    return;
  }

  if (!context.mounted) return;
  Navigator.of(context).push(
    MaterialPageRoute(builder: (_) => FullScreenImage(item.imageUrl)),
  );
}

class Gallery extends StatefulWidget {
  const Gallery({super.key});

  @override
  State<Gallery> createState() => _GalleryState();
}

class _GalleryState extends State<Gallery> {
  List<dynamic> _entries = [];
  List<String> _uniqueDates = [];
  bool _isLoading = false;
  bool _isRefreshing = false;
  String? _errorMessage;
  int _loadRequestId = 0;
  static const Duration _requestTimeout = Duration(seconds: 20);

  @override
  void initState() {
    super.initState();
    _loadGallery();
  }

  Future<void> _loadGallery({bool showLoader = true}) async {
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
      final dataProvider = DataProvider();
      final prefs = await SharedPreferences.getInstance();
      final role = prefs.getString('role');
      final projectId = prefs.getString('project_id');

      if (projectId == null) {
        throw Exception(
            'Project not selected. Please reopen the project and try again.');
      }

      List<dynamic>? cachedData;
      if (role != null &&
          role != 'Client' &&
          dataProvider.cachedGallery != null) {
        cachedData = dataProvider.cachedGallery;
      }

      if (cachedData != null && !showLoader) {
        _processData(cachedData, requestId);
        _fetchGalleryFromApi(projectId, requestId, dataProvider);
        return;
      }

      await _fetchGalleryFromApi(projectId, requestId, dataProvider);
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

  Future<void> _fetchGalleryFromApi(
    String projectId,
    int requestId,
    DataProvider dataProvider,
  ) async {
    try {
      final response = await http
          .get(Uri.parse(
              'https://office.buildahome.in/API/get_gallery_data?id=$projectId'))
          .timeout(_requestTimeout);

      if (response.statusCode != 200) {
        throw Exception('Unable to load gallery right now. Please try again.');
      }

      final data = jsonDecode(response.body) as List<dynamic>;

      final prefs = await SharedPreferences.getInstance();
      final role = prefs.getString('role');
      if (role != null && role != 'Client') {
        dataProvider.cachedGallery = data;
        dataProvider.lastGalleryLoad = DateTime.now();
      }

      _processData(data, requestId);
    } catch (e) {
      if (_shouldIgnoreLoad(requestId)) return;
      rethrow;
    }
  }

  void _processData(List<dynamic> data, int requestId) {
    if (_shouldIgnoreLoad(requestId)) return;
    if (!mounted) return;

    final dates = <String>[];
    for (final entry in data) {
      final date = entry['date']?.toString();
      if (date != null && !dates.contains(date)) {
        dates.add(date);
      }
    }

    setState(() {
      _entries = data;
      _uniqueDates = dates;
    });
  }

  bool _shouldIgnoreLoad(int requestId) =>
      !mounted || requestId != _loadRequestId;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final canPop = Navigator.of(context).canPop();
    return Scaffold(
      backgroundColor: AppTheme.getBackgroundPrimary(context),
      appBar: AppBar(
        backgroundColor: AppTheme.getBackgroundSecondary(context),
        foregroundColor: AppTheme.navy,
        elevation: 0,
        iconTheme: const IconThemeData(color: AppTheme.navy),
        actionsIconTheme: const IconThemeData(color: AppTheme.navy),
        automaticallyImplyLeading: canPop,
        leading: canPop
            ? IconButton(
                icon: const Icon(Icons.arrow_back_ios_new_rounded),
                onPressed: () => Navigator.of(context).maybePop(),
              )
            : null,
        title: Text(
          'Gallery',
          style: theme.textTheme.headlineSmall?.copyWith(
            fontSize: 20,
            color: AppTheme.navy,
            fontWeight: FontWeight.w800,
          ),
        ),
      ),
      body: SafeArea(
        child: RefreshIndicator(
          color: AppTheme.getPrimaryColor(context),
          onRefresh: () => _loadGallery(showLoader: false),
          child: _buildBody(context, theme),
        ),
      ),
    );
  }

  Widget _buildBody(BuildContext context, ThemeData theme) {
    if (_errorMessage != null && _entries.isEmpty) {
      return ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 32),
        children: [
          _buildHeader(theme),
          const SizedBox(height: 40),
          _buildErrorState(),
        ],
      );
    }

    if (_isLoading && _uniqueDates.isEmpty) {
      return ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 32),
        children: List.generate(6, (index) => _buildLoadingCard()),
      );
    }

    if (!_isLoading && _uniqueDates.isEmpty) {
      return ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 32),
        children: [
          _buildHeader(theme),
          const SizedBox(height: 40),
          _buildEmptyState(),
        ],
      );
    }

    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(16, 24, 16, 32),
      children: [
        _buildHeader(theme),
        const SizedBox(height: 24),
        if (_isRefreshing && _entries.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(bottom: 16),
            child: Center(
              child: SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  valueColor: AlwaysStoppedAnimation<Color>(
                    AppTheme.getPrimaryColor(context),
                  ),
                ),
              ),
            ),
          ),
        for (final date in _uniqueDates) _buildDateSection(context, date, theme),
      ],
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
            style: TextStyle(
              fontWeight: FontWeight.w600,
              color: AppTheme.getTextPrimary(context),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            _errorMessage ?? 'Please try again later.',
            textAlign: TextAlign.center,
            style: TextStyle(color: AppTheme.getTextSecondary(context)),
          ),
          const SizedBox(height: 16),
          ElevatedButton(
            onPressed: () => _loadGallery(),
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

  Widget _buildHeader(ThemeData theme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Project gallery',
          style:
              theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 8),
        Text(
          'Browse chronological site progress photographs shared by the buildAhome team.',
          style: theme.textTheme.bodyMedium
              ?.copyWith(color: AppTheme.getTextSecondary(context)),
        ),
      ],
    );
  }

  Widget _buildLoadingCard() {
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 8),
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
            height: 18,
            decoration: BoxDecoration(
              color: AppTheme.getBackgroundPrimaryLight(context),
              borderRadius: BorderRadius.circular(4),
            ),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 10,
            children: List.generate(
              3,
              (_) => Container(
                width: 90,
                height: 90,
                decoration: BoxDecoration(
                  color: AppTheme.getBackgroundPrimaryLight(context),
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState() {
    return Container(
      padding: const EdgeInsets.all(32),
      decoration: BoxDecoration(
        color: AppTheme.getBackgroundSecondary(context),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        children: [
          Icon(
            Icons.photo_library_outlined,
            color: AppTheme.getPrimaryColor(context),
            size: 32,
          ),
          const SizedBox(height: 12),
          Text(
            'No uploads yet',
            style: TextStyle(
              fontWeight: FontWeight.w600,
              color: AppTheme.getTextPrimary(context),
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'You will receive a notification as soon as the team shares the first set of photos.',
            textAlign: TextAlign.center,
            style: TextStyle(color: AppTheme.getTextSecondary(context)),
          ),
        ],
      ),
    );
  }

  Widget _buildDateSection(BuildContext context, String date, ThemeData theme) {
    final items = _entries.where((element) => element['date'] == date).toList();
    return Container(
      margin: const EdgeInsets.only(bottom: 24),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.getBackgroundSecondary(context),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: AppTheme.getPrimaryColor(context).withOpacity(0.08),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: AppTheme.getPrimaryColor(context).withOpacity(0.12),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(
                  Icons.date_range,
                  size: 18,
                  color: AppTheme.getPrimaryColor(context),
                ),
              ),
              const SizedBox(width: 12),
              Text(
                date,
                style:
                    theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children:
                items.map((entry) => _buildImageTile(context, entry)).toList(),
          ),
        ],
      ),
    );
  }

  Widget _buildImageTile(BuildContext context, dynamic entry) {
    final double tileSize =
        (MediaQuery.of(context).size.width - 16 * 2 - 27 * 2) / 3;
    final imageUrl =
        "https://office.buildahome.in/files/migrated/${entry['image']}";
    final child = CachedNetworkImage(
      imageUrl: imageUrl,
      fit: BoxFit.cover,
      progressIndicatorBuilder: (context, url, progress) => _buildImageSkeleton(),
      errorWidget: (context, url, error) => _buildBrokenImage(context),
    );
    final onTap = () => Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => FullScreenImage(imageUrl)),
        );

    return AnimatedWidgetSlide(
      direction: SlideDirection.bottomToTop,
      duration: const Duration(milliseconds: 300),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Ink(
          width: tileSize,
          height: tileSize,
          decoration: BoxDecoration(
            color: AppTheme.getBackgroundPrimaryLight(context),
            borderRadius: BorderRadius.circular(12),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.06),
                blurRadius: 8,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: child,
          ),
        ),
      ),
    );
  }

  Widget _buildBrokenImage(BuildContext context) {
    return Container(
      color: AppTheme.getBackgroundPrimaryLight(context),
      child: Center(
        child: Icon(
          Icons.broken_image_outlined,
          color: AppTheme.getTextSecondary(context),
        ),
      ),
    );
  }

  Widget _buildImageSkeleton() {
    return LayoutBuilder(
      builder: (context, constraints) {
        return Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.centerLeft,
              end: Alignment.centerRight,
              colors: [
                AppTheme.getBackgroundPrimaryLight(context),
                AppTheme.getBackgroundSecondary(context),
                AppTheme.getBackgroundPrimaryLight(context),
              ],
            ),
          ),
        );
      },
    );
  }
}

class TimelineGallery extends StatefulWidget {
  const TimelineGallery({super.key});

  @override
  State<TimelineGallery> createState() => _TimelineGalleryState();
}

class _TimelineGalleryState extends State<TimelineGallery> {
  List<_GallerySection> _sections = [];
  bool _isLoading = false;
  bool _isRefreshing = false;
  String? _errorMessage;
  int _loadRequestId = 0;
  static const Duration _requestTimeout = Duration(seconds: 20);

  @override
  void initState() {
    super.initState();
    _loadGallery();
  }

  Future<void> _loadGallery({bool showLoader = true}) async {
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
      // Try to load from cache first
      final dataProvider = DataProvider();
      final prefs = await SharedPreferences.getInstance();
      final role = prefs.getString('role');
      final projectId = prefs.getString('project_id');
      
      if (projectId == null) {
        throw Exception('Project not selected. Please reopen the project and try again.');
      }

      // For non-Client users, check cache first
      List<dynamic>? cachedData;
      if (role != null && role != 'Client' && dataProvider.cachedGallery != null) {
        cachedData = dataProvider.cachedGallery;
      }

      // Use cache if available and not refreshing
      if (cachedData != null && !showLoader) {
        _processData(cachedData, requestId);
        
        // Still refresh in background
        _fetchGalleryFromApi(projectId, requestId, dataProvider);
        return;
      }

      // Fetch from API
      await _fetchGalleryFromApi(projectId, requestId, dataProvider);
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

  Future<void> _fetchGalleryFromApi(
    String projectId,
    int requestId,
    DataProvider dataProvider,
  ) async {
    try {
      dynamic galleryData = <dynamic>[];
      dynamic salesSopDetails;
      dynamic taskData = <dynamic>[];

      try {
        final response = await http
            .get(Uri.parse('$_galleryApiBaseUrl/API/get_gallery_data?id=$projectId'))
            .timeout(_requestTimeout);

        if (response.statusCode == 200) {
          galleryData = jsonDecode(response.body);
        }
      } catch (e) {
        print('[Gallery] Old gallery load skipped: $e');
      }

      salesSopDetails = await _fetchSalesSopDetails(projectId);
      taskData = await _fetchProjectTasks(projectId);
      
      // Update cache for non-Client users
      final prefs = await SharedPreferences.getInstance();
      final role = prefs.getString('role');
      if (role != null && role != 'Client' && galleryData is List) {
        dataProvider.cachedGallery = galleryData;
        dataProvider.lastGalleryLoad = DateTime.now();
      }

      _processData(
        galleryData,
        requestId,
        salesSopDetails: salesSopDetails,
        taskData: taskData,
      );
    } catch (e) {
      if (_shouldIgnoreLoad(requestId)) return;
      rethrow;
    }
  }

  Future<dynamic> _fetchSalesSopDetails(String projectId) async {
    final prefs = await SharedPreferences.getInstance();
    final apiToken = prefs.getString('api_token');
    final userId = prefs.getString('user_id') ?? prefs.getString('userId');

    if (apiToken == null || apiToken.isEmpty) return null;

    final queryAttempts = <Map<String, String>>[
      {'project_id': projectId, 'api_token': apiToken},
      {'id': projectId, 'api_token': apiToken},
      if (userId != null && userId.isNotEmpty)
        {'id': userId, 'api_token': apiToken},
      {'api_token': apiToken},
    ];

    for (final query in queryAttempts) {
      try {
        final uri = Uri.parse('$_galleryApiBaseUrl/api/sales_sop_details')
            .replace(queryParameters: query);
        final response = await http.get(
          uri,
          headers: {'X-Api-Token': apiToken},
        ).timeout(_requestTimeout);
        if (response.statusCode == 200) {
          return jsonDecode(response.body);
        }
      } catch (e) {
        print('[Gallery] SOP details attempt skipped: $e');
      }
    }

    return null;
  }

  Future<dynamic> _fetchProjectTasks(String projectId) async {
    try {
      final uri = Uri.parse('$_galleryApiBaseUrl/API/get_tasks').replace(
        queryParameters: {'project_id': projectId},
      );
      final response = await http.get(uri).timeout(_requestTimeout);
      if (response.statusCode != 200) return <dynamic>[];
      return jsonDecode(response.body);
    } catch (e) {
      print('[Gallery] Task image load skipped: $e');
      return <dynamic>[];
    }
  }

  void _processData(
    dynamic data,
    int requestId, {
    dynamic salesSopDetails,
    dynamic taskData,
  }) {
    if (_shouldIgnoreLoad(requestId)) return;
    if (!mounted) return;

    final sections = _buildGallerySections(
      oldGalleryData: data,
      salesSopDetails: salesSopDetails,
      taskData: taskData,
    );

    setState(() {
      _sections = sections;
    });
  }

  List<_GallerySection> _buildGallerySections({
    required dynamic oldGalleryData,
    required dynamic salesSopDetails,
    required dynamic taskData,
  }) {
    final sectionMap = <String, _MutableGallerySection>{};
    final seenUrls = <String>{};

    _MutableGallerySection sectionFor(String id, String label) {
      final normalizedId = id.trim().isEmpty ? _generalSectionId : id.trim();
      final normalizedLabel = label.trim().isEmpty ? 'General' : label.trim();
      return sectionMap.putIfAbsent(
        normalizedId,
        () => _MutableGallerySection(
          id: normalizedId,
          label: normalizedLabel,
        ),
      );
    }

    void addItem(_GalleryImage item) {
      if (!seenUrls.add(item.imageUrl)) return;
      final section = sectionFor(item.sectionId, item.sectionLabel);
      section.items.add(item);
      if (item.taskName != null) section.taskNames.add(item.taskName!);
    }

    for (final section in _extractWorkflowGallerySections(salesSopDetails)) {
      final sectionId = _stringValue(section['section_id']) ??
          _stringValue(section['dashboard_section']) ??
          section['section_label']?.toString() ??
          _generalSectionId;
      final sectionLabel = _stringValue(section['section_label']) ??
          _stringValue(section['dashboard_section_label']) ??
          'General';
      final target = sectionFor(sectionId, sectionLabel);
      target.iconName = _stringValue(section['section_icon']) ??
          _stringValue(section['icon']) ??
          _stringValue(section['icon_name']);
      final rawItems = section['items'];
      if (rawItems is List) {
        for (final item in rawItems) {
          if (item is Map) {
            final image = _galleryImageFromMap(
              Map<String, dynamic>.from(item),
              defaultSectionId: target.id,
              defaultSectionLabel: target.label,
            );
            if (image != null) addItem(image);
          }
        }
      }
    }

    for (final map in _extractTaskGalleryMaps(taskData)) {
      final image = _galleryImageFromMap(
        map,
        defaultSectionId: _generalSectionId,
        defaultSectionLabel: 'General',
      );
      if (image != null) addItem(image);
    }

    for (final map in _extractMaps(oldGalleryData)) {
      final image = _galleryImageFromMap(
        map,
        defaultSectionId: _generalSectionId,
        defaultSectionLabel: 'General',
      );
      if (image != null) addItem(image);
    }

    final sections = sectionMap.values
        .map(
          (section) => _GallerySection(
            id: section.id,
            label: section.label,
            items: section.items,
            taskNames: section.taskNames.toList(),
            iconName: section.iconName,
          ),
        )
        .toList();

    sections.sort((a, b) {
      if (a.id == _generalSectionId && b.id != _generalSectionId) return 1;
      if (b.id == _generalSectionId && a.id != _generalSectionId) return -1;
      return 0;
    });

    return sections;
  }

  List<Map<String, dynamic>> _extractWorkflowGallerySections(dynamic value) {
    final details = _unwrapSalesSopDetails(value);
    if (details is! Map) return <Map<String, dynamic>>[];

    final workflowSections = details['workflow_dashboard_sections'];
    if (workflowSections is! Map) return <Map<String, dynamic>>[];

    final gallerySections = workflowSections['gallery'];
    if (gallerySections is! List) return <Map<String, dynamic>>[];

    return gallerySections
        .whereType<Map>()
        .map((section) => Map<String, dynamic>.from(section))
        .toList();
  }

  dynamic _unwrapSalesSopDetails(dynamic value) {
    if (value is! Map) return value;
    return value['api_sales_sop_details'] ??
        value['sales_sop_details'] ??
        value['data'] ??
        value['project'] ??
        value;
  }

  List<Map<String, dynamic>> _extractMaps(dynamic value) {
    final maps = <Map<String, dynamic>>[];

    void visit(dynamic item) {
      if (item is List) {
        for (final child in item) {
          visit(child);
        }
        return;
      }

      if (item is Map) {
        final map = Map<String, dynamic>.from(item);
        maps.add(map);
        for (final child in map.values) {
          if (child is Map || child is List) visit(child);
        }
      }
    }

    if (value is Map && value['tasks'] is List) {
      visit(value['tasks']);
    } else {
      visit(value);
    }

    return maps;
  }

  List<Map<String, dynamic>> _extractTaskGalleryMaps(dynamic value) {
    final maps = <Map<String, dynamic>>[];

    void visit(dynamic item, Map<String, dynamic> inherited) {
      if (item is List) {
        for (final child in item) {
          visit(child, inherited);
        }
        return;
      }

      if (item is! Map) return;

      final map = Map<String, dynamic>.from(item);
      final nextInherited = Map<String, dynamic>.from(inherited);
      for (final key in [
        'dashboard_card',
        'dashboard_section',
        'dashboard_section_label',
        'task_name',
        'task_id',
        'note',
        'status',
        'user_name',
        'assigned_to_name',
        ..._galleryUploaderFieldKeys,
        ..._galleryDateFieldKeys,
      ]) {
        if (map[key] != null) nextInherited[key] = map[key];
      }

      final card = _stringValue(nextInherited['dashboard_card'])?.toLowerCase();
      final mapCard = _stringValue(map['dashboard_card'])?.toLowerCase();
      if (card == 'gallery') {
        for (final entry in nextInherited.entries) {
          map.putIfAbsent(entry.key, () => entry.value);
        }
        maps.add(map);
      }

      if (card == 'gallery' || mapCard == 'gallery') {
        _appendGalleryFileMaps(
          maps,
          map,
          nextInherited,
        );
      }

      for (final actionsKey in const [
        'workflow_actions',
        'workflow_task_actions',
      ]) {
        final actions = map[actionsKey];
        if (actions is! List) continue;
        for (final action in actions) {
          if (action is! Map) continue;
          final actionMap = Map<String, dynamic>.from(action);
          final actionInherited = Map<String, dynamic>.from(nextInherited);
          final response = actionMap['response'];
          if (response is Map) {
            for (final key in _galleryDateFieldKeys) {
              if (response[key] != null) {
                actionInherited[key] = response[key];
              }
            }
            for (final key in _galleryUploaderFieldKeys) {
              if (response[key] != null) {
                actionInherited[key] = response[key];
              }
            }
          }
          _appendGalleryFileMaps(
            maps,
            actionMap,
            actionInherited,
          );
          if (response is Map) {
            _appendGalleryFileMaps(
              maps,
              Map<String, dynamic>.from(response),
              actionInherited,
            );
          }
        }
      }

      for (final responsesKey in const [
        'workflow_action_responses',
        'workflow_prior_responses',
      ]) {
        final responses = map[responsesKey];
        if (responses is! List) continue;
        for (final response in responses) {
          if (response is! Map) continue;
          final responseInherited = Map<String, dynamic>.from(nextInherited);
          for (final key in _galleryDateFieldKeys) {
            if (response[key] != null) {
              responseInherited[key] = response[key];
            }
          }
          _appendGalleryFileMaps(
            maps,
            Map<String, dynamic>.from(response),
            responseInherited,
          );
        }
      }

      for (final child in map.values) {
        if (child is Map || child is List) visit(child, nextInherited);
      }
    }

    if (value is Map && value['tasks'] is List) {
      visit(value['tasks'], <String, dynamic>{});
    } else {
      visit(value, <String, dynamic>{});
    }

    return maps;
  }

  void _appendGalleryFileMaps(
    List<Map<String, dynamic>> maps,
    Map<String, dynamic> source,
    Map<String, dynamic> inherited,
  ) {
    for (final key in [
      'files',
      'attachments',
      'uploaded_files',
      'uploads',
      'images',
      'photos',
    ]) {
      final children = source[key];
      if (children is! List) continue;
      for (final child in children) {
        if (child is! Map) continue;
        final merged = Map<String, dynamic>.from(inherited)
          ..addAll(Map<String, dynamic>.from(child));
        final url = _resolveImageUrl(merged);
        if (url == null) continue;
        final filename = _stringValue(merged['filename']) ??
            _stringValue(merged['file_name']) ??
            _stringValue(merged['image']);
        if (!_isGalleryMediaEntry(merged, filename ?? url)) continue;
        maps.add(merged);
      }
    }
  }

  _GalleryImage? _galleryImageFromMap(
    Map<String, dynamic> map, {
    required String defaultSectionId,
    required String defaultSectionLabel,
    bool requireGalleryCard = false,
  }) {
    final card = _stringValue(map['dashboard_card'])?.toLowerCase();
    if (requireGalleryCard && card != 'gallery') return null;

    final url = _resolveImageUrl(map);
    if (url == null) return null;

    final filename = _stringValue(map['filename']) ??
        _stringValue(map['file_name']) ??
        _stringValue(map['image']);

    if (!_isGalleryMediaEntry(map, filename ?? url)) return null;

    return _GalleryImage(
      imageUrl: url,
      isVideo: _isVideoEntry(map, filename ?? url),
      sectionId: _stringValue(map['dashboard_section']) ??
          _stringValue(map['section_id']) ??
          defaultSectionId,
      sectionLabel: _stringValue(map['dashboard_section_label']) ??
          _stringValue(map['section_label']) ??
          defaultSectionLabel,
      title: _stringValue(map['document_name']) ??
          _stringValue(map['task_name']) ??
          filename,
      uploadedAt: _extractUploadedAt(map),
      taskName: _stringValue(map['task_name']) ??
          _stringValue(map['task']) ??
          _stringValue(map['note']) ??
          _stringValue(map['document_name']),
      taskId: _stringValue(map['task_id']) ??
          _stringValue(map['id']) ??
          _stringValue(map['action_id']),
      uploadedBy: _firstStringValue(map, _galleryUploaderFieldKeys),
      taskStatus: _stringValue(map['status']) ?? _stringValue(map['task_status']),
    );
  }

  String? _firstStringValue(
    Map<String, dynamic> map,
    List<String> keys,
  ) {
    for (final key in keys) {
      final value = _stringValue(map[key]);
      if (value != null) return value;
    }
    return null;
  }

  String? _extractUploadedAt(Map<String, dynamic> map) {
    for (final key in _galleryDateFieldKeys) {
      final value = _stringValue(map[key]);
      if (value != null) return _formatGalleryDateTime(value);
    }

    final response = map['response'];
    if (response is Map) {
      final fromResponse =
          _extractUploadedAt(Map<String, dynamic>.from(response));
      if (fromResponse != null) return fromResponse;
    }

    return null;
  }

  String _formatGalleryDateTime(String value) {
    final trimmed = value.trim();
    if (RegExp(r'[A-Za-z]{3}').hasMatch(trimmed) &&
        (trimmed.contains(',') || trimmed.contains(' AM') || trimmed.contains(' PM'))) {
      return trimmed;
    }

    final parsed = DateTime.tryParse(trimmed) ?? _parseLooseDate(trimmed);
    if (parsed == null) return trimmed;
    return DateFormat('dd MMM yyyy, hh:mm a').format(parsed.toLocal());
  }

  String? _resolveImageUrl(Map<String, dynamic> map) {
    final directUrl = _stringValue(map['url']) ??
        _stringValue(map['file_url']) ??
        _stringValue(map['image_url']) ??
        _stringValue(map['video_url']) ??
        _stringValue(map['path']);
    if (directUrl != null) return _absoluteUrl(directUrl);

    final image = _stringValue(map['image']);
    if (image == null) return null;
    if (image.startsWith('http://') ||
        image.startsWith('https://') ||
        image.startsWith('/')) {
      return _absoluteUrl(image);
    }
    return '$_galleryApiBaseUrl/files/migrated/$image';
  }

  String _absoluteUrl(String value) {
    final trimmed = value.trim();
    if (trimmed.startsWith('http://') || trimmed.startsWith('https://')) {
      return trimmed;
    }
    if (trimmed.startsWith('/')) return '$_galleryApiBaseUrl$trimmed';
    return '$_galleryApiBaseUrl/$trimmed';
  }

  bool _isImageEntry(Map<String, dynamic> map, String candidate) {
    return _isImageGalleryEntry(map, candidate);
  }

  bool _isGalleryMediaEntry(Map<String, dynamic> map, String candidate) {
    return _isImageGalleryEntry(map, candidate) ||
        _isVideoEntry(map, candidate);
  }

  String? _stringValue(dynamic value) {
    final text = value?.toString().trim();
    if (text == null || text.isEmpty || text == 'null') return null;
    return text;
  }

  bool _shouldIgnoreLoad(int requestId) => !mounted || requestId != _loadRequestId;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final canPop = Navigator.of(context).canPop();
    return Scaffold(
      backgroundColor: AppTheme.getBackgroundPrimary(context),
      appBar: AppBar(
        backgroundColor: AppTheme.getBackgroundSecondary(context),
        foregroundColor: AppTheme.navy,
        elevation: 0,
        iconTheme: const IconThemeData(color: AppTheme.navy),
        actionsIconTheme: const IconThemeData(color: AppTheme.navy),
        automaticallyImplyLeading: canPop,
        leading: canPop
            ? IconButton(
                icon: const Icon(Icons.arrow_back_ios_new_rounded),
                onPressed: () => Navigator.of(context).maybePop(),
              )
            : null,
        title: Text(
          'Project Gallery',
          style: theme.textTheme.headlineSmall?.copyWith(
            fontSize: 20,
            color: AppTheme.navy,
            fontWeight: FontWeight.w800,
          ),
        ),
      ),
      body: SafeArea(
        child: RefreshIndicator(
          color: AppTheme.getPrimaryColor(context),
          onRefresh: () => _loadGallery(showLoader: false),
          child: _buildBody(context, theme),
        ),
      ),
    );
  }

  Widget _buildBody(BuildContext context, ThemeData theme) {
    if (_errorMessage != null && _sections.isEmpty) {
      return ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 32),
        children: [
          _buildHeader(theme),
          const SizedBox(height: 40),
          _buildErrorState(),
        ],
      );
    }

    if (_isLoading && _sections.isEmpty) {
      return ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 32),
        children: List.generate(6, (index) => _buildLoadingCard()),
      );
    }

    if (!_isLoading && _sections.isEmpty) {
      return ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 32),
        children: [
          _buildHeader(theme),
          const SizedBox(height: 40),
          _buildEmptyState(),
        ],
      );
    }

    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(16, 24, 16, 32),
      children: [
        _buildHeader(theme),
        const SizedBox(height: 24),
        if (_isRefreshing && _sections.isNotEmpty)
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
        for (final section in _sections)
          _buildGallerySection(context, section, theme),
      ],
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
            onPressed: () => _loadGallery(),
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

  Widget _buildHeader(ThemeData theme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Project Gallery',
          style: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 8),
        Text(
          'Workflow task uploads, automatically grouped into project sections.',
          style: theme.textTheme.bodyMedium?.copyWith(color: AppTheme.getTextSecondary(context)),
        ),
      ],
    );
  }

  Widget _buildLoadingCard() {
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 8),
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
            height: 18,
            decoration: BoxDecoration(
              color: AppTheme.getBackgroundPrimaryLight(context),
              borderRadius: BorderRadius.circular(4),
            ),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 10,
            children: List.generate(
              3,
              (_) => Container(
                width: 90,
                height: 90,
                decoration: BoxDecoration(
                  color: AppTheme.getBackgroundPrimaryLight(context),
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState() {
    return Container(
      padding: const EdgeInsets.all(32),
      decoration: BoxDecoration(
        color: AppTheme.getBackgroundSecondary(context),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        children: [
          Icon(Icons.photo_library_outlined, color: AppTheme.getPrimaryColor(context), size: 32),
          const SizedBox(height: 12),
          Text(
            'No uploads yet',
            style: TextStyle(fontWeight: FontWeight.w600, color: AppTheme.getTextPrimary(context)),
          ),
          const SizedBox(height: 4),
          Text(
            'You will receive a notification as soon as the team shares the first set of photos.',
            textAlign: TextAlign.center,
            style: TextStyle(color: AppTheme.getTextSecondary(context)),
          ),
        ],
      ),
    );
  }

  Widget _buildGallerySection(
    BuildContext context,
    _GallerySection section,
    ThemeData theme,
  ) {
    final accent = _sectionAccent(section);
    final icon = _sectionIcon(section);
    final latestItems = section.items.take(4).toList();

    return AnimatedWidgetSlide(
      direction: SlideDirection.bottomToTop,
      duration: const Duration(milliseconds: 280),
      child: InkWell(
        onTap: () => _openSection(context, section),
        borderRadius: BorderRadius.circular(24),
        child: Container(
          margin: const EdgeInsets.only(bottom: 22),
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: const Color(0xFFE8EDF4)),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.06),
                blurRadius: 26,
                offset: const Offset(0, 12),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    height: 48,
                    width: 48,
                    decoration: BoxDecoration(
                      color: accent.withOpacity(0.12),
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Icon(icon, color: accent, size: 24),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          section.label,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w800,
                            color: const Color(0xFF111827),
                            letterSpacing: -0.2,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          '${section.taskNames.length} contributing tasks',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: const Color(0xFF6B7280),
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF3F6FA),
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Text(
                      '${section.items.length} uploads',
                      style: const TextStyle(
                        color: Color(0xFF374151),
                        fontSize: 11,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Icon(Icons.chevron_right_rounded,
                      color: const Color(0xFF9CA3AF), size: 24),
                ],
              ),
              const SizedBox(height: 16),
              _buildPreviewGrid(context, latestItems, section.items.length),
              const SizedBox(height: 16),
              Row(
                children: [
                  _buildFooterMetric('Total Tasks', '${section.taskNames.length}'),
                  const SizedBox(width: 12),
                  _buildFooterMetric('Total Uploads', '${section.items.length}'),
                  const Spacer(),
                  _buildUpdatedBadge(section),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildPreviewGrid(
    BuildContext context,
    List<_GalleryImage> items,
    int totalCount,
  ) {
    if (items.isEmpty) {
      return Container(
        height: 156,
        width: double.infinity,
        decoration: BoxDecoration(
          color: const Color(0xFFF6F8FB),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: const Color(0xFFE5EAF1)),
        ),
        child: const Center(
          child: Text(
            'No photos uploaded yet',
            style: TextStyle(
              color: Color(0xFF6B7280),
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      );
    }

    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: items.length,
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        mainAxisSpacing: 10,
        crossAxisSpacing: 10,
        childAspectRatio: 1.34,
      ),
      itemBuilder: (context, index) {
        final item = items[index];
        final extraCount = totalCount - 4;
        final showMore = index == 3 && extraCount > 0;
        return ClipRRect(
          borderRadius: BorderRadius.circular(18),
          child: Stack(
            fit: StackFit.expand,
            children: [
              _buildGalleryMediaPreview(item),
              if (item.isVideo)
                Container(
                  color: Colors.black.withOpacity(0.22),
                  child: const Center(
                    child: Icon(
                      Icons.play_circle_fill_rounded,
                      color: Colors.white,
                      size: 42,
                    ),
                  ),
                ),
              if (showMore)
                Container(
                  color: Colors.black.withOpacity(0.48),
                  child: Center(
                    child: Text(
                      '+$extraCount',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 24,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildGalleryMediaPreview(_GalleryImage item) {
    if (item.isVideo) {
      return Container(
        color: const Color(0xFF111827),
        child: const Center(
          child: Icon(
            Icons.videocam_rounded,
            color: Colors.white70,
            size: 34,
          ),
        ),
      );
    }

    return CachedNetworkImage(
      imageUrl: item.imageUrl,
      fit: BoxFit.cover,
      progressIndicatorBuilder: (context, url, progress) =>
          _buildImageSkeleton(),
      errorWidget: (context, url, error) => _buildBrokenImage(context),
    );
  }

  Future<void> _openGalleryMedia(BuildContext context, _GalleryImage item) {
    return _openGalleryMediaItem(context, item);
  }

  Widget _buildFooterMetric(String label, String value) {
    return RichText(
      text: TextSpan(
        style: const TextStyle(color: Color(0xFF6B7280), fontSize: 11),
        children: [
          TextSpan(text: '$label: '),
          TextSpan(
            text: value,
            style: const TextStyle(
              color: Color(0xFF111827),
              fontWeight: FontWeight.w900,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildUpdatedBadge(_GallerySection section) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: const Color(0xFFEFFAF5),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        _updatedLabel(section),
        style: const TextStyle(
          color: Color(0xFF047857),
          fontSize: 11,
          fontWeight: FontWeight.w900,
        ),
      ),
    );
  }

  void _openSection(BuildContext context, _GallerySection section) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => _GallerySectionDetailScreen(
          section: section,
          accentColor: _sectionAccent(section),
          icon: _sectionIcon(section),
        ),
      ),
    );
  }

  IconData _sectionIcon(_GallerySection section) {
    final iconName = section.iconName?.toLowerCase().trim();
    const icons = {
      'painting': Icons.format_paint_rounded,
      'paint': Icons.format_paint_rounded,
      'kitchen': Icons.kitchen_rounded,
      'bathroom': Icons.bathtub_rounded,
      'tiling': Icons.grid_view_rounded,
      'tile': Icons.grid_view_rounded,
      'ceiling': Icons.layers_rounded,
      'floor': Icons.foundation_rounded,
      'foundation': Icons.account_balance_rounded,
      'electrical': Icons.electrical_services_rounded,
      'plumbing': Icons.plumbing_rounded,
      'wood': Icons.carpenter_rounded,
      'carpentry': Icons.carpenter_rounded,
      'gallery': Icons.photo_library_rounded,
      'photo': Icons.photo_camera_rounded,
      'site': Icons.apartment_rounded,
      'drawing': Icons.architecture_rounded,
      'finishing': Icons.auto_awesome_rounded,
    };
    if (iconName != null && icons.containsKey(iconName)) return icons[iconName]!;

    final fallbackIcons = [
      Icons.apartment_rounded,
      Icons.foundation_rounded,
      Icons.architecture_rounded,
      Icons.home_work_rounded,
      Icons.construction_rounded,
      Icons.dashboard_customize_rounded,
      Icons.view_in_ar_rounded,
      Icons.auto_awesome_rounded,
    ];
    return fallbackIcons[section.id.hashCode.abs() % fallbackIcons.length];
  }

  Color _sectionAccent(_GallerySection section) {
    const colors = [
      Color(0xFF2563EB),
      Color(0xFF7C3AED),
      Color(0xFF059669),
      Color(0xFFEA580C),
      Color(0xFF0D9488),
      Color(0xFFDB2777),
      Color(0xFF4F46E5),
      Color(0xFFB45309),
    ];
    return colors[section.id.hashCode.abs() % colors.length];
  }

  String _updatedLabel(_GallerySection section) {
    DateTime? latest;
    for (final item in section.items) {
      final parsed = _parseLooseDate(item.uploadedAt);
      if (parsed != null && (latest == null || parsed.isAfter(latest))) {
        latest = parsed;
      }
    }
    if (latest == null) return 'Updated Recently';

    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final date = DateTime(latest.year, latest.month, latest.day);
    final diff = today.difference(date).inDays;
    if (diff <= 0) return 'Updated Today';
    if (diff == 1) return 'Updated Yesterday';
    return 'Updated $diff Days Ago';
  }

  DateTime? _parseLooseDate(String? value) {
    if (value == null || value.trim().isEmpty) return null;
    final normalized = value.trim();
    final direct = DateTime.tryParse(normalized);
    if (direct != null) return direct;

    final match = RegExp(r'(\d{1,2})[-/ ]([A-Za-z]{3,}|\d{1,2})[-/ ](\d{4})')
        .firstMatch(normalized);
    if (match == null) return null;
    final day = int.tryParse(match.group(1)!);
    final year = int.tryParse(match.group(3)!);
    final monthValue = match.group(2)!;
    final month = int.tryParse(monthValue) ?? _monthFromName(monthValue);
    if (day == null || month == null || year == null) return null;
    return DateTime(year, month, day);
  }

  int? _monthFromName(String value) {
    const months = {
      'jan': 1,
      'feb': 2,
      'mar': 3,
      'apr': 4,
      'may': 5,
      'jun': 6,
      'jul': 7,
      'aug': 8,
      'sep': 9,
      'oct': 10,
      'nov': 11,
      'dec': 12,
    };
    return months[value.toLowerCase().substring(0, 3)];
  }

  Widget _buildBrokenImage(BuildContext context) {
    return Container(
      color: AppTheme.getBackgroundPrimaryLight(context),
      child: Center(
        child: Icon(Icons.broken_image_outlined, color: AppTheme.getTextSecondary(context)),
      ),
    );
  }

  Widget _buildImageSkeleton() {
    return LayoutBuilder(
      builder: (context, constraints) {
        return Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.centerLeft,
              end: Alignment.centerRight,
              colors: [
                AppTheme.getBackgroundPrimaryLight(context),
                AppTheme.getBackgroundSecondary(context),
                AppTheme.getBackgroundPrimaryLight(context),
              ],
            ),
          ),
        );
      },
    );
  }

}

const String _generalSectionId = '__general__';

class _GallerySection {
  final String id;
  final String label;
  final List<_GalleryImage> items;
  final List<String> taskNames;
  final String? iconName;

  const _GallerySection({
    required this.id,
    required this.label,
    required this.items,
    required this.taskNames,
    this.iconName,
  });
}

class _MutableGallerySection {
  final String id;
  final String label;
  final List<_GalleryImage> items = [];
  final Set<String> taskNames = {};
  String? iconName;

  _MutableGallerySection({
    required this.id,
    required this.label,
  });
}

class _GalleryImage {
  final String imageUrl;
  final String sectionId;
  final String sectionLabel;
  final String? title;
  final String? uploadedAt;
  final String? taskName;
  final String? taskId;
  final String? uploadedBy;
  final String? taskStatus;
  final bool isVideo;

  const _GalleryImage({
    required this.imageUrl,
    required this.sectionId,
    required this.sectionLabel,
    this.title,
    this.uploadedAt,
    this.taskName,
    this.taskId,
    this.uploadedBy,
    this.taskStatus,
    this.isVideo = false,
  });
}

class _GallerySectionDetailScreen extends StatelessWidget {
  final _GallerySection section;
  final Color accentColor;
  final IconData icon;

  const _GallerySectionDetailScreen({
    required this.section,
    required this.accentColor,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.getBackgroundPrimary(context),
      appBar: AppBar(
        backgroundColor: AppTheme.getBackgroundSecondary(context),
        foregroundColor: AppTheme.navy,
        elevation: 0,
        scrolledUnderElevation: 0,
        iconTheme: const IconThemeData(color: AppTheme.navy),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded),
          onPressed: () => Navigator.of(context).maybePop(),
        ),
        title: Text(
          section.label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
            fontWeight: FontWeight.w800,
            color: AppTheme.navy,
          ),
        ),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
          children: [
            _buildHeader(context),
            const SizedBox(height: 18),
            GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: section.items.length,
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 2,
                crossAxisSpacing: 12,
                mainAxisSpacing: 14,
                childAspectRatio: 0.64,
              ),
              itemBuilder: (context, index) {
                return _buildPhotoCard(context, section.items[index]);
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: const Color(0xFFE8EDF4)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 24,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            height: 52,
            width: 52,
            decoration: BoxDecoration(
              color: accentColor.withOpacity(0.12),
              borderRadius: BorderRadius.circular(18),
            ),
            child: Icon(icon, color: accentColor, size: 26),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  section.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Color(0xFF111827),
                    fontSize: 18,
                    fontWeight: FontWeight.w900,
                    letterSpacing: -0.2,
                  ),
                ),
                const SizedBox(height: 5),
                Text(
                  '${section.taskNames.length} tasks • ${section.items.length} uploads',
                  style: const TextStyle(
                    color: Color(0xFF6B7280),
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPhotoCard(BuildContext context, _GalleryImage item) {
    return InkWell(
      onTap: () => _openGalleryMediaItem(context, item),
      borderRadius: BorderRadius.circular(22),
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(22),
          border: Border.all(color: const Color(0xFFE8EDF4)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.05),
              blurRadius: 18,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: ClipRRect(
                borderRadius:
                    const BorderRadius.vertical(top: Radius.circular(22)),
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    item.isVideo
                        ? Container(
                            color: const Color(0xFF111827),
                            child: const Center(
                              child: Icon(
                                Icons.videocam_rounded,
                                color: Colors.white70,
                                size: 36,
                              ),
                            ),
                          )
                        : CachedNetworkImage(
                            imageUrl: item.imageUrl,
                            width: double.infinity,
                            fit: BoxFit.cover,
                            errorWidget: (context, url, error) => Container(
                              color: const Color(0xFFF3F6FA),
                              child: const Icon(Icons.broken_image_outlined,
                                  color: Color(0xFF9CA3AF)),
                            ),
                          ),
                    if (item.isVideo)
                      Container(
                        color: Colors.black.withOpacity(0.22),
                        child: const Center(
                          child: Icon(
                            Icons.play_circle_fill_rounded,
                            color: Colors.white,
                            size: 44,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(11),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    item.taskName ?? item.title ?? 'Workflow upload',
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Color(0xFF111827),
                      fontSize: 12,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 5),
                  if (item.taskId != null)
                    Text(
                      'Task #${item.taskId}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Color(0xFF6B7280),
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  if (item.uploadedBy != null)
                    Text(
                      'Uploaded by ${item.uploadedBy}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Color(0xFF6B7280),
                        fontSize: 10,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  if (item.uploadedAt != null) ...[
                    const SizedBox(height: 3),
                    Row(
                      children: [
                        const Icon(
                          Icons.schedule_rounded,
                          size: 11,
                          color: Color(0xFF9CA3AF),
                        ),
                        const SizedBox(width: 4),
                        Expanded(
                          child: Text(
                            item.uploadedAt!,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: Color(0xFF6B7280),
                              fontSize: 10,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                  if (item.taskStatus != null) ...[
                    const SizedBox(height: 7),
                    _buildStatusBadge(item.taskStatus!),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatusBadge(String status) {
    final normalized = status.replaceAll('_', ' ');
    final isDone = status.toLowerCase().contains('complete') ||
        status.toLowerCase().contains('done');
    final color = isDone ? const Color(0xFF047857) : const Color(0xFFB45309);
    final bg = isDone ? const Color(0xFFEFFAF5) : const Color(0xFFFFF7ED);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        normalized,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          color: color,
          fontSize: 9,
          fontWeight: FontWeight.w900,
        ),
      ),
    );
  }
}

enum SlideDirection { leftToRight, rightToLeft, topToBottom, bottomToTop }

class AnimatedWidgetSlide extends StatefulWidget {
  final Widget child;
  final SlideDirection direction;
  final Duration duration;

  const AnimatedWidgetSlide({
    super.key,
    required this.child,
    required this.direction,
    required this.duration,
  });

  @override
  State<AnimatedWidgetSlide> createState() => _AnimatedWidgetSlideState();
}

class _AnimatedWidgetSlideState extends State<AnimatedWidgetSlide> with SingleTickerProviderStateMixin {
  late AnimationController _animationController;
  late Animation<Offset> _slideAnimation;

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      vsync: this,
      duration: widget.duration,
    );

    switch (widget.direction) {
      case SlideDirection.leftToRight:
        _slideAnimation = Tween<Offset>(
          begin: const Offset(-1.0, 0.0),
          end: const Offset(0.0, 0.0),
        ).animate(CurvedAnimation(
          parent: _animationController,
          curve: Curves.easeIn,
        ));
        break;
      case SlideDirection.rightToLeft:
        _slideAnimation = Tween<Offset>(
          begin: const Offset(1.0, 0.0),
          end: const Offset(0.0, 0.0),
        ).animate(CurvedAnimation(
          parent: _animationController,
          curve: Curves.easeIn,
        ));
        break;
      case SlideDirection.topToBottom:
        _slideAnimation = Tween<Offset>(
          begin: const Offset(0.0, -1.0),
          end: const Offset(0.0, 0.0),
        ).animate(CurvedAnimation(
          parent: _animationController,
          curve: Curves.easeInOut,
        ));
        break;
      case SlideDirection.bottomToTop:
        _slideAnimation = Tween<Offset>(
          begin: const Offset(0.0, 1.0),
          end: const Offset(0.0, 0.0),
        ).animate(CurvedAnimation(
          parent: _animationController,
          curve: Curves.easeInOut,
        ));
        break;
    }

    _animationController.forward();
  }

  @override
  Widget build(BuildContext context) {
    return SlideTransition(
      position: _slideAnimation,
      child: widget.child,
    );
  }

  @override
  void dispose() {
    _animationController.dispose();
    super.dispose();
  }
}