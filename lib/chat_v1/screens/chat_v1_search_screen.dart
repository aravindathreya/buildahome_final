import 'package:flutter/material.dart';

import '../chat_v1_api.dart';
import '../chat_v1_controller.dart';
import '../chat_v1_models.dart';
import '../chat_v1_theme.dart';
import '../chat_v1_utils.dart';
import '../widgets/chat_v1_common.dart';

class ChatV1SearchScreen extends StatefulWidget {
  const ChatV1SearchScreen({super.key});

  @override
  State<ChatV1SearchScreen> createState() => _ChatV1SearchScreenState();
}

class _ChatV1SearchScreenState extends State<ChatV1SearchScreen> {
  final _controller = TextEditingController();
  final _ctrl = ChatV1Controller.instance;
  String _query = '';
  String _category = 'All';
  List<ChatV1SearchHit> _remote = [];
  bool _searching = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _runSearch(String q) async {
    setState(() {
      _query = q;
      _searching = true;
    });
    final hits = await ChatV1Api.instance.search(q);
    if (!mounted) return;
    setState(() {
      _remote = hits.map((h) {
        final title =
            (h['title'] ?? h['name'] ?? h['body'] ?? 'Result').toString();
        final subtitle =
            (h['subtitle'] ?? h['conversation_title'] ?? '').toString();
        final category = (h['category'] ?? h['type'] ?? 'Messages').toString();
        return ChatV1SearchHit(
          id: (h['id'] ?? title).toString(),
          title: title,
          subtitle: subtitle,
          category: category,
          icon: Icons.chat_bubble_outline_rounded,
        );
      }).toList();
      _searching = false;
    });
  }

  List<ChatV1SearchHit> _localHits(String q) {
    final query = q.trim().toLowerCase();
    if (query.isEmpty) return const [];
    final all = <ChatV1SearchHit>[
      ..._ctrl.channels.map((c) => ChatV1SearchHit(
            id: c.id,
            title: c.title,
            subtitle: c.lastMessage,
            category: 'Channels',
            icon: c.icon,
          )),
      ..._ctrl.customGroups.map((c) => ChatV1SearchHit(
            id: c.id,
            title: c.title,
            subtitle: c.lastMessage,
            category: 'Groups',
            icon: c.icon,
          )),
      ..._ctrl.dms.map((c) => ChatV1SearchHit(
            id: c.id,
            title: c.title,
            subtitle: c.lastMessage,
            category: 'People',
            icon: Icons.person_outline_rounded,
          )),
      ..._ctrl.allProjectTasks.map((t) => ChatV1SearchHit(
            id: t.id,
            title: t.title,
            subtitle: t.kindLabel,
            category: 'Tasks',
            icon: t.isWorkflow
                ? Icons.account_tree_outlined
                : Icons.task_alt_rounded,
          )),
      ..._ctrl.members.map((m) => ChatV1SearchHit(
            id: m.id,
            title: m.name,
            subtitle: m.role,
            category: 'People',
            icon: Icons.person_outline_rounded,
          )),
    ];
    return all
        .where((h) =>
            h.title.toLowerCase().contains(query) ||
            h.subtitle.toLowerCase().contains(query) ||
            h.category.toLowerCase().contains(query))
        .toList();
  }

  @override
  Widget build(BuildContext context) {
    final local = _localHits(_query);
    var hits = [..._remote, ...local];
    // Deduplicate by id+title
    final seen = <String>{};
    hits = hits.where((h) => seen.add('${h.id}|${h.title}')).toList();
    if (_category != 'All') {
      hits = hits.where((h) => h.category == _category).toList();
    }
    const cats = [
      'All',
      'Messages',
      'People',
      'Channels',
      'Groups',
      'Tasks',
    ];

    return Scaffold(
      backgroundColor: ChatV1Theme.bg(context),
      appBar: AppBar(title: const Text('Search')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 8, 14, 8),
            child: Cv1SearchField(
              controller: _controller,
              hint: 'Messages, people, channels, tasks…',
              onChanged: (v) {
                _runSearch(v);
              },
            ),
          ),
          SizedBox(
            height: 40,
            child: ListView.separated(
              padding: const EdgeInsets.symmetric(horizontal: 14),
              scrollDirection: Axis.horizontal,
              itemCount: cats.length,
              separatorBuilder: (_, __) => const SizedBox(width: 8),
              itemBuilder: (_, i) {
                final active = cats[i] == _category;
                return GestureDetector(
                  onTap: () => setState(() => _category = cats[i]),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14),
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: active
                          ? ChatV1Theme.accent
                          : ChatV1Theme.card(context),
                      borderRadius: BorderRadius.circular(999),
                      border: Border.all(
                        color: active
                            ? ChatV1Theme.accent
                            : ChatV1Theme.border(context),
                      ),
                    ),
                    child: Text(
                      cats[i],
                      style: TextStyle(
                        color: active
                            ? Colors.white
                            : ChatV1Theme.textSecondary(context),
                        fontWeight: FontWeight.w700,
                        fontSize: 12.5,
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
          const SizedBox(height: 8),
          if (_searching)
            const LinearProgressIndicator(minHeight: 2),
          Expanded(
            child: _query.trim().isEmpty
                ? Center(
                    child: Text(
                      'Search conversations and members',
                      style:
                          TextStyle(color: ChatV1Theme.textMuted(context)),
                    ),
                  )
                : hits.isEmpty
                    ? Center(
                        child: Text(
                          'No results for “${_query.trim()}”',
                          style: TextStyle(
                              color: ChatV1Theme.textMuted(context)),
                        ),
                      )
                    : ListView.separated(
                        physics: const BouncingScrollPhysics(),
                        itemCount: hits.length,
                        separatorBuilder: (_, __) => Divider(
                          height: 1,
                          color: ChatV1Theme.border(context),
                        ),
                        itemBuilder: (_, i) {
                          final hit = hits[i];
                          return ListTile(
                            leading: CircleAvatar(
                              backgroundColor:
                                  ChatV1Utils.colorForId(hit.id)
                                      .withValues(alpha: 0.2),
                              child: Icon(hit.icon,
                                  color: ChatV1Utils.colorForId(hit.id),
                                  size: 20),
                            ),
                            title: Text(hit.title),
                            subtitle: Text(
                              '${hit.category} · ${hit.subtitle}',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
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
