import 'package:flutter/material.dart';

import 'app_theme.dart';

const int kIndentListPageSize = 15;

bool indentTruthy(dynamic value) {
  if (value == true) return true;
  if (value is num) return value != 0;
  if (value is String) {
    final normalized = value.trim().toLowerCase();
    return normalized == 'true' || normalized == '1' || normalized == 'yes';
  }
  return false;
}

String indentProjectIdOf(dynamic indent) {
  if (indent is! Map) return '';
  for (final key in ['project_id', 'projectId', 'pr_id']) {
    final value = indent[key]?.toString().trim() ?? '';
    if (value.isNotEmpty && value != 'null') return value;
  }
  return '';
}

String indentProjectNameOf(dynamic indent) {
  if (indent is! Map) return '';
  for (final key in ['project_name', 'project', 'client_name']) {
    final value = indent[key]?.toString().trim() ?? '';
    if (value.isNotEmpty && value != 'null') return value;
  }
  return '';
}

bool indentMatchesProject(
  dynamic indent, {
  String? projectId,
  String? projectSearch,
}) {
  final lockedId = projectId?.trim() ?? '';
  if (lockedId.isNotEmpty) {
    return indentProjectIdOf(indent) == lockedId;
  }
  final query = projectSearch?.trim().toLowerCase() ?? '';
  if (query.isEmpty) return true;
  return indentProjectNameOf(indent).toLowerCase().contains(query);
}

class IndentListPageResult {
  final List items;
  final bool serverPaged;
  final bool hasMore;

  const IndentListPageResult({
    required this.items,
    required this.serverPaged,
    required this.hasMore,
  });
}

IndentListPageResult parseIndentListResponse(dynamic decoded) {
  if (decoded is Map) {
    List? list;
    for (final key in const [
      'items',
      'indents',
      'data',
      'proofs',
      'results',
    ]) {
      if (decoded[key] is List) {
        list = List.from(decoded[key] as List);
        break;
      }
    }
    if (list != null &&
        (decoded.containsKey('has_more') || decoded.containsKey('hasMore'))) {
      return IndentListPageResult(
        items: list,
        serverPaged: true,
        hasMore: indentTruthy(decoded['has_more'] ?? decoded['hasMore']),
      );
    }
    if (list != null) {
      return IndentListPageResult(
        items: list,
        serverPaged: false,
        hasMore: false,
      );
    }
  }
  if (decoded is List) {
    return IndentListPageResult(
      items: List.from(decoded),
      serverPaged: false,
      hasMore: false,
    );
  }
  return const IndentListPageResult(
    items: [],
    serverPaged: false,
    hasMore: false,
  );
}

class IndentPagedListController {
  List all = [];
  List visible = [];
  String search = '';
  String? lockedProjectId;
  bool serverPaged = false;
  bool hasMore = false;
  bool loadingMore = false;
  int offset = 0;
  int _visibleCount = kIndentListPageSize;

  bool get isLocked => (lockedProjectId ?? '').trim().isNotEmpty;

  int get filteredCount => _filtered().length;

  List _filtered() {
    return all
        .where((item) => indentMatchesProject(
              item,
              projectId: isLocked ? lockedProjectId : null,
              projectSearch: isLocked ? null : search,
            ))
        .toList();
  }

  void reset() {
    all = [];
    visible = [];
    offset = 0;
    _visibleCount = kIndentListPageSize;
    serverPaged = false;
    hasMore = false;
    loadingMore = false;
  }

  void acceptPage(IndentListPageResult page, {required bool reset}) {
    if (reset) {
      all = [];
      offset = 0;
      _visibleCount = kIndentListPageSize;
      serverPaged = page.serverPaged;
    } else if (page.serverPaged) {
      serverPaged = true;
    }

    if (serverPaged) {
      all = [...all, ...page.items];
      offset = all.length;
      hasMore = page.hasMore;
    } else {
      all = page.items;
    }
    rebuildVisible(resetClientPage: reset && !serverPaged);
  }

  void rebuildVisible({bool resetClientPage = false}) {
    final filtered = _filtered();
    if (serverPaged) {
      visible = filtered;
      return;
    }
    if (resetClientPage) {
      _visibleCount = kIndentListPageSize;
    }
    if (_visibleCount > filtered.length) {
      _visibleCount = filtered.length;
    }
    visible = filtered.take(_visibleCount).toList();
    hasMore = _visibleCount < filtered.length;
  }

  void showMoreClient() {
    if (serverPaged || !hasMore) return;
    final filtered = _filtered();
    _visibleCount =
        (_visibleCount + kIndentListPageSize).clamp(0, filtered.length).toInt();
    visible = filtered.take(_visibleCount).toList();
    hasMore = _visibleCount < filtered.length;
  }

  void removeById(dynamic id) {
    final idStr = id?.toString();
    all.removeWhere((item) => item is Map && item['id']?.toString() == idStr);
    rebuildVisible();
  }
}

class IndentProjectListHeader extends StatelessWidget {
  final String title;
  final int count;
  final String? lockedProjectName;
  final TextEditingController? searchController;
  final ValueChanged<String>? onSearchChanged;
  final VoidCallback? onSearchCleared;

  const IndentProjectListHeader({
    super.key,
    required this.title,
    required this.count,
    this.lockedProjectName,
    this.searchController,
    this.onSearchChanged,
    this.onSearchCleared,
  });

  bool get _showSearch {
    final locked = lockedProjectName?.trim() ?? '';
    return locked.isEmpty && searchController != null;
  }

  @override
  Widget build(BuildContext context) {
    final lockedName = lockedProjectName?.trim() ?? '';
    return Padding(
      padding: const EdgeInsets.fromLTRB(15, 12, 15, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '$title ($count)',
            style: TextStyle(
              color: AppTheme.getTextPrimary(context),
              fontSize: 20,
              fontWeight: FontWeight.w600,
            ),
          ),
          if (lockedName.isNotEmpty) ...[
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: const Color(0xFFEEF2FF),
                borderRadius: BorderRadius.circular(999),
                border: Border.all(color: const Color(0xFFC7D2FE)),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(
                    Icons.folder_outlined,
                    size: 14,
                    color: Color(0xFF4338CA),
                  ),
                  const SizedBox(width: 6),
                  Flexible(
                    child: Text(
                      lockedName,
                      style: const TextStyle(
                        color: Color(0xFF4338CA),
                        fontSize: 12.5,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
          if (_showSearch) ...[
            const SizedBox(height: 12),
            TextField(
              controller: searchController,
              onChanged: onSearchChanged,
              decoration: InputDecoration(
                hintText: 'Search by project',
                hintStyle: TextStyle(
                  color: AppTheme.getTextSecondary(context),
                  fontSize: 14,
                ),
                prefixIcon: Icon(
                  Icons.search_rounded,
                  color: AppTheme.getTextSecondary(context),
                  size: 22,
                ),
                suffixIcon: (searchController?.text.isNotEmpty ?? false)
                    ? IconButton(
                        icon: const Icon(Icons.close_rounded, size: 20),
                        onPressed: onSearchCleared,
                      )
                    : null,
                filled: true,
                fillColor: Theme.of(context).colorScheme.surface,
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 12,
                ),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: BorderSide(
                    color: AppTheme.getPrimaryColor(context).withValues(alpha: 0.2),
                  ),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: BorderSide(
                    color: AppTheme.getPrimaryColor(context).withValues(alpha: 0.2),
                  ),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: BorderSide(
                    color: AppTheme.getPrimaryColor(context),
                    width: 1.4,
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class IndentListLoadMoreTile extends StatelessWidget {
  const IndentListLoadMoreTile({super.key});

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.symmetric(vertical: 18),
      child: Center(
        child: SizedBox(
          width: 22,
          height: 22,
          child: CircularProgressIndicator(strokeWidth: 2.4),
        ),
      ),
    );
  }
}
