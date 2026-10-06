import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../services/data_provider.dart';
import '../chat_v1_api.dart';
import '../chat_v1_controller.dart';
import '../chat_v1_doc_clarification.dart';
import '../chat_v1_doc_store.dart';
import '../chat_v1_models.dart';
import '../chat_v1_theme.dart';
import '../chat_v1_utils.dart';
import '../widgets/chat_v1_common.dart';

class ChatV1DocThreadScreen extends StatefulWidget {
  final String salesSopId;
  final String docId;

  const ChatV1DocThreadScreen({
    super.key,
    required this.salesSopId,
    required this.docId,
  });

  @override
  State<ChatV1DocThreadScreen> createState() => _ChatV1DocThreadScreenState();
}

class _ChatV1DocThreadScreenState extends State<ChatV1DocThreadScreen> {
  final _composer = TextEditingController();
  final _scroll = ScrollController();
  final _stickKey = GlobalKey<Cv1StickToBottomState>();
  final _store = ChatV1DocStore.instance;
  final _api = ChatV1Api.instance;

  ChatV1DocRequest? _doc;
  bool _loading = true;
  bool _sending = false;
  bool _asking = false;
  bool _isClient =
      (DataProvider().currentRole ?? '').trim().toLowerCase() == 'client';
  String? _error;

  @override
  void initState() {
    super.initState();
    _resolveRole();
    _load();
  }

  Future<void> _resolveRole() async {
    final cached = (DataProvider().currentRole ?? '').trim();
    if (cached.isNotEmpty) {
      if (!mounted) return;
      setState(() => _isClient = cached.toLowerCase() == 'client');
      return;
    }
    final prefs = await SharedPreferences.getInstance();
    final role = (prefs.getString('role') ?? '').trim().toLowerCase();
    if (!mounted) return;
    setState(() => _isClient = role == 'client');
  }

  @override
  void dispose() {
    _composer.dispose();
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final doc = await _store.getById(widget.docId);
      if (!mounted) return;
      setState(() {
        _doc = doc;
        _loading = false;
      });
      WidgetsBinding.instance.addPostFrameCallback((_) {
        final pin = _stickKey.currentState;
        if (pin != null) {
          pin.jumpToEnd();
          return;
        }
        if (_scroll.hasClients) {
          _scroll.jumpTo(_scroll.position.maxScrollExtent);
        }
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = e.toString().replaceFirst('Exception: ', '');
      });
    }
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

  Future<void> _openPdf() async {
    final path = _doc?.pdfUrl;
    if (path == null || path.isEmpty) return;
    final uri = Uri.parse(path);
    final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!ok && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not open PDF')),
      );
    }
  }

  Future<void> _approve() async {
    final doc = _doc;
    if (doc == null || doc.status != ChatV1DocStatus.pending) return;
    if (!doc.canApprove) return;
    try {
      final updated = await _store.approve(doc.id);
      if (!mounted) return;
      setState(() => _doc = updated);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Difference of Cost approved')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.toString().replaceFirst('Exception: ', ''))),
      );
    }
  }

  Future<void> _askClarification() async {
    final doc = _doc;
    if (doc == null || !_isClient || _asking) return;
    if (doc.status != ChatV1DocStatus.pending) return;
    setState(() => _asking = true);
    try {
      final sop = (doc.salesSopId ?? widget.salesSopId).trim();
      final ctrl = ChatV1Controller.instance;
      var people = <DocClarificationPerson>[];
      if (sop.isNotEmpty &&
          ctrl.salesSopId == sop &&
          ctrl.members.isNotEmpty) {
        people = [
          for (final member in ctrl.members)
            DocClarificationPerson(
              userId: member.id,
              name: member.name,
              role: member.role,
            ),
        ];
      }
      if (buildDocClarificationDraft(people: people, description: doc.description)
              .userIds
              .isEmpty &&
          sop.isNotEmpty) {
        final rows = await _api.listMembers(sop);
        people = docClarificationPeopleFromRows(rows);
      }
      final draft = buildDocClarificationDraft(
        people: people,
        description: doc.description,
      );
      if (!draft.hasTags) {
        throw ChatV1ApiException(
          'Could not find the Project Coordinator or Assistant Project Coordinator for this project.',
        );
      }
      final msg = await _store.sendMessage(
        doc.id,
        body: draft.body,
        mentionedUserIds: draft.userIds,
      );
      if (!mounted) return;
      setState(() {
        final msgs = [...doc.messages, msg];
        _doc = doc.copyWith(
          messages: msgs,
          messageCount: msgs.length,
          updatedAt: DateTime.now(),
        );
        _asking = false;
      });
      WidgetsBinding.instance.addPostFrameCallback((_) {
        final pin = _stickKey.currentState;
        if (pin != null) {
          pin.jumpToEnd(animate: true);
          return;
        }
        if (_scroll.hasClients) {
          _scroll.animateTo(
            _scroll.position.maxScrollExtent,
            duration: const Duration(milliseconds: 220),
            curve: Curves.easeOut,
          );
        }
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Asked the Project Coordinator and Assistant Project Coordinator for clarification',
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _asking = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.toString().replaceFirst('Exception: ', ''))),
      );
    }
  }

  Future<void> _send({List<int>? fileBytes, String? fileName}) async {
    final text = _composer.text.trim();
    final doc = _doc;
    final hasFile = fileBytes != null && fileName != null;
    if ((text.isEmpty && !hasFile) || doc == null || _sending) return;
    setState(() => _sending = true);
    try {
      final body = text.isNotEmpty
          ? text
          : (hasFile ? 'Uploaded: $fileName' : '');
      List<Map<String, dynamic>>? attachments;
      if (hasFile) {
        final upload = await _api.uploadDiscussionAttachment(
          bytes: fileBytes,
          fileName: fileName,
        );
        final url =
            (upload?['url'] ?? upload?['storage_path'] ?? '').toString();
        final name =
            (upload?['filename'] ?? upload?['file_name'] ?? fileName).toString();
        if (url.isEmpty) throw ChatV1ApiException('File upload failed');
        final contentType = name.toLowerCase().endsWith('.pdf')
            ? 'application/pdf'
            : (name.toLowerCase().endsWith('.png')
                ? 'image/png'
                : (name.toLowerCase().endsWith('.jpg') ||
                        name.toLowerCase().endsWith('.jpeg')
                    ? 'image/jpeg'
                    : 'application/octet-stream'));
        attachments = [
          {
            'file_name': name,
            'storage_path': url,
            'content_type': contentType,
            'file_size': fileBytes.length,
          },
        ];
      }
      final msg = await _store.sendMessage(
        doc.id,
        body: body,
        attachments: attachments,
      );
      if (!mounted) return;
      _composer.clear();
      setState(() {
        final msgs = [...doc.messages, msg];
        _doc = doc.copyWith(
          messages: msgs,
          messageCount: msgs.length,
          updatedAt: DateTime.now(),
        );
        _sending = false;
      });
      WidgetsBinding.instance.addPostFrameCallback((_) {
        final pin = _stickKey.currentState;
        if (pin != null) {
          pin.jumpToEnd(animate: true);
          return;
        }
        if (_scroll.hasClients) {
          _scroll.animateTo(
            _scroll.position.maxScrollExtent,
            duration: const Duration(milliseconds: 220),
            curve: Curves.easeOut,
          );
        }
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _sending = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.toString().replaceFirst('Exception: ', ''))),
      );
    }
  }

  Future<void> _pickAttachment() async {
    final result = await FilePicker.platform.pickFiles(withData: true);
    if (result == null || result.files.isEmpty) return;
    final f = result.files.first;
    if (f.bytes == null) return;
    await _send(fileBytes: f.bytes, fileName: f.name);
  }

  @override
  Widget build(BuildContext context) {
    final doc = _doc;
    return Scaffold(
      backgroundColor: ChatV1Theme.chatBg(context),
      appBar: AppBar(
        title: doc == null
            ? const Text('Difference of Cost')
            : Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    doc.description,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  Text(
                    'Difference of Cost · ${doc.statusLabel}',
                    style: TextStyle(
                      color: ChatV1Theme.textMuted(context),
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
        actions: [
          if (doc != null)
            Padding(
              padding: const EdgeInsets.only(right: 12),
              child: Center(
                child: Cv1Badge(
                  label: doc.statusLabel,
                  color: _statusColor(doc.status),
                ),
              ),
            ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          _error!,
                          textAlign: TextAlign.center,
                          style: const TextStyle(color: ChatV1Theme.rejected),
                        ),
                        const SizedBox(height: 12),
                        FilledButton(
                          onPressed: _load,
                          child: const Text('Retry'),
                        ),
                      ],
                    ),
                  ),
                )
              : doc == null
                  ? Center(
                      child: Text(
                        'DOC not found',
                        style:
                            TextStyle(color: ChatV1Theme.textMuted(context)),
                      ),
                    )
                  : Column(
                      children: [
                        Expanded(
                          child: RefreshIndicator(
                            onRefresh: _load,
                            child: Cv1StickToBottom(
                              key: _stickKey,
                              controller: _scroll,
                              child: ListView(
                              controller: _scroll,
                              physics: const AlwaysScrollableScrollPhysics(),
                              padding:
                                  const EdgeInsets.fromLTRB(14, 12, 14, 12),
                              children: [
                                _summaryCard(context, doc),
                                const SizedBox(height: 16),
                                if (doc.messages.isEmpty)
                                  Padding(
                                    padding: const EdgeInsets.symmetric(
                                        vertical: 24),
                                    child: Center(
                                      child: Text(
                                        'No discussion yet',
                                        style: TextStyle(
                                          color:
                                              ChatV1Theme.textMuted(context),
                                        ),
                                      ),
                                    ),
                                  )
                                else
                                  ...doc.messages.map(_bubble),
                              ],
                            ),
                            ),
                          ),
                        ),
                        _composerBar(context),
                      ],
                    ),
    );
  }

  Widget _summaryCard(BuildContext context, ChatV1DocRequest doc) {
    return Container(
      decoration: BoxDecoration(
        color: ChatV1Theme.card(context),
        borderRadius: BorderRadius.circular(ChatV1Theme.rLg),
        border: Border.all(color: ChatV1Theme.border(context)),
        boxShadow: ChatV1Theme.shadow(context),
      ),
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Cv1Badge(
            label: 'Difference of Cost',
            color: Color(0xFF0EA5E9),
          ),
          const SizedBox(height: 12),
          _row(context, 'Description', doc.description),
          _row(
            context,
            'Amount',
            ChatV1Utils.formatInr(doc.amount),
            highlight: true,
          ),
          if (doc.pdfName != null &&
              doc.pdfName!.isNotEmpty &&
              (doc.pdfUrl?.isNotEmpty ?? false))
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Supporting PDF',
                    style: TextStyle(
                      color: ChatV1Theme.textMuted(context),
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 4),
                  InkWell(
                    onTap: _openPdf,
                    child: Row(
                      children: [
                        const Icon(Icons.picture_as_pdf_rounded,
                            color: Color(0xFF0EA5E9), size: 18),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            doc.pdfName!,
                            style: const TextStyle(
                              color: Color(0xFF0EA5E9),
                              fontWeight: FontWeight.w700,
                              decoration: TextDecoration.underline,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          if (doc.notes.isNotEmpty) _row(context, 'Notes', doc.notes),
          _row(context, 'Submitted By', doc.createdBy),
          _row(
            context,
            'Submitted On',
            ChatV1Utils.formatAbsolute(doc.createdAt),
          ),
          const SizedBox(height: 8),
          if (doc.status == ChatV1DocStatus.pending && doc.canApprove)
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: _approve,
                style: FilledButton.styleFrom(
                  backgroundColor: ChatV1Theme.completed,
                  minimumSize: const Size.fromHeight(44),
                ),
                child: const Text('Approve'),
              ),
            )
          else if (doc.status == ChatV1DocStatus.approved)
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: null,
                style: FilledButton.styleFrom(
                  minimumSize: const Size.fromHeight(44),
                ),
                child: const Text('Approved'),
              ),
            ),
          if (_isClient && doc.status == ChatV1DocStatus.pending) ...[
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton(
                onPressed: _asking ? null : _askClarification,
                style: OutlinedButton.styleFrom(
                  foregroundColor: const Color(0xFF0EA5E9),
                  side: const BorderSide(color: Color(0xFF0EA5E9)),
                  minimumSize: const Size.fromHeight(44),
                ),
                child: Text(
                  _asking ? 'Sending…' : 'Ask for clarification',
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _row(
    BuildContext context,
    String label,
    String value, {
    bool highlight = false,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: TextStyle(
              color: ChatV1Theme.textMuted(context),
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            value,
            style: TextStyle(
              color: highlight
                  ? const Color(0xFF0EA5E9)
                  : ChatV1Theme.text(context),
              fontWeight: highlight ? FontWeight.w800 : FontWeight.w600,
              fontSize: highlight ? 16 : 14,
            ),
          ),
        ],
      ),
    );
  }

  Widget _messageBody(BuildContext context, String body) {
    final base = TextStyle(
      color: ChatV1Theme.text(context),
      fontSize: 14.5,
      height: 1.35,
    );
    final mention = RegExp(r'@([^\s@.,!?;:]+)');
    if (!mention.hasMatch(body)) return Text(body, style: base);
    final mentionStyle = base.copyWith(
      color: const Color(0xFF0B5CAB),
      fontWeight: FontWeight.w700,
    );
    final spans = <InlineSpan>[];
    var index = 0;
    for (final match in mention.allMatches(body)) {
      if (match.start > index) {
        spans.add(TextSpan(text: body.substring(index, match.start)));
      }
      spans.add(TextSpan(text: match.group(0), style: mentionStyle));
      index = match.end;
    }
    if (index < body.length) {
      spans.add(TextSpan(text: body.substring(index)));
    }
    return Text.rich(TextSpan(style: base, children: spans));
  }

  Widget _bubble(ChatV1DocMessage msg) {
    final mine = msg.own;
    return Align(
      alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * 0.78,
        ),
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
        decoration: BoxDecoration(
          color: mine
              ? ChatV1Theme.bubbleMe(context)
              : ChatV1Theme.bubbleOther(context),
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(14),
            topRight: const Radius.circular(14),
            bottomLeft: Radius.circular(mine ? 14 : 4),
            bottomRight: Radius.circular(mine ? 4 : 14),
          ),
          border:
              mine ? null : Border.all(color: ChatV1Theme.border(context)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (!mine)
              Padding(
                padding: const EdgeInsets.only(bottom: 2),
                child: Text(
                  msg.author,
                  style: TextStyle(
                    color: ChatV1Theme.accent,
                    fontWeight: FontWeight.w700,
                    fontSize: 12,
                  ),
                ),
              ),
            _messageBody(context, msg.body),
            if (msg.attachments.isNotEmpty) ...[
              const SizedBox(height: 6),
              ...msg.attachments.map((att) {
                final isImage = att.isImage;
                if (isImage && att.storagePath.isNotEmpty) {
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 4),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: SizeChangedLayoutNotifier(
                        child: Image.network(
                          att.storagePath,
                          width: 180,
                          cacheWidth: 360,
                          cacheHeight: 360,
                          fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) => Text(att.fileName),
                        ),
                      ),
                    ),
                  );
                }
                return InkWell(
                  onTap: () {
                    if (att.storagePath.isEmpty) return;
                    launchUrl(
                      Uri.parse(att.storagePath),
                      mode: LaunchMode.externalApplication,
                    );
                  },
                  child: Padding(
                    padding: const EdgeInsets.only(bottom: 4),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.attach_file_rounded, size: 16),
                        const SizedBox(width: 4),
                        Flexible(
                          child: Text(
                            att.fileName,
                            style: const TextStyle(
                              decoration: TextDecoration.underline,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              }),
            ],
            const SizedBox(height: 4),
            Text(
              ChatV1Utils.clock(msg.createdAt),
              style: TextStyle(
                color: ChatV1Theme.textMuted(context),
                fontSize: 11,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _composerBar(BuildContext context) {
    return SafeArea(
      top: false,
      child: Container(
        padding: const EdgeInsets.fromLTRB(10, 8, 10, 10),
        decoration: BoxDecoration(
          color: ChatV1Theme.secondary(context),
          border: Border(
            top: BorderSide(color: ChatV1Theme.border(context)),
          ),
        ),
        child: Row(
          children: [
            IconButton(
              onPressed: _sending ? null : _pickAttachment,
              icon: Icon(
                Icons.attach_file_rounded,
                color: ChatV1Theme.textSecondary(context),
              ),
            ),
            Expanded(
              child: TextField(
                controller: _composer,
                minLines: 1,
                maxLines: 4,
                textInputAction: TextInputAction.send,
                onSubmitted: (_) => _send(),
                decoration: InputDecoration(
                  hintText: 'Message…',
                  filled: true,
                  fillColor: ChatV1Theme.card(context),
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 10,
                  ),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(22),
                    borderSide: BorderSide(color: ChatV1Theme.border(context)),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(22),
                    borderSide: BorderSide(color: ChatV1Theme.border(context)),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 8),
            IconButton.filled(
              onPressed: _sending ? null : () => _send(),
              style: IconButton.styleFrom(
                backgroundColor: ChatV1Theme.accent,
                foregroundColor: Colors.white,
              ),
              icon: const Icon(Icons.send_rounded),
            ),
          ],
        ),
      ),
    );
  }
}
