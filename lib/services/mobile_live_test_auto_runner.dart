import 'dart:convert';
import 'dart:io';

import 'package:image/image.dart' as img;
import 'package:path_provider/path_provider.dart';

import '../models/mobile_live_test.dart';
import 'mobile_live_test_access.dart';
import 'mobile_live_test_controller.dart';
import 'mobile_live_test_service.dart';

/// Walks assigned live-test tasks and submits real action payloads
/// (uploads, %, yes/no, status, complete) without opening each sheet.
class MobileLiveTestAutoRunner {
  MobileLiveTestAutoRunner({
    this.delayBetweenTasks = const Duration(milliseconds: 400),
    Future<String> Function()? sampleJpegPath,
  }) : _sampleJpegPath = sampleJpegPath ?? writeMobileLiveTestSampleJpeg;

  final Duration delayBetweenTasks;
  final Future<String> Function() _sampleJpegPath;

  bool running = false;
  String status = '';
  void Function()? _onChanged;

  void stop() {
    running = false;
    status = 'Stopped.';
    _onChanged?.call();
  }

  Future<void> run({
    required MobileLiveTestController controller,
    void Function()? onChanged,
  }) async {
    if (running) return;
    running = true;
    _onChanged = onChanged;
    final skipped = <int>{};
    var wasSyncing = controller.isSyncActive;
    if (wasSyncing) controller.stopSync();

    try {
      await controller.refresh();
      while (running) {
        final tasks = controller.visibleTasks
            .where((task) {
              final id = task.itemRunId;
              return id != null && id > 0 && !skipped.contains(id);
            })
            .toList();
        if (tasks.isEmpty) {
          status = 'Auto run finished. No pending tasks.';
          _onChanged?.call();
          break;
        }

        final task = tasks.first;
        final itemRunId = task.itemRunId!;
        status = 'Opening ${task.name}…';
        _onChanged?.call();

        try {
          await _completeTask(controller, itemRunId, task.name);
          await controller.refreshAfterTaskCompletion();
          final stillOpen = controller.visibleTasks
              .any((open) => open.itemRunId == itemRunId);
          if (stillOpen) {
            skipped.add(itemRunId);
            status = 'Skipped ${task.name} (needs a form Auto Run cannot fill).';
            _onChanged?.call();
          }
        } on MobileLiveTestException catch (e) {
          skipped.add(itemRunId);
          status = '${task.name}: ${e.message}';
          _onChanged?.call();
        } catch (e) {
          skipped.add(itemRunId);
          status = '${task.name}: ${e.toString().replaceFirst('Exception: ', '')}';
          _onChanged?.call();
        }

        if (!running) break;
        if (delayBetweenTasks > Duration.zero) {
          await Future<void>.delayed(delayBetweenTasks);
        }
      }
    } finally {
      running = false;
      _onChanged?.call();
      if (wasSyncing && controller.enabled) {
        controller.startSync();
      }
    }
  }

  Future<void> _completeTask(
    MobileLiveTestController controller,
    int itemRunId,
    String taskName,
  ) async {
    var ctx = await controller.service.openTask(itemRunId, forceRefresh: true);

    for (var round = 0; round < 16; round++) {
      if (!running) return;

      final actions = ctx.task.interactiveActions
          .where((action) => _actionNeedsWork(action))
          .toList();
      final next = _pickAction(actions);

      if (next == null) {
        if (_canFinish(ctx.task)) {
          status = 'Completing $taskName…';
          _onChanged?.call();
          final result = await controller.service.completeTask(
            itemRunId,
            decision: _preferredDecision(ctx.task),
          );
          _applyIfCompleted(controller, result, itemRunId);
        }
        return;
      }

      status = '$taskName — ${_statusForAction(next)}';
      _onChanged?.call();

      final finished = await _submitAction(
        controller,
        itemRunId,
        next,
      );
      if (finished) return;

      ctx = await controller.service.refreshTask(itemRunId);
    }
  }

  bool _actionNeedsWork(MobileLiveTestWorkflowAction action) {
    if (action.blocked) return false;
    if (_unsupportedTypes.contains(action.type)) return false;
    if (action.type == 'upload' && action.addPercentToTask) {
      final percent = action.currentPercent ?? 0;
      if (percent < 100) return true;
      return !_truthy(action.response['finalized']) &&
          !_truthy(action.response['completed']);
    }
    return !action.isSubmitted;
  }

  MobileLiveTestWorkflowAction? _pickAction(
    List<MobileLiveTestWorkflowAction> actions,
  ) {
    const order = [
      'upload',
      'checklist',
      'update_status',
      'yes_no',
      'view_prior_response',
      'complete_button',
      'text_list',
    ];
    for (final type in order) {
      for (final action in actions) {
        if (action.type == type) return action;
      }
    }
    return actions.isEmpty ? null : actions.first;
  }

  bool _canFinish(MobileLiveTestTaskDetail task) {
    if (task.hasUnsupportedRequirements) return false;
    if (task.mandatoryUploadsPending) return false;
    return task.canComplete ||
        task.showPlainComplete ||
        task.showActionButtons ||
        task.options.isNotEmpty;
  }

  String? _preferredDecision(MobileLiveTestTaskDetail task) {
    for (final option in task.options) {
      if (option.isYes || option.isApprove) return option.decision;
      if (option.isComplete && option.decision.isNotEmpty) {
        return option.decision;
      }
    }
    if (task.requiredDecision == 'yes_no') return 'yes';
    if (task.options.isNotEmpty && task.options.first.decision.isNotEmpty) {
      return task.options.first.decision;
    }
    return null;
  }

  String _statusForAction(MobileLiveTestWorkflowAction action) {
    switch (action.type) {
      case 'upload':
        if (action.addPercentToTask) {
          return 'uploading ${action.minNextPercent}%…';
        }
        return 'uploading photo…';
      case 'update_status':
        return 'updating status…';
      case 'yes_no':
        return 'selecting Yes…';
      case 'checklist':
        return 'filling checklist…';
      case 'complete_button':
        return 'completing…';
      case 'view_prior_response':
        return 'approving…';
      case 'text_list':
        return 'filling quantities…';
      default:
        return action.label;
    }
  }

  Future<bool> _submitAction(
    MobileLiveTestController controller,
    int itemRunId,
    MobileLiveTestWorkflowAction action,
  ) async {
    switch (action.type) {
      case 'upload':
        return _submitUpload(controller, itemRunId, action);
      case 'update_status':
        return _submitStatus(controller, itemRunId, action);
      case 'yes_no':
        return _completeDecision(controller, itemRunId, 'yes', action.id);
      case 'view_prior_response':
        return _completeDecision(controller, itemRunId, 'approve', action.id);
      case 'complete_button':
        return _completeDecision(controller, itemRunId, null, action.id);
      case 'checklist':
        return _submitChecklist(controller, itemRunId, action);
      case 'text_list':
        return _submitTextList(controller, itemRunId, action);
      default:
        return false;
    }
  }

  Future<bool> _submitUpload(
    MobileLiveTestController controller,
    int itemRunId,
    MobileLiveTestWorkflowAction action,
  ) async {
    final site = action.siteLocation;
    final lat = (site?.latitude ?? 12.9716).toString();
    final lng = (site?.longitude ?? 77.5946).toString();

    if (action.addPercentToTask) {
      var current = action.currentPercent ?? 0;
      if (current < 100) {
        final percent = 100;
        final finished = await _uploadPercent(
          controller,
          itemRunId,
          action,
          percent,
          lat,
          lng,
        );
        if (finished) return true;
        current = 100;
      }
      if (current >= 100) {
        final result = await controller.service.submitWorkflowAction(
          itemRunId,
          action,
          fields: {
            'action_id': action.id,
            'finalize': '1',
            'comment': 'Auto run',
            'upload_comment': 'Auto run',
          },
          files: const [],
        );
        return _applyActionResult(controller, result, itemRunId);
      }
      return false;
    }

    final path = await _sampleJpegPath();
    final result = await controller.service.submitWorkflowAction(
      itemRunId,
      action,
      fields: {
        'action_id': action.id,
        'latitude': lat,
        'longitude': lng,
        'comment': 'Auto run',
        'upload_comment': 'Auto run',
      },
      files: [
        MobileLiveTestUploadPart(
          fieldName: 'files',
          filePath: path,
          filename: 'auto_run.jpg',
        ),
      ],
    );
    return _applyActionResult(controller, result, itemRunId);
  }

  Future<bool> _uploadPercent(
    MobileLiveTestController controller,
    int itemRunId,
    MobileLiveTestWorkflowAction action,
    int percent,
    String lat,
    String lng,
  ) async {
    final path = await _sampleJpegPath();
    final result = await controller.service.submitWorkflowAction(
      itemRunId,
      action,
      fields: {
        'action_id': action.id,
        'completion_percents': jsonEncode([percent]),
        'latitude': lat,
        'longitude': lng,
        'comment': 'Auto run $percent%',
        'upload_comment': 'Auto run $percent%',
      },
      files: [
        MobileLiveTestUploadPart(
          fieldName: 'files',
          filePath: path,
          filename: 'auto_run_$percent.jpg',
        ),
      ],
    );
    return _applyActionResult(controller, result, itemRunId);
  }

  Future<bool> _submitStatus(
    MobileLiveTestController controller,
    int itemRunId,
    MobileLiveTestWorkflowAction action,
  ) async {
    final statuses = action.allowedStatuses;
    final status = statuses.isNotEmpty ? statuses.first : 'Completed';
    final result = await controller.service.submitJsonAction(
      itemRunId,
      MobileLiveTestAccess.taskActionPath(itemRunId, 'status'),
      payload: {
        'action_id': action.id,
        'status': status,
        'comment': 'Auto run',
        if (action.showNote) 'note': 'Auto run',
      },
    );
    return _applyActionResult(controller, result, itemRunId);
  }

  Future<bool> _submitChecklist(
    MobileLiveTestController controller,
    int itemRunId,
    MobileLiveTestWorkflowAction action,
  ) async {
    final responses = <String, dynamic>{};
    for (final raw in action.items) {
      if (raw is! Map) continue;
      final map = Map<String, dynamic>.from(raw);
      final id = map['id']?.toString() ?? map['key']?.toString() ?? '';
      if (id.isEmpty) continue;
      final fieldType = (map['field_type'] ?? 'checkbox').toString();
      responses[id] = fieldType == 'checkbox' ? true : 'OK';
    }
    final result = await controller.service.submitJsonAction(
      itemRunId,
      MobileLiveTestAccess.taskActionPath(itemRunId, 'checklist'),
      payload: {
        'action_id': action.id,
        'responses': responses,
      },
    );
    return _applyActionResult(controller, result, itemRunId);
  }

  Future<bool> _submitTextList(
    MobileLiveTestController controller,
    int itemRunId,
    MobileLiveTestWorkflowAction action,
  ) async {
    final lines = <Map<String, dynamic>>[];
    for (final raw in action.items) {
      if (raw is! Map) continue;
      final map = Map<String, dynamic>.from(raw);
      final id = map['id']?.toString() ?? '';
      if (id.isEmpty) continue;
      lines.add({
        'id': id,
        'text': map['text'] ?? map['label'] ?? '',
        'quantity': map['quantity'] ?? map['qty'] ?? '1',
        'unit': map['unit'] ?? '',
      });
    }
    if (lines.isEmpty) return false;
    final result = await controller.service.submitJsonAction(
      itemRunId,
      MobileLiveTestAccess.taskActionPath(itemRunId, 'text-list'),
      payload: {
        'action_id': action.id,
        'lines': lines,
      },
    );
    return _applyActionResult(controller, result, itemRunId);
  }

  Future<bool> _completeDecision(
    MobileLiveTestController controller,
    int itemRunId,
    String? decision,
    String? actionId,
  ) async {
    final result = await controller.service.completeTask(
      itemRunId,
      decision: decision,
      actionId: actionId,
      comment: 'Auto run',
    );
    _applyIfCompleted(controller, result, itemRunId);
    return result.taskCompleted;
  }

  bool _applyActionResult(
    MobileLiveTestController controller,
    MobileLiveTestActionResult result,
    int itemRunId,
  ) {
    if (!result.success && !result.taskCompleted) {
      throw MobileLiveTestException(
        result.message.isNotEmpty ? result.message : 'Action failed.',
      );
    }
    if (result.taskCompleted) {
      _applyIfCompleted(
        controller,
        MobileLiveTestCompletionResult(
          success: true,
          taskCompleted: true,
          itemRunId: result.itemRunId > 0 ? result.itemRunId : itemRunId,
          message: result.message,
        ),
        itemRunId,
      );
      return true;
    }
    return false;
  }

  void _applyIfCompleted(
    MobileLiveTestController controller,
    MobileLiveTestCompletionResult result,
    int itemRunId,
  ) {
    if (result.taskCompleted) {
      controller.applyCompletionResult(result, itemRunId: itemRunId);
    }
  }

  static const _unsupportedTypes = {
    'kyp_material_shift',
    'picture_choice_list',
    'picture_choice_pick',
    'slot_selection',
    'slot_confirmation',
    'user_checklist',
    'user_checklist_followup',
  };

  bool _truthy(dynamic value) {
    if (value is bool) return value;
    if (value is num) return value != 0;
    final text = value?.toString().trim().toLowerCase() ?? '';
    return text == '1' || text == 'true' || text == 'yes';
  }
}

Future<String> writeMobileLiveTestSampleJpeg() async {
  final image = img.Image(width: 64, height: 64);
  img.fill(image, color: img.ColorRgb8(30, 64, 175));
  final bytes = img.encodeJpg(image, quality: 85);
  Directory dir;
  try {
    dir = await getTemporaryDirectory();
  } catch (_) {
    dir = Directory.systemTemp;
  }
  final file = File(
    '${dir.path}${Platform.pathSeparator}live_test_auto_${DateTime.now().millisecondsSinceEpoch}.jpg',
  );
  await file.writeAsBytes(bytes, flush: true);
  return file.path;
}
