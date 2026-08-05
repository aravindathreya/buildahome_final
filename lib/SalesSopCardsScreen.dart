import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

import 'app_theme.dart';
import 'services/data_provider.dart';
import 'widgets/skeleton_loader.dart';

/// Known sales SOP card keys from Mobile Dashboard Project Details APIs.
/// Non-clients get every card; clients keep only shared cards (not nonClientOnly).
const Map<String, _CardMeta> _knownCards = {
  'client_information': _CardMeta(
    label: 'Client Info',
    icon: Icons.person_outline_rounded,
  ),
  'pending_tasks': _CardMeta(
    label: 'Pending Tasks',
    icon: Icons.pending_actions_outlined,
    nonClientOnly: true,
  ),
  'project_details': _CardMeta(
    label: 'Project Details',
    icon: Icons.home_work_outlined,
    nonClientOnly: true,
  ),
  'stages_status': _CardMeta(
    label: 'Stages',
    icon: Icons.account_tree_outlined,
    nonClientOnly: true,
  ),
  'bills_10_percent': _CardMeta(
    label: '10% & Bills',
    icon: Icons.receipt_long_outlined,
    nonClientOnly: true,
  ),
  'documents': _CardMeta(
    label: 'Documents',
    icon: Icons.description_outlined,
    nonClientOnly: true,
  ),
  'planning_commercial_documents': _CardMeta(
    label: 'Planning Docs',
    icon: Icons.folder_special_outlined,
    nonClientOnly: true,
  ),
  'architectural_site_documents': _CardMeta(
    label: 'Site Docs',
    icon: Icons.architecture_outlined,
    nonClientOnly: true,
  ),
  'client_kyc': _CardMeta(
    label: 'Client KYC',
    icon: Icons.badge_outlined,
    nonClientOnly: true,
  ),
  'assign_architects': _CardMeta(
    label: 'Architects',
    icon: Icons.groups_outlined,
    nonClientOnly: true,
  ),
  'doc_difference_of_cost': _CardMeta(
    label: 'DOC',
    icon: Icons.compare_arrows_outlined,
    nonClientOnly: true,
  ),
  'nt_list': _CardMeta(
    label: 'NT List',
    icon: Icons.playlist_add_check_outlined,
    nonClientOnly: true,
  ),
  'site_inspection': _CardMeta(
    label: 'Site Inspection',
    icon: Icons.fact_check_outlined,
    nonClientOnly: true,
  ),
  'client_kyc_documents': _CardMeta(
    label: 'KYC Docs',
    icon: Icons.folder_shared_outlined,
    nonClientOnly: true,
  ),
  'gfc_drawings': _CardMeta(
    label: 'GFC Drawings',
    icon: Icons.draw_outlined,
    nonClientOnly: true,
  ),
  'gallery': _CardMeta(
    label: 'Gallery',
    icon: Icons.photo_library_outlined,
    nonClientOnly: true,
  ),
  'initial_discussion': _CardMeta(
    label: 'Initial Discussion',
    icon: Icons.forum_outlined,
    nonClientOnly: true,
  ),
};

class _CardMeta {
  final String label;
  final IconData icon;
  final bool nonClientOnly;

  const _CardMeta({
    required this.label,
    required this.icon,
    this.nonClientOnly = false,
  });
}

class SalesSopCardsScreen extends StatefulWidget {
  /// Optional initial card to open. Defaults to client_information.
  final String initialCardKey;

  /// When true, cards marked nonClientOnly are hidden.
  final bool isClient;

  const SalesSopCardsScreen({
    super.key,
    this.initialCardKey = 'client_information',
    this.isClient = false,
  });

  @override
  State<SalesSopCardsScreen> createState() => _SalesSopCardsScreenState();
}

class _SalesSopCardsScreenState extends State<SalesSopCardsScreen>
    with SingleTickerProviderStateMixin {
  TabController? _tabController;
  List<String> _cardKeys = const ['client_information'];
  late bool _isClient = widget.isClient;

  final Map<String, Map<String, dynamic>?> _cardPayloads = {};
  final Map<String, String?> _cardErrors = {};
  final Set<String> _loadingKeys = {};

  @override
  void initState() {
    super.initState();
    _bootstrap();
  }

  Future<void> _bootstrap() async {
    if (!widget.isClient) {
      // Prefer role from prefs when caller didn't mark client explicitly.
      final prefs = await SharedPreferences.getInstance();
      final role = (prefs.getString('role') ?? '').trim().toLowerCase();
      _isClient = role == 'client';
    } else {
      _isClient = true;
    }

    // Non-clients: seed every known Project Details card so all APIs are wired.
    // Clients: keep the shared card(s) only.
    final seedKeys = !_isClient
        ? _knownCards.keys.toList()
        : <String>[widget.initialCardKey];

    if (!mounted) return;
    _ensureTabs(seedKeys);
    setState(() {});
    final initialKey = _filterCardKeys([widget.initialCardKey]).isNotEmpty
        ? widget.initialCardKey
        : (_cardKeys.isNotEmpty ? _cardKeys.first : 'client_information');
    _loadCard(initialKey);
  }

  @override
  void dispose() {
    _tabController?.dispose();
    super.dispose();
  }

  bool _isCardAllowed(String key) {
    final meta = _knownCards[key];
    if (meta?.nonClientOnly == true && _isClient) return false;
    return true;
  }

  List<String> _filterCardKeys(List<String> keys) {
    return keys
        .map((k) => k.trim())
        .where((k) => k.isNotEmpty && _isCardAllowed(k))
        .toList();
  }

  void _ensureTabs(List<String> keys) {
    final next = _filterCardKeys(keys);
    if (next.isEmpty) {
      final fallback = _filterCardKeys([widget.initialCardKey]);
      next.addAll(fallback.isNotEmpty ? fallback : ['client_information']);
    }

    // Keep known cards first, then any extras from the API.
    final ordered = <String>[];
    for (final known in _knownCards.keys) {
      if (next.contains(known) && _isCardAllowed(known)) ordered.add(known);
    }
    for (final key in next) {
      if (!ordered.contains(key) && _isCardAllowed(key)) ordered.add(key);
    }

    final same = ordered.length == _cardKeys.length &&
        List.generate(ordered.length, (i) => ordered[i] == _cardKeys[i])
            .every((v) => v);
    if (same && _tabController != null) return;

    final previousKey = _tabController != null
        ? _cardKeys[_tabController!.index.clamp(0, _cardKeys.length - 1)]
        : widget.initialCardKey;

    _tabController?.removeListener(_onTabChanged);
    _tabController?.dispose();

    _cardKeys = ordered;
    final initialIndex = _cardKeys.indexOf(previousKey);
    _tabController = TabController(
      length: _cardKeys.length,
      vsync: this,
      initialIndex: initialIndex >= 0 ? initialIndex : 0,
    );
    _tabController!.addListener(_onTabChanged);
  }

  void _onTabChanged() {
    if (_tabController == null || _tabController!.indexIsChanging) return;
    final key = _cardKeys[_tabController!.index];
    if (!_cardPayloads.containsKey(key) && !_loadingKeys.contains(key)) {
      _loadCard(key);
    }
  }

  String _labelFor(String key) {
    return _knownCards[key]?.label ??
        key
            .split('_')
            .map((part) => part.isEmpty
                ? part
                : '${part[0].toUpperCase()}${part.substring(1)}')
            .join(' ');
  }

  IconData _iconFor(String key) {
    return _knownCards[key]?.icon ?? Icons.folder_outlined;
  }

  Future<void> _loadCard(String cardKey, {bool force = false}) async {
    if (!force &&
        (_loadingKeys.contains(cardKey) ||
            (_cardPayloads.containsKey(cardKey) &&
                _cardErrors[cardKey] == null))) {
      return;
    }

    setState(() {
      _loadingKeys.add(cardKey);
      _cardErrors[cardKey] = null;
    });

    try {
      final payload = await DataProvider().loadSalesSopCard(cardKey);
      if (!mounted) return;

      final available = payload['available_cards'];
      if (available is List) {
        final keys = available
            .map((e) => e?.toString().trim() ?? '')
            .where((e) => e.isNotEmpty)
            .toList();
        final allowed = _filterCardKeys(keys);
        // Only wire tabs for cards we explicitly support (known APIs).
        final supported = allowed
            .where((key) => _knownCards.containsKey(key))
            .toList();
        if (supported.isNotEmpty) {
          // Non-clients: keep the full Project Details card set so every
          // documented API remains reachable even if available_cards is partial.
          if (!_isClient) {
            final merged = <String>[
              ..._filterCardKeys(_knownCards.keys.toList()),
              ...supported.where((k) => !_knownCards.containsKey(k)),
            ];
            _ensureTabs(merged);
          } else {
            _ensureTabs(supported);
          }
        }
      }

      setState(() {
        _cardPayloads[cardKey] = payload;
        _cardErrors[cardKey] = null;
        _loadingKeys.remove(cardKey);
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _cardErrors[cardKey] =
            e.toString().replaceFirst('Exception: ', '');
        _loadingKeys.remove(cardKey);
      });
    }
  }

  Future<void> _refreshCurrent() async {
    if (_tabController == null) return;
    final key = _cardKeys[_tabController!.index];
    await _loadCard(key, force: true);
  }

  @override
  Widget build(BuildContext context) {
    final controller = _tabController;
    if (controller == null) {
      return Scaffold(
        backgroundColor: AppTheme.getBackgroundPrimary(context),
        appBar: AppBar(
          backgroundColor: AppTheme.getBackgroundSecondary(context),
          foregroundColor: AppTheme.navy,
          elevation: 0,
          title: const Text('Project Details'),
        ),
        body: const SkeletonListLoader(cardCount: 4),
      );
    }

    return Scaffold(
      backgroundColor: AppTheme.getBackgroundPrimary(context),
      appBar: AppBar(
        backgroundColor: AppTheme.getBackgroundSecondary(context),
        foregroundColor: AppTheme.navy,
        elevation: 0,
        title: const Text(
          'Project Details',
          style: TextStyle(
            color: AppTheme.navy,
            fontSize: 18,
            fontWeight: FontWeight.w800,
          ),
        ),
        actions: [
          IconButton(
            tooltip: 'Refresh',
            onPressed: _refreshCurrent,
            icon: const Icon(Icons.refresh_rounded, color: AppTheme.navy),
          ),
        ],
        bottom: _cardKeys.length > 1
            ? PreferredSize(
                preferredSize: const Size.fromHeight(56),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
                  child: Container(
                    height: 48,
                    padding: const EdgeInsets.all(4),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF1F4F8),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: TabBar(
                      controller: controller,
                      isScrollable: _cardKeys.length > 3,
                      indicatorSize: TabBarIndicatorSize.tab,
                      dividerColor: Colors.transparent,
                      splashFactory: NoSplash.splashFactory,
                      overlayColor:
                          WidgetStateProperty.all(Colors.transparent),
                      labelPadding: EdgeInsets.zero,
                      indicator: BoxDecoration(
                        color: AppTheme.navy,
                        borderRadius: BorderRadius.circular(11),
                      ),
                      labelColor: Colors.white,
                      unselectedLabelColor: AppTheme.mutedGrey,
                      labelStyle: const TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w700,
                      ),
                      unselectedLabelStyle: const TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w600,
                      ),
                      tabs: _cardKeys
                          .map(
                            (key) => SizedBox(
                              height: 40,
                              child: Center(
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 10),
                                  child: Text(
                                    _labelFor(key),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              ),
                            ),
                          )
                          .toList(),
                    ),
                  ),
                ),
              )
            : null,
      ),
      body: TabBarView(
        controller: controller,
        children: _cardKeys.map(_buildCardTab).toList(),
      ),
    );
  }

  Widget _buildCardTab(String cardKey) {
    final loading = _loadingKeys.contains(cardKey);
    final error = _cardErrors[cardKey];
    final payload = _cardPayloads[cardKey];

    if (loading && payload == null) {
      return const SkeletonListLoader(cardCount: 5);
    }

    if (error != null && payload == null) {
      return _ErrorState(
        message: error,
        onRetry: () => _loadCard(cardKey, force: true),
      );
    }

    if (payload == null) {
      return const SkeletonListLoader(cardCount: 5);
    }

    final card = payload['card'];
    final cardMap = card is Map
        ? Map<String, dynamic>.from(card)
        : <String, dynamic>{};
    final title = cardMap['title']?.toString() ?? _labelFor(cardKey);

    return RefreshIndicator(
      color: AppTheme.navy,
      onRefresh: () => _loadCard(cardKey, force: true),
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 28),
        children: [
          _CardHeader(
            icon: _iconFor(cardKey),
            title: title,
            salesSopId: payload['sales_sop_id']?.toString(),
            convertedProjectId: payload['converted_project_id']?.toString(),
          ),
          if (error != null) ...[
            const SizedBox(height: 12),
            _InlineError(message: error),
          ],
          const SizedBox(height: 14),
          if (cardMap.isEmpty)
            _EmptyCardNotice()
          else
            ..._buildCardFields(cardMap),
        ],
      ),
    );
  }

  List<Widget> _buildCardFields(Map<String, dynamic> card) {
    final widgets = <Widget>[];
    card.forEach((key, value) {
      if (key == 'title') return;
      widgets.addAll(_renderValue(key, value, depth: 0));
    });
    if (widgets.isEmpty) {
      widgets.add(_EmptyCardNotice());
    }
    return widgets;
  }

  List<Widget> _renderValue(String key, dynamic value, {required int depth}) {
    if (value == null) return const [];

    if (value is Map) {
      final map = Map<String, dynamic>.from(value);
      if (map.isEmpty) return const [];
      return [
        _SectionTitle(title: _prettyKey(key), depth: depth),
        ...map.entries.expand(
          (entry) =>
              _renderValue(entry.key, entry.value, depth: depth + 1),
        ),
      ];
    }

    if (value is List) {
      if (value.isEmpty) return const [];
      final items = <Widget>[
        _SectionTitle(title: _prettyKey(key), depth: depth),
      ];
      for (var i = 0; i < value.length; i++) {
        final item = value[i];
        if (item is Map) {
          items.add(
            _NestedGroup(
              title: '${_prettyKey(key)} ${i + 1}',
              children: Map<String, dynamic>.from(item)
                  .entries
                  .expand(
                    (entry) => _renderValue(
                      entry.key,
                      entry.value,
                      depth: depth + 1,
                    ),
                  )
                  .toList(),
            ),
          );
        } else {
          final text = item?.toString() ?? '';
          if (text.isEmpty || text == 'null') continue;
          items.add(
            _InfoRow(
              label: '${_prettyKey(key)} ${i + 1}',
              value: text,
              depth: depth,
            ),
          );
        }
      }
      return items;
    }

    final text = value.toString().trim();
    if (text.isEmpty || text == 'null') return const [];

    return [
      _InfoRow(
        label: _prettyKey(key),
        value: text,
        depth: depth,
        isLink: _looksLikeUrl(text),
      ),
    ];
  }

  String _prettyKey(String key) {
    return key
        .replaceAllMapped(RegExp(r'([a-z])([A-Z])'), (m) => '${m[1]} ${m[2]}')
        .split(RegExp(r'[_\s]+'))
        .where((part) => part.isNotEmpty)
        .map((part) => '${part[0].toUpperCase()}${part.substring(1)}')
        .join(' ');
  }

  bool _looksLikeUrl(String value) {
    final lower = value.toLowerCase();
    return lower.startsWith('http://') || lower.startsWith('https://');
  }
}

class _CardHeader extends StatelessWidget {
  final IconData icon;
  final String title;
  final String? salesSopId;
  final String? convertedProjectId;

  const _CardHeader({
    required this.icon,
    required this.title,
    this.salesSopId,
    this.convertedProjectId,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppTheme.border),
      ),
      child: Row(
        children: [
          Container(
            width: 46,
            height: 46,
            decoration: BoxDecoration(
              color: AppTheme.navy.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, color: AppTheme.navy, size: 24),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w800,
                    color: AppTheme.navy,
                  ),
                ),
                if (salesSopId != null || convertedProjectId != null) ...[
                  const SizedBox(height: 4),
                  Text(
                    [
                      if (salesSopId != null) 'SOP #$salesSopId',
                      if (convertedProjectId != null)
                        'Project #$convertedProjectId',
                    ].join('  ·  '),
                    style: const TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w600,
                      color: AppTheme.mutedGrey,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  final String title;
  final int depth;

  const _SectionTitle({required this.title, required this.depth});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(depth * 8.0, 10, 0, 8),
      child: Text(
        title,
        style: TextStyle(
          fontSize: depth == 0 ? 14.5 : 13.5,
          fontWeight: FontWeight.w800,
          color: AppTheme.navy.withValues(alpha: 0.9),
        ),
      ),
    );
  }
}

class _NestedGroup extends StatelessWidget {
  final String title;
  final List<Widget> children;

  const _NestedGroup({required this.title, required this.children});

  @override
  Widget build(BuildContext context) {
    if (children.isEmpty) return const SizedBox.shrink();
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppTheme.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(
              fontSize: 13.5,
              fontWeight: FontWeight.w800,
              color: AppTheme.navy,
            ),
          ),
          const SizedBox(height: 8),
          ...children,
        ],
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  final String label;
  final String value;
  final int depth;
  final bool isLink;

  const _InfoRow({
    required this.label,
    required this.value,
    this.depth = 0,
    this.isLink = false,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: EdgeInsets.only(left: depth * 8.0, bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.border),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: AppTheme.mutedGrey,
                  ),
                ),
                const SizedBox(height: 4),
                isLink
                    ? GestureDetector(
                        onTap: () async {
                          final uri = Uri.tryParse(value);
                          if (uri != null && await canLaunchUrl(uri)) {
                            await launchUrl(
                              uri,
                              mode: LaunchMode.externalApplication,
                            );
                          }
                        },
                        child: Text(
                          value,
                          style: const TextStyle(
                            fontSize: 14.5,
                            fontWeight: FontWeight.w700,
                            color: AppTheme.accentBlue,
                            decoration: TextDecoration.underline,
                          ),
                        ),
                      )
                    : Text(
                        value,
                        style: const TextStyle(
                          fontSize: 14.5,
                          fontWeight: FontWeight.w700,
                          color: AppTheme.navy,
                        ),
                      ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _EmptyCardNotice extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppTheme.border),
      ),
      child: const Text(
        'No details available for this card yet.',
        style: TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.w600,
          color: AppTheme.mutedGrey,
        ),
      ),
    );
  }
}

class _InlineError extends StatelessWidget {
  final String message;

  const _InlineError({required this.message});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF1F2),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFFECACA)),
      ),
      child: Text(
        message,
        style: const TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w600,
          color: Color(0xFFB91C1C),
        ),
      ),
    );
  }
}

class _ErrorState extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;

  const _ErrorState({required this.message, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.error_outline_rounded,
              size: 42,
              color: AppTheme.navy.withValues(alpha: 0.45),
            ),
            const SizedBox(height: 12),
            Text(
              message,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: AppTheme.mutedGrey,
              ),
            ),
            const SizedBox(height: 16),
            TextButton.icon(
              onPressed: onRetry,
              style: TextButton.styleFrom(
                backgroundColor: AppTheme.navy,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(
                  horizontal: 18,
                  vertical: 12,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              icon: const Icon(Icons.refresh_rounded, size: 18),
              label: const Text(
                'Retry',
                style: TextStyle(fontWeight: FontWeight.w700),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
