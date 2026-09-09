/// Authorization for Mobile Test Mode. Matches backend
/// `can_manage_test_devices`: Super Admin only.
class MobileLiveTestAccess {
  static const superAdminRole = 'Super Admin';
  static const menuTitle = 'Mobile Live Test';

  static const liveTestBasePath = '/API/workflow/mobile-live-test';
  static const registerPath = '$liveTestBasePath/devices/register';
  static const heartbeatPath = '$liveTestBasePath/heartbeat';
  static const sessionPath = '$liveTestBasePath/session';
  static const tasksPath = '$liveTestBasePath/tasks';
  static const productionTasksPath = '/API/get_tasks';
  static const productionItemRunCompletePath = '/API/workflow/item-runs';

  static String taskOpenPath(int itemRunId) =>
      '$liveTestBasePath/tasks/$itemRunId/open';

  static String taskCompletePath(int itemRunId) =>
      '$liveTestBasePath/tasks/$itemRunId/complete';

  static String taskActionPath(int itemRunId, String slug) =>
      '$liveTestBasePath/tasks/$itemRunId/$slug';

  static const taskActionSlugs = <String>{
    'upload',
    'status',
    'checklist',
    'text-list',
    'material-shift',
    'slot-selection',
    'slot-confirmation',
    'picture-choice-list',
    'picture-choice-pick',
    'user-checklist',
    'user-checklist-followup',
    'approve',
    'reject',
    'comments',
    'documents',
  };

  /// Maps workflow action `type` to live-test task action slug (production parity).
  static String? slugForActionType(String type) {
    switch (type.trim().toLowerCase()) {
      case 'upload':
        return 'upload';
      case 'update_status':
        return 'status';
      case 'checklist':
        return 'checklist';
      case 'text_list':
        return 'text-list';
      case 'kyp_material_shift':
        return 'material-shift';
      case 'slot_selection':
        return 'slot-selection';
      case 'slot_confirmation':
        return 'slot-confirmation';
      case 'picture_choice_list':
        return 'picture-choice-list';
      case 'picture_choice_pick':
        return 'picture-choice-pick';
      case 'user_checklist':
        return 'user-checklist';
      case 'user_checklist_followup':
        return 'user-checklist-followup';
      default:
        return null;
    }
  }

  /// Resolve dedicated live-test submit path for a workflow action.
  static String resolveActionSubmitPath(
    int itemRunId,
    Map<String, dynamic> action,
  ) {
    final configured = (action['submit_url'] ??
            action['submit_endpoint'] ??
            action['endpoint'] ??
            action['url'] ??
            '')
        .toString()
        .trim();
    if (configured.contains('mobile-live-test')) {
      if (configured.startsWith('/API/')) return configured;
      if (configured.startsWith('/')) return configured;
      final uri = Uri.tryParse(configured);
      if (uri != null && uri.path.contains('mobile-live-test')) {
        return uri.path;
      }
    }
    if (configured.contains('/API/workflow/item-runs/')) {
      final rewritten = rewriteProductionWorkflowUrl(
        configured.startsWith('http')
            ? configured
            : 'https://office.buildahome.in$configured',
      );
      final uri = Uri.tryParse(rewritten);
      if (uri != null && uri.path.contains('mobile-live-test')) {
        return uri.path;
      }
    }
    final type = (action['type'] ?? '').toString();
    final slug = slugForActionType(type);
    if (slug == null || slug.isEmpty) return '';
    return taskActionPath(itemRunId, slug);
  }

  static final _itemRunPattern =
      RegExp(r'/API/workflow/item-runs/(\d+)/([^/?#]+)');

  /// Map production My Tasks workflow URLs onto live-test task APIs.
  static String rewriteProductionWorkflowUrl(String url) {
    final uri = Uri.tryParse(url);
    if (uri == null) return url;
    final match = _itemRunPattern.firstMatch(uri.path);
    if (match == null) return url;
    final id = int.tryParse(match.group(1) ?? '') ?? 0;
    if (id <= 0) return url;
    final slug = match.group(2) ?? '';
    final newPath = slug == 'actions'
        ? taskOpenPath(id)
        : slug == 'complete'
            ? taskCompletePath(id)
            : taskActionPath(id, slug);
    return uri.replace(path: newPath).toString();
  }

  static bool isLiveTestPath(String path) =>
      path.contains('/mobile-live-test/');

  static bool canEnable(String? role) =>
      (role ?? '').trim() == superAdminRole;
}
