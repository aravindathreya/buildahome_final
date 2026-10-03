import 'package:flutter/material.dart';

import '../chat_v1_controller.dart';
import '../chat_v1_models.dart';
import '../chat_v1_theme.dart';
import '../widgets/chat_v1_common.dart';

class ChatV1GroupInfoScreen extends StatelessWidget {
  final ChatV1ConvMeta meta;
  const ChatV1GroupInfoScreen({super.key, required this.meta});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: ChatV1Theme.bg(context),
      appBar: AppBar(title: const Text('Group info')),
      body: ListView(
        physics: const BouncingScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        children: [
          const SizedBox(height: 8),
          Center(
            child: Hero(
              tag: 'avatar_${meta.id}',
              child: Cv1Avatar(
                initials: meta.title.isNotEmpty ? meta.title[0] : '?',
                color: meta.accent,
                icon: meta.icon,
                size: 96,
              ),
            ),
          ),
          const SizedBox(height: 14),
          Text(
            meta.title,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: ChatV1Theme.text(context),
              fontSize: 22,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Group · ${meta.members.length} members',
            textAlign: TextAlign.center,
            style: TextStyle(color: ChatV1Theme.textMuted(context)),
          ),
          const SizedBox(height: 18),
          _card(
            context,
            title: 'About',
            child: Text(
              meta.description,
              style: TextStyle(
                color: ChatV1Theme.textSecondary(context),
                height: 1.4,
              ),
            ),
          ),
          _card(
            context,
            title: 'Members',
            child: Column(
              children: meta.members
                  .map(
                    (m) => ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: Cv1Avatar(
                        initials: m.initials,
                        color: m.color,
                        online: m.online,
                        size: 40,
                      ),
                      title: Text(m.name,
                          style: TextStyle(
                              color: ChatV1Theme.text(context),
                              fontWeight: FontWeight.w700)),
                      subtitle: Text(m.role,
                          style: TextStyle(
                              color: ChatV1Theme.textMuted(context))),
                      trailing: m.online
                          ? const Cv1Badge(
                              label: 'Online', color: ChatV1Theme.completed)
                          : null,
                    ),
                  )
                  .toList(),
            ),
          ),
          _card(
            context,
            title: 'Media, links & docs',
            child: Row(
              children: List.generate(
                4,
                (i) => Expanded(
                  child: Container(
                    height: 64,
                    margin: EdgeInsets.only(right: i == 3 ? 0 : 8),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(10),
                      gradient: LinearGradient(
                        colors: [
                          ChatV1Theme.accent.withValues(alpha: 0.3),
                          ChatV1Theme.accent.withValues(alpha: 0.08),
                        ],
                      ),
                    ),
                    child: const Icon(Icons.image_rounded, color: Colors.white70),
                  ),
                ),
              ),
            ),
          ),
          _card(
            context,
            title: 'Settings',
            child: _GroupSettings(meta: meta),
          ),
        ],
      ),
    );
  }

  Widget _card(BuildContext context,
      {required String title, required Widget child}) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: ChatV1Theme.card(context),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: ChatV1Theme.border(context)),
        boxShadow: ChatV1Theme.shadow(context),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title,
              style: TextStyle(
                  color: ChatV1Theme.text(context),
                  fontWeight: FontWeight.w800,
                  fontSize: 14)),
          const SizedBox(height: 10),
          child,
        ],
      ),
    );
  }
}

class _GroupSettings extends StatelessWidget {
  final ChatV1ConvMeta meta;
  const _GroupSettings({required this.meta});

  List<ChatV1Message> _cached() {
    return ChatV1Controller.instance.cachedMessages(meta.id) ??
        const <ChatV1Message>[];
  }

  Future<void> _showPinned(BuildContext context) async {
    final pinned = _cached().where((m) => m.isPinned && !m.isDeleted).toList();
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: ChatV1Theme.card(context),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
      ),
      builder: (ctx) {
        return SafeArea(
          child: pinned.isEmpty
              ? const Padding(
                  padding: EdgeInsets.all(24),
                  child: Text('No pinned messages in this chat.'),
                )
              : ListView.separated(
                  shrinkWrap: true,
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
                  itemCount: pinned.length,
                  separatorBuilder: (_, __) => const Divider(height: 1),
                  itemBuilder: (_, i) {
                    final message = pinned[i];
                    final text = message.body.trim().isEmpty
                        ? (message.fileName ?? 'Attachment')
                        : message.body.trim();
                    return ListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text(message.authorName),
                      subtitle: Text(text, maxLines: 3),
                    );
                  },
                ),
        );
      },
    );
  }

  Future<void> _search(BuildContext context) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: ChatV1Theme.card(context),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
      ),
      builder: (_) => _InChatSearchSheet(messages: _cached()),
    );
  }

  Future<void> _archive(BuildContext context) async {
    await ChatV1Controller.instance.setConversationFlag(
      meta.id,
      archived: true,
    );
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Chat archived')),
    );
    Navigator.of(context).pop();
  }

  Future<void> _leave(BuildContext context) async {
    final leave = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Leave group'),
        content: Text('Leave ${meta.title}?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Leave'),
          ),
        ],
      ),
    );
    if (leave != true || !context.mounted) return;
    await ChatV1Controller.instance.leaveConversation(meta.id);
    if (!context.mounted) return;
    final nav = Navigator.of(context);
    nav.pop();
    if (nav.canPop()) nav.pop();
  }

  @override
  Widget build(BuildContext context) {
    final ctrl = ChatV1Controller.instance;
    return ListenableBuilder(
      listenable: ctrl,
      builder: (context, _) {
        final muted = ctrl.findChatById(meta.id)?.isMuted ?? false;
        return Column(
          children: [
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Mute notifications'),
              value: muted,
              activeThumbColor: ChatV1Theme.accent,
              onChanged: (value) {
                ctrl.setConversationFlag(meta.id, muted: value);
              },
            ),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.push_pin_outlined),
              title: const Text('Pinned messages'),
              onTap: () => _showPinned(context),
            ),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.search_rounded),
              title: const Text('Search in chat'),
              onTap: () => _search(context),
            ),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.archive_outlined),
              title: const Text('Archive'),
              onTap: () => _archive(context),
            ),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: Icon(Icons.logout_rounded, color: ChatV1Theme.rejected),
              title: Text(
                'Leave group',
                style: TextStyle(color: ChatV1Theme.rejected),
              ),
              onTap: () => _leave(context),
            ),
          ],
        );
      },
    );
  }
}

class _InChatSearchSheet extends StatefulWidget {
  final List<ChatV1Message> messages;
  const _InChatSearchSheet({required this.messages});

  @override
  State<_InChatSearchSheet> createState() => _InChatSearchSheetState();
}

class _InChatSearchSheetState extends State<_InChatSearchSheet> {
  final _query = TextEditingController();

  @override
  void dispose() {
    _query.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final q = _query.text.trim().toLowerCase();
    final matches = q.isEmpty
        ? const <ChatV1Message>[]
        : widget.messages
            .where((m) =>
                !m.isDeleted &&
                (m.body.toLowerCase().contains(q) ||
                    m.authorName.toLowerCase().contains(q) ||
                    (m.fileName ?? '').toLowerCase().contains(q)))
            .toList();
    final bottom = MediaQuery.viewInsetsOf(context).bottom;
    return Padding(
      padding: EdgeInsets.fromLTRB(16, 16, 16, 16 + bottom),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              controller: _query,
              autofocus: true,
              decoration: const InputDecoration(
                hintText: 'Search in this chat',
                prefixIcon: Icon(Icons.search_rounded),
              ),
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: 12),
            if (widget.messages.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 12),
                child: Text(
                  'Open the chat to load messages, then search again.',
                ),
              )
            else if (q.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 12),
                child: Text('Type to search messages in this chat.'),
              )
            else if (matches.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 12),
                child: Text('No matching messages.'),
              )
            else
              ...matches.map((message) {
                final text = message.body.trim().isEmpty
                    ? (message.fileName ?? 'Attachment')
                    : message.body.trim();
                return ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(message.authorName),
                  subtitle: Text(text, maxLines: 3),
                );
              }),
          ],
        ),
      ),
    );
  }
}
