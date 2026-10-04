import 'dart:convert';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import 'AddDailyUpdate.dart';
import 'app_theme.dart';
import 'services/rbac_service.dart';
import 'widgets/themed_scaffold.dart';
import 'widgets/skeleton_loader.dart';

class DprScreen extends StatefulWidget {
  final String title;
  final bool embedded;

  const DprScreen({
    super.key,
    this.title = 'All Updates',
    this.embedded = false,
  });

  @override
  DprState createState() => DprState();
}

class DprState extends State<DprScreen> {
  static const Color _navy = AppTheme.navy;
  static const Color _mutedGrey = AppTheme.mutedGrey;
  static const String _imageBaseUrl =
      'https://office.buildahome.in/files/migrated';

  var entries;
  var listOfDates = [];
  /// Flat list of update cards: {title, date, ids, images}.
  var listOfUpdates = <Map<String, dynamic>>[];
  bool _isLoading = true;
  String? _error;
  bool _canAddDailyUpdate = false;
  String? _projectId;
  String? _projectName;

  String? _imageUrlFromFilename(dynamic filename) {
    final name = filename?.toString().trim() ?? '';
    if (name.isEmpty || name == 'null') return null;
    if (name.startsWith('http://') || name.startsWith('https://')) {
      return name;
    }
    if (name.startsWith('/')) {
      return 'https://office.buildahome.in$name';
    }
    return '$_imageBaseUrl/$name';
  }

  Future<Map<String, List<String>>> _loadGalleryImagesByDate(
      String projectId) async {
    final byDate = <String, List<String>>{};
    try {
      final response = await http
          .get(Uri.parse(
              'https://office.buildahome.in/API/get_gallery_data?id=$projectId'))
          .timeout(const Duration(seconds: 20));
      if (response.statusCode != 200) return byDate;
      final decoded = jsonDecode(response.body);
      if (decoded is! List) return byDate;
      for (final item in decoded) {
        if (item is! Map) continue;
        final date = item['date']?.toString() ?? '';
        final url = _imageUrlFromFilename(item['image']);
        if (date.isEmpty || url == null) continue;
        byDate.putIfAbsent(date, () => <String>[]).add(url);
      }
    } catch (_) {
      // Updates still render without images if gallery fetch fails.
    }
    return byDate;
  }

  /// Group consecutive same-title rows (multi-photo uploads) and attach
  /// gallery images for that date in API order.
  List<Map<String, dynamic>> _buildUpdateCards(
    List decoded,
    Map<String, List<String>> galleryByDate,
  ) {
    final rawByDate = <String, List<Map<String, dynamic>>>{};
    final dateOrder = <String>[];

    for (final item in decoded) {
      if (item is! Map) continue;
      final date = item['date']?.toString() ?? '';
      final title = item['update_title']?.toString() ?? '';
      final updateId = item['id'];
      if (date.isEmpty || title.isEmpty) continue;
      if (!dateOrder.contains(date)) dateOrder.add(date);
      rawByDate.putIfAbsent(date, () => <Map<String, dynamic>>[]).add({
        'id': updateId,
        'title': title,
      });
    }

    final cards = <Map<String, dynamic>>[];
    for (final date in dateOrder) {
      final rows = rawByDate[date] ?? const <Map<String, dynamic>>[];
      final imageQueue = List<String>.from(galleryByDate[date] ?? const []);
      final groups = <Map<String, dynamic>>[];

      for (final row in rows) {
        final title = row['title']?.toString() ?? '';
        if (groups.isNotEmpty && groups.last['title'] == title) {
          (groups.last['ids'] as List).add(row['id']);
        } else {
          groups.add({
            'title': title,
            'date': date,
            'ids': <dynamic>[row['id']],
            'images': <String>[],
          });
        }
      }

      for (final group in groups) {
        final ids = group['ids'] as List;
        final images = group['images'] as List<String>;
        for (var i = 0; i < ids.length && imageQueue.isNotEmpty; i++) {
          images.add(imageQueue.removeAt(0));
        }
        cards.add(group);
      }
    }
    return cards;
  }

  Future<void> call({bool showLoader = true}) async {
    if (showLoader && mounted) {
      setState(() {
        _isLoading = true;
        _error = null;
      });
    }

    try {
      SharedPreferences prefs = await SharedPreferences.getInstance();
      var id = prefs.getString('project_id');
      if (id == null || id.isEmpty) {
        if (!mounted) return;
        setState(() {
          listOfDates = [];
          listOfUpdates = [];
          entries = [];
          _isLoading = false;
          _error = 'No project selected';
        });
        return;
      }

      final updatesFuture = http
          .get(Uri.parse('https://office.buildahome.in/API/view_all_dpr?id=$id'))
          .timeout(const Duration(seconds: 20));
      final galleryFuture = _loadGalleryImagesByDate(id);

      final response = await updatesFuture;
      final galleryByDate = await galleryFuture;

      if (!mounted) return;

      if (response.statusCode != 200) {
        setState(() {
          _isLoading = false;
          _error = 'Could not load updates';
        });
        return;
      }

      final decoded = jsonDecode(response.body);
      final nextDates = <String>[];
      var nextCards = <Map<String, dynamic>>[];

      if (decoded is List) {
        for (final item in decoded) {
          if (item is! Map) continue;
          final date = item['date']?.toString() ?? '';
          if (date.isNotEmpty && !nextDates.contains(date)) {
            nextDates.add(date);
          }
        }
        nextCards = _buildUpdateCards(decoded, galleryByDate);
      }

      setState(() {
        entries = decoded;
        listOfDates = nextDates;
        listOfUpdates = nextCards;
        _isLoading = false;
        _error = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _error = 'Could not load updates';
      });
    }
  }

  @override
  void initState() {
    super.initState();
    _loadRoleAccess();
    call();
  }

  Future<void> _loadRoleAccess() async {
    final prefs = await SharedPreferences.getInstance();
    final role = RBACService().normalizeRole(prefs.getString('role')) ??
        prefs.getString('role') ??
        '';
    final normalized = role.toLowerCase().trim().replaceAll(RegExp(r'\s+'), ' ');
    // Super Admin is often stored as Admin in prefs.
    final allowed = normalized == 'site engineer' ||
        normalized == 'super admin' ||
        normalized == 'admin';
    if (!mounted) return;
    setState(() {
      _canAddDailyUpdate = allowed;
      _projectId = prefs.getString('project_id');
      _projectName =
          prefs.getString('client_name') ?? prefs.getString('project_name');
    });
  }

  Future<void> _openAddDailyUpdate() async {
    final projectId = (_projectId ?? '').trim();
    if (projectId.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No project selected')),
      );
      return;
    }

    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => AddDailyUpdate(
          initialProjectId: projectId,
          initialProjectName: _projectName,
        ),
      ),
    );
    if (!mounted) return;
    await call(showLoader: false);
  }

  Future<void> _confirmDelete(List<dynamic> updateIds) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: AppTheme.darkBackgroundSecondary,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(
          'Delete update?',
          style: TextStyle(
            color: AppTheme.darkTextPrimary,
            fontWeight: FontWeight.w800,
            fontSize: 18,
          ),
        ),
        content: const Text(
          'This update will be removed from the project timeline.',
          style: TextStyle(
            color: _mutedGrey,
            fontSize: 14,
            height: 1.4,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            style: TextButton.styleFrom(foregroundColor: const Color(0xFFDC2626)),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;

    try {
      for (final updateId in updateIds) {
        if (updateId == null) continue;
        final url =
            'https://office.buildahome.in/API/delete_update?id=$updateId';
        await http.get(Uri.parse(url)).timeout(const Duration(seconds: 15));
      }
      await call(showLoader: false);
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Failed to delete update')),
      );
    }
  }

  void _openImage(String imageUrl) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => FullScreenImage(NetworkImage(imageUrl)),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final body = _buildBody();
    if (widget.embedded) return body;

    return ThemedScaffold(
      title: widget.title,
      backgroundColor: AppTheme.darkBackgroundPrimary,
      actions: _canAddDailyUpdate
          ? [
              TextButton.icon(
                onPressed: _openAddDailyUpdate,
                icon: const Icon(Icons.add_rounded, color: Colors.white, size: 18),
                label: const Text(
                  'Add update',
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ]
          : null,
      body: body,
    );
  }

  Widget _buildBody() {
    if (_isLoading && listOfDates.isEmpty) {
      return const SkeletonListLoader(showSummary: false, cardCount: 4);
    }

    if (_error != null && listOfDates.isEmpty) {
      return _buildMessageState(
        icon: Icons.cloud_off_rounded,
        title: _error!,
        subtitle: 'Pull to refresh and try again.',
      );
    }

    if (listOfDates.isEmpty) {
      return _buildMessageState(
        icon: Icons.campaign_outlined,
        title: 'No updates yet',
        subtitle: 'Daily project updates will appear here.',
      );
    }

    return RefreshIndicator(
      color: _navy,
      onRefresh: () => call(showLoader: false),
      child: ListView.builder(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
        itemCount: listOfDates.length,
        itemBuilder: (context, index) {
          final date = listOfDates[index]?.toString() ?? '';
          final updatesForDate = listOfUpdates
              .where((update) => update['date']?.toString() == date)
              .toList();

          return _buildDateGroup(
            date: date,
            updates: updatesForDate,
            isFirst: index == 0,
          );
        },
      ),
    );
  }

  Widget _buildDateGroup({
    required String date,
    required List<Map<String, dynamic>> updates,
    required bool isFirst,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: EdgeInsets.only(top: isFirst ? 2 : 22, bottom: 12),
          child: Text(
            date.trim().isEmpty ? 'Undated' : date,
            style: TextStyle(
              color: AppTheme.darkTextSecondary,
              fontSize: 13,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.1,
            ),
          ),
        ),
        ...updates.map((update) => _buildUpdateCard(update)),
      ],
    );
  }

  Widget _buildUpdateCard(Map<String, dynamic> update) {
    final title = update['title']?.toString().trim() ?? '';
    final ids = (update['ids'] is List)
        ? List<dynamic>.from(update['ids'] as List)
        : <dynamic>[update['id']];
    final images = (update['images'] is List)
        ? (update['images'] as List)
            .map((e) => e.toString())
            .where((e) => e.isNotEmpty)
            .toList()
        : <String>[];
    final hasImages = images.isNotEmpty;

    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      decoration: BoxDecoration(
        color: AppTheme.darkBackgroundSecondary,
        borderRadius: BorderRadius.circular(18),
        boxShadow: const [
          BoxShadow(
            color: Color(0x22000000),
            blurRadius: 16,
            offset: Offset(0, 6),
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (hasImages) _buildUpdateImageHero(images),
          Padding(
            padding: EdgeInsets.fromLTRB(
              16,
              hasImages ? 14 : 16,
              8,
              16,
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Text(
                    title,
                    style: TextStyle(
                      color: AppTheme.darkTextPrimary,
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      height: 1.4,
                      letterSpacing: -0.15,
                    ),
                  ),
                ),
                if (_canAddDailyUpdate)
                  IconButton(
                    onPressed: () => _confirmDelete(ids),
                    tooltip: 'Delete',
                    visualDensity: VisualDensity.compact,
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(
                      minWidth: 36,
                      minHeight: 36,
                    ),
                    icon: Icon(
                      Icons.delete_outline_rounded,
                      color: const Color(0xFFEF4444).withValues(alpha: 0.9),
                      size: 20,
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildUpdateImageHero(List<String> images) {
    if (images.length == 1) {
      return _buildHeroImage(imageUrl: images.first);
    }

    return SizedBox(
      height: 210,
      child: Stack(
        children: [
          PageView.builder(
            itemCount: images.length,
            itemBuilder: (context, index) {
              return _buildHeroImage(imageUrl: images[index]);
            },
          ),
          Positioned(
            right: 12,
            bottom: 12,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.55),
                borderRadius: BorderRadius.circular(999),
              ),
              child: Text(
                '${images.length} photos',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeroImage({required String imageUrl}) {
    return GestureDetector(
      onTap: () => _openImage(imageUrl),
      child: SizedBox(
        height: 210,
        width: double.infinity,
        child: CachedNetworkImage(
          imageUrl: imageUrl,
          fit: BoxFit.cover,
          placeholder: (_, __) => Container(
            color: AppTheme.darkBackgroundPrimaryLight,
            alignment: Alignment.center,
            child: const SizedBox(
              width: 22,
              height: 22,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: AppTheme.accentBlue,
              ),
            ),
          ),
          errorWidget: (_, __, ___) => Container(
            color: AppTheme.darkBackgroundPrimaryLight,
            alignment: Alignment.center,
            child: const Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  Icons.broken_image_outlined,
                  color: _mutedGrey,
                  size: 28,
                ),
                SizedBox(height: 6),
                Text(
                  'Image unavailable',
                  style: TextStyle(
                    color: _mutedGrey,
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildMessageState({
    required IconData icon,
    required String title,
    required String subtitle,
  }) {
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 80),
      children: [
        Center(
          child: Container(
            width: 84,
            height: 84,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: AppTheme.darkBackgroundPrimaryLight,
              borderRadius: BorderRadius.circular(24),
            ),
            child: Icon(icon, size: 36, color: _mutedGrey),
          ),
        ),
        const SizedBox(height: 20),
        Text(
          title,
          textAlign: TextAlign.center,
          style: TextStyle(
            color: AppTheme.darkTextPrimary,
            fontSize: 18,
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          subtitle,
          textAlign: TextAlign.center,
          style: const TextStyle(
            color: _mutedGrey,
            fontSize: 14,
            fontWeight: FontWeight.w500,
            height: 1.4,
          ),
        ),
        if (_error != null) ...[
          const SizedBox(height: 20),
          Center(
            child: TextButton(
              onPressed: () => call(),
              child: const Text('Retry'),
            ),
          ),
        ],
        if (_canAddDailyUpdate && _error == null) ...[
          const SizedBox(height: 24),
          Center(
            child: FilledButton.icon(
              onPressed: _openAddDailyUpdate,
              style: FilledButton.styleFrom(
                backgroundColor: AppTheme.accentBlue,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              icon: const Icon(Icons.add_rounded, size: 18),
              label: const Text(
                'Add daily update',
                style: TextStyle(fontWeight: FontWeight.w700),
              ),
            ),
          ),
        ],
      ],
    );
  }
}
