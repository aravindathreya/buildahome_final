import 'package:flutter/material.dart';

import '../chat_v1_controller.dart';
import '../chat_v1_models.dart';
import '../chat_v1_theme.dart';
import '../widgets/chat_v1_common.dart';
import '../widgets/chat_v1_task_card.dart';

class ChatV1TaskListScreen extends StatefulWidget {
  final String hubTitle;
  final String hubKind; // kept for callers; always shows ERP + workflow
  final ValueChanged<ChatV1TaskItem> onOpenTask;

  const ChatV1TaskListScreen({
    super.key,
    required this.hubTitle,
    required this.onOpenTask,
    this.hubKind = 'tasks',
  });

  @override
  State<ChatV1TaskListScreen> createState() => _ChatV1TaskListScreenState();
}

class _ChatV1TaskListScreenState extends State<ChatV1TaskListScreen> {
  final _search = TextEditingController();
  final _ctrl = ChatV1Controller.instance;
  String _query = '';
  String _status = 'All';

  @override
  void initState() {
    super.initState();
    _ctrl.addListener(_onCtrl);
  }

  void _onCtrl() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _ctrl.removeListener(_onCtrl);
    _search.dispose();
    super.dispose();
  }

  List<ChatV1TaskItem> get _source => _ctrl.allProjectTasks;

  @override
  Widget build(BuildContext context) {
    var tasks = _source.where((t) {
      final q = _query.isEmpty ||
          t.title.toLowerCase().contains(_query) ||
          t.category.toLowerCase().contains(_query) ||
          t.assignee.toLowerCase().contains(_query) ||
          t.assigneeRole.toLowerCase().contains(_query);
      if (!q) return false;
      if (_status == 'All') return true;
      if (_status == 'Pending') {
        return t.status == ChatV1TaskStatus.pending ||
            t.status == ChatV1TaskStatus.inProgress;
      }
      if (_status == 'Completed') return t.status == ChatV1TaskStatus.completed;
      if (_status == 'Rejected') return t.status == ChatV1TaskStatus.rejected;
      return true;
    }).toList();

    return Scaffold(
      backgroundColor: ChatV1Theme.bg(context),
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(widget.hubTitle),
            Text(
              '${tasks.length} discussions',
              style: TextStyle(
                color: ChatV1Theme.textMuted(context),
                fontSize: 12,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 8, 14, 8),
            child: Cv1SearchField(
              controller: _search,
              hint: 'Search project & workflow tasks',
              onChanged: (v) => setState(() => _query = v.toLowerCase()),
            ),
          ),
          SizedBox(
            height: 40,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 14),
              children: ['All', 'Pending', 'Completed', 'Rejected'].map((s) {
                final active = s == _status;
                return Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: ChoiceChip(
                    label: Text(s),
                    selected: active,
                    onSelected: (_) => setState(() => _status = s),
                    selectedColor: ChatV1Theme.accentSoft,
                    labelStyle: TextStyle(
                      color: active
                          ? ChatV1Theme.accent
                          : ChatV1Theme.textSecondary(context),
                      fontWeight: FontWeight.w700,
                      fontSize: 12.5,
                    ),
                  ),
                );
              }).toList(),
            ),
          ),
          const SizedBox(height: 8),
          Expanded(
            child: tasks.isEmpty
                ? Center(
                    child: Text(
                      'No conversations yet',
                      style:
                          TextStyle(color: ChatV1Theme.textMuted(context)),
                    ),
                  )
                : ListView.builder(
                    physics: const BouncingScrollPhysics(),
                    padding: const EdgeInsets.fromLTRB(14, 0, 14, 24),
                    itemCount: tasks.length,
                    itemBuilder: (_, i) {
                      final task = tasks[i];
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 10),
                        child: Cv1TaskCard(
                          task: task,
                          onOpen: () => widget.onOpenTask(task),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}
