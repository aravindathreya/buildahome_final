import 'package:flutter/material.dart';

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
            child: Column(
              children: [
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Mute notifications'),
                  value: false,
                  activeThumbColor: ChatV1Theme.accent,
                  onChanged: (_) {},
                ),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.push_pin_outlined),
                  title: const Text('Pinned messages'),
                  onTap: () {},
                ),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.search_rounded),
                  title: const Text('Search in chat'),
                  onTap: () {},
                ),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.archive_outlined),
                  title: const Text('Archive'),
                  onTap: () {},
                ),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading:
                      Icon(Icons.logout_rounded, color: ChatV1Theme.rejected),
                  title: Text('Leave group',
                      style: TextStyle(color: ChatV1Theme.rejected)),
                  onTap: () {},
                ),
              ],
            ),
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
