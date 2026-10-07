enum NotificationKind {
  paymentProof,
  indentProof,
  indentApproval,
  task,
  indent,
  approvedPo,
  slots,
  siteVisit,
  project,
  payment,
  chat,
  externalUrl,
  none,
}

class NotificationTarget {
  final NotificationKind kind;
  final String? taskId;
  final String? indentId;
  final String? projectId;
  final String? projectName;
  final String? conversationId;
  final String? conversationTitle;
  final String? paymentQuery;
  final String? poQuery;
  final String? externalUrl;
  final String? reason;
  final bool myIndents;

  const NotificationTarget({
    required this.kind,
    this.taskId,
    this.indentId,
    this.projectId,
    this.projectName,
    this.conversationId,
    this.conversationTitle,
    this.paymentQuery,
    this.poQuery,
    this.externalUrl,
    this.reason,
    this.myIndents = false,
  });

  bool get isValid => kind != NotificationKind.none;

  static NotificationTarget resolve(Map<String, dynamic> notification) {
    final link = _firstString(notification, const [
      'redirect_url',
      'url',
      'link',
      'deep_link',
      'deeplink',
      'href',
      'open_url',
    ]);
    if (link != null) {
      final uri = Uri.tryParse(link);
      if (uri != null) {
        final screen = uri.queryParameters['native_screen'] ??
            uri.queryParameters['screen'] ??
            '';
        final token = screen.toLowerCase().replaceAll('-', '_');
        if (token.contains('payment_proof') ||
            token.contains('upload_proof') ||
            uri.path.toLowerCase().contains('payment_proof') ||
            uri.path.toLowerCase().contains('upload_proof')) {
          return const NotificationTarget(kind: NotificationKind.paymentProof);
        }
        if (uri.scheme == 'http' || uri.scheme == 'https') {
          return NotificationTarget(
            kind: NotificationKind.externalUrl,
            externalUrl: link,
          );
        }
      }
    }

    final screen = (_firstString(notification, const [
              'screen',
              'open_tab',
              'native_screen',
              'wf_native_screen',
              'redirect_page',
              'type',
              'category',
              'notification_type',
            ]) ??
            '')
        .toLowerCase()
        .replaceAll('-', '_')
        .replaceAll(' ', '_');

    final taskId = _firstString(notification, const [
      'task_id',
      'erp_task_id',
      'workflow_task_id',
      'focus_task_id',
    ]);
    final indentId = _firstString(notification, const [
      'indent_id',
      'indentId',
      'wf_indent_id',
    ]);
    final projectId = _firstString(notification, const [
      'project_id',
      'projectId',
      'pr_id',
    ]);
    final projectName = _firstString(notification, const [
      'project_name',
      'client_name',
      'project',
    ]);
    final conversationId = _firstString(notification, const [
      'conversation_id',
      'conversationId',
      'chat_id',
    ]);
    final paymentQuery = _firstString(notification, const [
      'payment_name',
      'bill_name',
      'stage_name',
      'payment_id',
      'bill_id',
    ]);
    final poQuery = _firstString(notification, const [
      'po_number',
      'po_id',
      'indent_id',
    ]);

    final blob =
        '${notification['title'] ?? ''} ${notification['body'] ?? ''} $screen'
            .toLowerCase();

    final explicitChat = screen == 'chat' ||
        screen == 'message' ||
        screen.contains('chat_message') ||
        screen == 'conversation';
    if (explicitChat || (conversationId != null && screen.contains('chat'))) {
      if (conversationId == null) {
        return const NotificationTarget(
          kind: NotificationKind.none,
          reason: 'missing_conversation',
        );
      }
      return NotificationTarget(
        kind: NotificationKind.chat,
        conversationId: conversationId,
        conversationTitle: _firstString(notification, const [
          'conversation_title',
          'title',
          'sender_name',
        ]),
      );
    }

    final explicitProject = screen == 'project' ||
        screen == 'projects' ||
        screen == 'project_home';
    if (explicitProject) {
      if (projectId == null) {
        return const NotificationTarget(
          kind: NotificationKind.none,
          reason: 'missing_project',
        );
      }
      return NotificationTarget(
        kind: NotificationKind.project,
        projectId: projectId,
        projectName: projectName,
      );
    }

    if (indentId != null &&
        (screen.contains('indent_proof') ||
            screen.contains('site_proof') ||
            blob.contains('indent proof') ||
            blob.contains('site proof'))) {
      return NotificationTarget(
        kind: NotificationKind.indentProof,
        indentId: indentId,
        projectId: projectId,
        projectName: projectName,
      );
    }

    if (indentId != null &&
        (screen.contains('indent_review') ||
            screen.contains('indents_view_open') ||
            screen.contains('view_open_indents') ||
            screen.contains('approval') ||
            blob.contains('review and approve the indent') ||
            (blob.contains('review') &&
                blob.contains('approve') &&
                blob.contains('indent') &&
                !blob.contains('proof')))) {
      return NotificationTarget(
        kind: NotificationKind.indentApproval,
        indentId: indentId,
        projectId: projectId,
        projectName: projectName,
      );
    }

    if (screen.contains('payment_proof') ||
        screen.contains('upload_proof') ||
        blob.contains('upload proof') ||
        blob.contains('payment proof')) {
      return const NotificationTarget(kind: NotificationKind.paymentProof);
    }

    final explicitPayment = screen == 'payment' ||
        screen == 'payments' ||
        screen == 'bill' ||
        screen == 'invoice' ||
        screen.contains('payment_schedule');
    if (explicitPayment) {
      return NotificationTarget(
        kind: NotificationKind.payment,
        projectId: projectId,
        paymentQuery: paymentQuery,
        taskId: taskId,
      );
    }

    final explicitPo = screen.contains('approved_po') ||
        screen.contains('purchase_order') ||
        ((poQuery != null) &&
            (screen == 'po' ||
                blob.contains('approved po') ||
                blob.contains('purchase order')));
    if (explicitPo) {
      return NotificationTarget(
        kind: NotificationKind.approvedPo,
        projectId: projectId,
        projectName: projectName,
        indentId: indentId,
        poQuery: poQuery,
      );
    }

    if (taskId != null ||
        screen.contains('task') ||
        blob.contains('task') ||
        blob.contains('assigned')) {
      return NotificationTarget(
        kind: NotificationKind.task,
        taskId: taskId,
        projectId: projectId,
        projectName: projectName,
      );
    }

    if (indentId != null ||
        screen.contains('indent') ||
        blob.contains('indent')) {
      final mine = blob.contains('my indent') ||
          blob.contains('has been approved') ||
          blob.contains('has been rejected') ||
          blob.contains('edited and approved');
      return NotificationTarget(
        kind: NotificationKind.indent,
        indentId: indentId,
        projectId: projectId,
        projectName: projectName,
        myIndents: mine,
      );
    }

    if (blob.contains('approved po') ||
        blob.contains('purchase order') ||
        RegExp(r'\bpo\b').hasMatch(blob)) {
      return NotificationTarget(
        kind: NotificationKind.approvedPo,
        projectId: projectId,
        projectName: projectName,
        indentId: indentId,
        poQuery: poQuery,
      );
    }

    if (screen.contains('slot') ||
        blob.contains('visit date') ||
        blob.contains('site visit slot') ||
        blob.contains('slots')) {
      return NotificationTarget(
        kind: NotificationKind.slots,
        projectId: projectId,
      );
    }

    if (screen.contains('site_visit') || blob.contains('site visit')) {
      return NotificationTarget(
        kind: NotificationKind.siteVisit,
        projectId: projectId,
      );
    }

    if (screen.contains('approval') || screen.contains('approve')) {
      if (taskId != null) {
        return NotificationTarget(
          kind: NotificationKind.task,
          taskId: taskId,
          projectId: projectId,
        );
      }
      return const NotificationTarget(
        kind: NotificationKind.none,
        reason: 'missing_approval_target',
      );
    }

    return const NotificationTarget(
      kind: NotificationKind.none,
      reason: 'unknown',
    );
  }

  static bool taskListContains(List<dynamic> tasks, String taskId) {
    final wanted = taskId.trim();
    if (wanted.isEmpty) return false;
    for (final task in tasks) {
      if (task is! Map) continue;
      for (final key in const [
        'id',
        'task_id',
        'erp_task_id',
        'workflow_task_id',
      ]) {
        final value = task[key]?.toString().trim() ?? '';
        if (value.isNotEmpty && value == wanted) return true;
      }
    }
    return false;
  }

  static bool userIsParticipant(dynamic participants, String userId) {
    if (participants is! List || participants.isEmpty) return true;
    final me = userId.trim();
    if (me.isEmpty) return false;
    for (final entry in participants) {
      if (entry is Map) {
        final id = (entry['user_id'] ?? entry['id'] ?? entry['userId'] ?? '')
            .toString()
            .trim();
        if (id == me) return true;
      } else if (entry?.toString().trim() == me) {
        return true;
      }
    }
    return false;
  }

  static String? _firstString(Map<String, dynamic> map, List<String> keys) {
    for (final key in keys) {
      final value = map[key]?.toString().trim() ?? '';
      if (value.isNotEmpty && value.toLowerCase() != 'null') return value;
    }
    return null;
  }
}
