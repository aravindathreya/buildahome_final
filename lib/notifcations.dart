import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

import 'MyTasksScreen.dart';
import 'SlotsScreen.dart';
import 'SiteVisitReports.dart';
import 'app_theme.dart';
import 'approved_pos_screen.dart';
import 'indents_screen.dart';
import 'services/data_provider.dart';
import 'services/notification_service.dart';
import 'widgets/themed_scaffold.dart';
import 'widgets/skeleton_loader.dart';

const int kNotificationPageSize = 20;

class Notifications extends StatelessWidget {
  const Notifications({super.key});

  @override
  Widget build(BuildContext context) {
    return ThemedScaffold(
      title: 'Notifications',
      backgroundColor: const Color(0xFFF7F8FB),
      body: const SafeArea(child: NotificationPageBody()),
    );
  }
}

class NotificationPageBody extends StatefulWidget {
  const NotificationPageBody({super.key});

  @override
  NotificationPageBodyState createState() => NotificationPageBodyState();
}

class NotificationPageBodyState extends State<NotificationPageBody> {
  static const Color _navy = AppTheme.navy;
  static const Color _mutedGrey = AppTheme.mutedGrey;
  static const Color _cardBorder = AppTheme.border;

  final NotificationService _service = NotificationService.instance;
  final ScrollController _scrollController = ScrollController();

  bool _bootstrapping = true;
  bool _opening = false;
  int _visibleCount = kNotificationPageSize;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
    _bootstrap();
  }

  @override
  void dispose() {
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _bootstrap() async {
    await _service.ensureHydrated();
    if (mounted) setState(() {});
    await _service.markAllAsRead();
    if (mounted) {
      setState(() => _bootstrapping = false);
    }
  }

  Future<void> _handleRefresh() async {
    setState(() => _visibleCount = kNotificationPageSize);
    await _service.markAllAsRead();
  }

  void _onScroll() {
    if (!_scrollController.hasClients) return;
    if (_scrollController.position.pixels >=
        _scrollController.position.maxScrollExtent - 240) {
      _showMore();
    }
  }

  void _showMore() {
    final total = _sortedNotifications(_service.notifications).length;
    if (_visibleCount >= total) return;
    setState(() {
      _visibleCount =
          (_visibleCount + kNotificationPageSize).clamp(0, total).toInt();
    });
  }

  List<Map<String, dynamic>> _sortedNotifications(
    List<Map<String, dynamic>> notifications,
  ) {
    final dated = notifications.map((notification) {
      return MapEntry(_parseNotificationDate(notification), notification);
    }).toList()
      ..sort((a, b) {
        final aDate = a.key ?? DateTime.fromMillisecondsSinceEpoch(0);
        final bDate = b.key ?? DateTime.fromMillisecondsSinceEpoch(0);
        return bDate.compareTo(aDate);
      });
    return dated.map((e) => e.value).toList();
  }

  DateTime? _parseNotificationDate(dynamic notification) {
    if (notification is! Map) return null;
    final candidates = [
      notification['created_at'],
      notification['createdAt'],
      notification['date'],
      notification['datetime'],
      notification['time'],
      notification['timestamp'],
    ];

    for (final raw in candidates) {
      if (raw == null) continue;
      final parsed = _tryParseDate(raw.toString());
      if (parsed != null) return parsed;
    }
    return null;
  }

  DateTime? _tryParseDate(String raw) {
    final value = raw.trim();
    if (value.isEmpty) return null;

    if (value == '0' ||
        value.toLowerCase() == 'just now' ||
        value.toLowerCase() == 'now') {
      return DateTime.now();
    }

    final asInt = int.tryParse(value);
    if (asInt != null) {
      if (asInt > 1000000000000) {
        return DateTime.fromMillisecondsSinceEpoch(asInt);
      }
      if (asInt > 1000000000) {
        return DateTime.fromMillisecondsSinceEpoch(asInt * 1000);
      }
    }

    final asDouble = double.tryParse(value);
    if (asDouble != null && asDouble > 1000000000) {
      return DateTime.fromMillisecondsSinceEpoch((asDouble * 1000).round());
    }

    try {
      return DateTime.parse(value).toLocal();
    } catch (_) {}

    for (final pattern in [
      'yyyy-MM-dd HH:mm:ss',
      'dd-MM-yyyy HH:mm:ss',
      'dd/MM/yyyy HH:mm:ss',
      'yyyy-MM-dd',
      'dd MMM yyyy',
      'd MMM yyyy',
      'EEEE d MMMM HH:mm',
      'EEEE dd MMMM H:m',
      'EEEE dd MMMM HH:mm',
    ]) {
      try {
        return DateFormat(pattern).parse(value).toLocal();
      } catch (_) {}
    }

    final lower = value.toLowerCase();
    final now = DateTime.now();

    final minuteMatch = RegExp(r'(\d+)\s*minutes?\s*ago').firstMatch(lower);
    if (minuteMatch != null) {
      return now.subtract(Duration(minutes: int.parse(minuteMatch.group(1)!)));
    }

    final hourMatch = RegExp(r'(\d+)\s*hours?\s*ago').firstMatch(lower);
    if (hourMatch != null) {
      return now.subtract(Duration(hours: int.parse(hourMatch.group(1)!)));
    }

    if (lower.contains('yesterday')) {
      return now.subtract(const Duration(days: 1));
    }

    final dayMatch = RegExp(r'(\d+)\s*days?\s*ago').firstMatch(lower);
    if (dayMatch != null) {
      return now.subtract(Duration(days: int.parse(dayMatch.group(1)!)));
    }

    final weekMatch = RegExp(r'(\d+)\s*weeks?\s*ago').firstMatch(lower);
    if (weekMatch != null) {
      return now.subtract(Duration(days: 7 * int.parse(weekMatch.group(1)!)));
    }

    return null;
  }

  String _groupLabelFor(DateTime? date) {
    if (date == null) return 'Earlier';

    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final target = DateTime(date.year, date.month, date.day);
    final dayDiff = today.difference(target).inDays;

    if (dayDiff <= 0) return 'Latest';
    if (dayDiff == 1) return 'Yesterday';
    if (dayDiff == 2) return '2 days ago';
    if (dayDiff == 3) return '3 days ago';
    if (dayDiff <= 6) return 'This week';
    if (dayDiff <= 13) return 'Last week';
    if (dayDiff <= 30) return 'Earlier this month';
    return 'Older';
  }

  List<MapEntry<String, List<Map<String, dynamic>>>> _groupedNotifications(
    List<Map<String, dynamic>> notifications,
  ) {
    const order = [
      'Latest',
      'Yesterday',
      '2 days ago',
      '3 days ago',
      'This week',
      'Last week',
      'Earlier this month',
      'Older',
      'Earlier',
    ];

    final buckets = <String, List<Map<String, dynamic>>>{
      for (final label in order) label: <Map<String, dynamic>>[],
    };

    for (final notification in notifications) {
      final label = _groupLabelFor(_parseNotificationDate(notification));
      buckets.putIfAbsent(label, () => <Map<String, dynamic>>[]).add(notification);
    }

    return order
        .where((label) => buckets[label]!.isNotEmpty)
        .map((label) => MapEntry(label, buckets[label]!))
        .toList();
  }

  String _displayTime(Map<String, dynamic> notification, DateTime? date) {
    final raw = notification['timestamp']?.toString() ?? '';
    if (raw == '0' || raw.toLowerCase() == 'just now') return 'Just now';
    if (date != null) {
      final now = DateTime.now();
      final today = DateTime(now.year, now.month, now.day);
      final target = DateTime(date.year, date.month, date.day);
      if (today == target) {
        return DateFormat('h:mm a').format(date);
      }
      return DateFormat('d MMM • h:mm a').format(date);
    }
    if (raw.isNotEmpty) return raw;
    return '';
  }

  bool _isUnread(Map<String, dynamic> notification) {
    final value = notification['unread'];
    if (value is bool) return value;
    if (value is num) return value != 0;
    final asString = value?.toString().trim().toLowerCase();
    return asString == '1' || asString == 'true' || asString == 'yes';
  }

  String? _firstString(Map<String, dynamic> map, List<String> keys) {
    for (final key in keys) {
      final value = map[key]?.toString().trim() ?? '';
      if (value.isNotEmpty && value.toLowerCase() != 'null') return value;
    }
    return null;
  }

  Future<void> _openNotification(Map<String, dynamic> notification) async {
    if (_opening) return;
    setState(() => _opening = true);
    try {
      final opened = await _navigateForNotification(notification);
      if (!opened && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('No linked page for this notification yet.'),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _opening = false);
    }
  }

  Future<bool> _navigateForNotification(
    Map<String, dynamic> notification,
  ) async {
    final link = _firstString(notification, [
      'redirect_url',
      'url',
      'link',
      'deep_link',
      'deeplink',
      'href',
      'open_url',
    ]);
    if (link != null) {
      final uri = Uri.tryParse(link);
      if (uri != null &&
          (uri.scheme == 'http' || uri.scheme == 'https') &&
          await canLaunchUrl(uri)) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
        return true;
      }
    }

    final screen = (_firstString(notification, [
              'screen',
              'open_tab',
              'native_screen',
              'wf_native_screen',
              'redirect_page',
              'type',
              'category',
              'notification_type',
            ]) ??
            '')
        .toLowerCase()
        .replaceAll('-', '_')
        .replaceAll(' ', '_');

    final taskId = _firstString(notification, [
      'task_id',
      'erp_task_id',
      'workflow_task_id',
      'focus_task_id',
    ]);
    final indentId = _firstString(notification, [
      'indent_id',
      'indentId',
      'wf_indent_id',
    ]);
    final projectId = _firstString(notification, [
      'project_id',
      'projectId',
      'pr_id',
    ]);
    final projectName = _firstString(notification, [
      'project_name',
      'client_name',
      'project',
    ]);

    final blob =
        '${notification['title'] ?? ''} ${notification['body'] ?? ''} $screen'
            .toLowerCase();

    if (indentId != null &&
        (screen.contains('indent_proof') ||
            screen.contains('site_proof') ||
            blob.contains('indent proof') ||
            blob.contains('site proof'))) {
      await openIndentProofScreen(context, indentId: indentId);
      return true;
    }

    if (taskId != null ||
        screen.contains('task') ||
        blob.contains('task') ||
        blob.contains('assigned')) {
      await _openMyTasks(focusTaskId: taskId);
      return true;
    }

    if (indentId != null ||
        screen.contains('indent') ||
        blob.contains('indent')) {
      final prefs = await SharedPreferences.getInstance();
      await Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => IndentsScreenLayout(
            initialTab: blob.contains('my indent')
                ? kIndentsMyIndentsTab
                : kIndentsViewOpenTab,
            initialProjectId: projectId ?? prefs.getString('project_id'),
            initialProjectName: projectName ?? prefs.getString('client_name'),
          ),
        ),
      );
      return true;
    }

    if (screen.contains('approved_po') ||
        screen.contains('purchase_order') ||
        blob.contains('approved po') ||
        blob.contains('purchase order') ||
        RegExp(r'\bpo\b').hasMatch(blob)) {
      final prefs = await SharedPreferences.getInstance();
      await Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => ApprovedPosScreenLayout(
            initialProjectId: projectId ?? prefs.getString('project_id'),
            initialProjectName: projectName ?? prefs.getString('client_name'),
          ),
        ),
      );
      return true;
    }

    if (screen.contains('slot') ||
        blob.contains('visit date') ||
        blob.contains('site visit slot') ||
        blob.contains('slots')) {
      await Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => const SlotsScreen()),
      );
      return true;
    }

    if (screen.contains('site_visit') || blob.contains('site visit')) {
      final prefs = await SharedPreferences.getInstance();
      final fixedId = projectId ?? prefs.getString('project_id');
      await Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => SiteVisitReportsScreen(
            fixedProjectId: fixedId,
            projectFixed: fixedId != null && fixedId.isNotEmpty,
          ),
        ),
      );
      return true;
    }

    return false;
  }

  Future<void> _openMyTasks({String? focusTaskId}) async {
    final dp = DataProvider();
    final tasks = <dynamic>[
      ...dp.clientPendingTasks,
      ...dp.clientTimelineTasks,
    ];
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => MyTasksScreen(
          tasks: tasks,
          focusTaskId: focusTaskId,
          onRefresh: () async {
            await dp.reloadData();
            return <dynamic>[
              ...DataProvider().clientPendingTasks,
              ...DataProvider().clientTimelineTasks,
            ];
          },
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: Listenable.merge([
        _service.notificationsNotifier,
        _service.isSyncingNotifier,
      ]),
      builder: (context, _) {
        final all = _sortedNotifications(_service.notificationsNotifier.value);
        final syncing = _service.isSyncingNotifier.value;
        final showInitialLoader =
            all.isEmpty && (_bootstrapping || syncing);

        if (_visibleCount > all.length && all.isNotEmpty) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) setState(() => _visibleCount = all.length);
          });
        }

        Widget content;
        if (showInitialLoader) {
          content = const SkeletonListLoader(
            showSummary: false,
            cardCount: 6,
            padding: EdgeInsets.fromLTRB(20, 8, 20, 32),
          );
        } else if (all.isEmpty) {
          content = _buildEmptyState();
        } else {
          final visible = all.take(_visibleCount).toList();
          final groups = _groupedNotifications(visible);
          final hasMore = _visibleCount < all.length;
          content = ListView.builder(
            controller: _scrollController,
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
            itemCount: groups.length + (hasMore ? 1 : 0),
            itemBuilder: (context, index) {
              if (index >= groups.length) {
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  if (mounted) _showMore();
                });
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
              final group = groups[index];
              return _buildGroup(group.key, group.value, index == 0);
            },
          );
        }

        return RefreshIndicator(
          color: _navy,
          onRefresh: _handleRefresh,
          child: content,
        );
      },
    );
  }

  Widget _buildGroup(
    String label,
    List<Map<String, dynamic>> items,
    bool isFirst,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: EdgeInsets.only(top: isFirst ? 8 : 22, bottom: 6),
          child: Text(
            label.toUpperCase(),
            style: const TextStyle(
              color: _mutedGrey,
              fontSize: 11.5,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.9,
            ),
          ),
        ),
        ...List.generate(items.length, (index) {
          final notification = items[index];
          final date = _parseNotificationDate(notification);
          final isLast = index == items.length - 1;
          return _buildNotificationRow(
            notification,
            date,
            showDivider: !isLast,
          );
        }),
      ],
    );
  }

  Widget _buildNotificationRow(
    Map<String, dynamic> notification,
    DateTime? date, {
    required bool showDivider,
  }) {
    final isUnread = _isUnread(notification);
    final timeLabel = _displayTime(notification, date);

    return Column(
      children: [
        Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: _opening ? null : () => _openNotification(notification),
            borderRadius: BorderRadius.circular(12),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 2),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 10,
                    height: 10,
                    margin: const EdgeInsets.only(top: 5),
                    decoration: BoxDecoration(
                      color: isUnread ? _navy : const Color(0xFFD5DBE5),
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(
                              child: Text(
                                notification['title']?.toString() ??
                                    'Notification',
                                style: TextStyle(
                                  fontWeight: isUnread
                                      ? FontWeight.w800
                                      : FontWeight.w700,
                                  fontSize: 14.5,
                                  color: _navy,
                                  letterSpacing: -0.1,
                                  height: 1.25,
                                ),
                              ),
                            ),
                            if (timeLabel.isNotEmpty) ...[
                              const SizedBox(width: 10),
                              Text(
                                timeLabel,
                                style: const TextStyle(
                                  color: _mutedGrey,
                                  fontSize: 11.5,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ],
                        ),
                        if ((notification['body'] ?? '')
                            .toString()
                            .trim()
                            .isNotEmpty) ...[
                          const SizedBox(height: 5),
                          Text(
                            notification['body']?.toString() ?? '',
                            style: const TextStyle(
                              color: _mutedGrey,
                              fontSize: 13.5,
                              fontWeight: FontWeight.w500,
                              height: 1.4,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(width: 6),
                  const Padding(
                    padding: EdgeInsets.only(top: 2),
                    child: Icon(
                      Icons.chevron_right_rounded,
                      size: 20,
                      color: Color(0xFFC0C7D4),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        if (showDivider)
          const Divider(height: 1, thickness: 1, color: _cardBorder),
      ],
    );
  }

  Widget _buildEmptyState() {
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
              color: const Color(0xFFEEF2FF),
              borderRadius: BorderRadius.circular(24),
            ),
            child: const Icon(
              Icons.notifications_off_outlined,
              size: 36,
              color: _navy,
            ),
          ),
        ),
        const SizedBox(height: 22),
        const Text(
          "You're all caught up!",
          textAlign: TextAlign.center,
          style: TextStyle(
            color: _navy,
            fontSize: 18,
            fontWeight: FontWeight.w800,
            letterSpacing: -0.2,
          ),
        ),
        const SizedBox(height: 8),
        const Text(
          "We'll let you know when there's something new.",
          textAlign: TextAlign.center,
          style: TextStyle(
            color: _mutedGrey,
            fontSize: 14,
            fontWeight: FontWeight.w500,
            height: 1.4,
          ),
        ),
      ],
    );
  }
}
