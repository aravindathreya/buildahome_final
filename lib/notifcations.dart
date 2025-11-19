import 'package:flutter/material.dart';
import 'package:flutter/widgets.dart';
import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'app_theme.dart';

class Notifications extends StatelessWidget {
  const Notifications({super.key});

  @override
  Widget build(BuildContext context) {
    return Theme(
      data: AppTheme.darkTheme,
      child: const _NotificationsShell(),
    );
  }
}

class _NotificationsShell extends StatelessWidget {
  const _NotificationsShell();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.backgroundPrimary,
      appBar: AppBar(
        automaticallyImplyLeading: true,
        title: Text(
          'My Notifications',
          style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600),
        ),
      ),
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
  List<dynamic> notifcations = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadNotifications();
  }

  Future<void> _loadNotifications() async {
    final prefs = await SharedPreferences.getInstance();
    final userId = prefs.get('user_id');
    final response = await http.get(Uri.parse('https://office.buildahome.in/API/get_notifications?recipient=$userId'));
    final markRead = http.get(Uri.parse('https://office.buildahome.in/API/mark_notifications_as_read?user_id=$userId'));
    final decoded = jsonDecode(response.body);
    await markRead;
    if (!mounted) return;
    setState(() {
      notifcations = (decoded as List).reversed.toList();
      _isLoading = false;
    });
  }

  Future<void> _handleRefresh() async {
    setState(() {
      _isLoading = true;
    });
    await _loadNotifications();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    Widget content;
    if (_isLoading) {
      content = const Center(child: CircularProgressIndicator());
    } else if (notifcations.isEmpty) {
      content = _buildEmptyState(theme);
    } else {
      content = ListView.separated(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
        itemCount: notifcations.length,
        separatorBuilder: (_, __) => const SizedBox(height: 12),
        itemBuilder: (context, index) => _buildNotificationCard(context, notifcations[index]),
      );
    }

    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 250),
      child: RefreshIndicator(
        key: ValueKey(_isLoading ? 'loading' : 'loaded'),
        color: AppTheme.primaryColorConst,
        onRefresh: _handleRefresh,
        child: content,
      ),
    );
  }

  Widget _buildNotificationCard(BuildContext context, dynamic notification) {
    final theme = Theme.of(context);
    final isUnread = notification['unread'] == 1;
    final timestamp = notification['timestamp']?.toString() ?? '';

    return Container(
      decoration: BoxDecoration(
        color: AppTheme.backgroundSecondary,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: isUnread ? AppTheme.primaryColorConst.withOpacity(0.4) : AppTheme.primaryColorConst.withOpacity(0.15),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.08),
            blurRadius: 8,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: (isUnread ? AppTheme.primaryColorConst : AppTheme.primaryColorConst.withOpacity(0.15)),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  isUnread ? Icons.notifications_active : Icons.notifications_outlined,
                  size: 18,
                  color: isUnread ? Colors.white : AppTheme.primaryColorConst,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      notification['title'] ?? 'Notification',
                      style: theme.textTheme.bodyLarge?.copyWith(
                        fontWeight: FontWeight.w700,
                        color: AppTheme.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      notification['body'] ?? '',
                      style: theme.textTheme.bodyMedium,
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Icon(Icons.schedule, size: 16, color: AppTheme.textSecondary),
              const SizedBox(width: 6),
              Text(
                timestamp == '0' ? 'Just now' : timestamp,
                style: theme.textTheme.bodySmall?.copyWith(color: AppTheme.textSecondary),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState(ThemeData theme) {
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 80),
      children: [
        Icon(Icons.notifications_off_outlined, size: 72, color: AppTheme.textSecondary),
        const SizedBox(height: 20),
        Text(
          'You’re all caught up!',
          textAlign: TextAlign.center,
          style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 8),
        Text(
          'We’ll let you know when there’s something new.',
          textAlign: TextAlign.center,
          style: theme.textTheme.bodyMedium?.copyWith(color: AppTheme.textSecondary),
        ),
      ],
    );
  }
}
