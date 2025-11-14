import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import 'ShowAlert.dart';
import 'app_theme.dart';

class ChecklistItemsLayout extends StatelessWidget {
  final String category;

  const ChecklistItemsLayout(this.category, {super.key});

  @override
  Widget build(BuildContext context) {
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
        title: Text(category),
      ),
      body: ChecklistItems(category),
    );
  }
}

class ChecklistItems extends StatefulWidget {
  final String category;

  const ChecklistItems(this.category, {super.key});

  @override
  ChecklistItemsState createState() {
    return ChecklistItemsState();
  }
}

class ChecklistItemsState extends State<ChecklistItems> {
  List<dynamic> data = [];
  bool _isLoading = false;
  String? projectId;
  String? role;
  String? userId;

  @override
  void initState() {
    super.initState();
    call();
  }

  Future<void> call() async {
    setState(() {
      _isLoading = true;
    });
    try {
      SharedPreferences prefs = await SharedPreferences.getInstance();
      projectId = prefs.getString('project_id');
      role = prefs.getString('role');
      userId = prefs.getString('user_id');
      if (projectId == null) return;
      var url = 'https://office.buildahome.in/API/get_checklist_items_for_category';
      var response = await http.post(Uri.parse(url), body: {'project_id': projectId, 'category': widget.category});
      if (!mounted) return;
      setState(() {
        data = jsonDecode(response.body)['data'];
      });
    } catch (err) {
      debugPrint('Failed to load checklist items: $err');
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return RefreshIndicator(
      color: AppTheme.primaryColorConst,
      onRefresh: call,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 24, 16, 32),
        children: [
          Text(
            'Checklist for ${widget.category}',
            style: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 16),
          if (_isLoading && data.isEmpty)
            ...List.generate(4, (_) => _buildSkeleton())
          else if (data.isEmpty)
            _buildEmptyState()
          else
            ...List.generate(data.length, (index) => _buildItemCard(index)),
        ],
      ),
    );
  }

  Widget _buildItemCard(int index) {
    final item = data[index];
    final bool bahChecked = item[2] != null && item[2] != 0;
    final bool clientChecked = item[3] != null && item[3] != 0;

    final Color statusColor;
    final IconData statusIcon;
    final String statusLabel;

    if (bahChecked && clientChecked) {
      statusColor = Colors.green;
      statusIcon = Icons.verified;
      statusLabel = 'Completed';
    } else if (bahChecked) {
      statusColor = Colors.orange;
      statusIcon = Icons.task_alt;
      statusLabel = 'Client action pending';
    } else {
      statusColor = Colors.grey;
      statusIcon = Icons.schedule;
      statusLabel = 'Scheduled';
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.backgroundSecondary,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppTheme.primaryColorConst.withOpacity(0.08)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: statusColor.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(statusIcon, color: statusColor),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  item[1].toString(),
                  style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: statusColor.withOpacity(0.12),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text(
              statusLabel,
              style: TextStyle(color: statusColor, fontWeight: FontWeight.w600, fontSize: 12),
            ),
          ),
          if (bahChecked) ...[
            const SizedBox(height: 8),
            Text(
              'Checked by buildAhome on ${item[4]}',
              style: const TextStyle(color: AppTheme.textSecondary, fontSize: 12),
            ),
          ],
          if (clientChecked) ...[
            const SizedBox(height: 4),
            Text(
              'Marked as checked by you on ${item[5]}',
              style: const TextStyle(color: Colors.green, fontSize: 12),
            ),
          ],
          if (bahChecked && !clientChecked && role == 'Client')
            _buildActionButton(index, isClient: true),
          if (bahChecked && role != 'Client' && !clientChecked)
            _buildActionButton(index, isClient: false),
        ],
      ),
    );
  }

  Widget _buildActionButton(int index, {required bool isClient}) {
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Align(
        alignment: Alignment.centerRight,
        child: FilledButton(
          onPressed: () => _confirmCheck(index, isClient: isClient),
          child: const Text('Mark as checked'),
        ),
      ),
    );
  }

  Future<void> _confirmCheck(int index, {required bool isClient}) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Confirmation'),
        content: const Text('Are you sure you want to mark this item as checked?'),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(false), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.of(context).pop(true), child: const Text('Yes, confirm')),
        ],
      ),
    );

    if (confirm != true) return;
    if (projectId == null) return;

    try {
      final endpoint = isClient ? 'update_checklist_item_by_client' : 'update_project_checklist_item_api';
      final body = {
        'project_id': projectId,
        'checklist_item_id': data[index][0].toString(),
      };
      if (!isClient) {
        body['user_id'] = userId ?? '';
      }
      final response = await http.post(Uri.parse('https://office.buildahome.in/API/$endpoint'), body: body);
      if (response.statusCode != 200) {
        throw Exception('Failed to update item');
      }
      await call();
    } catch (err) {
      showDialog(
        context: context,
        builder: (BuildContext context) {
          return ShowAlert("Something went wrong", false);
        },
      );
    }
  }

  Widget _buildSkeleton() {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      height: 96,
      decoration: BoxDecoration(
        color: AppTheme.backgroundSecondary,
        borderRadius: BorderRadius.circular(16),
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
          Icon(Icons.fact_check, color: AppTheme.primaryColorConst, size: 32),
          const SizedBox(height: 12),
          const Text(
            'No checklist items yet',
            style: TextStyle(fontWeight: FontWeight.w600, color: AppTheme.textPrimary),
          ),
          const SizedBox(height: 4),
          const Text(
            'Items will appear once the project team shares the checklist.',
            style: TextStyle(color: AppTheme.textSecondary),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}
