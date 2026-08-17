import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../chat_v1_controller.dart';
import '../chat_v1_models.dart';
import '../chat_v1_theme.dart';
import '../widgets/chat_v1_chat_tile.dart';
import '../widgets/chat_v1_common.dart';
import '../widgets/chat_v1_opening_splash.dart';
import 'chat_v1_create_group_sheet.dart';

class ChatV1HomeScreen extends StatefulWidget {
  final bool darkMode;
  final VoidCallback onToggleTheme;
  final ValueChanged<ChatV1ChatItem> onOpenChat;
  final VoidCallback onOpenSearch;
  final String? salesSopId;

  const ChatV1HomeScreen({
    super.key,
    required this.darkMode,
    required this.onToggleTheme,
    required this.onOpenChat,
    required this.onOpenSearch,
    this.salesSopId,
  });

  @override
  State<ChatV1HomeScreen> createState() => _ChatV1HomeScreenState();
}

class _ChatV1HomeScreenState extends State<ChatV1HomeScreen> {
  final _search = TextEditingController();
  final _ctrl = ChatV1Controller.instance;
  String _query = '';
  ChatV1Filter _filter = ChatV1Filter.all;
  final Set<String> _selected = {};
  /// True until the first cold load finishes (no cached chats yet).
  bool _showOpeningSplash = false;

  bool get _hasCachedChats =>
      _ctrl.channels.isNotEmpty ||
      _ctrl.customGroups.isNotEmpty ||
      _ctrl.dms.isNotEmpty ||
      _ctrl.allProjectTasks.isNotEmpty;

  @override
  void initState() {
    super.initState();
    _ctrl.addListener(_onCtrl);
    _showOpeningSplash = !_hasCachedChats;
    _reload();
  }

  @override
  void dispose() {
    _ctrl.removeListener(_onCtrl);
    _search.dispose();
    super.dispose();
  }

  void _onCtrl() {
    if (!mounted) return;
    // Dismiss branded splash once first load completes or cache appears.
    if (_showOpeningSplash && (!_ctrl.loading || _hasCachedChats)) {
      setState(() => _showOpeningSplash = false);
      return;
    }
    setState(() {});
  }

  Future<void> _reload() =>
      _ctrl.loadProjectChat(salesSopIdOverride: widget.salesSopId);

  List<ChatV1ChatItem> _apply(List<ChatV1ChatItem> source) {
    return source.where((c) {
      final q = _query.isEmpty ||
          c.title.toLowerCase().contains(_query) ||
          c.lastMessage.toLowerCase().contains(_query);
      if (!q) return false;
      switch (_filter) {
        case ChatV1Filter.all:
          return true;
        case ChatV1Filter.groups:
          return !c.isDm;
        case ChatV1Filter.tasks:
          return c.isTaskHub || c.opensAs == ChatV1OpensAs.taskList;
        case ChatV1Filter.unread:
          return c.unread > 0 || c.mentions > 0;
      }
    }).toList();
  }

  void _updateItem(String id, ChatV1ChatItem Function(ChatV1ChatItem) fn) {
    setState(() {
      _ctrl.channels =
          _ctrl.channels.map((e) => e.id == id ? fn(e) : e).toList();
      _ctrl.customGroups =
          _ctrl.customGroups.map((e) => e.id == id ? fn(e) : e).toList();
      _ctrl.dms = _ctrl.dms.map((e) => e.id == id ? fn(e) : e).toList();
    });
  }

  Future<void> _openCreateGroup() async {
    final created = await showModalBottomSheet<ChatV1ChatItem>(
      context: context,
      isScrollControlled: true,
      backgroundColor: ChatV1Theme.secondary(context),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
      ),
      builder: (_) => ChatV1CreateGroupSheet(members: _ctrl.members),
    );
    if (created != null && mounted) {
      widget.onOpenChat(created);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_showOpeningSplash) {
      return const ChatV1OpeningSplash(
        subtitle: 'Loading your project conversations…',
      );
    }

    final channels = _apply(_ctrl.channels);
    final hubs = _apply([
      if (_ctrl.channels.isNotEmpty || _ctrl.allProjectTasks.isNotEmpty)
        _ctrl.tasksHub,
    ]);
    final custom = _apply(_ctrl.customGroups);
    final dms = _apply(_ctrl.dms);

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: ChatV1Theme.isDark(context)
          ? SystemUiOverlayStyle.light
          : SystemUiOverlayStyle.dark,
      child: Scaffold(
        backgroundColor: ChatV1Theme.bg(context),
        body: SafeArea(
          child: Column(
            children: [
              _header(context),
              Padding(
                padding: const EdgeInsets.fromLTRB(14, 4, 14, 8),
                child: Cv1SearchField(
                  controller: _search,
                  hint: 'Search',
                  onChanged: (v) => setState(() => _query = v.toLowerCase()),
                ),
              ),
              Cv1FilterChips(
                selected: _filter,
                onChanged: (f) => setState(() => _filter = f),
              ),
              const SizedBox(height: 4),
              Expanded(
                child: RefreshIndicator(
                  color: ChatV1Theme.accent,
                  onRefresh: _reload,
                  child: _ctrl.loading &&
                          _ctrl.channels.isEmpty &&
                          _ctrl.customGroups.isEmpty &&
                          _ctrl.dms.isEmpty
                      ? ListView(
                          physics: const AlwaysScrollableScrollPhysics(),
                          children: const [
                            SizedBox(height: 120),
                            Center(child: CircularProgressIndicator()),
                          ],
                        )
                      : _ctrl.error != null && _ctrl.channels.isEmpty
                          ? ListView(
                              physics: const AlwaysScrollableScrollPhysics(),
                              padding: const EdgeInsets.all(24),
                              children: [
                                const SizedBox(height: 80),
                                Icon(Icons.cloud_off_outlined,
                                    size: 42,
                                    color: ChatV1Theme.textMuted(context)),
                                const SizedBox(height: 12),
                                Text(
                                  _ctrl.error!,
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                    color: ChatV1Theme.textSecondary(context),
                                  ),
                                ),
                                const SizedBox(height: 16),
                                Center(
                                  child: TextButton(
                                    onPressed: _reload,
                                    child: const Text('Retry'),
                                  ),
                                ),
                              ],
                            )
                          : ListView(
                              physics: const BouncingScrollPhysics(
                                parent: AlwaysScrollableScrollPhysics(),
                              ),
                              children: [
                                if (_ctrl.salesSopId != null)
                                  Padding(
                                    padding: const EdgeInsets.fromLTRB(
                                        16, 4, 16, 8),
                                    child: Text(
                                      'Project SOP #${_ctrl.salesSopId}',
                                      style: TextStyle(
                                        color: ChatV1Theme.textMuted(context),
                                        fontSize: 12,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ),
                                if (channels.isNotEmpty) ...[
                                  const Cv1SectionHeader(label: 'Channels'),
                                  ...channels.map(_tile),
                                ],
                                if (hubs.isNotEmpty) ...[
                                  const Cv1SectionHeader(
                                      label: 'Task & workflow'),
                                  ...hubs.map(_tile),
                                ],
                                if (custom.isNotEmpty) ...[
                                  Padding(
                                    padding:
                                        const EdgeInsets.fromLTRB(16, 8, 16, 8),
                                    child: Divider(
                                        color: ChatV1Theme.border(context)),
                                  ),
                                  const Cv1SectionHeader(
                                      label: 'Custom groups'),
                                  ...custom.map(_tile),
                                ],
                                if (dms.isNotEmpty) ...[
                                  const Cv1SectionHeader(
                                      label: 'Direct messages'),
                                  ...dms.map(_tile),
                                ],
                                if (channels.isEmpty &&
                                    hubs.isEmpty &&
                                    custom.isEmpty &&
                                    dms.isEmpty)
                                  Padding(
                                    padding: const EdgeInsets.all(40),
                                    child: Center(
                                      child: Text(
                                        'No chats match your filter',
                                        style: TextStyle(
                                            color: ChatV1Theme.textMuted(
                                                context)),
                                      ),
                                    ),
                                  ),
                                const SizedBox(height: 88),
                              ],
                            ),
                ),
              ),
            ],
          ),
        ),
        floatingActionButton: FloatingActionButton(
          onPressed: _openCreateGroup,
          child: const Icon(Icons.group_add_rounded),
        ),
      ),
    );
  }

  Widget _tile(ChatV1ChatItem item) {
    return Cv1ChatTile(
      item: item,
      selected: _selected.contains(item.id),
      onTap: () {
        if (_selected.isNotEmpty) {
          setState(() {
            if (_selected.contains(item.id)) {
              _selected.remove(item.id);
            } else {
              _selected.add(item.id);
            }
          });
          return;
        }
        widget.onOpenChat(item);
      },
      onLongPress: () {
        setState(() {
          if (_selected.contains(item.id)) {
            _selected.remove(item.id);
          } else {
            _selected.add(item.id);
          }
        });
      },
      onPin: () =>
          _updateItem(item.id, (e) => e.copyWith(isPinned: !e.isPinned)),
      onMute: () =>
          _updateItem(item.id, (e) => e.copyWith(isMuted: !e.isMuted)),
      onMarkRead: () => _updateItem(item.id, (e) => e.copyWith(unread: 0)),
    );
  }

  Widget _header(BuildContext context) {
    final selecting = _selected.isNotEmpty;
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 4, 4, 0),
      child: Row(
        children: [
          IconButton(
            onPressed: () {
              if (selecting) {
                setState(() => _selected.clear());
              } else {
                Navigator.of(context).maybePop();
              }
            },
            icon: Icon(
              selecting ? Icons.close_rounded : Icons.arrow_back_rounded,
              color: ChatV1Theme.text(context),
            ),
          ),
          Expanded(
            child: Text(
              selecting ? '${_selected.length} selected' : 'Chats',
              style: TextStyle(
                color: ChatV1Theme.text(context),
                fontSize: 22,
                fontWeight: FontWeight.w800,
                letterSpacing: -0.4,
              ),
            ),
          ),
          IconButton(
            onPressed: widget.onOpenSearch,
            icon: Icon(Icons.search_rounded, color: ChatV1Theme.text(context)),
          ),
          IconButton(
            onPressed: widget.onToggleTheme,
            icon: Icon(
              widget.darkMode
                  ? Icons.light_mode_outlined
                  : Icons.dark_mode_outlined,
              color: ChatV1Theme.text(context),
            ),
          ),
          PopupMenuButton<String>(
            icon: Icon(Icons.more_vert_rounded,
                color: ChatV1Theme.text(context)),
            color: ChatV1Theme.card(context),
            onSelected: (v) {
              if (v == 'new') _openCreateGroup();
            },
            itemBuilder: (_) => const [
              PopupMenuItem(value: 'new', child: Text('New group')),
            ],
          ),
        ],
      ),
    );
  }
}
