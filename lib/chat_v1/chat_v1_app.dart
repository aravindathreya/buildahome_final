import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../services/data_provider.dart';
import 'chat_v1_controller.dart';
import 'chat_v1_models.dart';
import 'chat_v1_theme.dart';
import 'chat_v1_utils.dart';
import 'screens/chat_v1_conversation_screen.dart';
import 'screens/chat_v1_doc_list_screen.dart';
import 'screens/chat_v1_group_info_screen.dart';
import 'screens/chat_v1_home_screen.dart';
import 'screens/chat_v1_search_screen.dart';
import 'screens/chat_v1_task_list_screen.dart';

/// ChatV1 entry — wired to `/api/v1/chat` + Socket.IO.
class ChatV1App extends StatefulWidget {
  final String? salesSopId;

  const ChatV1App({super.key, this.salesSopId});

  /// Sync open — no network await before the route pushes.
  /// Prefer this from menus so Chat appears immediately.
  static ChatV1App openQuick({
    String? erpProjectId,
    Map<String, dynamic>? project,
    Iterable<dynamic>? tasksHint,
  }) {
    final dp = DataProvider();
    // Prefer last successful chat session, then DataProvider memory.
    String? sopId = ChatV1Controller.instance.salesSopId ?? dp.clientSalesSopId;

    if ((sopId == null || sopId.isEmpty) && project != null) {
      for (final key in const [
        'sales_sop_id',
        'salesSopId',
        'sop_id',
        'sopId',
      ]) {
        final v = project[key]?.toString().trim();
        if (v != null && v.isNotEmpty && v.toLowerCase() != 'null') {
          sopId = v;
          break;
        }
      }
    }

    if ((sopId == null || sopId.isEmpty) && tasksHint != null) {
      for (final task in tasksHint) {
        if (task is! Map) continue;
        final v = (task['sales_sop_id'] ?? task['salesSopId'])
            ?.toString()
            .trim();
        if (v != null && v.isNotEmpty && v.toLowerCase() != 'null') {
          sopId = v;
          break;
        }
      }
    }

    if ((sopId == null || sopId.isEmpty) &&
        erpProjectId != null &&
        erpProjectId.isNotEmpty) {
      for (final p in dp.projects) {
        if (p is! Map) continue;
        if (p['id']?.toString() != erpProjectId) continue;
        final v = (p['sales_sop_id'] ?? p['salesSopId'])?.toString().trim();
        if (v != null && v.isNotEmpty && v.toLowerCase() != 'null') {
          sopId = v;
        }
        break;
      }
    }

    print('[ChatV1App] openQuick sales_sop_id=$sopId (sync, no await)');
    return ChatV1App(salesSopId: sopId);
  }

  /// Resolve sales_sop_id (may hit network) then build ChatV1.
  /// Prefer [openQuick] for menu taps; keep this for deep links that need certainty.
  static Future<ChatV1App> openResolved({
    String? erpProjectId,
    Map<String, dynamic>? project,
    Iterable<dynamic>? tasksHint,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final token = (prefs.getString('api_token') ?? '').trim();
    final projectId = erpProjectId ?? prefs.getString('project_id');
    final role = (prefs.getString('role') ?? '').trim();
    final dp = DataProvider();

    // Fast path: same sync resolution as openQuick.
    final quick = openQuick(
      erpProjectId: projectId,
      project: project,
      tasksHint: tasksHint,
    );
    if (quick.salesSopId != null && quick.salesSopId!.isNotEmpty) {
      return quick;
    }

    // Client (and others) may already have sales_sop_id cached in prefs.
    String? sopId = dp.clientSalesSopId;
    if (sopId == null || sopId.isEmpty) {
      final cached = prefs.getString('sales_sop_id');
      if (cached != null &&
          cached.isNotEmpty &&
          cached.toLowerCase() != 'null') {
        if (role == 'Client') {
          sopId = cached;
        } else {
          final cachedErp = prefs.getString('sales_sop_erp_project_id');
          if (cachedErp == null ||
              projectId == null ||
              cachedErp == projectId) {
            sopId = cached;
          }
        }
      }
    }

    Map<String, dynamic>? projectHint = project;
    if (projectHint == null &&
        projectId != null &&
        projectId.isNotEmpty) {
      for (final p in dp.projects) {
        if (p is! Map) continue;
        final id = p['id']?.toString();
        if (id == projectId) {
          projectHint = Map<String, dynamic>.from(p);
          break;
        }
      }
    }

    if ((sopId == null || sopId.isEmpty) && token.isNotEmpty) {
      sopId = await dp.resolveSalesSopId(
        projectId: projectId,
        apiToken: token,
        projectHint: projectHint,
        tasksHint: tasksHint,
        useCache: true,
      );
    }

    print(
      '[ChatV1App] openResolved role=$role erpProjectId=$projectId '
      'sales_sop_id=$sopId',
    );
    return ChatV1App(salesSopId: sopId);
  }

  @override
  State<ChatV1App> createState() => _ChatV1AppState();
}

class _ChatV1AppState extends State<ChatV1App> {
  bool _dark = false;

  @override
  Widget build(BuildContext context) {
    return Theme(
      data: ChatV1Theme.data(dark: _dark),
      child: Builder(
        builder: (context) => ChatV1HomeScreen(
          darkMode: _dark,
          salesSopId: widget.salesSopId,
          onToggleTheme: () => setState(() => _dark = !_dark),
          onOpenChat: (item) => _openChat(context, item),
          onOpenSearch: () => _open(context, const ChatV1SearchScreen()),
        ),
      ),
    );
  }

  Future<void> _openChat(BuildContext context, ChatV1ChatItem item) async {
    if (item.opensAs == ChatV1OpensAs.docList ||
        ChatV1Utils.isUpdateAndDocChannel(item.title)) {
      await _open(
        context,
        ChatV1DocListScreen(
          salesSopId:
              widget.salesSopId ?? ChatV1Controller.instance.salesSopId,
        ),
      );
      return;
    }
    if (item.opensAs == ChatV1OpensAs.taskList) {
      await _open(
        context,
        ChatV1TaskListScreen(
          hubTitle: item.title,
          hubKind: item.hubKind ?? 'tasks',
          onOpenTask: (task) => _openConversation(
            context,
            item,
            task: task,
          ),
        ),
      );
      return;
    }
    await _openConversation(context, item);
  }

  Future<void> _openConversation(
    BuildContext context,
    ChatV1ChatItem item, {
    ChatV1TaskItem? task,
  }) async {
    final ctrl = ChatV1Controller.instance;
    final meta = task != null
        ? ctrl.metaForTask(task)
        : ctrl.metaFor(item);
    await _open(
      context,
      ChatV1ConversationScreen(
        meta: meta,
        onOpenInfo: () => _open(context, ChatV1GroupInfoScreen(meta: meta)),
      ),
    );
  }

  Future<void> _open(BuildContext context, Widget page) {
    return Navigator.of(context).push(
      PageRouteBuilder(
        pageBuilder: (_, __, ___) => page,
        transitionsBuilder: (_, anim, __, child) {
          final curved =
              CurvedAnimation(parent: anim, curve: Curves.easeOutCubic);
          return FadeTransition(
            opacity: curved,
            child: SlideTransition(
              position: Tween<Offset>(
                begin: const Offset(0.04, 0),
                end: Offset.zero,
              ).animate(curved),
              child: child,
            ),
          );
        },
        transitionDuration: const Duration(milliseconds: 260),
      ),
    );
  }
}
