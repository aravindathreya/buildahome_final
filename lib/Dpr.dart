import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import 'app_theme.dart';
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
  static const Color _cardBorder = AppTheme.border;

  var entries;
  var listOfDates = [];
  var listOfUpdates = [];
  var updateDates = [];
  var updateIds = [];
  bool _isLoading = true;
  String? _error;

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
          updateDates = [];
          updateIds = [];
          entries = [];
          _isLoading = false;
          _error = 'No project selected';
        });
        return;
      }

      var url = 'https://office.buildahome.in/API/view_all_dpr?id=$id';
      var response =
          await http.get(Uri.parse(url)).timeout(const Duration(seconds: 20));

      if (!mounted) return;

      if (response.statusCode != 200) {
        setState(() {
          _isLoading = false;
          _error = 'Could not load updates';
        });
        return;
      }

      final decoded = jsonDecode(response.body);
      final nextDates = [];
      final nextUpdates = [];
      final nextUpdateDates = [];
      final nextUpdateIds = [];

      if (decoded is List) {
        for (int i = 0; i < decoded.length; i++) {
          final item = decoded[i];
          if (item is! Map) continue;
          final date = item['date']?.toString() ?? '';
          final title = item['update_title']?.toString() ?? '';
          final updateId = item['id'];

          if (date.isNotEmpty && !nextDates.contains(date)) {
            nextDates.add(date);
          }
          if (title.isNotEmpty && !nextUpdates.contains(title)) {
            nextUpdates.add(title);
            nextUpdateDates.add(date);
            nextUpdateIds.add(updateId);
          }
        }
      }

      setState(() {
        entries = decoded;
        listOfDates = nextDates;
        listOfUpdates = nextUpdates;
        updateDates = nextUpdateDates;
        updateIds = nextUpdateIds;
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
    call();
  }

  Future<void> _confirmDelete(dynamic updateId) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text(
          'Delete update?',
          style: TextStyle(
            color: _navy,
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
      var url = 'https://office.buildahome.in/API/delete_update?id=$updateId';
      await http.get(Uri.parse(url)).timeout(const Duration(seconds: 15));
      await call(showLoader: false);
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Failed to delete update')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final body = _buildBody();
    if (widget.embedded) return body;

    return ThemedScaffold(
      title: widget.title,
      backgroundColor: const Color(0xFFF7F8FB),
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
          final updatesForDate = <Map<String, dynamic>>[];
          for (int x = 0; x < updateIds.length; x++) {
            if (updateDates[x] == listOfDates[index]) {
              updatesForDate.add({
                'title': listOfUpdates[x],
                'id': updateIds[x],
              });
            }
          }

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
          padding: EdgeInsets.only(top: isFirst ? 4 : 20, bottom: 10),
          child: Row(
            children: [
              Container(
                width: 28,
                height: 28,
                decoration: BoxDecoration(
                  color: const Color(0xFFEEF2F7),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(
                  Icons.calendar_today_rounded,
                  size: 14,
                  color: _navy,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  date.trim().isEmpty ? 'Undated' : date,
                  style: const TextStyle(
                    color: _navy,
                    fontSize: 14.5,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.1,
                  ),
                ),
              ),
            ],
          ),
        ),
        ...updates.map((update) => _buildUpdateCard(update)),
      ],
    );
  }

  Widget _buildUpdateCard(Map<String, dynamic> update) {
    final title = update['title']?.toString() ?? '';
    final id = update['id'];

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.fromLTRB(14, 14, 10, 14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _cardBorder),
        boxShadow: const [
          BoxShadow(
            color: AppTheme.softShadow,
            blurRadius: 12,
            offset: Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: const Color(0xFFDBEAFE),
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(
              Icons.campaign_rounded,
              size: 18,
              color: Color(0xFF2563EB),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              title,
              style: const TextStyle(
                color: _navy,
                fontSize: 14.5,
                fontWeight: FontWeight.w600,
                height: 1.35,
              ),
            ),
          ),
          const SizedBox(width: 4),
          IconButton(
            onPressed: () => _confirmDelete(id),
            tooltip: 'Delete',
            visualDensity: VisualDensity.compact,
            icon: const Icon(
              Icons.delete_outline_rounded,
              color: Color(0xFFDC2626),
              size: 20,
            ),
          ),
        ],
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
              color: const Color(0xFFEEF2F7),
              borderRadius: BorderRadius.circular(24),
            ),
            child: Icon(icon, size: 36, color: _mutedGrey),
          ),
        ),
        const SizedBox(height: 20),
        Text(
          title,
          textAlign: TextAlign.center,
          style: const TextStyle(
            color: _navy,
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
      ],
    );
  }
}
