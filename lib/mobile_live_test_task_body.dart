import 'dart:async';

import 'package:flutter/material.dart';

import 'mobile_live_test_actions.dart';
import 'mobile_live_test_widgets.dart';
import 'models/mobile_live_test.dart';
import 'services/mobile_live_test_controller.dart';
import 'services/mobile_live_test_service.dart';
import 'widgets/modern_task_card.dart';

/// Shared My Tasks-style task card body (list + detail screen).
class MobileLiveTestTaskBody extends StatefulWidget {
  final int itemRunId;
  final MobileLiveTestService service;
  final MobileLiveTestController? listController;
  final MobileLiveTestTask? listPreview;
  final bool showTestBadge;
  final VoidCallback? onUnavailable;
  final VoidCallback? onCompleted;

  const MobileLiveTestTaskBody({
    super.key,
    required this.itemRunId,
    required this.service,
    this.listController,
    this.listPreview,
    this.showTestBadge = false,
    this.onUnavailable,
    this.onCompleted,
  });

  @override
  State<MobileLiveTestTaskBody> createState() => _MobileLiveTestTaskBodyState();
}

class _MobileLiveTestTaskBodyState extends State<MobileLiveTestTaskBody> {
  final _commentController = TextEditingController();

  bool _loading = true;
  bool _submitting = false;
  String? _error;
  MobileLiveTestExecutionContext? _context;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(covariant MobileLiveTestTaskBody oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.itemRunId != widget.itemRunId) {
      _context = null;
      _load();
    }
  }

  @override
  void dispose() {
    _commentController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final context = await widget.service.openTask(widget.itemRunId);
      if (!mounted) return;
      setState(() {
        _context = context;
        _loading = false;
      });
    } on MobileLiveTestException catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.message;
        _loading = false;
      });
      if (e.isTaskUnavailable || e.isDeviceAuthFailure) {
        widget.onUnavailable?.call();
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString().replaceFirst('Exception: ', '');
        _loading = false;
      });
    }
  }

  Future<void> _refresh() async {
    try {
      final context = await widget.service.openTask(
        widget.itemRunId,
        forceRefresh: true,
      );
      if (!mounted) return;
      setState(() {
        _context = context;
        _error = null;
      });
    } on MobileLiveTestException catch (e) {
      if (!mounted) return;
      setState(() => _error = e.message);
      if (e.isTaskUnavailable || e.isDeviceAuthFailure) {
        widget.onUnavailable?.call();
      }
    }
  }

  Future<void> _handleComplete({
    String? decision,
    String? actionId,
    String? comment,
  }) async {
    if (comment != null && comment.trim().isNotEmpty) {
      _commentController.text = comment.trim();
    }
    await _complete(decision: decision, actionId: actionId);
  }

  Future<bool> _complete({
    String? decision,
    String? actionId,
  }) async {
    if (_submitting || _context == null) return false;
    setState(() => _submitting = true);
    try {
      final result = await widget.service.completeTask(
        widget.itemRunId,
        decision: decision,
        comment: _commentController.text,
        actionId: actionId,
      );
      final completed = result.success && result.taskCompleted;
      if (completed) {
        widget.listController?.applyCompletionResult(
          result,
          itemRunId: widget.itemRunId,
        );
      }
      if (!mounted) return completed;
      if (completed) {
        widget.onCompleted?.call();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              result.message.isNotEmpty
                  ? result.message
                  : 'Task completed through the real workflow engine.',
            ),
            duration: const Duration(seconds: 2),
          ),
        );
        return true;
      }
      setState(() {
        _submitting = false;
        _error = result.message.isNotEmpty
            ? result.message
            : 'Could not complete this task.';
      });
      return false;
    } on MobileLiveTestException catch (e) {
      if (!mounted) return false;
      setState(() {
        _submitting = false;
        _error = e.message;
      });
      if (e.isTaskUnavailable) {
        widget.onUnavailable?.call();
      }
      return false;
    } catch (e) {
      if (!mounted) return false;
      setState(() {
        _submitting = false;
        _error = e.toString().replaceFirst('Exception: ', '');
      });
      return false;
    }
  }

  MobileLiveTestWorkflowAction? _findSwipeCompleteAction(
    MobileLiveTestTaskDetail task,
  ) {
    for (final action in task.workflowActions) {
      if (action.type == 'complete_button' && !action.blocked) {
        return action;
      }
    }
    return null;
  }

  Future<bool> Function()? _swipeCompleteHandler(MobileLiveTestTaskDetail task) {
    if (!task.canComplete || _submitting || task.showActionButtons) {
      return null;
    }
    final completeAction = _findSwipeCompleteAction(task);
    if (completeAction == null && !task.showPlainComplete) {
      return null;
    }
    return () => _complete(actionId: completeAction?.id);
  }

  String _swipeCompleteLabel(MobileLiveTestTaskDetail task) {
    final action = _findSwipeCompleteAction(task);
    if (action != null && action.label.trim().isNotEmpty) {
      return 'Swipe to ${toSentenceCaseLabel(action.label).toLowerCase()}';
    }
    return 'Swipe to complete';
  }

  List<Widget> _buildCardFooter(
    MobileLiveTestExecutionContext execution,
    MobileLiveTestTaskDetail task,
  ) {
    final actingUser = execution.actingUser;
    final authUser = execution.authenticatedUser;
    final children = <Widget>[];

    children.add(
      _ActingAsFooterLine(
        authenticatedUser: authUser,
        actingUser: actingUser,
      ),
    );

    final description = task.description.trim();
    if (description.isNotEmpty) {
      children.add(const SizedBox(height: 8));
      children.add(
        Text(
          description,
          style: const TextStyle(
            color: kTaskMuted,
            fontSize: 12.5,
            fontWeight: FontWeight.w500,
            height: 1.4,
          ),
        ),
      );
    }

    if (_error != null) {
      children.add(const SizedBox(height: 10));
      children.add(MobileLiveTestErrorBanner(message: _error!));
    }

    if (task.mandatoryUploadsPending) {
      children.add(const SizedBox(height: 10));
      children.add(MobileLiveTestWarningBanner(message: task.unsupportedMessage));
    } else if (task.hasUnsupportedRequirements) {
      children.add(const SizedBox(height: 10));
      children.add(
        MobileLiveTestWarningBanner(message: task.unsupportedMessage),
      );
    } else if (task.blockReason.trim().isNotEmpty && !task.canComplete) {
      children.add(const SizedBox(height: 10));
      children.add(MobileLiveTestWarningBanner(message: task.blockReason));
    }

    if (task.interactiveActions.isNotEmpty) {
      children.add(const SizedBox(height: 10));
      children.add(
        MobileLiveTestActionsSection(
          itemRunId: widget.itemRunId,
          task: task,
          service: widget.service,
          busy: _submitting,
          onRefresh: _refresh,
          onComplete: _handleComplete,
          onTaskFinished: (message) async {
            widget.listController?.dismissTask(widget.itemRunId);
            widget.listController?.service.invalidateOpenTaskCache(
              widget.itemRunId,
            );
            if (message != null && message.trim().isNotEmpty && mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(message.trim()),
                  duration: const Duration(seconds: 2),
                ),
              );
            }
            unawaited(widget.listController?.refreshAfterTaskCompletion());
            widget.onCompleted?.call();
          },
          onError: (message) => setState(() => _error = message),
        ),
      );
    }

    if (task.showActionButtons || task.showPlainComplete) {
      children.add(const SizedBox(height: 10));
      children.add(
        MobileLiveTestCompletionSection(
          task: task,
          busy: _submitting,
          commentController: _commentController,
          onComplete: _handleComplete,
          embeddedInCardFooter: true,
        ),
      );
    }

    return children;
  }

  @override
  Widget build(BuildContext context) {
    final execution = _context;
    final preview = widget.listPreview;
    final task = execution?.task;

    if (_loading && execution == null) {
      return ModernTaskCard(
        title: preview?.name.isNotEmpty == true ? preview!.name : 'Task',
        projectName: 'Mobile live test',
        assigneeName: preview?.assignedUserName,
        dateLabel: preview?.role,
        status: preview?.status ?? 'ready',
        statusLabel: preview?.statusLabel,
        accentIndex: widget.itemRunId % 6,
        margin: EdgeInsets.zero,
        footer: const Padding(
          padding: EdgeInsets.only(top: 8),
          child: Center(
            child: SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
          ),
        ),
      );
    }

    if (execution == null || task == null) {
      return MobileLiveTestErrorBanner(
        message: _error ?? 'Could not load this test task.',
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (widget.showTestBadge) ...[
          const _TestBadge(),
          const SizedBox(height: 10),
        ],
        ModernTaskCard(
          title: task.name,
          projectName: 'Mobile live test',
          assigneeName: execution.actingUser?.name.isNotEmpty == true
              ? execution.actingUser!.name
              : task.assignee,
          dateLabel: execution.actingUser?.role.isNotEmpty == true
              ? execution.actingUser!.role
              : task.role,
          status: task.status,
          statusLabel: task.statusLabel,
          accentIndex: widget.itemRunId % 6,
          margin: EdgeInsets.zero,
          onSwipeComplete: _swipeCompleteHandler(task),
          swipeCompleteLabel: _swipeCompleteLabel(task),
          footer: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: _buildCardFooter(execution, task),
          ),
        ),
        const SizedBox(height: 16),
        MobileLiveTestCommentsSection(
          itemRunId: widget.itemRunId,
          initialComments: task.comments,
          service: widget.service,
          busy: _submitting,
          onRefresh: _refresh,
          onError: (message) => setState(() => _error = message),
          embeddedInCardFooter: true,
        ),
      ],
    );
  }
}

class _TestBadge extends StatelessWidget {
  const _TestBadge();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: const Color(0xFFECFDF5),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: const Color(0xFF86EFAC)),
      ),
      child: const Text(
        'MOBILE LIVE TEST',
        style: TextStyle(
          color: Color(0xFF047857),
          fontWeight: FontWeight.w800,
          letterSpacing: 0.5,
          fontSize: 11,
        ),
      ),
    );
  }
}

class _ActingAsFooterLine extends StatelessWidget {
  final MobileLiveTestUser? authenticatedUser;
  final MobileLiveTestUser? actingUser;

  const _ActingAsFooterLine({
    required this.authenticatedUser,
    required this.actingUser,
  });

  @override
  Widget build(BuildContext context) {
    final actingLabel = actingUser?.name.isNotEmpty == true
        ? '${actingUser!.name} (${actingUser!.role})'
        : 'Mapped test user';
    final loggedIn = authenticatedUser?.name.isNotEmpty == true
        ? '${authenticatedUser!.name} (${authenticatedUser!.role})'
        : 'Super Admin';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Acting as $actingLabel',
          style: const TextStyle(
            color: kTaskNavy,
            fontSize: 12.5,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          'Logged-in user: $loggedIn',
          style: const TextStyle(
            color: kTaskMuted,
            fontSize: 11.5,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }
}
