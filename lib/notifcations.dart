import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'app_theme.dart';
import 'services/notification_service.dart';
import 'widgets/themed_scaffold.dart';
import 'widgets/skeleton_loader.dart';

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
  bool _bootstrapping = true;

  @override
  void initState() {
    super.initState();
    _bootstrap();
  }

  Future<void> _bootstrap() async {
    await _service.ensureHydrated();
    if (mounted) setState(() {});
    // Open screen: sync delta (or full snapshot) then mark read so the badge clears.
    await _service.markAllAsRead();
    if (mounted) {
      setState(() => _bootstrapping = false);
    }
  }

  Future<void> _handleRefresh() async {
    await _service.markAllAsRead();
  }

  DateTime? _parseNotificationDate(dynamic notification) {
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
      'EEEE dd MMMM HH:mm',
    ]) {
      try {
        return DateFormat(pattern).parse(value).toLocal();
      } catch (_) {}
    }

    final lower = value.toLowerCase();
    final now = DateTime.now();

    final minuteMatch =
        RegExp(r'(\d+)\s*minutes?\s*ago').firstMatch(lower);
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

  List<MapEntry<String, List<dynamic>>> _groupedNotifications(
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

    final buckets = <String, List<dynamic>>{
      for (final label in order) label: <dynamic>[],
    };

    final dated = notifications.map((notification) {
      return MapEntry(_parseNotificationDate(notification), notification);
    }).toList()
      ..sort((a, b) {
        final aDate = a.key ?? DateTime.fromMillisecondsSinceEpoch(0);
        final bDate = b.key ?? DateTime.fromMillisecondsSinceEpoch(0);
        return bDate.compareTo(aDate);
      });

    for (final entry in dated) {
      final label = _groupLabelFor(entry.key);
      buckets.putIfAbsent(label, () => <dynamic>[]).add(entry.value);
    }

    return order
        .where((label) => buckets[label]!.isNotEmpty)
        .map((label) => MapEntry(label, buckets[label]!))
        .toList();
  }

  String _displayTime(dynamic notification, DateTime? date) {
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

  bool _isUnread(dynamic notification) {
    final value = notification is Map ? notification['unread'] : null;
    if (value is bool) return value;
    if (value is num) return value != 0;
    final asString = value?.toString().trim().toLowerCase();
    return asString == '1' || asString == 'true' || asString == 'yes';
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: Listenable.merge([
        _service.notificationsNotifier,
        _service.isSyncingNotifier,
      ]),
      builder: (context, _) {
        final notifications = _service.notificationsNotifier.value;
        final syncing = _service.isSyncingNotifier.value;
        final showInitialLoader =
            notifications.isEmpty && (_bootstrapping || syncing);

        Widget content;
        if (showInitialLoader) {
          content = const SkeletonListLoader(
            showSummary: false,
            cardCount: 6,
            padding: EdgeInsets.fromLTRB(20, 8, 20, 32),
          );
        } else if (notifications.isEmpty) {
          content = _buildEmptyState();
        } else {
          final groups = _groupedNotifications(notifications);
          content = ListView.builder(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
            itemCount: groups.length,
            itemBuilder: (context, groupIndex) {
              final group = groups[groupIndex];
              return _buildGroup(group.key, group.value, groupIndex == 0);
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

  Widget _buildGroup(String label, List<dynamic> items, bool isFirst) {
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
    dynamic notification,
    DateTime? date, {
    required bool showDivider,
  }) {
    final isUnread = _isUnread(notification);
    final timeLabel = _displayTime(notification, date);

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 14),
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
                            notification['title'] ?? 'Notification',
                            style: TextStyle(
                              fontWeight:
                                  isUnread ? FontWeight.w800 : FontWeight.w700,
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
                        notification['body'] ?? '',
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
            ],
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
