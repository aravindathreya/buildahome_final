import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../chat_v1_controller.dart';
import '../chat_v1_mapper.dart';
import '../chat_v1_models.dart';
import '../chat_v1_theme.dart';
import '../widgets/chat_v1_chat_tile.dart';
import '../widgets/chat_v1_common.dart';

class ChatV1HomeScreen extends StatefulWidget {
  final ValueChanged<ChatV1ChatItem> onOpenChat;
  final VoidCallback onOpenSearch;
  final VoidCallback? onBack;
  final String? salesSopId;

  /// Conversation row to open once this project's chat list has loaded.
  final Map<String, dynamic>? openConversation;

  const ChatV1HomeScreen({
    super.key,
    required this.onOpenChat,
    required this.onOpenSearch,
    this.onBack,
    this.salesSopId,
    this.openConversation,
  });

  @override
  State<ChatV1HomeScreen> createState() => _ChatV1HomeScreenState();
}

class _ChatV1HomeScreenState extends State<ChatV1HomeScreen> {
  final _search = TextEditingController();
  final _ctrl = ChatV1Controller.instance;
  String _query = '';
  Timer? _searchDebounce;
  ChatV1Filter _filter = ChatV1Filter.all;
  final Set<String> _selected = {};
  bool _openedTarget = false;

  @override
  void initState() {
    super.initState();
    _ctrl.addListener(_onCtrl);
    _reload();
  }

  @override
  void dispose() {
    _searchDebounce?.cancel();
    _ctrl.removeListener(_onCtrl);
    _search.dispose();
    super.dispose();
  }

  void _onCtrl() {
    if (!mounted) return;
    setState(() {});
    _openTargetChat();
  }

  /// Lands inside the unread conversation after the project chat shell loads.
  void _openTargetChat() {
    final raw = widget.openConversation;
    if (raw == null || _openedTarget || _ctrl.loading) return;
    final id = (raw['id'] ?? raw['conversation_id'] ?? '').toString().trim();
    if (id.isEmpty) return;
    _openedTarget = true;
    final item = _ctrl.findChatById(id) ??
        ChatV1Mapper.conversationToChatItem(raw);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      widget.onOpenChat(item);
    });
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

  @override
  Widget build(BuildContext context) {
    final channels = _apply(_ctrl.channels);
    final hubs = _apply([
      if (_ctrl.channels.isNotEmpty || _ctrl.allProjectTasks.isNotEmpty)
        _ctrl.tasksHub,
    ]);
    final custom = _apply(_ctrl.customGroups);
    final dms = _apply(_ctrl.dms);
    final chatRows = _chatHomeRows(
      channels: channels,
      hubs: hubs,
      custom: custom,
      dms: dms,
    );

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
                  onChanged: (v) {
                    _searchDebounce?.cancel();
                    _searchDebounce = Timer(const Duration(milliseconds: 140), () {
                      if (!mounted) return;
                      setState(() => _query = v.toLowerCase());
                    });
                  },
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
                          : ListView.builder(
                              physics: const BouncingScrollPhysics(
                                parent: AlwaysScrollableScrollPhysics(),
                              ),
                              itemCount: chatRows.length,
                              itemBuilder: (context, index) {
                                return _buildChatHomeRow(context, chatRows[index]);
                              },
                            ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _tile(ChatV1ChatItem item) {
    return RepaintBoundary(
      child: Cv1ChatTile(
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
      onPin: () => _ctrl.setConversationFlag(
        item.id,
        pinned: !item.isPinned,
      ),
      onMute: () => _ctrl.setConversationFlag(
        item.id,
        muted: !item.isMuted,
      ),
      onMarkRead: () => _updateItem(item.id, (e) => e.copyWith(unread: 0)),
    ),
    );
  }

  List<_Cv1HomeRow> _chatHomeRows({
    required List<ChatV1ChatItem> channels,
    required List<ChatV1ChatItem> hubs,
    required List<ChatV1ChatItem> custom,
    required List<ChatV1ChatItem> dms,
  }) {
    final rows = <_Cv1HomeRow>[];
    if (_ctrl.salesSopId != null) {
      rows.add(_Cv1HomeRow.sop('Project SOP #${_ctrl.salesSopId}'));
    }
    if (channels.isNotEmpty) {
      rows.add(const _Cv1HomeRow.header('Channels'));
      rows.addAll(channels.map(_Cv1HomeRow.tile));
    }
    if (hubs.isNotEmpty) {
      rows.add(const _Cv1HomeRow.header('Task & workflow'));
      rows.addAll(hubs.map(_Cv1HomeRow.tile));
    }
    if (custom.isNotEmpty) {
      rows.add(const _Cv1HomeRow.divider());
      rows.add(const _Cv1HomeRow.header('Custom groups'));
      rows.addAll(custom.map(_Cv1HomeRow.tile));
    }
    if (dms.isNotEmpty) {
      rows.add(const _Cv1HomeRow.header('Direct messages'));
      rows.addAll(dms.map(_Cv1HomeRow.tile));
    }
    if (channels.isEmpty && hubs.isEmpty && custom.isEmpty && dms.isEmpty) {
      rows.add(const _Cv1HomeRow.empty());
    }
    rows.add(const _Cv1HomeRow.spacer());
    return rows;
  }

  Widget _buildChatHomeRow(BuildContext context, _Cv1HomeRow row) {
    switch (row.kind) {
      case 3:
        return Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
          child: Text(
            row.label ?? '',
            style: TextStyle(
              color: ChatV1Theme.textMuted(context),
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
        );
      case 0:
        return Cv1SectionHeader(label: row.label ?? '');
      case 2:
        return Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
          child: Divider(color: ChatV1Theme.border(context)),
        );
      case 1:
        return _tile(row.item!);
      case 4:
        return Padding(
          padding: const EdgeInsets.all(40),
          child: Center(
            child: Text(
              'No chats match your filter',
              style: TextStyle(color: ChatV1Theme.textMuted(context)),
            ),
          ),
        );
      default:
        return const SizedBox(height: 88);
    }
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
              } else if (widget.onBack != null) {
                widget.onBack!();
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
        ],
      ),
    );
  }
}

class _Cv1HomeRow {
  const _Cv1HomeRow._(this.kind, {this.item, this.label});
  const _Cv1HomeRow.header(String label) : this._(0, label: label);
  const _Cv1HomeRow.tile(ChatV1ChatItem item) : this._(1, item: item);
  const _Cv1HomeRow.divider() : this._(2);
  const _Cv1HomeRow.sop(String label) : this._(3, label: label);
  const _Cv1HomeRow.empty() : this._(4);
  const _Cv1HomeRow.spacer() : this._(5);

  final int kind;
  final ChatV1ChatItem? item;
  final String? label;
}
