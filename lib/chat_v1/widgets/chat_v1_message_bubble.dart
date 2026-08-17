import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../chat_v1_models.dart';
import '../chat_v1_theme.dart';
import '../chat_v1_utils.dart';
import 'chat_v1_common.dart';

class Cv1MessageBubble extends StatelessWidget {
  final ChatV1Message message;
  final bool showAuthor;
  final bool highlighted;
  final VoidCallback? onLongPress;
  final VoidCallback? onReplyTap;
  final ValueChanged<String>? onReactionTap;
  final GlobalKey? messageKey;

  const Cv1MessageBubble({
    super.key,
    required this.message,
    this.showAuthor = true,
    this.highlighted = false,
    this.onLongPress,
    this.onReplyTap,
    this.onReactionTap,
    this.messageKey,
  });

  @override
  Widget build(BuildContext context) {
    if (message.type == ChatV1MsgType.system ||
        message.type == ChatV1MsgType.pinned) {
      return _system(context);
    }

    final mine = message.isMine;
    return Padding(
      key: messageKey,
      padding: EdgeInsets.only(
        left: mine ? 52 : 10,
        right: mine ? 10 : 52,
        bottom: 4,
        top: 2,
      ),
      child: Align(
        alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
        child: GestureDetector(
          onLongPress: message.isDeleted ? null : onLongPress,
          child: Column(
            crossAxisAlignment:
                mine ? CrossAxisAlignment.end : CrossAxisAlignment.start,
            children: [
              Container(
                constraints: BoxConstraints(
                  maxWidth: MediaQuery.of(context).size.width * 0.8,
                ),
                padding: const EdgeInsets.fromLTRB(10, 7, 10, 5),
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
                  boxShadow: ChatV1Theme.shadow(context),
                  border: highlighted
                      ? Border.all(color: ChatV1Theme.accent, width: 1.5)
                      : mine
                          ? null
                          : Border.all(
                              color: ChatV1Theme.border(context)
                                  .withValues(alpha: 0.6)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (!mine && showAuthor)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 3),
                        child: Text(
                          message.authorName,
                          style: TextStyle(
                            color: message.authorColor,
                            fontSize: 12.5,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    if (message.replyPreview != null) _reply(context),
                    if (message.isDeleted)
                      Text(
                        'This message was deleted',
                        style: TextStyle(
                          color: ChatV1Theme.textMuted(context),
                          fontSize: 14,
                          fontStyle: FontStyle.italic,
                        ),
                      )
                    else if (message.attachments.isNotEmpty)
                      _attachments(context)
                    else
                      _body(context),
                    if (!message.isDeleted &&
                        message.attachments.isNotEmpty &&
                        message.body.trim().isNotEmpty &&
                        !message.body.trim().toLowerCase().startsWith('uploaded:')) ...[
                      const SizedBox(height: 6),
                      Text(
                        message.body,
                        style: TextStyle(
                          color: ChatV1Theme.text(context),
                          fontSize: 15,
                          height: 1.35,
                        ),
                      ),
                    ],
                    const SizedBox(height: 3),
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (message.isPinned) ...[
                          Icon(
                            Icons.push_pin_rounded,
                            size: 12,
                            color: ChatV1Theme.textMuted(context),
                          ),
                          const SizedBox(width: 3),
                        ],
                        if (message.edited)
                          Text(
                            'edited  ',
                            style: TextStyle(
                              color: ChatV1Theme.textMuted(context),
                              fontSize: 10.5,
                              fontStyle: FontStyle.italic,
                            ),
                          ),
                        Text(
                          ChatV1Utils.clock(message.sentAt),
                          style: TextStyle(
                            color: ChatV1Theme.textMuted(context),
                            fontSize: 11,
                          ),
                        ),
                        if (mine) ...[
                          const SizedBox(width: 3),
                          Icon(
                            message.read
                                ? Icons.done_all_rounded
                                : Icons.done_rounded,
                            size: 15,
                            color: message.read
                                ? ChatV1Theme.readTick
                                : ChatV1Theme.textMuted(context),
                          ),
                        ],
                      ],
                    ),
                  ],
                ),
              ),
              if (message.reactions.isNotEmpty) ...[
                const SizedBox(height: 3),
                Wrap(
                  spacing: 4,
                  children: message.reactions
                      .map(
                        (r) => Material(
                          color: Colors.transparent,
                          child: InkWell(
                            borderRadius: BorderRadius.circular(999),
                            onTap: onReactionTap == null
                                ? null
                                : () => onReactionTap!(r.emoji),
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                color: ChatV1Theme.card(context),
                                borderRadius: BorderRadius.circular(999),
                                border: Border.all(
                                  color: r.mine
                                      ? ChatV1Theme.accent
                                      : ChatV1Theme.border(context),
                                ),
                              ),
                              child: Text('${r.emoji} ${r.count}',
                                  style: const TextStyle(fontSize: 11)),
                            ),
                          ),
                        ),
                      )
                      .toList(),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _reply(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onReplyTap,
        borderRadius: BorderRadius.circular(8),
        child: Container(
          width: double.infinity,
          margin: const EdgeInsets.only(bottom: 6),
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.06),
            borderRadius: BorderRadius.circular(8),
            border: const Border(
              left: BorderSide(color: ChatV1Theme.accent, width: 3),
            ),
          ),
          child: Text(
            message.replyPreview!,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: ChatV1Theme.textSecondary(context),
              fontSize: 12,
            ),
          ),
        ),
      ),
    );
  }

  Widget _system(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Center(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
          decoration: BoxDecoration(
            color: ChatV1Theme.card(context),
            borderRadius: BorderRadius.circular(8),
            boxShadow: ChatV1Theme.shadow(context),
          ),
          child: Text(
            message.body,
            style: TextStyle(
              color: ChatV1Theme.textSecondary(context),
              fontSize: 12,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
      ),
    );
  }

  Widget _attachments(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: message.attachments.map((att) {
        if (att.isImage &&
            (att.storagePath.isNotEmpty || att.previewBytes != null)) {
          return Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: _imageAttachment(context, att),
          );
        }
        return Padding(
          padding: const EdgeInsets.only(bottom: 6),
          child: _documentCard(context, att),
        );
      }).toList(),
    );
  }

  Widget _imageAttachment(BuildContext context, ChatV1Attachment att) {
    final url = ChatV1Utils.resolveMediaUrl(att.storagePath);
    final bytes = att.previewBytes;
    Widget image;
    if (bytes != null && bytes.isNotEmpty) {
      image = Image.memory(
        Uint8List.fromList(bytes),
        width: 240,
        fit: BoxFit.cover,
        gaplessPlayback: true,
      );
    } else {
      image = Image.network(
        url,
        width: 240,
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => _fileTile(
          context,
          name: att.fileName,
          meta: att.contentType,
          icon: Icons.broken_image_outlined,
          onTap: () => _openUrl(url),
        ),
        loadingBuilder: (context, child, progress) {
          if (progress == null) return child;
          return Container(
            width: 240,
            height: 160,
            alignment: Alignment.center,
            color: ChatV1Theme.bg(context),
            child: const SizedBox(
              width: 22,
              height: 22,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
          );
        },
      );
    }

    return ClipRRect(
      borderRadius: BorderRadius.circular(10),
      child: GestureDetector(
        onTap: () => _showImageViewer(context, att),
        child: image,
      ),
    );
  }

  void _showImageViewer(BuildContext context, ChatV1Attachment att) {
    final url = ChatV1Utils.resolveMediaUrl(att.storagePath);
    final bytes = att.previewBytes;
    Navigator.of(context).push(
      PageRouteBuilder(
        opaque: false,
        barrierColor: Colors.black.withValues(alpha: 0.92),
        pageBuilder: (_, __, ___) {
          return GestureDetector(
            onTap: () => Navigator.of(context).pop(),
            child: Scaffold(
              backgroundColor: Colors.transparent,
              appBar: AppBar(
                backgroundColor: Colors.black,
                foregroundColor: Colors.white,
                title: Text(
                  att.fileName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 15),
                ),
                actions: [
                  if (url.isNotEmpty)
                    IconButton(
                      tooltip: 'Open',
                      icon: const Icon(Icons.open_in_new_rounded),
                      onPressed: () => _openUrl(url),
                    ),
                ],
              ),
              body: Center(
                child: InteractiveViewer(
                  child: bytes != null && bytes.isNotEmpty
                      ? Image.memory(Uint8List.fromList(bytes))
                      : Image.network(
                          url,
                          errorBuilder: (_, __, ___) => const Icon(
                            Icons.broken_image_outlined,
                            color: Colors.white70,
                            size: 48,
                          ),
                        ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  /// WhatsApp-style document bubble with open / share actions.
  Widget _documentCard(BuildContext context, ChatV1Attachment att) {
    final url = ChatV1Utils.resolveMediaUrl(att.storagePath);
    final accent = att.isPdf ? ChatV1Theme.rejected : ChatV1Theme.mention;
    final meta = [
      att.displayExt,
      if (att.fileSize > 0) ChatV1Utils.formatBytes(att.fileSize),
    ].join(' · ');

    return Material(
      color: Colors.black.withValues(alpha: 0.05),
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => _showDocumentActions(context, att),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(10, 10, 8, 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 46,
                    height: 46,
                    decoration: BoxDecoration(
                      color: accent.withValues(alpha: 0.16),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(
                      att.isPdf
                          ? Icons.picture_as_pdf_rounded
                          : Icons.insert_drive_file_rounded,
                      color: accent,
                      size: 26,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          att.fileName,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: ChatV1Theme.text(context),
                            fontWeight: FontWeight.w700,
                            fontSize: 13.5,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          meta,
                          style: TextStyle(
                            color: ChatV1Theme.textSecondary(context),
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Icon(
                    Icons.chevron_right_rounded,
                    color: ChatV1Theme.textMuted(context),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Divider(
                height: 1,
                color: ChatV1Theme.border(context).withValues(alpha: 0.7),
              ),
              const SizedBox(height: 4),
              Row(
                children: [
                  Expanded(
                    child: TextButton.icon(
                      onPressed: url.isEmpty ? null : () => _openUrl(url),
                      icon: const Icon(Icons.open_in_new_rounded, size: 16),
                      label: const Text('Open'),
                      style: TextButton.styleFrom(
                        foregroundColor: ChatV1Theme.accent,
                        padding: const EdgeInsets.symmetric(vertical: 6),
                        textStyle: const TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 13,
                        ),
                      ),
                    ),
                  ),
                  Container(
                    width: 1,
                    height: 22,
                    color: ChatV1Theme.border(context),
                  ),
                  Expanded(
                    child: TextButton.icon(
                      onPressed: url.isEmpty
                          ? null
                          : () => _showDocumentActions(context, att),
                      icon: const Icon(Icons.more_horiz_rounded, size: 18),
                      label: const Text('More'),
                      style: TextButton.styleFrom(
                        foregroundColor: ChatV1Theme.textSecondary(context),
                        padding: const EdgeInsets.symmetric(vertical: 6),
                        textStyle: const TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 13,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _showDocumentActions(
    BuildContext context,
    ChatV1Attachment att,
  ) async {
    final url = ChatV1Utils.resolveMediaUrl(att.storagePath);
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: ChatV1Theme.secondary(context),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
      ),
      builder: (sheetContext) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(8, 10, 8, 12),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 36,
                  height: 4,
                  decoration: BoxDecoration(
                    color: ChatV1Theme.border(context),
                    borderRadius: BorderRadius.circular(99),
                  ),
                ),
                const SizedBox(height: 14),
                ListTile(
                  leading: Icon(
                    att.isPdf
                        ? Icons.picture_as_pdf_rounded
                        : Icons.insert_drive_file_rounded,
                    color: att.isPdf
                        ? ChatV1Theme.rejected
                        : ChatV1Theme.mention,
                  ),
                  title: Text(
                    att.fileName,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                  subtitle: Text(
                    [
                      att.displayExt,
                      if (att.fileSize > 0)
                        ChatV1Utils.formatBytes(att.fileSize),
                    ].join(' · '),
                  ),
                ),
                const Divider(height: 8),
                ListTile(
                  leading: const Icon(Icons.open_in_new_rounded),
                  title: const Text('Open'),
                  subtitle: const Text('Open with another app'),
                  enabled: url.isNotEmpty,
                  onTap: () {
                    Navigator.pop(sheetContext);
                    _openUrl(url);
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.language_rounded),
                  title: const Text('Open in browser'),
                  enabled: url.isNotEmpty,
                  onTap: () {
                    Navigator.pop(sheetContext);
                    _openUrl(url);
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.link_rounded),
                  title: const Text('Copy link'),
                  enabled: url.isNotEmpty,
                  onTap: () async {
                    Navigator.pop(sheetContext);
                    await Clipboard.setData(ClipboardData(text: url));
                    if (!context.mounted) return;
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Link copied')),
                    );
                  },
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _fileTile(
    BuildContext context, {
    required String name,
    required String meta,
    required IconData icon,
    VoidCallback? onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Row(
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: ChatV1Theme.accent.withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, color: ChatV1Theme.accent),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(name,
                    style: TextStyle(
                        color: ChatV1Theme.text(context),
                        fontWeight: FontWeight.w700,
                        fontSize: 13.5)),
                if (meta.isNotEmpty)
                  Text(meta,
                      style: TextStyle(
                          color: ChatV1Theme.textSecondary(context),
                          fontSize: 12)),
              ],
            ),
          ),
          Icon(Icons.open_in_new_rounded,
              size: 16, color: ChatV1Theme.textMuted(context)),
        ],
      ),
    );
  }

  Future<void> _openUrl(String url) async {
    final resolved = ChatV1Utils.resolveMediaUrl(url);
    final uri = Uri.tryParse(resolved);
    if (uri == null) return;
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  Widget _body(BuildContext context) {
    switch (message.type) {
      case ChatV1MsgType.pdf:
      case ChatV1MsgType.document:
        return _file(context);
      case ChatV1MsgType.image:
      case ChatV1MsgType.video:
        return _media(context);
      case ChatV1MsgType.approval:
      case ChatV1MsgType.workflow:
      case ChatV1MsgType.purchaseOrder:
      case ChatV1MsgType.indent:
        return _erpCard(context, Icons.fact_check_rounded, 'Approval');
      case ChatV1MsgType.differenceOfCost:
        return _erpCard(context, Icons.currency_rupee_rounded, 'DoC');
      case ChatV1MsgType.taskAssignment:
      case ChatV1MsgType.siteUpdate:
        return _erpCard(context, Icons.task_alt_rounded, 'Task');
      default:
        return Text(
          message.body,
          style: TextStyle(
            color: ChatV1Theme.text(context),
            fontSize: 15,
            height: 1.35,
          ),
        );
    }
  }

  Widget _file(BuildContext context) {
    final pdf = message.type == ChatV1MsgType.pdf;
    return Row(
      children: [
        Container(
          width: 42,
          height: 42,
          decoration: BoxDecoration(
            color: (pdf ? ChatV1Theme.rejected : ChatV1Theme.completed)
                .withValues(alpha: 0.14),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(
            pdf ? Icons.picture_as_pdf_rounded : Icons.insert_drive_file_rounded,
            color: pdf ? ChatV1Theme.rejected : ChatV1Theme.completed,
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(message.fileName ?? 'File',
                  style: TextStyle(
                      color: ChatV1Theme.text(context),
                      fontWeight: FontWeight.w700,
                      fontSize: 13.5)),
              Text(message.fileMeta ?? '',
                  style: TextStyle(
                      color: ChatV1Theme.textSecondary(context), fontSize: 12)),
            ],
          ),
        ),
      ],
    );
  }

  Widget _media(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          height: 140,
          width: double.infinity,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(10),
            gradient: LinearGradient(
              colors: [
                ChatV1Theme.accent.withValues(alpha: 0.35),
                ChatV1Theme.accent.withValues(alpha: 0.1),
              ],
            ),
          ),
          child: Icon(
            message.type == ChatV1MsgType.video
                ? Icons.play_circle_outline_rounded
                : Icons.image_rounded,
            color: Colors.white70,
            size: 40,
          ),
        ),
        const SizedBox(height: 6),
        Text(message.fileName ?? 'Media',
            style: TextStyle(
                color: ChatV1Theme.text(context),
                fontWeight: FontWeight.w600,
                fontSize: 13)),
      ],
    );
  }

  Widget _erpCard(BuildContext context, IconData icon, String fallback) {
    final data = message.card ?? {};
    final status = data['status']?.toString() ?? 'Pending';
    Color statusColor = ChatV1Theme.pending;
    if (status.toLowerCase().contains('complete') ||
        status.toLowerCase().contains('approv')) {
      statusColor = ChatV1Theme.completed;
    } else if (status.toLowerCase().contains('reject')) {
      statusColor = ChatV1Theme.rejected;
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(icon, color: ChatV1Theme.accent, size: 18),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                data['title']?.toString() ?? fallback,
                style: TextStyle(
                  color: ChatV1Theme.text(context),
                  fontWeight: FontWeight.w700,
                  fontSize: 14,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Cv1Badge(label: status, color: statusColor),
        const SizedBox(height: 8),
        ...['creator', 'amount', 'items', 'delta', 'reason', 'assignee', 'category']
            .where((k) => data[k] != null)
            .map(
              (k) => Padding(
                padding: const EdgeInsets.only(bottom: 3),
                child: Row(
                  children: [
                    SizedBox(
                      width: 72,
                      child: Text(
                        k[0].toUpperCase() + k.substring(1),
                        style: TextStyle(
                          color: ChatV1Theme.textMuted(context),
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    Expanded(
                      child: Text(
                        data[k].toString(),
                        style: TextStyle(
                          color: ChatV1Theme.text(context),
                          fontSize: 12.5,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: OutlinedButton(
                onPressed: () {},
                style: OutlinedButton.styleFrom(
                  foregroundColor: ChatV1Theme.rejected,
                  side: const BorderSide(color: ChatV1Theme.rejected),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10)),
                ),
                child: const Text('Reject',
                    style: TextStyle(fontWeight: FontWeight.w700)),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: ElevatedButton(
                onPressed: () {},
                style: ElevatedButton.styleFrom(
                  backgroundColor: ChatV1Theme.completed,
                  foregroundColor: Colors.white,
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10)),
                ),
                child: const Text('Approve',
                    style: TextStyle(fontWeight: FontWeight.w700)),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

