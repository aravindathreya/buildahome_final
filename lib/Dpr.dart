import 'dart:convert';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'AddDailyUpdate.dart';
import 'FullScreenImage.dart' as gallery_viewer;
import 'app_theme.dart';
import 'services/rbac_service.dart';
import 'widgets/themed_scaffold.dart';
import 'widgets/skeleton_loader.dart';

class DprScreen extends StatefulWidget {
  final String title;
  final bool embedded;

  /// View-only: hides Add and Delete regardless of role.
  final bool readOnly;

  /// ERP project to show; defaults to the selected project in prefs.
  final String? projectId;

  const DprScreen({
    super.key,
    this.title = 'All Updates',
    this.embedded = false,
    this.readOnly = false,
    this.projectId,
  });

  @override
  DprState createState() => DprState();
}

/// Parses the App_updates `date` string ("Thursday October 29 2026").
DateTime? parseDprDate(String raw) {
  final s = raw.trim();
  if (s.isEmpty) return null;
  for (final pattern in const ['EEEE MMMM dd yyyy', 'EEEE MMMM d yyyy']) {
    try {
      return DateFormat(pattern).parseLoose(s);
    } catch (_) {}
  }
  return DateTime.tryParse(s);
}

/// Parses a tradesmen map ("{Carpenter: 3, Mason: 2}", JSON, or a Map) into
/// ordered name -> count entries. Empty when missing.
List<MapEntry<String, String>> parseDprTradesmen(dynamic raw) {
  if (raw == null) return const [];
  if (raw is Map) {
    return raw.entries
        .map((e) => MapEntry(e.key.toString().trim(), e.value.toString().trim()))
        .where((e) => e.key.isNotEmpty && e.value.isNotEmpty && e.value != '0')
        .toList();
  }
  if (raw is List) {
    return raw
        .whereType<Map>()
        .map((m) => m.length == 1
            ? MapEntry(m.keys.first.toString().trim(),
                m.values.first.toString().trim())
            : MapEntry(
              (m['name'] ?? m['trade'] ?? '').toString().trim(),
              (m['count'] ?? m['value'] ?? '').toString().trim(),
            ))
        .where((e) => e.key.isNotEmpty && e.value.isNotEmpty && e.value != '0')
        .toList();
  }
  var s = raw.toString().trim();
  if (s.isEmpty || s == 'null' || s == '{}') return const [];
  try {
    final decoded = jsonDecode(s);
    if (decoded is Map || decoded is List) return parseDprTradesmen(decoded);
  } catch (_) {}
  if (s.startsWith('{')) s = s.substring(1);
  if (s.endsWith('}')) s = s.substring(0, s.length - 1);
  final out = <MapEntry<String, String>>[];
  for (final part in s.split(',')) {
    final idx = part.lastIndexOf(':');
    if (idx <= 0) continue;
    final name = part.substring(0, idx).replaceAll('"', '').replaceAll("'", '').trim();
    final count = part.substring(idx + 1).replaceAll('"', '').replaceAll("'", '').trim();
    if (name.isEmpty || count.isEmpty || count == '0') continue;
    out.add(MapEntry(name, count));
  }
  return out;
}

/// One timeline day: every update row for that date plus its gallery photos.
class DprDayGroup {
  final String date;
  final DateTime? day;
  final List<Map<String, dynamic>> updates;
  final List<String> images;
  final DateTime? submittedAt;

  DprDayGroup({
    required this.date,
    required this.day,
    required this.updates,
    required this.images,
    this.submittedAt,
  });
}

/// Builds day groups from /API/view_all_dpr rows (newest first) and gallery
/// images keyed by date. Consecutive same-title rows are merged (multi-photo).
List<DprDayGroup> buildDprDayGroups(
  List rows,
  Map<String, List<String>> galleryByDate,
) {
  final order = <String>[];
  final byDate = <String, List<Map<String, dynamic>>>{};
  final submitted = <String, DateTime?>{};
  for (final item in rows) {
    if (item is! Map) continue;
    final date = item['date']?.toString() ?? '';
    final title = item['update_title']?.toString() ?? '';
    if (date.isEmpty || title.isEmpty) continue;
    if (!order.contains(date)) {
      order.add(date);
      submitted[date] = DateTime.tryParse(
          (item['updated_at'] ?? item['created_at'] ?? '').toString());
    }
    final list = byDate.putIfAbsent(date, () => <Map<String, dynamic>>[]);
    final tradesmen =
        parseDprTradesmen(item['tradesmenMap'] ?? item['tradesmen']);
    if (list.isNotEmpty && list.last['title'] == title) {
      (list.last['ids'] as List).add(item['id']);
      if ((list.last['tradesmen'] as List).isEmpty && tradesmen.isNotEmpty) {
        list.last['tradesmen'] = tradesmen;
      }
    } else {
      list.add({
        'title': title,
        'ids': <dynamic>[item['id']],
        'tradesmen': tradesmen,
        'updatedAt': DateTime.tryParse(
            (item['updated_at'] ?? item['created_at'] ?? '').toString()),
      });
    }
  }
  return order
      .map((date) => DprDayGroup(
            date: date,
            day: parseDprDate(date),
            updates: byDate[date] ?? const [],
            images: List<String>.from(galleryByDate[date] ?? const <String>[]),
            submittedAt: submitted[date],
          ))
      .toList();
}

class DprState extends State<DprScreen> {
  static const Color _navy = AppTheme.navy;
  static const Color _mutedGrey = AppTheme.mutedGrey;
  static const String _imageBaseUrl =
      'https://office.buildahome.in/files/migrated';

  var entries;
  var listOfDates = [];
  List<DprDayGroup> _groups = <DprDayGroup>[];
  int _totalPhotos = 0;
  bool _isLoading = true;
  String? _error;
  bool _canAddDailyUpdate = false;
  bool _canDeleteUpdate = false;
  String? _projectId;
  String? _projectName;
  String? _projectNumber;

  // Filters (applied locally on loaded data).
  DateTime? _fromDate;
  DateTime? _toDate;
  DateTime? _appliedFrom;
  DateTime? _appliedTo;
  bool _latestFirst = true;

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

  Future<void> call({bool showLoader = true}) async {
    if (showLoader && mounted) {
      setState(() {
        _isLoading = true;
        _error = null;
      });
    }

    try {
      SharedPreferences prefs = await SharedPreferences.getInstance();
      final override = widget.projectId?.trim() ?? '';
      var id = override.isNotEmpty ? override : prefs.getString('project_id');
      if (id == null || id.isEmpty) {
        if (!mounted) return;
        setState(() {
          listOfDates = [];
          _groups = [];
          _totalPhotos = 0;
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
      var nextGroups = <DprDayGroup>[];
      if (decoded is List) {
        nextGroups = buildDprDayGroups(decoded, galleryByDate);
      }
      var photos = 0;
      for (final list in galleryByDate.values) {
        photos += list.length;
      }

      setState(() {
        entries = decoded;
        _groups = nextGroups;
        listOfDates = nextGroups.map((g) => g.date).toList();
        _totalPhotos = photos;
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
    // Site engineers can add updates, but cannot delete photos or updates.
    final canAdd = normalized == 'site engineer' ||
        normalized == 'super admin' ||
        normalized == 'admin';
    final canDelete =
        normalized == 'super admin' || normalized == 'admin';
    if (!mounted) return;
    final prefsProjectId = prefs.getString('project_id');
    final projectId = (widget.projectId?.trim().isNotEmpty ?? false)
        ? widget.projectId!.trim()
        : prefsProjectId;
    // Only trust the cached name/number when they belong to this project.
    final sameProject = projectId != null && projectId == prefsProjectId;
    setState(() {
      _canAddDailyUpdate = canAdd && !widget.readOnly;
      _canDeleteUpdate = canDelete && !widget.readOnly;
      _projectId = projectId;
      _projectName = sameProject
          ? (prefs.getString('client_name') ?? prefs.getString('project_name'))
          : null;
      _projectNumber = sameProject ? prefs.getString('project_number') : null;
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
    if (!_canDeleteUpdate) return;
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

  void _openImage(List<String> images, int index) {
    if (images.isEmpty) return;
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => gallery_viewer.FullScreenImage(
          images[index],
          imageUrls: images,
          initialIndex: index,
        ),
      ),
    );
  }

  // Web /project_dlr_dpr palette.
  static const Color _ink = Color(0xFF0F172A);
  static const Color _slate = Color(0xFF64748B);
  static const Color _line = Color(0xFFE2E8F0);
  static const Color _webNavy = Color(0xFF00004E);
  static const Color _blue = Color(0xFF2563EB);
  bool get _dark => AppTheme.isDark;
  Color get _cardBg => _dark ? AppTheme.darkBackgroundSecondary : Colors.white;
  Color get _pageBg =>
      _dark ? AppTheme.darkBackgroundPrimary : const Color(0xFFF5F7FB);
  Color get _textMain => _dark ? AppTheme.darkTextPrimary : _ink;
  Color get _textSub => _dark ? AppTheme.darkTextSecondary : _slate;
  Color get _border => _dark ? AppTheme.border : _line;
  Color get _softBox =>
      _dark ? AppTheme.darkBackgroundPrimaryLight : const Color(0xFFF1F5F9);

  bool get _isDlrMode =>
      widget.title.toUpperCase().contains('DLR') ||
      widget.title.toUpperCase().contains('DPR');

  List<DprDayGroup> get _visibleGroups {
    final out = _groups.where((g) {
      final d = g.day;
      if (_appliedFrom == null && _appliedTo == null) return true;
      if (d == null) return false;
      final day = DateTime(d.year, d.month, d.day);
      if (_appliedFrom != null && day.isBefore(_appliedFrom!)) return false;
      if (_appliedTo != null && day.isAfter(_appliedTo!)) return false;
      return true;
    }).toList();
    return _latestFirst ? out : out.reversed.toList();
  }

  String _fmtDay(DateTime? d, String fallback) {
    if (d == null) return fallback.trim().isEmpty ? 'Undated' : fallback;
    return DateFormat('EEEE MMMM d yyyy').format(d);
  }

  String _fmtTime(DateTime d) => DateFormat('hh:mm a').format(d);

  @override
  Widget build(BuildContext context) {
    final body = Container(color: _pageBg, child: _buildBody());
    if (widget.embedded) return body;

    return ThemedScaffold(
      title: widget.title,
      backgroundColor: _pageBg,
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
    if (_isLoading && _groups.isEmpty) {
      return const SkeletonListLoader(showSummary: true, cardCount: 4);
    }

    if (_error != null && _groups.isEmpty) {
      return _buildMessageState(
        icon: Icons.cloud_off_rounded,
        title: _error!,
        subtitle: 'Pull to refresh and try again.',
      );
    }

    if (_groups.isEmpty) {
      return _buildMessageState(
        icon: Icons.campaign_outlined,
        title: 'No updates yet',
        subtitle: 'Daily project updates will appear here.',
      );
    }

    final visible = _visibleGroups;
    return RefreshIndicator(
      color: _navy,
      onRefresh: () => call(showLoader: false),
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(14, 14, 14, 32),
        children: [
          _buildHeader(),
          const SizedBox(height: 14),
          _buildSummaryCards(),
          const SizedBox(height: 12),
          _buildFilterBar(),
          const SizedBox(height: 18),
          _buildSectionHeader(),
          const SizedBox(height: 10),
          if (visible.isEmpty)
            _buildInlineEmpty()
          else
            for (var i = 0; i < visible.length; i++)
              _buildTimelineItem(visible[i], isLast: i == visible.length - 1),
        ],
      ),
    );
  }

  BoxDecoration _cardDecoration({double radius = 14}) => BoxDecoration(
        color: _cardBg,
        borderRadius: BorderRadius.circular(radius),
        border: Border.all(color: _border),
        boxShadow: const [
          BoxShadow(color: Color(0x0F0F172A), blurRadius: 10, offset: Offset(0, 3)),
        ],
      );

  Widget _buildHeader() {
    final name = (_projectName ?? '').trim();
    final number = (_projectNumber ?? '').trim();
    final id = (_projectId ?? '').trim();
    final parts = <String>[
      if (name.isNotEmpty) name,
      if (number.isNotEmpty) 'Project #$number',
      if (id.isNotEmpty) 'ID $id',
    ];
    final canPop = !widget.embedded && Navigator.of(context).canPop();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 40,
              height: 40,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: _dark ? AppTheme.darkBackgroundPrimaryLight : _webNavy,
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(Icons.photo_camera_rounded,
                  color: Colors.white, size: 22),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _isDlrMode ? 'DLR / DPR Updates' : widget.title,
                    style: TextStyle(
                      color: _dark ? _textMain : _webNavy,
                      fontSize: 21,
                      fontWeight: FontWeight.w800,
                      letterSpacing: -0.3,
                    ),
                  ),
                  if (parts.isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text(
                      parts.join(' · '),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: _textSub,
                        fontSize: 12.5,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
        if (canPop) ...[
          const SizedBox(height: 10),
          Align(
            alignment: Alignment.centerRight,
            child: OutlinedButton.icon(
              onPressed: () => Navigator.of(context).maybePop(),
              style: OutlinedButton.styleFrom(
                foregroundColor: _dark ? _textMain : _webNavy,
                backgroundColor: _cardBg,
                side: BorderSide(color: _border),
                visualDensity: VisualDensity.compact,
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              ),
              icon: const Icon(Icons.arrow_back_rounded, size: 16),
              label: Text(_isDlrMode ? 'Back to project' : 'Back',
                  style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildSummaryCards() {
    // The web "Avg. labour per update" card is intentionally NOT shown in the app.
    final latest = _groups.isEmpty ? null : _groups.first;
    final latestValue = latest?.day != null
        ? DateFormat('d MMM yyyy').format(latest!.day!)
        : (latest?.date ?? '—');
    final latestSub =
        latest?.submittedAt != null ? _fmtTime(latest!.submittedAt!) : 'Most recent';
    var totalUpdates = 0;
    for (final g in _groups) {
      for (final u in g.updates) {
        totalUpdates += (u['ids'] as List).length;
      }
    }
    final cards = [
      _summaryCard(
        icon: Icons.description_outlined,
        tint: const Color(0xFFEFF6FF),
        chip: const Color(0xFFDBEAFE),
        iconColor: _blue,
        value: '$totalUpdates',
        label: 'Total updates',
        sub: 'All time',
      ),
      _summaryCard(
        icon: Icons.image_outlined,
        tint: const Color(0xFFF0FDF4),
        chip: const Color(0xFFDCFCE7),
        iconColor: const Color(0xFF16A34A),
        value: '$_totalPhotos',
        label: 'Site photos',
        sub: 'All time',
      ),
      _summaryCard(
        icon: Icons.calendar_month_outlined,
        tint: const Color(0xFFF5F3FF),
        chip: const Color(0xFFEDE9FE),
        iconColor: const Color(0xFF7C3AED),
        value: latestValue,
        label: 'Latest update',
        sub: latestSub,
      ),
    ];
    return LayoutBuilder(builder: (context, c) {
      if (c.maxWidth >= 560) {
        return Row(
          children: [
            for (var i = 0; i < cards.length; i++) ...[
              if (i > 0) const SizedBox(width: 10),
              Expanded(child: cards[i]),
            ],
          ],
        );
      }
      return Column(
        children: [
          Row(
            children: [
              Expanded(child: cards[0]),
              const SizedBox(width: 10),
              Expanded(child: cards[1]),
            ],
          ),
          const SizedBox(height: 10),
          cards[2],
        ],
      );
    });
  }

  Widget _summaryCard({
    required IconData icon,
    required Color tint,
    required Color chip,
    required Color iconColor,
    required String value,
    required String label,
    required String sub,
  }) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
      decoration: BoxDecoration(
        color: _dark ? iconColor.withValues(alpha: 0.12) : tint,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: _dark ? iconColor.withValues(alpha: 0.2) : chip,
              shape: BoxShape.circle,
            ),
            child: Icon(icon, color: iconColor, size: 20),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  value,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: _textMain,
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: _textMain,
                    fontSize: 12.5,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                Text(sub, style: TextStyle(color: _textSub, fontSize: 11)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _pickDate({required bool from}) async {
    final now = DateTime.now();
    final initial = (from ? _fromDate : _toDate) ?? now;
    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(2015),
      lastDate: DateTime(now.year + 1, 12, 31),
    );
    if (picked == null || !mounted) return;
    setState(() {
      if (from) {
        _fromDate = picked;
      } else {
        _toDate = picked;
      }
    });
  }

  Widget _dateField(String label, DateTime? value, bool from) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label,
            style: TextStyle(
                color: _textMain, fontSize: 12.5, fontWeight: FontWeight.w500)),
        const SizedBox(height: 5),
        InkWell(
          onTap: () => _pickDate(from: from),
          borderRadius: BorderRadius.circular(8),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
            decoration: BoxDecoration(
              color: _cardBg,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: _dark ? _border : const Color(0xFFCBD5E1)),
            ),
            child: Row(
              children: [
                Icon(Icons.calendar_today_outlined, size: 14, color: _textSub),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    value == null ? 'dd-mm-yyyy' : DateFormat('dd-MM-yyyy').format(value),
                    style: TextStyle(
                      color: value == null ? _textSub : _textMain,
                      fontSize: 13,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildFilterBar() {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: _cardDecoration(radius: 12),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(child: _dateField('From date', _fromDate, true)),
              const SizedBox(width: 10),
              Expanded(child: _dateField('To date', _toDate, false)),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: FilledButton.icon(
                  onPressed: () {
                    if (_fromDate != null &&
                        _toDate != null &&
                        _fromDate!.isAfter(_toDate!)) {
                      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                          content: Text('From date must be before To date')));
                      return;
                    }
                    setState(() {
                      _appliedFrom = _fromDate;
                      _appliedTo = _toDate;
                    });
                  },
                  style: FilledButton.styleFrom(
                    backgroundColor: _webNavy,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                  icon: const Icon(Icons.filter_alt_outlined, size: 16),
                  label: const Text('Apply', style: TextStyle(fontWeight: FontWeight.w600)),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () => setState(() {
                    _fromDate = null;
                    _toDate = null;
                    _appliedFrom = null;
                    _appliedTo = null;
                  }),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: _textMain,
                    backgroundColor: _cardBg,
                    side: BorderSide(color: _dark ? _border : const Color(0xFFCBD5E1)),
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                  icon: const Icon(Icons.refresh_rounded, size: 16),
                  label: const Text('Reset', style: TextStyle(fontWeight: FontWeight.w600)),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildSectionHeader() {
    return Row(
      children: [
        Expanded(
          child: Text(
            'Daily Updates',
            style: TextStyle(
              color: _dark ? _textMain : _webNavy,
              fontSize: 18,
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
        PopupMenuButton<bool>(
          tooltip: 'Sort',
          color: _cardBg,
          onSelected: (v) => setState(() => _latestFirst = v),
          itemBuilder: (_) => const [
            PopupMenuItem(value: true, child: Text('Latest first')),
            PopupMenuItem(value: false, child: Text('Oldest first')),
          ],
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 4),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.sort_rounded, size: 18, color: _textMain),
                const SizedBox(width: 8),
                Text(
                  _latestFirst ? 'Latest first' : 'Oldest first',
                  style: TextStyle(
                      color: _textMain, fontSize: 13, fontWeight: FontWeight.w500),
                ),
                const SizedBox(width: 6),
                Icon(Icons.keyboard_arrow_down_rounded, size: 18, color: _textMain),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildInlineEmpty() {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 36, horizontal: 16),
      decoration: BoxDecoration(
        color: _cardBg,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFCBD5E1)),
      ),
      child: Column(
        children: [
          const Icon(Icons.event_busy_outlined, color: Color(0xFF94A3B8), size: 34),
          const SizedBox(height: 8),
          Text('No DLR/DPR updates yet',
              style: TextStyle(color: _textMain, fontWeight: FontWeight.w600)),
          const SizedBox(height: 4),
          Text('No updates in the selected date range.',
              style: TextStyle(color: _textSub, fontSize: 13)),
        ],
      ),
    );
  }

  Widget _pill(String text, Color bg, Color fg) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: _dark ? fg.withValues(alpha: 0.18) : bg,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(text,
          style: TextStyle(
              color: _dark ? bg : fg, fontSize: 11.5, fontWeight: FontWeight.w600)),
    );
  }

  Widget _sectionTitle(IconData icon, String text) => Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Row(
          children: [
            Icon(icon, size: 15, color: _textSub),
            const SizedBox(width: 8),
            Flexible(
              child: Text(
                text,
                style: TextStyle(
                  color: _textSub,
                  fontSize: 10.5,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.5,
                ),
              ),
            ),
          ],
        ),
      );

  // No IntrinsicHeight here: the day card contains a LayoutBuilder (photo grid),
  // which cannot report intrinsic sizes and made the whole list fail to lay out.
  Widget _buildTimelineItem(DprDayGroup group, {required bool isLast}) {
    return Stack(
      children: [
        Positioned(
          left: 7,
          top: 0,
          bottom: 0,
          child: Container(width: 2, color: _border),
        ),
        Positioned(
          left: 3,
          top: 22,
          child: Container(
            width: 10,
            height: 10,
            decoration: const BoxDecoration(
              color: _blue,
              shape: BoxShape.circle,
            ),
          ),
        ),
        Padding(
          padding: EdgeInsets.only(left: 24, bottom: isLast ? 0 : 14),
          child: _buildDayCard(group),
        ),
      ],
    );
  }

  Widget _buildDayCard(DprDayGroup group) {
    var updateCount = 0;
    final deletable = <Map<String, dynamic>>[];
    for (final u in group.updates) {
      updateCount += (u['ids'] as List).length;
      deletable.add(u);
    }
    final photoCount = group.images.length;
    final submitted = group.submittedAt;
    return Container(
      decoration: _cardDecoration(),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 4, 10),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 34,
                  height: 34,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: _dark
                        ? _blue.withValues(alpha: 0.18)
                        : const Color(0xFFEFF6FF),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(Icons.calendar_month_outlined,
                      size: 18, color: _blue),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _fmtDay(group.day, group.date),
                        style: TextStyle(
                          color: _dark ? _textMain : _webNavy,
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      if (submitted != null)
                        Text(_fmtTime(submitted),
                            style: TextStyle(color: _textSub, fontSize: 12)),
                      const SizedBox(height: 6),
                      Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        children: [
                          _pill('$updateCount update${updateCount == 1 ? '' : 's'}',
                              const Color(0xFFE0E7FF), const Color(0xFF3730A3)),
                          _pill('$photoCount photo${photoCount == 1 ? '' : 's'}',
                              const Color(0xFFDCFCE7), const Color(0xFF166534)),
                        ],
                      ),
                    ],
                  ),
                ),
                if (_canDeleteUpdate)
                  PopupMenuButton<int>(
                    tooltip: 'More',
                    color: _cardBg,
                    icon: Icon(Icons.more_vert_rounded, size: 20, color: _textMain),
                    onSelected: (i) =>
                        _confirmDelete(List<dynamic>.from(deletable[i]['ids'] as List)),
                    itemBuilder: (_) => [
                      for (var i = 0; i < deletable.length; i++)
                        PopupMenuItem(
                          value: i,
                          child: Text(
                            deletable.length == 1
                                ? 'Delete update'
                                : 'Delete: ${deletable[i]['title']}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(color: Color(0xFFDC2626)),
                          ),
                        ),
                    ],
                  ),
              ],
            ),
          ),
          Divider(height: 1, thickness: 1, color: _border),
          LayoutBuilder(builder: (context, c) {
            final left = Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (final update in group.updates) _buildUpdateBlock(update),
              ],
            );
            if (group.images.isEmpty) {
              return Padding(padding: const EdgeInsets.all(12), child: left);
            }
            final right = _buildImagesSection(group.images);
            if (c.maxWidth >= 600) {
              return Padding(
                padding: const EdgeInsets.all(12),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(child: left),
                    Container(
                      width: 1,
                      height: 200,
                      margin: const EdgeInsets.symmetric(horizontal: 12),
                      color: _border,
                    ),
                    Expanded(child: right),
                  ],
                ),
              );
            }
            return Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  left,
                  const SizedBox(height: 4),
                  Divider(height: 16, color: _border),
                  right,
                ],
              ),
            );
          }),
        ],
      ),
    );
  }

  Widget _buildUpdateBlock(Map<String, dynamic> update) {
    final title = update['title']?.toString().trim() ?? '';
    final updatedAt = update['updatedAt'] is DateTime ? update['updatedAt'] as DateTime : null;
    final tradesmen = (update['tradesmen'] as List?)
            ?.whereType<MapEntry<String, String>>()
            .toList() ??
        const <MapEntry<String, String>>[];
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _sectionTitle(Icons.description_outlined, 'WHAT WAS UPDATED'),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: _softBox,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              title,
              style: TextStyle(color: _textMain, fontSize: 13.5, height: 1.45),
            ),
          ),
          if (tradesmen.isNotEmpty) ...[
            const SizedBox(height: 12),
            _sectionTitle(Icons.groups_outlined, 'LABOUR / TRADESMEN'),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final t in tradesmen)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                      color: _dark
                          ? _blue.withValues(alpha: 0.18)
                          : const Color(0xFFEFF6FF),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.engineering_outlined,
                            size: 15,
                            color: _dark ? const Color(0xFF93C5FD) : const Color(0xFF1D4ED8)),
                        const SizedBox(width: 6),
                        Text('${t.key}: ${t.value}',
                            style: TextStyle(
                                color: _dark
                                    ? const Color(0xFF93C5FD)
                                    : const Color(0xFF1D4ED8),
                                fontSize: 12.5,
                                fontWeight: FontWeight.w500)),
                      ],
                    ),
                  ),
              ],
            ),
          ],
          if (updatedAt != null) ...[
            const SizedBox(height: 12),
            Row(
              children: [
                Icon(Icons.access_time_rounded, size: 15, color: _textSub),
                const SizedBox(width: 8),
                Text(
                  'Submitted ${DateFormat('d MMM yyyy, hh:mm a').format(updatedAt)}',
                  style: TextStyle(color: _textSub, fontSize: 12),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildImagesSection(List<String> images) {
    final shown = images.length > 4 ? images.sublist(0, 4) : images;
    final extra = images.length - shown.length;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: _sectionTitle(
                  Icons.image_outlined, 'DLR / DPR IMAGES (${images.length})'),
            ),
            InkWell(
              onTap: () => _openImage(images, 0),
              child: Padding(
                padding: const EdgeInsets.only(bottom: 6, left: 8),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text('View gallery',
                        style: TextStyle(
                            color: _textMain,
                            fontSize: 12.5,
                            fontWeight: FontWeight.w500)),
                    const SizedBox(width: 4),
                    Icon(Icons.chevron_right_rounded, size: 18, color: _textMain),
                  ],
                ),
              ),
            ),
          ],
        ),
        GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          padding: EdgeInsets.zero,
          itemCount: shown.length,
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 2,
            crossAxisSpacing: 8,
            mainAxisSpacing: 8,
            childAspectRatio: 4 / 3.3,
          ),
          itemBuilder: (_, i) {
            return GestureDetector(
              onTap: () => _openImage(images, i),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    CachedNetworkImage(
                      imageUrl: shown[i],
                      fit: BoxFit.cover,
                      placeholder: (_, __) => Container(color: _line),
                      errorWidget: (_, __, ___) => Container(
                        color: _softBox,
                        alignment: Alignment.center,
                        child: const Icon(Icons.broken_image_outlined,
                            color: _mutedGrey, size: 22),
                      ),
                    ),
                    if (extra > 0 && i == shown.length - 1)
                      Container(
                        color: Colors.black.withValues(alpha: 0.5),
                        alignment: Alignment.center,
                        child: Text('+$extra',
                            style: const TextStyle(
                                color: Colors.white,
                                fontSize: 20,
                                fontWeight: FontWeight.w800)),
                      ),
                  ],
                ),
              ),
            );
          },
        ),
      ],
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
