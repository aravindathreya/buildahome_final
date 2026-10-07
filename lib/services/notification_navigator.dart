import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

import '../MyTasksScreen.dart';
import '../Payments.dart';
import '../SiteVisitReports.dart';
import '../SlotsScreen.dart';
import '../UploadPaymentProofScreen.dart';
import '../UserHome.dart';
import '../app_navigator.dart';
import '../approved_pos_screen.dart';
import '../chat_v1/chat_v1_api.dart';
import '../chat_v1/chat_v1_mapper.dart';
import '../chat_v1/screens/chat_v1_conversation_screen.dart';
import '../chat_v1/screens/chat_v1_group_info_screen.dart';
import '../indents_screen.dart';
import 'push/notification_target.dart';

/// Opens the same destinations as the in-app notifications list.
class NotificationNavigator {
  static Future<bool> open(
    BuildContext context,
    Map<String, dynamic> notification,
  ) async {
    final target = NotificationTarget.resolve(notification);
    if (!target.isValid) {
      _snack(_invalidMessage(target.reason));
      return false;
    }

    switch (target.kind) {
      case NotificationKind.externalUrl:
        final uri = Uri.tryParse(target.externalUrl ?? '');
        if (uri != null && await canLaunchUrl(uri)) {
          await launchUrl(uri, mode: LaunchMode.externalApplication);
          return true;
        }
        _snack('This link is no longer available.');
        return false;
      case NotificationKind.paymentProof:
        await Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => const UploadPaymentProofScreen(),
          ),
        );
        return true;
      case NotificationKind.indentProof:
        await openIndentProofScreen(context, indentId: target.indentId!);
        return true;
      case NotificationKind.indentApproval:
        await openIndentViewOpenScreen(
          context,
          indentId: target.indentId!,
          projectId: target.projectId,
          projectName: target.projectName,
        );
        return true;
      case NotificationKind.payment:
        await _rememberProject(target);
        if (!context.mounted) return false;
        await Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => PaymentsDashboard(
              initialCategory: PaymentCategory.tender,
              initialSearch: target.paymentQuery,
            ),
          ),
        );
        return true;
      case NotificationKind.task:
        return _openTask(context, target);
      case NotificationKind.indent:
        final prefs = await SharedPreferences.getInstance();
        if (!context.mounted) return false;
        await Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => IndentsScreenLayout(
              initialTab: target.myIndents
                  ? kIndentsMyIndentsTab
                  : kIndentsViewOpenTab,
              initialIndentId: target.indentId,
              initialProjectId: target.projectId ?? prefs.getString('project_id'),
              initialProjectName:
                  target.projectName ?? prefs.getString('client_name'),
            ),
          ),
        );
        return true;
      case NotificationKind.approvedPo:
        final prefs = await SharedPreferences.getInstance();
        if (!context.mounted) return false;
        await Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => ApprovedPosScreenLayout(
              initialProjectId:
                  target.projectId ?? prefs.getString('project_id'),
              initialProjectName:
                  target.projectName ?? prefs.getString('client_name'),
              initialSearch: target.poQuery ?? target.indentId,
            ),
          ),
        );
        return true;
      case NotificationKind.slots:
        await Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => const SlotsScreen()),
        );
        return true;
      case NotificationKind.siteVisit:
        final prefs = await SharedPreferences.getInstance();
        if (!context.mounted) return false;
        final fixedId = target.projectId ?? prefs.getString('project_id');
        await Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => SiteVisitReportsScreen(
              fixedProjectId: fixedId,
              projectFixed: fixedId != null && fixedId.isNotEmpty,
            ),
          ),
        );
        return true;
      case NotificationKind.project:
        return _openProject(context, target);
      case NotificationKind.chat:
        return _openChat(context, target);
      case NotificationKind.none:
        _snack(_invalidMessage(target.reason));
        return false;
    }
  }

  static Future<bool> _openTask(
    BuildContext context,
    NotificationTarget target,
  ) async {
    final taskId = target.taskId?.trim();
    await _rememberProject(target);
    List<dynamic> tasks;
    try {
      tasks = await fetchTasksForCurrentUser();
    } catch (_) {
      _snack('This task is no longer available.');
      return false;
    }
    if (!context.mounted) return false;
    if (taskId != null &&
        taskId.isNotEmpty &&
        !NotificationTarget.taskListContains(tasks, taskId)) {
      _snack('This task is no longer available.');
      return false;
    }
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => MyTasksScreen(
          tasks: tasks,
          focusTaskId: taskId,
          onRefresh: fetchTasksForCurrentUser,
        ),
      ),
    );
    return true;
  }

  static Future<bool> _openProject(
    BuildContext context,
    NotificationTarget target,
  ) async {
    final projectId = target.projectId?.trim() ?? '';
    if (projectId.isEmpty) {
      _snack('This project is no longer available.');
      return false;
    }
    final reachable = await _projectReachable(projectId);
    if (reachable == false) {
      _snack('This project is no longer available.');
      return false;
    }
    if (!context.mounted) return false;
    final prefs = await SharedPreferences.getInstance();
    final role = (prefs.getString('role') ?? '').trim().toLowerCase();
    await prefs.setString('project_id', projectId);
    final name = target.projectName?.trim();
    if (name != null && name.isNotEmpty) {
      await prefs.setString('client_name', name);
    }
    if (!context.mounted) return false;
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => Home(fromAdminDashboard: role != 'client'),
      ),
    );
    return true;
  }

  static Future<bool> _openChat(
    BuildContext context,
    NotificationTarget target,
  ) async {
    final conversationId = target.conversationId?.trim() ?? '';
    if (conversationId.isEmpty) {
      _snack('This chat is no longer available.');
      return false;
    }
    final prefs = await SharedPreferences.getInstance();
    final userId =
        (prefs.getString('userId') ?? prefs.getString('user_id') ?? '').trim();
    Map<String, dynamic> data;
    try {
      data = await ChatV1Api.instance.getConversation(conversationId);
    } catch (_) {
      _snack('This chat is no longer available.');
      return false;
    }
    if (!context.mounted) return false;

    final conversation = data['conversation'] is Map
        ? Map<String, dynamic>.from(data['conversation'] as Map)
        : data;
    final participants = conversation['participants'] ??
        conversation['members'] ??
        data['participants'] ??
        data['members'];
    if (!NotificationTarget.userIsParticipant(participants, userId)) {
      _snack('You no longer have access to this chat.');
      return false;
    }

    final item = ChatV1Mapper.conversationToChatItem(conversation);
    if (item.id.trim().isEmpty) {
      _snack('This chat is no longer available.');
      return false;
    }
    final meta = ChatV1Mapper.metaFromChatItem(
      item,
      members: const [],
    );
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (routeContext) => ChatV1ConversationScreen(
          meta: meta,
          onOpenInfo: () {
            Navigator.of(routeContext).push(
              MaterialPageRoute(
                builder: (_) => ChatV1GroupInfoScreen(meta: meta),
              ),
            );
          },
        ),
      ),
    );
    return true;
  }

  static Future<void> _rememberProject(NotificationTarget target) async {
    final projectId = target.projectId?.trim() ?? '';
    if (projectId.isEmpty) return;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('project_id', projectId);
    final name = target.projectName?.trim();
    if (name != null && name.isNotEmpty) {
      await prefs.setString('client_name', name);
    }
  }

  /// True when the project endpoint accepts the id, false when it is gone,
  /// null when the check itself could not run.
  static Future<bool?> _projectReachable(String projectId) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final token = (prefs.getString('api_token') ?? '').trim();
      final uri = Uri.parse(
        'https://office.buildahome.in/API/get_project_percentage',
      ).replace(queryParameters: {
        'id': projectId,
        'detail': '0',
        if (token.isNotEmpty) 'api_token': token,
      });
      final response = await http.get(uri).timeout(const Duration(seconds: 12));
      if (response.statusCode == 404) return false;
      final body = response.body.toLowerCase();
      if (body.contains('not found') || body.contains('invalid project')) {
        return false;
      }
      if (response.statusCode >= 200 && response.statusCode < 300) return true;
      return null;
    } catch (_) {
      return null;
    }
  }

  static String _invalidMessage(String? reason) {
    switch (reason) {
      case 'missing_conversation':
        return 'This chat is no longer available.';
      case 'missing_project':
        return 'This project is no longer available.';
      case 'missing_approval_target':
        return 'This approval is no longer available.';
      default:
        return 'This update is no longer available.';
    }
  }

  static void _snack(String message) {
    globalScaffoldMessengerKey.currentState?.showSnackBar(
      SnackBar(content: Text(message)),
    );
  }
}
