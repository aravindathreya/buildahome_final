import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import 'app_theme.dart';
import 'mobile_live_test_media.dart';
import 'mobile_live_test_widgets.dart';
import 'models/mobile_live_test.dart';
import 'services/mobile_live_test_access.dart';
import 'services/mobile_live_test_service.dart';

import 'widgets/modern_task_card.dart';

typedef LiveTestRefreshCallback = Future<void> Function();
typedef LiveTestCompleteCallback = Future<void> Function({
  String? decision,
  String? actionId,
  String? comment,
});
typedef LiveTestErrorCallback = void Function(String message);

typedef LiveTestTaskFinishedCallback = Future<void> Function(String? message);

/// Renders workflow `task.actions` from the live-test open payload.
class MobileLiveTestActionsSection extends StatelessWidget {
  final int itemRunId;
  final MobileLiveTestTaskDetail task;
  final MobileLiveTestService service;
  final bool busy;
  final LiveTestRefreshCallback onRefresh;
  final LiveTestCompleteCallback onComplete;
  final LiveTestTaskFinishedCallback? onTaskFinished;
  final LiveTestErrorCallback onError;

  const MobileLiveTestActionsSection({
    super.key,
    required this.itemRunId,
    required this.task,
    required this.service,
    required this.busy,
    required this.onRefresh,
    required this.onComplete,
    this.onTaskFinished,
    required this.onError,
  });

  @override
  Widget build(BuildContext context) {
    final actions = task.interactiveActions;
    if (actions.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const MobileLiveTestSectionHeader(title: 'Actions'),
        const SizedBox(height: 12),
        Wrap(
          spacing: 10,
          runSpacing: 10,
          children: actions
              .map(
                (action) => MobileLiveTestActionChipLauncher(
                  itemRunId: itemRunId,
                  action: action,
                  service: service,
                  busy: busy,
                  onRefresh: onRefresh,
                  onComplete: onComplete,
                  onTaskFinished: onTaskFinished,
                  onError: onError,
                ),
              )
              .toList(),
        ),
      ],
    );
  }
}

/// Tappable action chip that opens a bottom sheet (My Tasks parity).
class MobileLiveTestActionChipLauncher extends StatefulWidget {
  final int itemRunId;
  final MobileLiveTestWorkflowAction action;
  final MobileLiveTestService service;
  final bool busy;
  final LiveTestRefreshCallback onRefresh;
  final LiveTestCompleteCallback onComplete;
  final LiveTestTaskFinishedCallback? onTaskFinished;
  final LiveTestErrorCallback onError;

  const MobileLiveTestActionChipLauncher({
    super.key,
    required this.itemRunId,
    required this.action,
    required this.service,
    required this.busy,
    required this.onRefresh,
    required this.onComplete,
    this.onTaskFinished,
    required this.onError,
  });

  @override
  State<MobileLiveTestActionChipLauncher> createState() =>
      _MobileLiveTestActionChipLauncherState();
}

class _MobileLiveTestActionChipLauncherState
    extends State<MobileLiveTestActionChipLauncher> {
  bool _opening = false;

  String _chipLabel() {
    final action = widget.action;
    if (action.type == 'user_checklist_followup') {
      return 'Checklist follow-up';
    }
    final meta = workflowActionChipMeta(action.type);
    final label = action.label.trim();
    return toSentenceCaseLabel(label.isEmpty ? meta.defaultLabel : label);
  }

  WorkflowActionChipMeta _chipMeta() => workflowActionChipMeta(widget.action.type);

  Future<void> _handleTap() async {
    final action = widget.action;
    if (widget.busy || _opening) return;

    if (action.blocked && action.blockedMessage.isNotEmpty) {
      widget.onError(action.blockedMessage);
      return;
    }

    if (action.type == 'complete_button') {
      setState(() => _opening = true);
      try {
        await widget.onComplete(actionId: action.id);
      } finally {
        if (mounted) setState(() => _opening = false);
      }
      return;
    }

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) {
        final meta = _chipMeta();
        return MobileLiveTestBottomSheetFrame(
          title: _chipLabel(),
          icon: meta.icon,
          child: _MobileLiveTestActionSheetBody(
            itemRunId: widget.itemRunId,
            actionId: action.id,
            service: widget.service,
            busy: widget.busy,
            onComplete: widget.onComplete,
            onTaskFinished: widget.onTaskFinished,
            onError: widget.onError,
          ),
        );
      },
    );
    if (mounted) {
      await widget.onRefresh();
    }
  }

  @override
  Widget build(BuildContext context) {
    final action = widget.action;
    final meta = _chipMeta();
    final blocked = action.blocked && action.blockedMessage.isNotEmpty;
    return MobileLiveTestWorkflowActionChip(
      label: _chipLabel(),
      icon: meta.icon,
      color: meta.color,
      isOutlined: meta.outlined,
      isLoading: _opening,
      visuallyDisabled: blocked,
      onPressed: widget.busy ? null : _handleTap,
    );
  }
}

/// Keeps sheet action state in sync after uploads / form saves.
class _MobileLiveTestActionSheetBody extends StatefulWidget {
  final int itemRunId;
  final String actionId;
  final MobileLiveTestService service;
  final bool busy;
  final LiveTestCompleteCallback onComplete;
  final LiveTestTaskFinishedCallback? onTaskFinished;
  final LiveTestErrorCallback onError;

  const _MobileLiveTestActionSheetBody({
    required this.itemRunId,
    required this.actionId,
    required this.service,
    required this.busy,
    required this.onComplete,
    this.onTaskFinished,
    required this.onError,
  });

  @override
  State<_MobileLiveTestActionSheetBody> createState() =>
      _MobileLiveTestActionSheetBodyState();
}

class _MobileLiveTestActionSheetBodyState
    extends State<_MobileLiveTestActionSheetBody> {
  MobileLiveTestWorkflowAction? _action;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  Future<void> _reload() async {
    try {
      final context = await widget.service.openTask(widget.itemRunId);
      final match = context.task.workflowActions
          .where((a) => a.id == widget.actionId)
          .toList();
      if (!mounted) return;
      setState(() {
        _action = match.isNotEmpty ? match.first : null;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);
      widget.onError(
        e.toString().replaceFirst('Exception: ', ''),
      );
    }
  }

  Future<void> _refresh() async {
    await _reload();
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: CircularProgressIndicator(),
        ),
      );
    }
    final action = _action;
    if (action == null) {
      return const Text(
        'This action is no longer available.',
        style: TextStyle(color: AppTheme.mutedGrey),
      );
    }
    return MobileLiveTestActionCard(
      itemRunId: widget.itemRunId,
      action: action,
      service: widget.service,
      busy: widget.busy,
      embeddedInSheet: true,
      onRefresh: _refresh,
      onComplete: widget.onComplete,
      onTaskFinished: widget.onTaskFinished,
      onError: widget.onError,
      onCloseSheet: () => Navigator.pop(context),
    );
  }
}

class MobileLiveTestActionCard extends StatefulWidget {
  final int itemRunId;
  final MobileLiveTestWorkflowAction action;
  final MobileLiveTestService service;
  final bool busy;
  final bool embeddedInSheet;
  final LiveTestRefreshCallback onRefresh;
  final LiveTestCompleteCallback onComplete;
  final LiveTestTaskFinishedCallback? onTaskFinished;
  final LiveTestErrorCallback onError;
  final VoidCallback? onCloseSheet;

  const MobileLiveTestActionCard({
    super.key,
    required this.itemRunId,
    required this.action,
    required this.service,
    required this.busy,
    this.embeddedInSheet = false,
    required this.onRefresh,
    required this.onComplete,
    this.onTaskFinished,
    required this.onError,
    this.onCloseSheet,
  });

  @override
  State<MobileLiveTestActionCard> createState() =>
      _MobileLiveTestActionCardState();
}

class _MobileLiveTestActionCardState extends State<MobileLiveTestActionCard> {
  bool _submitting = false;
  final _commentController = TextEditingController();
  final _percentController = TextEditingController();
  String? _selectedStatus;
  final Map<String, dynamic> _checklistResponses = {};
  final Map<String, TextEditingController> _lineControllers = {};
  List<String> _selectedFiles = [];
  String? _pendingPercentFile;
  String? _percentError;
  double? _uploadLatitude;
  double? _uploadLongitude;
  double? _pendingVideoDurationSeconds;

  @override
  void dispose() {
    _commentController.dispose();
    _percentController.dispose();
    for (final c in _lineControllers.values) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _run(Future<void> Function() work) async {
    if (_submitting || widget.busy) return;
    setState(() => _submitting = true);
    try {
      await work();
    } on MobileLiveTestException catch (e) {
      widget.onError(e.message);
    } on TimeoutException {
      widget.onError(
        'Upload timed out. Check your connection and try a smaller file.',
      );
    } catch (e) {
      widget.onError(e.toString().replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  Future<void> _afterAction(MobileLiveTestActionResult result) async {
    if (result.message.trim().isNotEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(result.message.trim())),
      );
    }
    if (result.taskCompleted) {
      widget.onCloseSheet?.call();
      if (widget.onTaskFinished != null) {
        await widget.onTaskFinished!(result.message);
      } else {
        await widget.onRefresh();
      }
      return;
    }
    await widget.onRefresh();
  }

  Future<void> _pickFiles() async {
    final result = await FilePicker.platform.pickFiles(allowMultiple: true);
    if (result == null) return;
    setState(() {
      _selectedFiles = result.paths.whereType<String>().toList();
    });
  }

  Future<void> _pickImage(ImageSource source) async {
    final action = widget.action;
    if (source == ImageSource.gallery &&
        (!action.allowGalleryUpload || action.liveImageOnly || action.requireNearSite)) {
      widget.onError('Gallery is not allowed for this upload.');
      return;
    }
    final picker = ImagePicker();
    final image = await picker.pickImage(source: source, imageQuality: 85);
    if (image == null) return;
    setState(() {
      if (widget.action.addPercentToTask) {
        _pendingPercentFile = image.path;
        _percentError = null;
      } else {
        _selectedFiles = [image.path];
      }
    });
  }

  Future<void> _pickVideo() async {
    final action = widget.action;
    try {
      final file = await recordMobileLiveTestVideo(
        context: context,
        maxDurationSeconds: action.maxVideoDurationSeconds ?? 60,
        maxSizeMb: action.maxVideoSizeMb ?? 50,
      );
      if (file == null) return;
      setState(() {
        _selectedFiles = [file.path];
        _pendingVideoDurationSeconds = file.videoDurationSeconds;
      });
    } on MobileLiveTestMediaException catch (e) {
      widget.onError(e.message);
    }
  }

  Future<bool> _ensureGpsForUpload(MobileLiveTestWorkflowAction action) async {
    if (!action.needsGpsForUpload) return true;
    // Live Test never requires being physically at the project site.
    final site = action.siteLocation;
    _uploadLatitude = site?.latitude ?? 12.9716;
    _uploadLongitude = site?.longitude ?? 77.5946;
    return true;
  }

  Map<String, String> _withGpsFields(
    Map<String, String> fields,
    MobileLiveTestWorkflowAction action,
  ) {
    if (_uploadLatitude != null && _uploadLongitude != null) {
      fields['latitude'] = _uploadLatitude!.toString();
      fields['longitude'] = _uploadLongitude!.toString();
    }
    if (action.liveImageOnly) {
      fields['live_image_only'] = 'true';
    }
    if (_pendingVideoDurationSeconds != null) {
      fields['video_duration_seconds'] =
          _pendingVideoDurationSeconds!.toString();
    }
    return fields;
  }

  Future<void> _pickSingleFile() async {
    final result = await FilePicker.platform.pickFiles(allowMultiple: false);
    final path = result?.files.single.path;
    if (path == null || path.isEmpty) return;
    setState(() {
      _pendingPercentFile = path;
      _percentError = null;
    });
  }

  Future<void> _submitUpload() async {
    if (widget.action.addPercentToTask) {
      await _submitPercentUpload();
      return;
    }
    if (_selectedFiles.isEmpty) {
      widget.onError('Select a file to upload.');
      return;
    }
    if (!await _ensureGpsForUpload(widget.action)) return;
    final fields = _withGpsFields(<String, String>{
      'action_id': widget.action.id,
    }, widget.action);
    final comment = _commentController.text.trim();
    if (comment.isNotEmpty) {
      fields['upload_comment'] = comment;
      fields['comment'] = comment;
    }
    final parts = _selectedFiles
        .map(
          (path) => MobileLiveTestUploadPart(
            fieldName: 'files',
            filePath: path,
            filename: path.split(Platform.pathSeparator).last,
          ),
        )
        .toList();
    await _run(() async {
      final result = await widget.service.submitWorkflowAction(
        widget.itemRunId,
        widget.action,
        fields: fields,
        files: parts,
      );
      setState(() {
        _selectedFiles = [];
        _pendingVideoDurationSeconds = null;
      });
      await _afterAction(result);
    });
  }

  Future<void> _submitPercentUpload() async {
    if (_pendingPercentFile == null) {
      widget.onError('Select a file to upload.');
      return;
    }
    final current = widget.action.currentPercent ?? 0;
    final validation =
        widget.action.validatePercentInput(_percentController.text, current);
    if (validation != null) {
      setState(() => _percentError = validation);
      widget.onError(validation);
      return;
    }
    if (!await _ensureGpsForUpload(widget.action)) return;
    final percentValue = int.parse(_percentController.text.trim());
    final fields = _withGpsFields(<String, String>{
      'action_id': widget.action.id,
      'completion_percents': jsonEncode([percentValue]),
    }, widget.action);
    final parts = [
      MobileLiveTestUploadPart(
        fieldName: 'files',
        filePath: _pendingPercentFile!,
        filename: _pendingPercentFile!.split(Platform.pathSeparator).last,
      ),
    ];
    await _run(() async {
      final result = await widget.service.submitWorkflowAction(
        widget.itemRunId,
        widget.action,
        fields: fields,
        files: parts,
      );
      setState(() {
        _pendingPercentFile = null;
        _percentController.clear();
        _percentError = null;
      });
      await _afterAction(result);
    });
  }

  Future<void> _finalizePercentUpload() async {
    final action = widget.action;
    if ((action.currentPercent ?? 0) < 100) {
      widget.onError('Upload progress must reach 100% before finishing.');
      return;
    }
    if (action.requireComment && _commentController.text.trim().isEmpty) {
      widget.onError('Please add a comment.');
      return;
    }
    final fields = <String, String>{
      'action_id': action.id,
      'finalize': '1',
    };
    final comment = _commentController.text.trim();
    if (comment.isNotEmpty) {
      fields['upload_comment'] = comment;
      fields['comment'] = comment;
    }
    await _run(() async {
      final result = await widget.service.submitWorkflowAction(
        widget.itemRunId,
        action,
        fields: fields,
        files: const [],
      );
      await _afterAction(result);
    });
  }

  Future<void> _submitChecklist() async {
    final items = widget.action.items;
    for (final raw in items) {
      if (raw is! Map) continue;
      final map = Map<String, dynamic>.from(raw);
      final id = map['id']?.toString() ?? map['key']?.toString() ?? '';
      if (map['required'] == true && !_hasValue(_checklistResponses[id])) {
        widget.onError('${map['label'] ?? 'Item'} is required.');
        return;
      }
    }
    await _run(() async {
      final result = await widget.service.submitJsonAction(
        widget.itemRunId,
        MobileLiveTestAccess.taskActionPath(widget.itemRunId, 'checklist'),
        payload: {
          'action_id': widget.action.id,
          'responses': _checklistResponses,
        },
      );
      await _afterAction(result);
    });
  }

  Future<void> _submitStatus() async {
    final status = (_selectedStatus ?? '').trim();
    if (status.isEmpty) {
      widget.onError('Select a status.');
      return;
    }
    if (widget.action.requireComment &&
        _commentController.text.trim().isEmpty) {
      widget.onError('Comment is required.');
      return;
    }
    await _run(() async {
      final result = await widget.service.submitJsonAction(
        widget.itemRunId,
        MobileLiveTestAccess.taskActionPath(widget.itemRunId, 'status'),
        payload: {
          'action_id': widget.action.id,
          'status': status,
          'comment': _commentController.text.trim(),
          if (widget.action.showNote)
            'note': _commentController.text.trim(),
        },
      );
      await _afterAction(result);
    });
  }

  Future<void> _submitTextList() async {
    final lines = <Map<String, dynamic>>[];
    for (final raw in widget.action.items) {
      if (raw is! Map) continue;
      final map = Map<String, dynamic>.from(raw);
      final id = map['id']?.toString() ?? '';
      final controller = _lineControllers[id];
      final qty = controller?.text.trim() ?? '';
      if (qty.isNotEmpty) {
        lines.add({
          'id': id,
          'text': map['text'] ?? map['label'] ?? '',
          'quantity': qty,
          'unit': map['unit'] ?? '',
        });
      }
    }
    if (lines.isEmpty) {
      widget.onError('Enter at least one line value.');
      return;
    }
    await _run(() async {
      final result = await widget.service.submitJsonAction(
        widget.itemRunId,
        MobileLiveTestAccess.taskActionPath(widget.itemRunId, 'text-list'),
        payload: {
          'action_id': widget.action.id,
          'lines': lines,
        },
      );
      await _afterAction(result);
    });
  }

  Future<void> _submitGenericJson() async {
    await _run(() async {
      final result = await widget.service.submitWorkflowAction(
        widget.itemRunId,
        widget.action,
        jsonPayload: {
          'action_id': widget.action.id,
          if (_commentController.text.trim().isNotEmpty)
            'comment': _commentController.text.trim(),
        },
      );
      await _afterAction(result);
    });
  }

  List<Widget> _buildStandardUploadFields(bool loading) {
    final action = widget.action;
    final showGallery = action.allowGalleryUpload;
    final showCamera = action.allowLiveCamera;
    final showVideo = action.allowVideoUpload;
    return [
      Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          if (showGallery)
            OutlinedButton.icon(
              onPressed: loading ? null : () => _pickImage(ImageSource.gallery),
              icon: const Icon(Icons.photo_library_outlined, size: 18),
              label: const Text('Gallery'),
            ),
          if (showCamera)
            OutlinedButton.icon(
              onPressed: loading ? null : () => _pickImage(ImageSource.camera),
              icon: const Icon(Icons.photo_camera_outlined, size: 18),
              label: const Text('Camera'),
            ),
          if (showVideo)
            OutlinedButton.icon(
              onPressed: loading ? null : _pickVideo,
              icon: const Icon(Icons.videocam_outlined, size: 18),
              label: const Text('Video'),
            ),
          OutlinedButton.icon(
            onPressed: loading ? null : _pickFiles,
            icon: const Icon(Icons.attach_file, size: 18),
            label: const Text('File'),
          ),
        ],
      ),
      if (_selectedFiles.isNotEmpty) ...[
        const SizedBox(height: 8),
        ..._selectedFiles.map(
          (path) => Text(
            path.split(Platform.pathSeparator).last,
            style: const TextStyle(color: AppTheme.navySoft),
          ),
        ),
      ],
      if (action.allowComment) ...[
        const SizedBox(height: 10),
        TextField(
          controller: _commentController,
          enabled: !loading,
          decoration: const InputDecoration(
            labelText: 'Upload comment (optional)',
            border: OutlineInputBorder(),
          ),
        ),
      ],
      const SizedBox(height: 12),
      MobileLiveTestActionButton(
        label: 'UPLOAD',
        backgroundColor: AppTheme.navy,
        loading: loading,
        onPressed: _submitUpload,
      ),
    ];
  }

  List<Widget> _buildPercentUploadFields(bool loading) {
    final action = widget.action;
    final current = action.currentPercent ?? 0;
    final minNext = action.minNextPercent;
    final atFullProgress = current >= 100;

    return [
      Row(
        children: [
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: LinearProgressIndicator(
                value: current / 100,
                minHeight: 8,
                backgroundColor: AppTheme.border,
                color: const Color(0xFF16A34A),
              ),
            ),
          ),
          const SizedBox(width: 10),
          Text(
            '$current%',
            style: const TextStyle(
              fontWeight: FontWeight.w800,
              color: AppTheme.navy,
            ),
          ),
        ],
      ),
      const SizedBox(height: 6),
      Text(
        'Add completion % for each document until you reach 100%.',
        style: TextStyle(
          color: AppTheme.mutedGrey,
          fontSize: 12,
          fontWeight: FontWeight.w500,
        ),
      ),
      if (action.progressEntries.isNotEmpty) ...[
        const SizedBox(height: 12),
        ...action.progressEntries.whereType<Map>().map((raw) {
          final entry = Map<String, dynamic>.from(raw);
          final pct = entry['percent'] ?? entry['completion_percent'];
          final files = entry['files'];
          String name = 'Document';
          if (files is List && files.isNotEmpty && files.first is Map) {
            final file = Map<String, dynamic>.from(files.first as Map);
            name = (file['original_filename'] ??
                    file['filename'] ??
                    file['name'] ??
                    'Document')
                .toString();
          }
          return Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: Text(
              '${pct ?? '—'}% — $name',
              style: const TextStyle(
                color: AppTheme.navySoft,
                fontWeight: FontWeight.w600,
                fontSize: 13,
              ),
            ),
          );
        }),
      ],
      if (!atFullProgress) ...[
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            OutlinedButton.icon(
              onPressed: loading ? null : () => _pickImage(ImageSource.gallery),
              icon: const Icon(Icons.photo_library_outlined, size: 18),
              label: const Text('Gallery'),
            ),
            OutlinedButton.icon(
              onPressed: loading ? null : () => _pickImage(ImageSource.camera),
              icon: const Icon(Icons.photo_camera_outlined, size: 18),
              label: const Text('Camera'),
            ),
            OutlinedButton.icon(
              onPressed: loading ? null : _pickSingleFile,
              icon: const Icon(Icons.attach_file, size: 18),
              label: const Text('File'),
            ),
          ],
        ),
        if (_pendingPercentFile != null) ...[
          const SizedBox(height: 8),
          Text(
            _pendingPercentFile!.split(Platform.pathSeparator).last,
            style: const TextStyle(color: AppTheme.navySoft),
          ),
        ],
        const SizedBox(height: 10),
        TextField(
          controller: _percentController,
          enabled: !loading,
          keyboardType: TextInputType.number,
          decoration: InputDecoration(
            labelText: 'Completion % (min $minNext%)',
            hintText: 'e.g. $minNext',
            errorText: _percentError,
            border: const OutlineInputBorder(),
          ),
          onChanged: (_) {
            if (_percentError != null) {
              setState(() => _percentError = null);
            }
          },
        ),
        const SizedBox(height: 12),
        MobileLiveTestActionButton(
          label: 'SAVE DOCUMENT',
          backgroundColor: AppTheme.navy,
          loading: loading,
          onPressed: _submitPercentUpload,
        ),
      ],
      if (atFullProgress) ...[
        const SizedBox(height: 12),
        const Text(
          'Progress is at 100%. Add a comment and finish this upload.',
          style: TextStyle(
            color: AppTheme.navySoft,
            fontWeight: FontWeight.w600,
          ),
        ),
        if (action.allowComment) ...[
          const SizedBox(height: 10),
          TextField(
            controller: _commentController,
            enabled: !loading,
            decoration: InputDecoration(
              labelText: action.requireComment
                  ? 'Comment (required)'
                  : 'Comment (optional)',
              border: const OutlineInputBorder(),
            ),
          ),
        ],
        const SizedBox(height: 12),
        MobileLiveTestActionButton(
          label: 'FINISH UPLOAD',
          backgroundColor: const Color(0xFF16A34A),
          loading: loading,
          onPressed: _finalizePercentUpload,
        ),
      ],
    ];
  }

  bool _hasValue(dynamic value) {
    if (value == null) return false;
    if (value is bool) return value;
    return value.toString().trim().isNotEmpty;
  }

  @override
  Widget build(BuildContext context) {
    final action = widget.action;
    if (!widget.embeddedInSheet &&
        action.blocked &&
        action.blockedMessage.isNotEmpty) {
      return MobileLiveTestWarningBanner(message: action.blockedMessage);
    }

    final fields = _buildFields(context);
    if (widget.embeddedInSheet) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (action.documentName.trim().isNotEmpty &&
              action.documentName.trim() != action.label.trim())
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text(
                action.documentName,
                style: const TextStyle(
                  color: AppTheme.navySoft,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          if (action.isSubmitted) ...[
            const Text(
              'Saved',
              style: TextStyle(
                color: Color(0xFF047857),
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 12),
          ],
          if (action.blocked && action.blockedMessage.isNotEmpty) ...[
            MobileLiveTestWarningBanner(message: action.blockedMessage),
            const SizedBox(height: 12),
          ],
          ...fields,
        ],
      );
    }

    final title = _titleForType(action.type);
    return MobileLiveTestPanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(
              fontWeight: FontWeight.w800,
              color: AppTheme.navy,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            action.documentName,
            style: const TextStyle(
              color: AppTheme.navySoft,
              fontWeight: FontWeight.w600,
            ),
          ),
          if (action.isSubmitted) ...[
            const SizedBox(height: 8),
            const Text(
              'Saved',
              style: TextStyle(
                color: Color(0xFF047857),
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
          const SizedBox(height: 12),
          ...fields,
        ],
      ),
    );
  }

  String _titleForType(String type) {
    switch (type) {
      case 'upload':
        return '📤 Required upload';
      case 'update_status':
        return '📝 Status';
      case 'checklist':
      case 'user_checklist':
      case 'user_checklist_followup':
        return '☑ Checklist';
      case 'text_list':
      case 'kyp_material_shift':
        return '📝 Required form';
      case 'yes_no':
        return '❓ Decision';
      case 'view_prior_response':
        return '👁 Review';
      default:
        return '⚙️ Action';
    }
  }

  List<Widget> _buildFields(BuildContext context) {
    final action = widget.action;
    final loading = _submitting || widget.busy;

    switch (action.type) {
      case 'upload':
        if (action.addPercentToTask) {
          return _buildPercentUploadFields(loading);
        }
        return _buildStandardUploadFields(loading);
      case 'checklist':
        return [
          ...action.items.map((raw) {
            if (raw is! Map) return const SizedBox.shrink();
            final item = Map<String, dynamic>.from(raw);
            final id = item['id']?.toString() ?? item['key']?.toString() ?? '';
            final label = item['label']?.toString() ?? 'Item';
            final fieldType = item['field_type']?.toString() ?? 'checkbox';
            if (fieldType == 'checkbox') {
              return CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(label),
                value: _checklistResponses[id] == true,
                onChanged: loading
                    ? null
                    : (v) => setState(() => _checklistResponses[id] = v == true),
              );
            }
            return Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: TextField(
                enabled: !loading,
                decoration: InputDecoration(
                  labelText: label,
                  border: const OutlineInputBorder(),
                ),
                onChanged: (v) => _checklistResponses[id] = v,
              ),
            );
          }),
          const SizedBox(height: 8),
          MobileLiveTestActionButton(
            label: 'SAVE CHECKLIST',
            backgroundColor: AppTheme.navy,
            loading: loading,
            onPressed: _submitChecklist,
          ),
        ];
      case 'update_status':
        return [
          DropdownButtonFormField<String>(
            initialValue: _selectedStatus,
            decoration: const InputDecoration(
              labelText: 'Status',
              border: OutlineInputBorder(),
            ),
            items: action.allowedStatuses
                .map(
                  (s) => DropdownMenuItem(value: s, child: Text(s)),
                )
                .toList(),
            onChanged: loading ? null : (v) => setState(() => _selectedStatus = v),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _commentController,
            enabled: !loading,
            decoration: InputDecoration(
              labelText: action.requireComment
                  ? 'Comment (required)'
                  : 'Comment (optional)',
              border: const OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 12),
          MobileLiveTestActionButton(
            label: 'SAVE',
            backgroundColor: AppTheme.navy,
            loading: loading,
            onPressed: _submitStatus,
          ),
        ];
      case 'text_list':
        return [
          ...action.items.map((raw) {
            if (raw is! Map) return const SizedBox.shrink();
            final item = Map<String, dynamic>.from(raw);
            final id = item['id']?.toString() ?? '';
            _lineControllers.putIfAbsent(id, TextEditingController.new);
            final label = item['text']?.toString() ??
                item['label']?.toString() ??
                'Line';
            return Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: TextField(
                controller: _lineControllers[id],
                enabled: !loading,
                decoration: InputDecoration(
                  labelText: label,
                  border: const OutlineInputBorder(),
                ),
              ),
            );
          }),
          const SizedBox(height: 8),
          MobileLiveTestActionButton(
            label: 'SAVE',
            backgroundColor: AppTheme.navy,
            loading: loading,
            onPressed: _submitTextList,
          ),
        ];
      case 'yes_no':
        return [
          Row(
            children: [
              Expanded(
                child: ElevatedButton(
                  onPressed: loading
                      ? null
                      : () => _run(() async {
                            await widget.onComplete(
                              decision: 'yes',
                              actionId: action.id,
                            );
                            widget.onCloseSheet?.call();
                          }),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF10B981),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                  child: Text(toSentenceCaseLabel(action.yesLabel)),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: OutlinedButton(
                  onPressed: loading
                      ? null
                      : () => _run(() async {
                            await widget.onComplete(
                              decision: 'no',
                              actionId: action.id,
                            );
                            widget.onCloseSheet?.call();
                          }),
                  child: Text(toSentenceCaseLabel(action.noLabel)),
                ),
              ),
            ],
          ),
        ];
      case 'complete_button':
        return [
          MobileLiveTestActionButton(
            label: action.label.toUpperCase(),
            backgroundColor: AppTheme.navy,
            loading: loading,
            onPressed: () => _run(() async {
              await widget.onComplete(actionId: action.id);
            }),
          ),
        ];
      case 'view_prior_response':
        if (!action.enableApprove) return const [];
        return [
          Row(
            children: [
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: loading
                      ? null
                      : () => _run(() async {
                            await widget.onComplete(
                              decision: 'approve',
                              actionId: action.id,
                              comment: _commentController.text,
                            );
                            widget.onCloseSheet?.call();
                          }),
                  icon: const Icon(Icons.check_circle_outline_rounded, size: 18),
                  label: const Text('Approve'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.primaryColorConst,
                    foregroundColor: Colors.white,
                    elevation: 0,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: loading
                      ? null
                      : () => _run(() async {
                            await widget.onComplete(
                              decision: 'reject',
                              actionId: action.id,
                              comment: _commentController.text,
                            );
                            widget.onCloseSheet?.call();
                          }),
                  icon: const Icon(Icons.close_rounded, size: 18),
                  label: const Text('Reject'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: const Color(0xFFB91C1C),
                    side: const BorderSide(color: Color(0xFFB91C1C)),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ];
      default:
        if (action.submitSlug.isEmpty &&
            MobileLiveTestAccess.slugForActionType(action.type) == null) {
          return [
            MobileLiveTestWarningBanner(
              message:
                  'This action type (${action.type}) is not yet supported in Mobile Live Test UI.',
            ),
          ];
        }
        return [
          if (action.allowComment)
            TextField(
              controller: _commentController,
              enabled: !loading,
              decoration: const InputDecoration(
                labelText: 'Comment (optional)',
                border: OutlineInputBorder(),
              ),
            ),
          const SizedBox(height: 8),
          MobileLiveTestActionButton(
            label: 'SAVE',
            backgroundColor: AppTheme.navy,
            loading: loading,
            onPressed: _submitGenericJson,
          ),
        ];
    }
  }
}

extension on MobileLiveTestWorkflowAction {
  String get submitSlug =>
      MobileLiveTestAccess.slugForActionType(type) ?? '';
}

/// Task comments loaded via dedicated live-test API.
class MobileLiveTestCommentsSection extends StatefulWidget {
  final int itemRunId;
  final List<dynamic> initialComments;
  final MobileLiveTestService service;
  final bool busy;
  final LiveTestRefreshCallback onRefresh;
  final LiveTestErrorCallback onError;
  final bool embeddedInCardFooter;

  const MobileLiveTestCommentsSection({
    super.key,
    required this.itemRunId,
    required this.initialComments,
    required this.service,
    required this.busy,
    required this.onRefresh,
    required this.onError,
    this.embeddedInCardFooter = false,
  });

  @override
  State<MobileLiveTestCommentsSection> createState() =>
      _MobileLiveTestCommentsSectionState();
}

class _MobileLiveTestCommentsSectionState
    extends State<MobileLiveTestCommentsSection> {
  final _controller = TextEditingController();
  bool _submitting = false;
  late List<MobileLiveTestComment> _comments;

  @override
  void initState() {
    super.initState();
    _comments = widget.initialComments
        .whereType<Map>()
        .map((m) => MobileLiveTestComment.fromJson(
              Map<String, dynamic>.from(m),
            ))
        .toList();
  }

  @override
  void didUpdateWidget(covariant MobileLiveTestCommentsSection oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.initialComments != widget.initialComments) {
      _comments = widget.initialComments
          .whereType<Map>()
          .map((m) => MobileLiveTestComment.fromJson(
                Map<String, dynamic>.from(m),
              ))
          .toList();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _addComment() async {
    final text = _controller.text.trim();
    if (text.isEmpty || _submitting || widget.busy) return;
    setState(() => _submitting = true);
    try {
      await widget.service.addTaskComment(widget.itemRunId, text);
      _controller.clear();
      final refreshed = await widget.service.fetchComments(widget.itemRunId);
      setState(() => _comments = refreshed);
      await widget.onRefresh();
    } on MobileLiveTestException catch (e) {
      widget.onError(e.message);
    } catch (e) {
      widget.onError(e.toString().replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final content = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (widget.embeddedInCardFooter)
          const MobileLiveTestSectionHeader(
            title: 'Comments',
            icon: Icons.chat_bubble_outline_rounded,
          )
        else
          const Text(
            '💬 Comments',
            style: TextStyle(
              fontWeight: FontWeight.w800,
              color: AppTheme.navy,
            ),
          ),
        const SizedBox(height: 10),
        if (_comments.isEmpty)
          const Text(
            'No comments yet.',
            style: TextStyle(color: AppTheme.mutedGrey),
          ),
        ..._comments.map(
          (c) => Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  c.authorName.isNotEmpty
                      ? c.authorName
                      : 'Workflow comment',
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    color: kTaskNavy,
                  ),
                ),
                if (c.authorRole.isNotEmpty)
                  Text(
                    c.authorRole,
                    style: const TextStyle(
                      color: kTaskMuted,
                      fontSize: 12,
                    ),
                  ),
                if (c.createdAt.isNotEmpty)
                  Text(
                    c.createdAt,
                    style: const TextStyle(
                      color: kTaskMuted,
                      fontSize: 12,
                    ),
                  ),
                const SizedBox(height: 4),
                Text(
                  c.body,
                  style: const TextStyle(color: kTaskNavy),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _controller,
          enabled: !_submitting && !widget.busy,
          maxLines: 3,
          decoration: InputDecoration(
            labelText: 'Write comment',
            filled: true,
            fillColor: Colors.white,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: kTaskBorder),
            ),
          ),
        ),
        const SizedBox(height: 10),
        SizedBox(
          width: double.infinity,
          height: 46,
          child: OutlinedButton(
            onPressed: _submitting || widget.busy ? null : _addComment,
            style: OutlinedButton.styleFrom(
              foregroundColor: kTaskNavy,
              side: const BorderSide(color: kTaskBorder),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
            ),
            child: _submitting
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Text(
                    'Post comment',
                    style: TextStyle(fontWeight: FontWeight.w800),
                  ),
          ),
        ),
      ],
    );

    if (widget.embeddedInCardFooter) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: kTaskBorder),
          boxShadow: const [
            BoxShadow(
              color: kTaskSoftShadow,
              blurRadius: 14,
              offset: Offset(0, 6),
            ),
          ],
        ),
        child: content,
      );
    }

    return MobileLiveTestPanel(child: content);
  }
}

/// Completion options (yes/no / approve/reject / plain complete) from task.options.
class MobileLiveTestCompletionSection extends StatelessWidget {
  final MobileLiveTestTaskDetail task;
  final bool busy;
  final TextEditingController commentController;
  final LiveTestCompleteCallback onComplete;

  final bool embeddedInCardFooter;

  const MobileLiveTestCompletionSection({
    super.key,
    required this.task,
    required this.busy,
    required this.commentController,
    required this.onComplete,
    this.embeddedInCardFooter = false,
  });

  @override
  Widget build(BuildContext context) {
    final hasCompletionControls =
        task.showActionButtons || task.showPlainComplete;
    if (!hasCompletionControls) {
      if (embeddedInCardFooter) return const SizedBox.shrink();
      return const MobileLiveTestPanel(
        child: Text(
          'Complete this task after all required actions are satisfied.',
          style: TextStyle(color: AppTheme.mutedGrey),
        ),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (!embeddedInCardFooter) ...[
          const MobileLiveTestSectionHeader(
            title: 'Complete task',
            icon: Icons.flag_outlined,
          ),
          const SizedBox(height: 12),
        ],
        if (task.showActionButtons)
          _buildOptionButtons(task, busy, onComplete)
        else if (task.showPlainComplete && !embeddedInCardFooter)
          SizedBox(
            width: double.infinity,
            height: 48,
            child: ElevatedButton.icon(
              onPressed: busy ? null : () => onComplete(),
              icon: busy
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Icon(Icons.check_circle_outline_rounded, size: 18),
              label: Text(busy ? 'Completing...' : 'Complete task'),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.primaryColorConst,
                foregroundColor: Colors.white,
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
              ),
            ),
          )
        else
          const SizedBox.shrink(),
        if (task.showActionButtons || task.showPlainComplete) ...[
          const SizedBox(height: 16),
          TextField(
            controller: commentController,
            enabled: !busy,
            maxLines: 3,
            decoration: InputDecoration(
              labelText: 'Comment (optional)',
              hintText: 'Add a note for this completion',
              filled: true,
              fillColor: Colors.white,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(color: AppTheme.border),
              ),
            ),
          ),
        ],
      ],
    );
  }

  static Widget _buildOptionButtons(
    MobileLiveTestTaskDetail task,
    bool busy,
    LiveTestCompleteCallback onComplete,
  ) {
    final options = task.options;
    if (options.length == 2) {
      final first = options[0];
      final second = options[1];
      final firstPositive = _isPositiveOption(first);
      final secondNegative = _isNegativeOption(second);
      final secondPositive = _isPositiveOption(second);
      final firstNegative = _isNegativeOption(first);
      if ((firstPositive && secondNegative) || (firstNegative && secondPositive)) {
        final positive = firstPositive ? first : second;
        final negative = firstNegative ? first : second;
        return Row(
          children: [
            Expanded(
              child: SizedBox(
                height: 48,
                child: ElevatedButton.icon(
                  onPressed: busy
                      ? null
                      : () => onComplete(
                            decision: positive.decision.isEmpty
                                ? null
                                : positive.decision,
                          ),
                  icon: busy
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Icon(Icons.check_circle_outline_rounded, size: 18),
                  label: Text(
                    busy ? 'Submitting...' : _optionLabel(positive),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.primaryColorConst,
                    foregroundColor: Colors.white,
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: SizedBox(
                height: 48,
                child: OutlinedButton.icon(
                  onPressed: busy
                      ? null
                      : () => onComplete(
                            decision: negative.decision.isEmpty
                                ? null
                                : negative.decision,
                          ),
                  icon: busy
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.close_rounded, size: 18),
                  label: Text(
                    busy ? 'Submitting...' : _optionLabel(negative),
                  ),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: const Color(0xFFB91C1C),
                    side: const BorderSide(color: Color(0xFFB91C1C)),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                  ),
                ),
              ),
            ),
          ],
        );
      }
    }

    return Column(
      children: options
          .map(
            (option) => Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: MobileLiveTestActionButton(
                label: _optionLabel(option),
                backgroundColor: mobileLiveTestActionColor(
                  actionStyleForOption(
                    decision: option.decision,
                    kind: option.kind,
                  ),
                ),
                loading: busy,
                onPressed: () => onComplete(
                  decision: option.decision.isEmpty ? null : option.decision,
                ),
              ),
            ),
          )
          .toList(),
    );
  }

  static bool _isPositiveOption(MobileLiveTestTaskOption option) {
    return option.decision == 'approve' ||
        option.decision == 'yes' ||
        option.kind == 'yes';
  }

  static bool _isNegativeOption(MobileLiveTestTaskOption option) {
    return option.decision == 'reject' ||
        option.decision == 'no' ||
        option.kind == 'no';
  }

  static String _optionLabel(MobileLiveTestTaskOption option) {
    if (option.label.trim().isNotEmpty) {
      return toSentenceCaseLabel(option.label);
    }
    return toSentenceCaseLabel(option.decision);
  }
}
