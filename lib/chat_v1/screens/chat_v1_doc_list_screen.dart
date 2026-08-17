import 'package:flutter/material.dart';

import '../chat_v1_controller.dart';
import '../chat_v1_doc_store.dart';
import '../chat_v1_models.dart';
import '../chat_v1_theme.dart';
import '../chat_v1_utils.dart';
import '../widgets/chat_v1_common.dart';
import 'chat_v1_create_doc_sheet.dart';
import 'chat_v1_doc_thread_screen.dart';

/// Difference of Cost list — opened from "Update and Doc" channel.
class ChatV1DocListScreen extends StatefulWidget {
  final String? salesSopId;

  const ChatV1DocListScreen({super.key, this.salesSopId});

  @override
  State<ChatV1DocListScreen> createState() => _ChatV1DocListScreenState();
}

class _ChatV1DocListScreenState extends State<ChatV1DocListScreen> {
  final _search = TextEditingController();
  final _store = ChatV1DocStore.instance;
  List<ChatV1DocRequest> _docs = [];
  String _query = '';
  bool _loading = true;
  String? _error;

  String? get _sopId =>
      widget.salesSopId ?? ChatV1Controller.instance.salesSopId;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _reload() async {
    final sop = _sopId;
    if (sop == null || sop.isEmpty) {
      setState(() {
        _docs = [];
        _loading = false;
        _error = null;
      });
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final docs = await _store.list(sop);
      if (!mounted) return;
      setState(() {
        _docs = docs;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = e.toString().replaceFirst('Exception: ', '');
      });
    }
  }

  List<ChatV1DocRequest> get _filtered {
    final q = _query.trim().toLowerCase();
    if (q.isEmpty) return _docs;
    return _docs.where((d) {
      return d.description.toLowerCase().contains(q) ||
          (d.pdfName ?? '').toLowerCase().contains(q) ||
          d.createdBy.toLowerCase().contains(q) ||
          d.statusLabel.toLowerCase().contains(q) ||
          d.amount.toString().contains(q) ||
          ChatV1Utils.formatInr(d.amount).toLowerCase().contains(q);
    }).toList();
  }

  Future<void> _openCreate() async {
    final sop = _sopId;
    if (sop == null || sop.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Select a project first')),
      );
      return;
    }
    final created = await showModalBottomSheet<ChatV1DocRequest>(
      context: context,
      isScrollControlled: true,
      backgroundColor: ChatV1Theme.card(context),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
      ),
      builder: (_) => ChatV1CreateDocSheet(salesSopId: sop),
    );
    if (created == null || !mounted) return;
    await _reload();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Difference of Cost submitted for approval'),
      ),
    );
    await _openDoc(created);
  }

  Future<void> _openDoc(ChatV1DocRequest doc) async {
    final sop = _sopId;
    if (sop == null) return;
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ChatV1DocThreadScreen(
          salesSopId: sop,
          docId: doc.id,
        ),
      ),
    );
    await _reload();
  }

  Color _statusColor(ChatV1DocStatus s) {
    switch (s) {
      case ChatV1DocStatus.pending:
        return ChatV1Theme.pending;
      case ChatV1DocStatus.approved:
        return ChatV1Theme.completed;
      case ChatV1DocStatus.rejected:
        return ChatV1Theme.rejected;
    }
  }

  @override
  Widget build(BuildContext context) {
    final docs = _filtered;
    return Scaffold(
      backgroundColor: ChatV1Theme.bg(context),
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Difference of Cost'),
            Text(
              'All submitted Difference of Cost requests',
              style: TextStyle(
                color: ChatV1Theme.textMuted(context),
                fontSize: 12,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
        actions: [
          TextButton.icon(
            onPressed: _openCreate,
            icon: const Icon(Icons.add_rounded, size: 18),
            label: const Text('Create DOC'),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _openCreate,
        backgroundColor: ChatV1Theme.accent,
        foregroundColor: Colors.white,
        icon: const Icon(Icons.add_rounded),
        label: const Text('Create DOC'),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 8, 14, 8),
            child: Cv1SearchField(
              controller: _search,
              hint: 'Search DOC requests',
              onChanged: (v) => setState(() => _query = v),
            ),
          ),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 0, 14, 8),
              child: Text(
                _error!,
                style: const TextStyle(
                  color: ChatV1Theme.rejected,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : docs.isEmpty
                    ? _empty(context)
                    : RefreshIndicator(
                        onRefresh: _reload,
                        child: ListView.builder(
                          physics: const AlwaysScrollableScrollPhysics(
                            parent: BouncingScrollPhysics(),
                          ),
                          padding: const EdgeInsets.fromLTRB(14, 0, 14, 88),
                          itemCount: docs.length,
                          itemBuilder: (_, i) => Padding(
                            padding: const EdgeInsets.only(bottom: 10),
                            child: _card(context, docs[i]),
                          ),
                        ),
                      ),
          ),
        ],
      ),
    );
  }

  Widget _empty(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.description_outlined,
              size: 56,
              color: ChatV1Theme.textMuted(context),
            ),
            const SizedBox(height: 14),
            Text(
              'Submit a Difference of Cost request to start a discussion thread.',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: ChatV1Theme.textSecondary(context),
                fontSize: 14.5,
                height: 1.4,
              ),
            ),
            const SizedBox(height: 18),
            FilledButton.icon(
              onPressed: _openCreate,
              icon: const Icon(Icons.add_rounded),
              label: const Text('Create DOC'),
              style: FilledButton.styleFrom(
                backgroundColor: ChatV1Theme.accent,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _card(BuildContext context, ChatV1DocRequest doc) {
    final statusColor = _statusColor(doc.status);
    return Container(
      decoration: BoxDecoration(
        color: ChatV1Theme.card(context),
        borderRadius: BorderRadius.circular(ChatV1Theme.rLg),
        border: Border.all(color: ChatV1Theme.border(context)),
        boxShadow: ChatV1Theme.shadow(context),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(ChatV1Theme.rLg),
          onTap: () => _openDoc(doc),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 42,
                  height: 42,
                  decoration: BoxDecoration(
                    color: const Color(0xFF0EA5E9).withValues(alpha: 0.14),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(
                    Icons.picture_as_pdf_rounded,
                    color: Color(0xFF0EA5E9),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              doc.description,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: ChatV1Theme.text(context),
                                fontWeight: FontWeight.w800,
                                fontSize: 15,
                              ),
                            ),
                          ),
                          if (doc.unread)
                            Container(
                              width: 8,
                              height: 8,
                              margin: const EdgeInsets.only(left: 8, top: 4),
                              decoration: const BoxDecoration(
                                color: ChatV1Theme.unread,
                                shape: BoxShape.circle,
                              ),
                            ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Text(
                        ChatV1Utils.formatInr(doc.amount),
                        style: const TextStyle(
                          color: Color(0xFF0EA5E9),
                          fontWeight: FontWeight.w800,
                          fontSize: 14.5,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        'Created by ${doc.createdBy} · ${ChatV1Utils.timeAgo(doc.updatedAt)}',
                        style: TextStyle(
                          color: ChatV1Theme.textMuted(context),
                          fontSize: 12,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Cv1Badge(
                            label: doc.statusLabel,
                            color: statusColor,
                          ),
                          const SizedBox(width: 8),
                          Text(
                            '${doc.messageCount} Message${doc.messageCount == 1 ? '' : 's'}',
                            style: TextStyle(
                              color: ChatV1Theme.textSecondary(context),
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
