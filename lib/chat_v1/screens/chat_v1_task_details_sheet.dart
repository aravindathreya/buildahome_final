import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../chat_v1_models.dart';
import '../chat_v1_theme.dart';

/// ERP task details sheet (web right panel parity).
class ChatV1TaskDetailsSheet extends StatelessWidget {
  final ChatV1ErpTaskDetails details;

  const ChatV1TaskDetailsSheet({super.key, required this.details});

  static Future<void> show(
    BuildContext context,
    ChatV1ErpTaskDetails details,
  ) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: ChatV1Theme.secondary(context),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
      ),
      builder: (_) => ChatV1TaskDetailsSheet(details: details),
    );
  }

  Color _statusColor(String status) {
    switch (status.toLowerCase()) {
      case 'completed':
      case 'done':
        return ChatV1Theme.completed;
      case 'in_progress':
      case 'in progress':
        return ChatV1Theme.accent;
      case 'rejected':
      case 'cancelled':
        return ChatV1Theme.rejected;
      default:
        return ChatV1Theme.pending;
    }
  }

  Future<void> _openUrl(String url) async {
    final uri = Uri.tryParse(url);
    if (uri == null) return;
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  @override
  Widget build(BuildContext context) {
    final statusColor = _statusColor(details.status);
    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.72,
      minChildSize: 0.4,
      maxChildSize: 0.94,
      builder: (context, scroll) {
        return ListView(
          controller: scroll,
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 28),
          children: [
            Center(
              child: Container(
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: ChatV1Theme.border(context),
                  borderRadius: BorderRadius.circular(99),
                ),
              ),
            ),
            const SizedBox(height: 12),
            Text(
              'Task details',
              style: TextStyle(
                color: ChatV1Theme.textMuted(context),
                fontWeight: FontWeight.w700,
                fontSize: 12,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              details.title,
              style: TextStyle(
                color: ChatV1Theme.text(context),
                fontWeight: FontWeight.w800,
                fontSize: 18,
              ),
            ),
            const SizedBox(height: 14),
            _section(
              context,
              title: 'Summary',
              child: Column(
                children: [
                  _metaRow(context, 'Status', details.statusDisplay,
                      valueColor: statusColor),
                  _metaRow(
                    context,
                    'Assignee',
                    details.assigneeLabel.isNotEmpty
                        ? details.assigneeLabel
                        : 'Unassigned',
                  ),
                  if (details.dueDateDisplay != null &&
                      details.dueDateDisplay!.isNotEmpty)
                    _metaRow(context, 'Due date', details.dueDateDisplay!),
                  if (details.category != null &&
                      details.category!.isNotEmpty)
                    _metaRow(
                      context,
                      'Category',
                      details.category!.replaceAll('_', ' '),
                    ),
                ],
              ),
            ),
            if (details.noteItems.isNotEmpty) ...[
              const SizedBox(height: 12),
              _section(
                context,
                title: details.noteResponseTitle ?? 'Task response',
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (details.responseAuthorName != null)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 10),
                        child: Text(
                          [
                            'Submitted by ${details.responseAuthorName}',
                            if (details.responseAuthorRole != null)
                              details.responseAuthorRole!,
                            if (details.responseAtDisplay != null)
                              details.responseAtDisplay!,
                          ].join(' · '),
                          style: TextStyle(
                            color: ChatV1Theme.textMuted(context),
                            fontSize: 12,
                          ),
                        ),
                      ),
                    ...details.noteItems.map((item) {
                      final yes = item.value.toLowerCase() == 'yes';
                      final no = item.value.toLowerCase() == 'no';
                      return Container(
                        width: double.infinity,
                        margin: const EdgeInsets.only(bottom: 8),
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: ChatV1Theme.bg(context),
                          borderRadius: BorderRadius.circular(12),
                          border:
                              Border.all(color: ChatV1Theme.border(context)),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(item.label,
                                style: TextStyle(
                                  color: ChatV1Theme.text(context),
                                  fontWeight: FontWeight.w700,
                                )),
                            const SizedBox(height: 4),
                            Text(
                              item.value.isEmpty ? '—' : item.value,
                              style: TextStyle(
                                color: yes
                                    ? ChatV1Theme.completed
                                    : no
                                        ? ChatV1Theme.rejected
                                        : ChatV1Theme.textSecondary(context),
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                            if (item.comment.isNotEmpty) ...[
                              const SizedBox(height: 4),
                              Text(
                                'Comment: ${item.comment}',
                                style: TextStyle(
                                  color: ChatV1Theme.textMuted(context),
                                  fontSize: 12.5,
                                ),
                              ),
                            ],
                          ],
                        ),
                      );
                    }),
                  ],
                ),
              ),
            ],
            if (details.attachments.isNotEmpty) ...[
              const SizedBox(height: 12),
              _section(
                context,
                title: 'Attachments',
                child: Column(
                  children: details.attachments.map((f) {
                    final isImage = f.name.toLowerCase().endsWith('.png') ||
                        f.name.toLowerCase().endsWith('.jpg') ||
                        f.name.toLowerCase().endsWith('.jpeg') ||
                        f.name.toLowerCase().endsWith('.webp') ||
                        f.url.toLowerCase().contains('.jpg') ||
                        f.url.toLowerCase().contains('.png');
                    return ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: Icon(
                        isImage
                            ? Icons.image_outlined
                            : Icons.attach_file_rounded,
                        color: ChatV1Theme.accent,
                      ),
                      title: Text(f.name),
                      trailing: const Icon(Icons.open_in_new_rounded, size: 18),
                      onTap: () => _openUrl(f.url),
                    );
                  }).toList(),
                ),
              ),
            ],
          ],
        );
      },
    );
  }

  Widget _section(
    BuildContext context, {
    required String title,
    required Widget child,
  }) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: ChatV1Theme.card(context),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: ChatV1Theme.border(context)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: TextStyle(
              color: ChatV1Theme.text(context),
              fontWeight: FontWeight.w800,
              fontSize: 13.5,
            ),
          ),
          const SizedBox(height: 10),
          child,
        ],
      ),
    );
  }

  Widget _metaRow(
    BuildContext context,
    String label,
    String value, {
    Color? valueColor,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 88,
            child: Text(
              label,
              style: TextStyle(
                color: ChatV1Theme.textMuted(context),
                fontSize: 12.5,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: TextStyle(
                color: valueColor ?? ChatV1Theme.text(context),
                fontWeight: FontWeight.w700,
                fontSize: 13,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
