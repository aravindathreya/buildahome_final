import 'package:http/http.dart' as http;

import '../models/mobile_live_test.dart';
import 'api_http.dart';
import 'mobile_live_test_access.dart';
import 'mobile_live_test_service.dart';

/// Routes My Tasks workflow HTTP through live-test APIs while Test Mode
/// is showing the real My Tasks UI.
class MobileLiveTestWorkflow {
  MobileLiveTestWorkflow._();

  static MobileLiveTestService? service;

  static bool isTask(Map? task) {
    if (task == null) return false;
    return _flag(task['mobile_live_test']) || skipProjectGates(task);
  }

  /// Isolated live tests have no project / site. Ignore GPS, delay, indent PH,
  /// and "configure site" even if an older payload still includes those gates.
  static bool skipProjectGates(Map? data) {
    if (data == null) return false;
    if (_flag(data['mobile_live_test'])) return true;
    if (_flag(data['skip_project_gates'])) return true;
    if (_flag(data['test_mode'])) return true;
    if (_flag(data['test_execution'])) return true;
    final nested = data['task'];
    if (nested is Map) {
      return _flag(nested['skip_project_gates']) ||
          _flag(nested['test_mode']) ||
          _flag(nested['test_execution']) ||
          _flag(nested['mobile_live_test']);
    }
    return false;
  }

  static bool _flag(dynamic value) {
    if (value is bool) return value;
    if (value is num) return value != 0;
    final text = value?.toString().trim().toLowerCase() ?? '';
    return text == '1' || text == 'true' || text == 'yes';
  }

  static bool isMandatoryUploadBlock(Map? task) {
    if (task == null) return false;
    if (_flag(task['mandatory_uploads_pending'])) return true;
    final msg =
        (task['workflow_mandatory_upload_block_msg'] ?? task['block_reason'])
            ?.toString()
            .trim() ??
            '';
    if (msg.toLowerCase().contains('upload')) return true;
    return false;
  }

  static bool looksLikeSkippedProjectGate({
    String? message,
    String? actionType,
  }) {
    final type = (actionType ?? '').trim().toLowerCase();
    if (type == 'delay_timer') return true;
    final msg = (message ?? '').trim().toLowerCase();
    if (msg.isEmpty) return false;
    return msg.contains('site') ||
        msg.contains('gps') ||
        msg.contains('location') ||
        msg.contains('near the project') ||
        msg.contains('go to the project') ||
        msg.contains('delay') ||
        msg.contains('scheduled') ||
        msg.contains('unlock') ||
        (msg.contains('indent') && msg.contains('approved')) ||
        msg.contains('purchase order') ||
        msg.contains('approved po') ||
        msg.contains('no project') ||
        msg.contains('project is required') ||
        msg.contains('required to create an indent') ||
        (msg.contains('project') && msg.contains('indent')) ||
        msg.contains('configure site') ||
        msg.contains('sales_sop');
  }

  /// Extra JSON fields so live-test POSTs do not try to create a real indent
  /// or require a live `project_id`.
  static Map<String, dynamic> submitPayloadFlags(Map? task) {
    if (!skipProjectGates(task)) return const {};
    return {
      'skip_project_gates': true,
      'test_mode': true,
      'test_execution': true,
      'skip_indent_creation': true,
    };
  }

  /// Strip project-only gates from a live-test task / open payload.
  static Map<String, dynamic> applySkipProjectGates(
    Map<String, dynamic> task,
  ) {
    if (!skipProjectGates(task) && !_flag(task['mobile_live_test'])) {
      return task;
    }
    final next = Map<String, dynamic>.from(task);
    next['mobile_live_test'] = true;
    next['skip_project_gates'] = true;
    next['test_mode'] = true;
    next['indent_reason_blocks_complete'] = false;
    next['indent_reason_block_message'] = '';
    next['completes_on_indent_approved_pos'] = false;
    next['workflow_delay_gate'] = {
      'is_delay_gated': false,
      'seconds_remaining': 0,
    };
    final status = (next['workflow_status'] ?? next['status'] ?? '')
        .toString()
        .trim()
        .toLowerCase()
        .replaceAll(' ', '_');
    if (status == 'scheduled') {
      next['status'] = 'ready';
      next['workflow_status'] = 'ready';
      next['workflow_status_label'] = 'Pending';
    }
    next['can_update'] = true;
    next['can_update_workflow_task'] = true;
    if (!isMandatoryUploadBlock(next)) {
      next['can_complete_workflow_task'] = true;
    }

    for (final key in const ['workflow_actions', 'workflow_task_actions']) {
      final list = next[key];
      if (list is! List) continue;
      next[key] = list
          .whereType<Map>()
          .map((item) => sanitizeAction(Map<String, dynamic>.from(item)))
          .where((action) => action['type']?.toString() != 'delay_timer')
          .toList();
    }
    return next;
  }

  static Map<String, dynamic> sanitizeAction(Map<String, dynamic> action) {
    final next = Map<String, dynamic>.from(action);
    next['require_near_site'] = false;
    next['unlock_requires_near_site'] = false;
    next['require_gps_for_upload'] = false;
    next['site_location_available'] = true;
    next['completes_on_indent_approved_pos'] = false;
    final blockedMsg = next['blocked_message']?.toString();
    if (_flag(next['blocked']) &&
        looksLikeSkippedProjectGate(
          message: blockedMsg,
          actionType: next['type']?.toString(),
        )) {
      next['blocked'] = false;
      next['blocked_message'] = '';
    }
    return next;
  }

  static String deviceToken(Map? task) {
    return task?['live_test_device_token']?.toString().trim() ?? '';
  }

  static http.Client clientFor(Map? task) {
    if (isTask(task) && service != null) return service!.httpClient;
    return ApiHttp.client;
  }

  static String rewriteUrl(String url, Map? task) {
    if (!isTask(task)) return url;
    return MobileLiveTestAccess.rewriteProductionWorkflowUrl(url);
  }

  static Uri rewriteUri(Uri uri, Map? task) {
    if (!isTask(task)) return uri;
    var next = Uri.parse(
      MobileLiveTestAccess.rewriteProductionWorkflowUrl(uri.toString()),
    );
    final token = deviceToken(task);
    if (token.isEmpty) return next;
    return next.replace(
      queryParameters: {
        ...next.queryParameters,
        'device_token': token,
      },
    );
  }

  static Map<String, String> headers(Map<String, String> headers, Map? task) {
    if (!isTask(task)) return headers;
    final token = deviceToken(task);
    if (token.isEmpty) return headers;
    return {
      ...headers,
      'X-Live-Test-Device-Token': token,
    };
  }

  static void applyToMultipart(http.MultipartRequest request, Map? task) {
    if (!isTask(task)) return;
    final token = deviceToken(task);
    if (token.isEmpty) return;
    request.headers['X-Live-Test-Device-Token'] = token;
    request.fields['device_token'] = token;
  }

  /// Live-test `/open` nests workflow fields under `task`.
  static Map<String, dynamic> flattenOpenPayload(Map<String, dynamic> payload) {
    final nestedRaw = payload['task'];
    if (nestedRaw is! Map) return payload;

    final nested = Map<String, dynamic>.from(nestedRaw);
    final flattened = Map<String, dynamic>.from(payload);
    final actions = nested['workflow_actions'] ??
        nested['workflow_task_actions'] ??
        nested['actions'];
    flattened.putIfAbsent('workflow_actions', () => actions);
    flattened.putIfAbsent('workflow_task_actions', () => actions);
    flattened.putIfAbsent(
      'workflow_action_responses',
      () => nested['workflow_action_responses'] ?? nested['action_responses'],
    );
    flattened.putIfAbsent(
      'can_update_workflow_task',
      () => nested['can_update_workflow_task'] ??
          nested['can_update'] ??
          nested['can_complete'],
    );
    flattened.putIfAbsent(
      'can_complete_workflow_task',
      () => nested['can_complete_workflow_task'] ?? nested['can_complete'],
    );
    flattened.putIfAbsent(
      'can_update',
      () => nested['can_update'] ?? nested['can_complete'],
    );
    flattened.putIfAbsent('status', () => nested['status']);
    flattened.putIfAbsent('workflow_status', () => nested['status']);
    flattened.putIfAbsent(
      'workflow_status_label',
      () => nested['status_label'] ?? nested['workflow_status_label'],
    );
    flattened.putIfAbsent(
      'workflow_delay_gate',
      () => nested['workflow_delay_gate'],
    );
    flattened.putIfAbsent(
      'indent_reason_blocks_complete',
      () => nested['indent_reason_blocks_complete'],
    );
    flattened.putIfAbsent(
      'indent_reason_block_message',
      () => nested['indent_reason_block_message'],
    );
    flattened.putIfAbsent(
      'can_approve_workflow_task',
      () => nested['can_approve_workflow_task'],
    );
    flattened.putIfAbsent(
      'skip_project_gates',
      () => nested['skip_project_gates'] ?? payload['skip_project_gates'],
    );
    flattened.putIfAbsent(
      'test_mode',
      () => nested['test_mode'] ?? payload['test_mode'],
    );
    flattened.putIfAbsent(
      'test_execution',
      () => nested['test_execution'] ?? payload['test_execution'],
    );
    flattened.putIfAbsent(
      'mandatory_uploads_pending',
      () => nested['mandatory_uploads_pending'],
    );
    flattened.putIfAbsent(
      'workflow_mandatory_upload_block_msg',
      () => nested['workflow_mandatory_upload_block_msg'],
    );
    return applySkipProjectGates(flattened);
  }
}

extension MobileLiveTestTaskMyTasksMap on MobileLiveTestTask {
  Map<String, dynamic> toMyTasksMap({String? deviceToken}) {
    final runId = itemRunId;
    final id = runId == null || runId <= 0
        ? 'live-${nodeKey.isNotEmpty ? nodeKey : name}'
        : '-$runId';
    return {
      'id': id,
      'is_workflow_task': true,
      'mobile_live_test': true,
      'skip_project_gates': true,
      'test_mode': true,
      if (deviceToken != null && deviceToken.trim().isNotEmpty)
        'live_test_device_token': deviceToken.trim(),
      'workflow_item_run_id': runId,
      'note': name,
      's_note': name,
      'status': status.isEmpty ? 'ready' : status,
      'workflow_status': status.isEmpty ? 'ready' : status,
      'workflow_status_label': statusLabel,
      'assigned_to_name': assignedUserName,
      'assigned_to': assignedUserId,
      'assigned_to_role': role,
      'project_name': 'Mobile live test',
      'can_complete_workflow_task': canComplete,
      'can_update_workflow_task': canComplete,
      'can_update': canComplete,
    };
  }
}
