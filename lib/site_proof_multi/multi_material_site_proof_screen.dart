import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';

import '../app_theme.dart';
import '../models/approved_po.dart';
import '../models/multi_material_site_proof.dart';
import '../services/camera_permission.dart';
import '../services/location_service.dart';
import '../services/capture_time.dart';
import '../services/multi_material_site_proof_service.dart';
import '../widgets/themed_scaffold.dart';

enum _WizardPhase { select, evidence, success }

class _LocalMedia {
  final File file;
  final bool isVideo;
  final DateTime? capturedAt;

  const _LocalMedia({
    required this.file,
    required this.isVideo,
    this.capturedAt,
  });
}

class _MaterialDraft {
  final String materialKey;
  bool selected = false;
  String quantityReceivedToday = '';
  String comment = '';
  final List<_LocalMedia> photos = <_LocalMedia>[];
  final List<_LocalMedia> videos = <_LocalMedia>[];
  bool savedToServer = false;

  _MaterialDraft({required this.materialKey});
}

/// Multi-material site-proof:
/// 1) Select materials + quantity on each card
/// 2) Delivery proof (photo + video + measurement) + vehicle (Indian plate + media)
class MultiMaterialSiteProofScreen extends StatefulWidget {
  final String indentId;
  final String itemRunId;
  final Map<String, dynamic> task;
  final ApprovedPo? approvedPo;
  final Future<void> Function() onChanged;
  final Future<void> Function(String taskId)? onTaskFinished;

  const MultiMaterialSiteProofScreen({
    super.key,
    required this.indentId,
    required this.itemRunId,
    required this.task,
    required this.onChanged,
    this.approvedPo,
    this.onTaskFinished,
  });

  @override
  State<MultiMaterialSiteProofScreen> createState() =>
      _MultiMaterialSiteProofScreenState();
}

class _MultiMaterialSiteProofScreenState
    extends State<MultiMaterialSiteProofScreen> {
  final _service = MultiMaterialSiteProofService();
  final _searchController = TextEditingController();
  final _measurementController = TextEditingController();
  final _measurementUnitController = TextEditingController();
  final _vehicleNumberController = TextEditingController();
  final _driverNameController = TextEditingController();
  final _driverPhoneController = TextEditingController();
  final _vehicleCommentController = TextEditingController();
  final _siteCommentController = TextEditingController();

  MultiMaterialSiteProofSession? _session;
  final Map<String, _MaterialDraft> _drafts = {};
  List<String> _selectedOrder = [];
  _WizardPhase _phase = _WizardPhase.select;
  String _vehicleType = 'Truck';
  final List<_LocalMedia> _commonPhotos = [];
  final List<_LocalMedia> _commonVideos = [];
  final List<_LocalMedia> _vehiclePhotos = [];
  final List<_LocalMedia> _vehicleVideos = [];
  final List<MultiMaterialRemoteMedia> _remoteDeliveryMedia = [];
  final List<MultiMaterialRemoteMedia> _remoteVehicleMedia = [];

  Timer? _commonAutosaveTimer;
  bool _autosaving = false;
  bool _applyingSession = false;
  bool _loading = true;
  bool _busy = false;
  String? _error;
  String? _selectValidation;

  bool _checkingLocation = true;
  bool _onSite = false;
  bool _siteConfigured = true;
  String? _locationError;
  bool _openSettingsHint = false;
  double? _distanceMeters;
  int _radiusMeters = 500;

  MultiMaterialSubmitResult? _submitResult;

  static const _vehicleTypes = [
    'Truck',
    'Tempo',
    'Tractor',
    'Pickup',
    'Other',
  ];

  @override
  void initState() {
    super.initState();
    _measurementController.addListener(_scheduleCommonAutosave);
    _measurementUnitController.addListener(_scheduleCommonAutosave);
    _vehicleNumberController.addListener(_scheduleCommonAutosave);
    _driverNameController.addListener(_scheduleCommonAutosave);
    _driverPhoneController.addListener(_scheduleCommonAutosave);
    _vehicleCommentController.addListener(_scheduleCommonAutosave);
    _siteCommentController.addListener(_scheduleCommonAutosave);
    _bootstrap();
  }

  @override
  void dispose() {
    _commonAutosaveTimer?.cancel();
    _measurementController.removeListener(_scheduleCommonAutosave);
    _measurementUnitController.removeListener(_scheduleCommonAutosave);
    _vehicleNumberController.removeListener(_scheduleCommonAutosave);
    _driverNameController.removeListener(_scheduleCommonAutosave);
    _driverPhoneController.removeListener(_scheduleCommonAutosave);
    _vehicleCommentController.removeListener(_scheduleCommonAutosave);
    _siteCommentController.removeListener(_scheduleCommonAutosave);
    _searchController.dispose();
    _measurementController.dispose();
    _measurementUnitController.dispose();
    _vehicleNumberController.dispose();
    _driverNameController.dispose();
    _driverPhoneController.dispose();
    _vehicleCommentController.dispose();
    _siteCommentController.dispose();
    super.dispose();
  }

  String get _itemRunId {
    final fromSession = _session?.itemRunId.toString() ?? '';
    if (fromSession.isNotEmpty && fromSession != '0') return fromSession;
    return widget.itemRunId.trim();
  }

  /// Vendor scoped to the opened task (spawn_meta / task fields).
  String? get _vendorId {
    final direct = widget.task['vendor_id']?.toString().trim() ?? '';
    if (direct.isNotEmpty) return direct;
    final meta = widget.task['spawn_meta'];
    if (meta is Map) {
      final v = meta['vendor_id']?.toString().trim() ?? '';
      if (v.isNotEmpty) return v;
    }
    final nested = widget.task['workflow_item_result'];
    if (nested is Map && nested['spawn_meta'] is Map) {
      final v =
          (nested['spawn_meta'] as Map)['vendor_id']?.toString().trim() ?? '';
      if (v.isNotEmpty) return v;
    }
    final ctx = widget.task['context'] ?? widget.task['context_json'];
    if (ctx is Map) {
      final v = ctx['vendor_id']?.toString().trim() ?? '';
      if (v.isNotEmpty) return v;
    }
    return null;
  }

  String get _subtitle {
    final po = widget.approvedPo;
    final parts = <String>[];
    final poNo =
        (po?.displayPoNumber() ?? _session?.poNumber ?? '').trim();
    if (poNo.isNotEmpty) parts.add(poNo);
    final project = (po?.projectName ?? _session?.projectName ?? '').trim();
    if (project.isNotEmpty) parts.add(project);
    final indent = widget.indentId.trim();
    if (indent.isNotEmpty) parts.add('#$indent');
    return parts.join(' · ');
  }

  List<MultiMaterialLine> get _materials => _session?.materials ?? const [];

  /// Materials that still have remaining quantity (partial deliveries).
  List<MultiMaterialLine> get _materialsWithRemaining {
    return _materials.where((m) {
      final remaining = m.remainingAsNumber;
      return remaining == null || remaining > 0.0001;
    }).toList();
  }

  List<MultiMaterialLine> get _filteredMaterials {
    final q = _searchController.text.trim().toLowerCase();
    final source = _materialsWithRemaining;
    if (q.isEmpty) return source;
    return source
        .where(
          (m) =>
              m.material.toLowerCase().contains(q) ||
              m.unit.toLowerCase().contains(q),
        )
        .toList();
  }

  List<MultiMaterialLine> get _selectedMaterials {
    return _selectedOrder
        .map((key) {
          try {
            return _materials.firstWhere((m) => m.materialKey == key);
          } catch (_) {
            return null;
          }
        })
        .whereType<MultiMaterialLine>()
        .toList();
  }

  _MaterialDraft _draftFor(String key) {
    return _drafts.putIfAbsent(key, () => _MaterialDraft(materialKey: key));
  }

  Future<void> _bootstrap() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final session = await _service.fetchSession(
        indentId: widget.indentId,
        itemRunId: widget.itemRunId.isEmpty ? null : widget.itemRunId,
        vendorId: _vendorId,
      );
      if (!mounted) return;
      if (session.itemRunId <= 0) {
        setState(() {
          _loading = false;
          _error =
              'No open site-proof delivery for remaining materials. '
              'Backend must return a new/open item_run_id when quantities remain.';
        });
        return;
      }
      _applySession(session);
      setState(() => _loading = false);
      await _refreshLocation();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = e.toString().replaceFirst('Exception: ', '');
      });
    }
  }

  void _applySession(MultiMaterialSiteProofSession session) {
    _applyingSession = true;
    _session = session;
    _radiusMeters = session.nearSiteRadiusMeters;
    _measurementController.text = session.common.measurement;
    _measurementUnitController.text = session.common.measurementUnit.isNotEmpty
        ? session.common.measurementUnit
        : 'Sq. ft';
    _vehicleNumberController.text = session.common.vehicleNumber;
    _driverNameController.text = session.common.driverName;
    _driverPhoneController.text = session.common.driverPhone;
    _vehicleCommentController.text = session.common.vehicleComment;
    _siteCommentController.text = session.common.siteComment;
    if (session.common.vehicleType.trim().isNotEmpty) {
      _vehicleType = session.common.vehicleType.trim();
    }

    _remoteDeliveryMedia
      ..clear()
      ..addAll(session.deliveryMedia);
    _remoteVehicleMedia
      ..clear()
      ..addAll(session.vehicleMedia);

    _selectedOrder = [];
    for (final line in session.materials) {
      final draft = _draftFor(line.materialKey);
      draft.selected = line.selected || line.completed;
      draft.quantityReceivedToday = line.quantityReceivedToday;
      draft.comment = line.comment;
      draft.savedToServer =
          line.completed || line.quantityReceivedToday.trim().isNotEmpty;
      if (draft.selected) _selectedOrder.add(line.materialKey);
    }

    // Auto-select when only one outstanding material (normal 1-line POs).
    final outstanding = session.materials.where((m) {
      final remaining = m.remainingAsNumber;
      if (remaining != null && remaining <= 0.0001) return false;
      return !m.completed;
    }).toList();
    if (_selectedOrder.isEmpty && outstanding.length == 1) {
      final line = outstanding.first;
      final draft = _draftFor(line.materialKey);
      draft.selected = true;
      if (draft.quantityReceivedToday.trim().isEmpty) {
        draft.quantityReceivedToday = '';
      }
      _selectedOrder = [line.materialKey];
    } else if (_selectedOrder.isEmpty && session.materials.length == 1) {
      final line = session.materials.first;
      final draft = _draftFor(line.materialKey);
      draft.selected = true;
      _selectedOrder = [line.materialKey];
    }
    _applyingSession = false;
  }

  void _scheduleCommonAutosave() {
    if (_applyingSession) return;
    if (_phase != _WizardPhase.evidence || _busy || _loading) return;
    if (_itemRunId.isEmpty) return;
    _commonAutosaveTimer?.cancel();
    _commonAutosaveTimer = Timer(const Duration(milliseconds: 900), () {
      unawaited(_autosaveCommonFields());
    });
  }

  Future<void> _autosaveCommonFields() async {
    if (_busy || _autosaving || _itemRunId.isEmpty) return;
    _autosaving = true;
    try {
      final fields = MultiMaterialCommonFields(
        measurement: _measurementController.text.trim(),
        measurementUnit: _measurementUnitController.text.trim(),
        siteComment: _siteCommentController.text.trim(),
        vehicleNumber: _normalizeIndianVehicleNumber(
          _vehicleNumberController.text,
        ),
        vehicleType: _vehicleType,
        driverName: _driverNameController.text.trim(),
        driverPhone: _driverPhoneController.text.trim(),
        vehicleComment: _vehicleCommentController.text.trim(),
      );
      await _service.saveCommon(itemRunId: _itemRunId, fields: fields);
    } catch (_) {
      // Soft fail — user can still submit later.
    } finally {
      _autosaving = false;
    }
  }

  Future<void> _autosaveSelectedMaterials() async {
    if (_itemRunId.isEmpty) return;
    for (final line in _selectedMaterials) {
      final draft = _draftFor(line.materialKey);
      final err = _validateQuantity(line, draft);
      if (err != null) continue;
      try {
        await _service.saveMaterial(
          itemRunId: _itemRunId,
          materialKey: line.materialKey,
          quantityReceivedToday: draft.quantityReceivedToday.trim(),
          comment: draft.comment,
        );
        draft.savedToServer = true;
      } catch (_) {}
    }
  }

  Future<void> _refreshLocation() async {
    final session = _session;
    setState(() {
      _checkingLocation = true;
      _locationError = null;
      _openSettingsHint = false;
    });

    if (session == null) {
      setState(() {
        _checkingLocation = false;
        _onSite = true;
        _siteConfigured = true;
      });
      return;
    }

    final site = session.siteLocation;
    final available = session.siteLocationAvailable && site != null;
    if (!available) {
      setState(() {
        _checkingLocation = false;
        _siteConfigured = false;
        _onSite = true;
        _locationError = null;
      });
      return;
    }

    final permission = await LocationService.ensurePermission();
    if (!permission.ok) {
      if (!mounted) return;
      var resultOk = false;
      if (kDebugMode && mounted) {
        resultOk = await _confirmDebugLocationOverride(
          permission.error ?? 'Location permission required.',
        );
      }
      if (!mounted) return;
      setState(() {
        _checkingLocation = false;
        _siteConfigured = true;
        _onSite = resultOk;
        _locationError = resultOk ? null : permission.error;
        _openSettingsHint = permission.openSettings;
      });
      return;
    }

    try {
      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: Duration(seconds: 15),
        ),
      );
      final distance = Geolocator.distanceBetween(
        position.latitude,
        position.longitude,
        site.latitude,
        site.longitude,
      );
      final onSite = distance <= _radiusMeters;
      if (!onSite && kDebugMode && mounted) {
        final override = await _confirmDebugLocationOverride(
          'You are about ${distance.round()} m away from site.',
        );
        if (!mounted) return;
        setState(() {
          _checkingLocation = false;
          _siteConfigured = true;
          _onSite = override;
          _distanceMeters = distance;
          _locationError = override
              ? null
              : 'Go to the project site to continue. You are about ${distance.round()} m away.';
        });
        return;
      }
      if (!mounted) return;
      setState(() {
        _checkingLocation = false;
        _siteConfigured = true;
        _onSite = onSite;
        _distanceMeters = distance;
        _locationError = onSite
            ? null
            : 'Go to the project site to continue. You are about ${distance.round()} m away.';
      });
    } catch (e) {
      if (!mounted) return;
      var ok = false;
      if (kDebugMode) {
        ok = await _confirmDebugLocationOverride(
          'Unable to read GPS. ${e.toString()}',
        );
      }
      if (!mounted) return;
      setState(() {
        _checkingLocation = false;
        _siteConfigured = true;
        _onSite = ok;
        _locationError = ok ? null : 'Unable to get your current location.';
      });
    }
  }

  Future<bool> _confirmDebugLocationOverride(String message) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Debug: Override site check?'),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Keep blocked'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Override'),
          ),
        ],
      ),
    );
    return result == true;
  }

  void _toggleMaterial(MultiMaterialLine line, bool? value) {
    final draft = _draftFor(line.materialKey);
    final selected = value ?? !draft.selected;
    setState(() {
      draft.selected = selected;
      _selectValidation = null;
      if (selected) {
        if (!_selectedOrder.contains(line.materialKey)) {
          _selectedOrder.add(line.materialKey);
        }
        if (draft.quantityReceivedToday.trim().isEmpty) {
          draft.quantityReceivedToday = '0';
        }
      } else {
        _selectedOrder.remove(line.materialKey);
      }
    });
  }

  String? _validateQuantity(MultiMaterialLine line, _MaterialDraft draft) {
    final qtyText = draft.quantityReceivedToday.trim();
    final qty = double.tryParse(qtyText.replaceAll(',', ''));
    if (qtyText.isEmpty || qty == null) {
      return 'Enter quantity for ${line.material}.';
    }
    if (qty <= 0) {
      return 'Quantity for ${line.material} must be greater than zero.';
    }
    final remaining = line.remainingAsNumber;
    if (remaining != null && qty > remaining + 0.0001) {
      return '${line.material}: cannot exceed remaining (${line.remainingQuantity} ${line.unit}).';
    }
    return null;
  }

  Future<void> _continueFromSelect() async {
    if (!_onSite && _siteConfigured) {
      _snack(_locationError ?? 'You must be on site to continue.', error: true);
      return;
    }
    if (_selectedOrder.isEmpty) {
      setState(() => _selectValidation = 'Select at least one material.');
      return;
    }
    for (final line in _selectedMaterials) {
      final err = _validateQuantity(line, _draftFor(line.materialKey));
      if (err != null) {
        setState(() => _selectValidation = err);
        return;
      }
    }
    setState(() {
      _selectValidation = null;
      _busy = true;
    });
    try {
      await _autosaveSelectedMaterials();
      if (!mounted) return;
      setState(() {
        _busy = false;
        _phase = _WizardPhase.evidence;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _busy = false);
      _snack(e.toString().replaceFirst('Exception: ', ''), error: true);
    }
  }

  /// Indian RTO plate (KA 01 AB 1234 / KA01AB1234) or BH series (22BH1234AA).
  static final RegExp _indianVehicleNumberPattern = RegExp(
    r'^(?:'
    r'[A-Z]{2}[0-9]{1,2}[A-Z]{1,3}[0-9]{4}'
    r'|'
    r'[0-9]{2}BH[0-9]{4}[A-Z]{1,2}'
    r')$',
  );

  String _normalizeIndianVehicleNumber(String raw) {
    return raw.trim().toUpperCase().replaceAll(RegExp(r'[\s\-./]'), '');
  }

  bool _isValidIndianVehicleNumber(String raw) {
    final normalized = _normalizeIndianVehicleNumber(raw);
    if (normalized.isEmpty) return false;
    return _indianVehicleNumberPattern.hasMatch(normalized);
  }

  Future<void> _submitAll() async {
    final hasDeliveryPhoto = _commonPhotos.isNotEmpty ||
        _remoteDeliveryMedia.any((m) => !m.isVideo);
    final hasDeliveryVideo = _commonVideos.isNotEmpty ||
        _remoteDeliveryMedia.any((m) => m.isVideo);
    if (!hasDeliveryPhoto) {
      _snack('Add at least 1 delivery photo.', error: true);
      return;
    }
    if (!hasDeliveryVideo) {
      _snack('Add at least 1 delivery video.', error: true);
      return;
    }
    if (_measurementController.text.trim().isEmpty) {
      _snack('Measurement is required.', error: true);
      return;
    }

    final vehicleRaw = _vehicleNumberController.text.trim();
    if (vehicleRaw.isEmpty) {
      _snack('Vehicle number is required.', error: true);
      return;
    }
    if (!_isValidIndianVehicleNumber(vehicleRaw)) {
      _snack(
        'Enter a valid Indian vehicle number (e.g. KA 01 AB 1234).',
        error: true,
      );
      return;
    }
    final hasVehiclePhoto = _vehiclePhotos.isNotEmpty ||
        _remoteVehicleMedia.any((m) => !m.isVideo);
    final hasVehicleVideo = _vehicleVideos.isNotEmpty ||
        _remoteVehicleMedia.any((m) => m.isVideo);
    if (!hasVehiclePhoto) {
      _snack('Add at least 1 vehicle photo.', error: true);
      return;
    }
    if (!hasVehicleVideo) {
      _snack('Add at least 1 vehicle video.', error: true);
      return;
    }

    final normalizedVehicle = _normalizeIndianVehicleNumber(vehicleRaw);

    setState(() => _busy = true);
    try {
      // 1) Save each material quantity only (no per-material media)
      for (final line in _selectedMaterials) {
        final draft = _draftFor(line.materialKey);
        await _service.saveMaterial(
          itemRunId: _itemRunId,
          materialKey: line.materialKey,
          quantityReceivedToday: draft.quantityReceivedToday.trim(),
          comment: draft.comment,
        );
        draft.savedToServer = true;
      }

      // 2) Delivery-level common fields
      final fields = MultiMaterialCommonFields(
        measurement: _measurementController.text.trim(),
        measurementUnit: _measurementUnitController.text.trim(),
        siteComment: _siteCommentController.text.trim(),
        vehicleNumber: normalizedVehicle,
        vehicleType: _vehicleType,
        driverName: _driverNameController.text.trim(),
        driverPhone: _driverPhoneController.text.trim(),
        vehicleComment: _vehicleCommentController.text.trim(),
      );
      await _service.saveCommon(itemRunId: _itemRunId, fields: fields);

      // 3) Delivery proof media
      final deliveryMedia = <_LocalMedia>[
        ..._commonPhotos,
        ..._commonVideos,
      ];
      if (deliveryMedia.isNotEmpty) {
        await _service.uploadCommonFiles(
          itemRunId: _itemRunId,
          files: deliveryMedia.map((m) => m.file).toList(),
          capturedAts: deliveryMedia
              .map((m) => m.capturedAt)
              .whereType<DateTime>()
              .map(CaptureTime.toOffsetIso)
              .toList(),
        );
      }

      // 4) Vehicle media
      final vehicleMedia = <_LocalMedia>[
        ..._vehiclePhotos,
        ..._vehicleVideos,
      ];
      if (vehicleMedia.isNotEmpty) {
        await _service.uploadVehicleFiles(
          itemRunId: _itemRunId,
          files: vehicleMedia.map((m) => m.file).toList(),
          capturedAts: vehicleMedia
              .map((m) => m.capturedAt)
              .whereType<DateTime>()
              .map(CaptureTime.toOffsetIso)
              .toList(),
        );
      }

      // 5) Submit
      final result = await _service.submit(itemRunId: _itemRunId);
      await widget.onChanged();
      if (!mounted) return;
      setState(() {
        _busy = false;
        _submitResult = result;
      });
      await _showSubmitConfirmationAndExit(result);
    } catch (e) {
      if (!mounted) return;
      setState(() => _busy = false);
      _snack(e.toString().replaceFirst('Exception: ', ''), error: true);
    }
  }

  Future<void> _showSubmitConfirmationAndExit(
    MultiMaterialSubmitResult result,
  ) async {
    final remaining = result.hasRemainingMaterials;
    // Partial delivery keeps the task open for the next cycle.
    final markFinished = !remaining;
    final title = remaining ? 'Delivery submitted' : 'Task completed';
    final body = result.message.trim().isNotEmpty
        ? result.message.trim()
        : (remaining
            ? 'Site proof for this delivery was submitted successfully. '
                'This PO is partially completed — you can upload another '
                'delivery for remaining materials.'
            : 'Site proof submitted successfully. This task is completed.');

    if (!mounted) return;
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => AlertDialog(
        title: Text(title),
        content: Text(body),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('OK'),
          ),
        ],
      ),
    );
    if (markFinished) {
      final taskId = widget.task['id']?.toString().trim() ?? '';
      if (taskId.isNotEmpty) {
        await widget.onTaskFinished?.call(taskId);
      }
    }
    if (!mounted) return;
    Navigator.of(context).pop(true);
  }

  Future<void> _uploadDeliveryMediaNow(List<_LocalMedia> mediaItems) async {
    if (mediaItems.isEmpty || _itemRunId.isEmpty) return;
    final files = mediaItems.map((m) => m.file).toList();
    final capturedAts = mediaItems
        .map((m) => m.capturedAt)
        .whereType<DateTime>()
        .map(CaptureTime.toOffsetIso)
        .toList();
    try {
      await _service.uploadCommonFiles(
        itemRunId: _itemRunId,
        files: files,
        capturedAts: capturedAts,
      );
    } catch (e) {
      if (!mounted) return;
      _snack(
        'Could not autosave delivery media: ${e.toString().replaceFirst('Exception: ', '')}',
        error: true,
      );
    }
  }

  Future<void> _uploadVehicleMediaNow(List<_LocalMedia> mediaItems) async {
    if (mediaItems.isEmpty || _itemRunId.isEmpty) return;
    final files = mediaItems.map((m) => m.file).toList();
    final capturedAts = mediaItems
        .map((m) => m.capturedAt)
        .whereType<DateTime>()
        .map(CaptureTime.toOffsetIso)
        .toList();
    try {
      await _service.uploadVehicleFiles(
        itemRunId: _itemRunId,
        files: files,
        capturedAts: capturedAts,
      );
    } catch (e) {
      if (!mounted) return;
      _snack(
        'Could not autosave vehicle media: ${e.toString().replaceFirst('Exception: ', '')}',
        error: true,
      );
    }
  }

  Future<_LocalMedia?> _capturePhoto() async {
    if (!await ensureCameraPermission(context)) return null;
    if (!mounted) return null;
    final picked = await ImagePicker().pickImage(
      source: ImageSource.camera,
      imageQuality: 88,
    );
    if (picked == null) return null;
    final capturedAt = CaptureTime.nowLocal();
    final stampedName = CaptureTime.stampFilename(isVideo: false, at: capturedAt);
    final stampedPath =
        '${Directory.systemTemp.path}${Platform.pathSeparator}$stampedName';
    final copied = await File(picked.path).copy(stampedPath);
    return _LocalMedia(
      file: copied,
      isVideo: false,
      capturedAt: capturedAt,
    );
  }

  Future<_LocalMedia?> _recordVideo() async {
    if (!await ensureCameraPermission(context, includeMicrophone: true)) {
      return null;
    }
    if (!mounted) return null;
    final picked = await ImagePicker().pickVideo(
      source: ImageSource.camera,
      maxDuration: const Duration(seconds: 60),
    );
    if (picked == null) return null;
    final capturedAt = CaptureTime.nowLocal();
    final name = CaptureTime.stampFilename(isVideo: true, at: capturedAt);
    final path =
        '${Directory.systemTemp.path}${Platform.pathSeparator}$name';
    final copied = await File(picked.path).copy(path);
    return _LocalMedia(file: copied, isVideo: true, capturedAt: capturedAt);
  }

  void _snack(String message, {bool error = false}) {
    if (!mounted || message.trim().isEmpty) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message.trim()),
        backgroundColor: error ? Colors.red : Colors.green,
      ),
    );
  }

  void _goBack() {
    if (_busy) return;
    switch (_phase) {
      case _WizardPhase.select:
        Navigator.of(context).maybePop();
        break;
      case _WizardPhase.evidence:
        setState(() => _phase = _WizardPhase.select);
        break;
      case _WizardPhase.success:
        Navigator.of(context).pop();
        break;
    }
  }

  String? _remainingAfterThis(MultiMaterialLine line, String qtyText) {
    final remaining = line.remainingAsNumber;
    final qty = double.tryParse(qtyText.trim().replaceAll(',', ''));
    if (remaining == null || qty == null) return null;
    final after = remaining - qty;
    final formatted = after == after.roundToDouble()
        ? after.round().toString()
        : after.toStringAsFixed(2);
    return '$formatted ${line.unit}'.trim();
  }

  @override
  Widget build(BuildContext context) {
    return ThemedScaffold(
      title: 'Upload site proof for PO',
      automaticallyImplyLeading: false,
      leading: IconButton(
        icon: const Icon(Icons.arrow_back_rounded),
        onPressed: _busy ? null : _goBack,
      ),
      actions: [
        if (_phase == _WizardPhase.evidence)
          const Padding(
            padding: EdgeInsets.only(right: 12),
            child: Center(
              child: Text(
                '2 of 2',
                style: TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: 13,
                  color: AppTheme.mutedGrey,
                ),
              ),
            ),
          ),
      ],
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? _ErrorPane(message: _error!, onRetry: _bootstrap)
              : Stack(
                  children: [
                    _buildPhaseBody(),
                    if (_busy)
                      Positioned.fill(
                        child: Container(
                          color: Colors.black26,
                          child: const Center(
                            child: CircularProgressIndicator(),
                          ),
                        ),
                      ),
                  ],
                ),
    );
  }

  Widget _buildPhaseBody() {
    switch (_phase) {
      case _WizardPhase.select:
        return _buildSelectPhase();
      case _WizardPhase.evidence:
        return _buildEvidencePhase();
      case _WizardPhase.success:
        return _buildSuccessPhase();
    }
  }

  // ─── STEP 1: select + quantity ───────────────────────────────────────────

  Widget _buildSelectPhase() {
    final selectedCount = _selectedOrder.length;
    return Column(
      children: [
        Expanded(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
            children: [
              if (_subtitle.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Text(
                    _subtitle,
                    style: const TextStyle(
                      color: AppTheme.mutedGrey,
                      fontWeight: FontWeight.w600,
                      height: 1.35,
                    ),
                  ),
                ),
              _GpsBanner(
                isChecking: _checkingLocation,
                onSite: _onSite,
                siteConfigured: _siteConfigured,
                error: _locationError,
                distanceMeters: _distanceMeters,
                radiusMeters: _radiusMeters,
                showOpenSettings: _openSettingsHint,
                onRecheck: _checkingLocation ? null : _refreshLocation,
                onOpenSettings: _openSettingsHint
                    ? () => Geolocator.openAppSettings()
                    : null,
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Text(
                    'Materials (${_materialsWithRemaining.length})',
                    style: const TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w800,
                      color: AppTheme.darkTextPrimary,
                    ),
                  ),
                  const Spacer(),
                  Text(
                    '$selectedCount selected',
                    style: const TextStyle(
                      color: AppTheme.mutedGrey,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              const Text(
                'Tick materials and enter quantity received on each card.',
                style: TextStyle(
                  color: AppTheme.mutedGrey,
                  fontWeight: FontWeight.w600,
                  fontSize: 13,
                ),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: _searchController,
                onChanged: (_) => setState(() {}),
                decoration: _inputDecoration('Search materials').copyWith(
                  prefixIcon: const Icon(Icons.search),
                ),
              ),
              const SizedBox(height: 12),
              if (_materialsWithRemaining.isEmpty) ...[
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF8FAFC),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: AppTheme.border),
                  ),
                  child: Text(
                    _materials.isEmpty
                        ? 'No materials found for this vendor/PO.'
                        : 'No remaining quantity for this vendor/batch. '
                            'Ordered/received totals below are scoped to this '
                            'task only (not sibling vendors).',
                    style: const TextStyle(
                      color: AppTheme.mutedGrey,
                      fontWeight: FontWeight.w600,
                      height: 1.35,
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                ..._materials.map(_buildSelectCard),
              ] else ...[
                ..._filteredMaterials.map(_buildSelectCard),
              ],
              if (_selectValidation != null) ...[
                const SizedBox(height: 8),
                Text(
                  _selectValidation!,
                  style: const TextStyle(
                    color: Color(0xFFB91C1C),
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ],
          ),
        ),
        _BottomBar(
          child: SizedBox(
            width: double.infinity,
            height: 52,
            child: ElevatedButton(
              onPressed: selectedCount == 0 ? null : _continueFromSelect,
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.accentBlue,
                foregroundColor: Colors.white,
                disabledBackgroundColor: const Color(0xFFBFDBFE),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
              child: Text(
                selectedCount == 0
                    ? 'Select materials to continue'
                    : 'Continue ($selectedCount) →',
                style: const TextStyle(
                  fontWeight: FontWeight.w800,
                  fontSize: 16,
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildSelectCard(MultiMaterialLine line) {
    final draft = _draftFor(line.materialKey);
    final selected = draft.selected;
    final remainingAfter =
        selected ? _remainingAfterThis(line, draft.quantityReceivedToday) : null;

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: selected ? const Color(0xFF93C5FD) : AppTheme.border,
            width: selected ? 1.5 : 1,
          ),
          color: selected ? const Color(0xFFEFF6FF) : Colors.white,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            InkWell(
              onTap: () => _toggleMaterial(line, !selected),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Checkbox(
                    value: selected,
                    onChanged: (v) => _toggleMaterial(line, v),
                  ),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          line.material,
                          style: const TextStyle(
                            fontWeight: FontWeight.w800,
                            fontSize: 16,
                            color: AppTheme.darkTextPrimary,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Ordered: ${line.orderedQuantity} ${line.unit}'.trim(),
                          style: const TextStyle(
                            color: AppTheme.mutedGrey,
                            fontWeight: FontWeight.w600,
                            fontSize: 13,
                          ),
                        ),
                        Text(
                          'Received: ${line.previouslyReceivedQuantity}  ·  Remaining: ${line.remainingQuantity}',
                          style: const TextStyle(
                            color: AppTheme.mutedGrey,
                            fontWeight: FontWeight.w600,
                            fontSize: 13,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            if (selected) ...[
              const SizedBox(height: 12),
              const Text(
                'Quantity received today *',
                style: TextStyle(
                  fontWeight: FontWeight.w700,
                  color: AppTheme.darkTextPrimary,
                ),
              ),
              const SizedBox(height: 8),
              _QuantityStepper(
                valueText: draft.quantityReceivedToday.isEmpty
                    ? '0'
                    : draft.quantityReceivedToday,
                unit: line.unit,
                onChanged: (next) {
                  setState(() {
                    draft.quantityReceivedToday = next;
                    _selectValidation = null;
                  });
                },
              ),
              if (remainingAfter != null) ...[
                const SizedBox(height: 8),
                Text(
                  'Remaining after this: $remainingAfter',
                  style: const TextStyle(
                    color: Color(0xFF065F46),
                    fontWeight: FontWeight.w700,
                    fontSize: 13,
                  ),
                ),
              ],
            ],
          ],
        ),
      ),
    );
  }

  // ─── STEP 2: selected materials summary + delivery + vehicle ─────────────

  Widget _buildEvidencePhase() {
    final materials = _selectedMaterials;
    return Column(
      children: [
        Expanded(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
            children: [
              const Text(
                'Evidence & delivery details',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                  color: AppTheme.darkTextPrimary,
                ),
              ),
              const SizedBox(height: 4),
              const Text(
                'Delivery proof needs at least 1 photo and 1 video, measurement, and vehicle details with photo and video. Per-material photos are not required.',
                style: TextStyle(
                  color: AppTheme.mutedGrey,
                  fontWeight: FontWeight.w600,
                  height: 1.35,
                ),
              ),
              const SizedBox(height: 16),
              const Text(
                'Selected materials',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                  color: AppTheme.darkTextPrimary,
                ),
              ),
              const SizedBox(height: 10),
              ...materials.map(_buildMaterialEvidenceCard),
              const SizedBox(height: 8),
              const Divider(height: 32),
              const Text(
                'Delivery proof *',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                  color: AppTheme.darkTextPrimary,
                ),
              ),
              const SizedBox(height: 4),
              const Text(
                'Minimum 1 photo and 1 video required',
                style: TextStyle(
                  color: AppTheme.mutedGrey,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 12),
              _MediaRow(
                title: 'Delivery photo *',
                items: _commonPhotos,
                remoteItems: _remoteDeliveryMedia
                    .where((m) => !m.isVideo)
                    .toList(),
                addLabel: 'Add photo',
                onAdd: () async {
                  final media = await _capturePhoto();
                  if (media == null || !mounted) return;
                  setState(() => _commonPhotos.add(media));
                  unawaited(_uploadDeliveryMediaNow([media]));
                },
                onRemove: (i) => setState(() => _commonPhotos.removeAt(i)),
              ),
              const SizedBox(height: 14),
              _MediaRow(
                title: 'Delivery video *',
                items: _commonVideos,
                remoteItems: _remoteDeliveryMedia
                    .where((m) => m.isVideo)
                    .toList(),
                addLabel: 'Add video',
                maxItems: 2,
                onAdd: () async {
                  final media = await _recordVideo();
                  if (media == null || !mounted) return;
                  setState(() => _commonVideos.add(media));
                  unawaited(_uploadDeliveryMediaNow([media]));
                },
                onRemove: (i) => setState(() => _commonVideos.removeAt(i)),
              ),
              const SizedBox(height: 20),
              const Text(
                'Measurement *',
                style: TextStyle(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _measurementController,
                decoration: _inputDecoration('e.g. Area levelled'),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: _measurementUnitController,
                decoration: _inputDecoration('Unit (e.g. Sq. ft)'),
              ),
              const SizedBox(height: 20),
              const Text(
                'Vehicle details',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                  color: AppTheme.darkTextPrimary,
                ),
              ),
              const SizedBox(height: 10),
              const Text(
                'Vehicle number *',
                style: TextStyle(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _vehicleNumberController,
                textCapitalization: TextCapitalization.characters,
                decoration: _inputDecoration('KA 01 AB 1234'),
              ),
              const SizedBox(height: 4),
              const Text(
                'Indian standard format (spaces/hyphens optional). Example: KA01AB1234 or 22BH1234AA',
                style: TextStyle(
                  color: AppTheme.mutedGrey,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 10),
              DropdownButtonFormField<String>(
                value: _vehicleTypes.contains(_vehicleType)
                    ? _vehicleType
                    : _vehicleTypes.first,
                items: _vehicleTypes
                    .map((t) => DropdownMenuItem(value: t, child: Text(t)))
                    .toList(),
                onChanged: (v) {
                  if (v == null) return;
                  setState(() => _vehicleType = v);
                  _scheduleCommonAutosave();
                },
                decoration: _inputDecoration('Vehicle type'),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: _driverNameController,
                decoration: _inputDecoration('Driver name'),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: _driverPhoneController,
                keyboardType: TextInputType.phone,
                decoration: _inputDecoration('Driver phone'),
              ),
              const SizedBox(height: 12),
              _MediaRow(
                title: 'Vehicle photo *',
                items: _vehiclePhotos,
                remoteItems: _remoteVehicleMedia
                    .where((m) => !m.isVideo)
                    .toList(),
                addLabel: 'Add photo',
                maxItems: 3,
                onAdd: () async {
                  final media = await _capturePhoto();
                  if (media == null || !mounted) return;
                  setState(() => _vehiclePhotos.add(media));
                  unawaited(_uploadVehicleMediaNow([media]));
                },
                onRemove: (i) => setState(() => _vehiclePhotos.removeAt(i)),
              ),
              const SizedBox(height: 14),
              _MediaRow(
                title: 'Vehicle video *',
                items: _vehicleVideos,
                remoteItems: _remoteVehicleMedia
                    .where((m) => m.isVideo)
                    .toList(),
                addLabel: 'Add video',
                maxItems: 2,
                onAdd: () async {
                  final media = await _recordVideo();
                  if (media == null || !mounted) return;
                  setState(() => _vehicleVideos.add(media));
                  unawaited(_uploadVehicleMediaNow([media]));
                },
                onRemove: (i) => setState(() => _vehicleVideos.removeAt(i)),
              ),
              const SizedBox(height: 20),
              const Text(
                'Comments',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                  color: AppTheme.darkTextPrimary,
                ),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _siteCommentController,
                maxLines: 3,
                decoration: _inputDecoration('Site / delivery comment'),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: _vehicleCommentController,
                maxLines: 2,
                decoration: _inputDecoration('Vehicle comment (optional)'),
              ),
            ],
          ),
        ),
        _BottomBar(
          child: Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: _busy ? null : _goBack,
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size.fromHeight(48),
                  ),
                  child: const Text('Back'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                flex: 2,
                child: ElevatedButton.icon(
                  onPressed: _busy ? null : _submitAll,
                  icon: const Icon(Icons.check_circle_outline),
                  label: const Text(
                    'Submit Proof',
                    style: TextStyle(fontWeight: FontWeight.w800),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF059669),
                    foregroundColor: Colors.white,
                    minimumSize: const Size.fromHeight(52),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildMaterialEvidenceCard(MultiMaterialLine line) {
    final draft = _draftFor(line.materialKey);
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppTheme.border),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  line.material,
                  style: const TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 16,
                    color: AppTheme.darkTextPrimary,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  '${draft.quantityReceivedToday} / ${line.orderedQuantity} ${line.unit}'
                      .trim(),
                  style: const TextStyle(
                    color: AppTheme.mutedGrey,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSuccessPhase() {
    final materials = _selectedMaterials;
    final remaining = _submitResult?.hasRemainingMaterials == true;
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 32, 24, 24),
      child: Column(
        children: [
          const Spacer(),
          Container(
            width: 88,
            height: 88,
            decoration: const BoxDecoration(
              color: Color(0xFFECFDF5),
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.check_rounded,
              size: 52,
              color: Color(0xFF059669),
            ),
          ),
          const SizedBox(height: 20),
          const Text(
            'Proof submitted successfully!',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.w800,
              color: AppTheme.darkTextPrimary,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Site proof for PO #${widget.indentId} has been submitted.',
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: AppTheme.mutedGrey,
              fontWeight: FontWeight.w600,
              height: 1.35,
            ),
          ),
          if (remaining) ...[
            const SizedBox(height: 14),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFFFFFBEB),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFFFDE68A)),
              ),
              child: const Text(
                'Some material quantities are still pending. You can submit another delivery for the remaining amounts.',
                style: TextStyle(
                  color: Color(0xFF92400E),
                  fontWeight: FontWeight.w700,
                  height: 1.35,
                ),
              ),
            ),
          ],
          const SizedBox(height: 20),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: AppTheme.border),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${materials.length} material${materials.length == 1 ? '' : 's'} added',
                  style: const TextStyle(fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 8),
                ...materials.map((line) {
                  final draft = _draftFor(line.materialKey);
                  return Text(
                    '${line.material} · ${draft.quantityReceivedToday} ${line.unit}',
                    style: const TextStyle(
                      fontWeight: FontWeight.w600,
                      color: AppTheme.mutedGrey,
                    ),
                  );
                }),
              ],
            ),
          ),
          const Spacer(),
          if (remaining) ...[
            SizedBox(
              width: double.infinity,
              height: 52,
              child: ElevatedButton(
                onPressed: _busy ? null : _startAnotherRemainingDelivery,
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.accentBlue,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
                child: const Text(
                  'Add remaining materials',
                  style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
                ),
              ),
            ),
            const SizedBox(height: 10),
          ],
          SizedBox(
            width: double.infinity,
            height: 52,
            child: remaining
                ? OutlinedButton(
                    onPressed: () => Navigator.of(context).pop(),
                    style: OutlinedButton.styleFrom(
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                    child: const Text(
                      'Back to Home',
                      style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
                    ),
                  )
                : ElevatedButton(
                    onPressed: () => Navigator.of(context).pop(),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppTheme.accentBlue,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                    child: const Text(
                      'Back to Home',
                      style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
                    ),
                  ),
          ),
        ],
      ),
    );
  }

  Future<void> _startAnotherRemainingDelivery() async {
    setState(() {
      _busy = true;
      _submitResult = null;
      _selectedOrder = [];
      _drafts.clear();
      _commonPhotos.clear();
      _commonVideos.clear();
      _vehiclePhotos.clear();
      _vehicleVideos.clear();
      _remoteDeliveryMedia.clear();
      _remoteVehicleMedia.clear();
      _measurementController.clear();
      _measurementUnitController.clear();
      _vehicleNumberController.clear();
      _driverNameController.clear();
      _driverPhoneController.clear();
      _vehicleCommentController.clear();
      _siteCommentController.clear();
    });
    try {
      final session = await _service.fetchSession(
        indentId: widget.indentId,
        itemRunId: _itemRunId.isEmpty ? null : _itemRunId,
        vendorId: _vendorId,
      );
      if (!mounted) return;
      _applySession(session);
      final stillOutstanding = session.materials.any((m) {
        final remaining = m.remainingAsNumber;
        return remaining == null || remaining > 0.0001;
      });
      if (!stillOutstanding) {
        setState(() => _busy = false);
        _snack('All materials are fully received.');
        return;
      }
      setState(() {
        _busy = false;
        _phase = _WizardPhase.select;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _busy = false);
      _snack(e.toString().replaceFirst('Exception: ', ''), error: true);
    }
  }

  InputDecoration _inputDecoration(String? hint) {
    return InputDecoration(
      hintText: hint,
      filled: true,
      fillColor: AppTheme.darkBackgroundPrimaryLight,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: AppTheme.border),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: AppTheme.border),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: AppTheme.accentBlue, width: 1.4),
      ),
    );
  }
}

// ─── shared widgets ──────────────────────────────────────────────────────────

class _ErrorPane extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;

  const _ErrorPane({required this.message, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              message,
              textAlign: TextAlign.center,
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 16),
            ElevatedButton(onPressed: onRetry, child: const Text('Retry')),
          ],
        ),
      ),
    );
  }
}

class _BottomBar extends StatelessWidget {
  final Widget child;

  const _BottomBar({required this.child});

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: Container(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
        decoration: const BoxDecoration(
          color: Colors.white,
          border: Border(top: BorderSide(color: AppTheme.border)),
        ),
        child: child,
      ),
    );
  }
}

class _GpsBanner extends StatelessWidget {
  final bool isChecking;
  final bool onSite;
  final bool siteConfigured;
  final String? error;
  final double? distanceMeters;
  final int radiusMeters;
  final bool showOpenSettings;
  final Future<void> Function()? onRecheck;
  final Future<void> Function()? onOpenSettings;

  const _GpsBanner({
    required this.isChecking,
    required this.onSite,
    required this.siteConfigured,
    required this.error,
    required this.distanceMeters,
    required this.radiusMeters,
    required this.showOpenSettings,
    required this.onRecheck,
    required this.onOpenSettings,
  });

  @override
  Widget build(BuildContext context) {
    final hasError = siteConfigured && !onSite;
    final bg = isChecking
        ? const Color(0xFFEFF6FF)
        : hasError
            ? const Color(0xFFFEF2F2)
            : const Color(0xFFECFDF5);
    final border = isChecking
        ? const Color(0xFFBFDBFE)
        : hasError
            ? const Color(0xFFFECACA)
            : const Color(0xFFA7F3D0);
    final ink = isChecking
        ? const Color(0xFF1D4ED8)
        : hasError
            ? const Color(0xFF991B1B)
            : const Color(0xFF065F46);

    String message;
    if (isChecking) {
      message = 'Checking your distance from the project site…';
    } else if (!siteConfigured) {
      message = 'Site location not provided — continuing without geofence.';
    } else if (!onSite) {
      message = error?.trim().isNotEmpty == true
          ? error!.trim()
          : 'Go to the project site to continue.';
    } else {
      message = 'You are on site';
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              if (isChecking)
                const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              else
                Icon(
                  onSite ? Icons.location_on : Icons.lock_outline,
                  color: ink,
                  size: 20,
                ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  message,
                  style: TextStyle(
                    color: ink,
                    fontWeight: FontWeight.w700,
                    fontSize: 13,
                    height: 1.35,
                  ),
                ),
              ),
            ],
          ),
          if (!isChecking && onSite && distanceMeters != null) ...[
            const SizedBox(height: 6),
            Text(
              'About ${distanceMeters!.round()} m from site · ${radiusMeters}m radius',
              style: TextStyle(
                color: ink.withValues(alpha: 0.8),
                fontSize: 11,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
          const SizedBox(height: 10),
          OutlinedButton.icon(
            onPressed: onRecheck,
            icon: const Icon(Icons.my_location, size: 16),
            label: const Text('Recheck location'),
            style: OutlinedButton.styleFrom(
              foregroundColor: ink,
              side: BorderSide(color: border),
              visualDensity: VisualDensity.compact,
            ),
          ),
          if (showOpenSettings && onOpenSettings != null)
            TextButton(
              onPressed: onOpenSettings,
              child: const Text('Open settings'),
            ),
        ],
      ),
    );
  }
}

class _QuantityStepper extends StatefulWidget {
  final String valueText;
  final String unit;
  final ValueChanged<String> onChanged;

  const _QuantityStepper({
    required this.valueText,
    required this.unit,
    required this.onChanged,
  });

  @override
  State<_QuantityStepper> createState() => _QuantityStepperState();
}

class _QuantityStepperState extends State<_QuantityStepper> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.valueText);
  }

  @override
  void didUpdateWidget(covariant _QuantityStepper oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.valueText != widget.valueText &&
        _controller.text != widget.valueText) {
      _controller.text = widget.valueText;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  double get _value =>
      double.tryParse(_controller.text.replaceAll(',', '')) ?? 0;

  void _bump(double delta) {
    final next = (_value + delta).clamp(0, 999999);
    final text = next == next.roundToDouble()
        ? next.round().toString()
        : next.toStringAsFixed(2);
    _controller.text = text;
    widget.onChanged(text);
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        _RoundIconButton(icon: Icons.remove, onPressed: () => _bump(-1)),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: TextField(
              controller: _controller,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.w800,
              ),
              onChanged: widget.onChanged,
              decoration: InputDecoration(
                suffixText: widget.unit,
                filled: true,
                fillColor: AppTheme.darkBackgroundPrimaryLight,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
          ),
        ),
        _RoundIconButton(icon: Icons.add, onPressed: () => _bump(1)),
      ],
    );
  }
}

class _RoundIconButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback onPressed;

  const _RoundIconButton({required this.icon, required this.onPressed});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 48,
      height: 48,
      child: OutlinedButton(
        onPressed: onPressed,
        style: OutlinedButton.styleFrom(
          padding: EdgeInsets.zero,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
        child: Icon(icon),
      ),
    );
  }
}

class _MediaRow extends StatelessWidget {
  final String title;
  final List<_LocalMedia> items;
  final List<MultiMaterialRemoteMedia> remoteItems;
  final String addLabel;
  final Future<void> Function() onAdd;
  final ValueChanged<int> onRemove;
  final int? maxItems;

  const _MediaRow({
    required this.title,
    required this.items,
    required this.addLabel,
    required this.onAdd,
    required this.onRemove,
    this.remoteItems = const [],
    this.maxItems,
  });

  @override
  Widget build(BuildContext context) {
    final totalCount = items.length + remoteItems.length;
    final canAdd = maxItems == null || totalCount < maxItems!;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: const TextStyle(
            fontWeight: FontWeight.w700,
            color: AppTheme.darkTextPrimary,
            fontSize: 13,
          ),
        ),
        const SizedBox(height: 8),
        SizedBox(
          height: 80,
          child: ListView(
            scrollDirection: Axis.horizontal,
            children: [
              ...remoteItems.map((remote) {
                return Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: remote.isVideo
                        ? Container(
                            width: 80,
                            height: 80,
                            color: AppTheme.darkTextPrimary,
                            child: const Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(
                                  Icons.play_circle_fill,
                                  color: Colors.white,
                                  size: 28,
                                ),
                                SizedBox(height: 4),
                                Text(
                                  'Saved',
                                  style: TextStyle(
                                    color: Colors.white70,
                                    fontSize: 10,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ],
                            ),
                          )
                        : Stack(
                            children: [
                              Image.network(
                                remote.url,
                                width: 80,
                                height: 80,
                                fit: BoxFit.cover,
                                errorBuilder: (_, __, ___) => Container(
                                  width: 80,
                                  height: 80,
                                  color: const Color(0xFFE5E7EB),
                                  child: const Icon(Icons.image),
                                ),
                              ),
                              Positioned(
                                bottom: 4,
                                left: 4,
                                child: Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 4,
                                    vertical: 2,
                                  ),
                                  decoration: BoxDecoration(
                                    color: Colors.black54,
                                    borderRadius: BorderRadius.circular(4),
                                  ),
                                  child: const Text(
                                    'Saved',
                                    style: TextStyle(
                                      color: Colors.white,
                                      fontSize: 9,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                  ),
                );
              }),
              ...List.generate(items.length, (index) {
                final item = items[index];
                return Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: Stack(
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(12),
                        child: item.isVideo
                            ? Container(
                                width: 80,
                                height: 80,
                                color: AppTheme.darkTextPrimary,
                                child: const Icon(
                                  Icons.play_circle_fill,
                                  color: Colors.white,
                                  size: 32,
                                ),
                              )
                            : Image.file(
                                item.file,
                                width: 80,
                                height: 80,
                                fit: BoxFit.cover,
                              ),
                      ),
                      Positioned(
                        top: 4,
                        right: 4,
                        child: InkWell(
                          onTap: () => onRemove(index),
                          child: Container(
                            decoration: const BoxDecoration(
                              color: Colors.black54,
                              shape: BoxShape.circle,
                            ),
                            padding: const EdgeInsets.all(2),
                            child: const Icon(
                              Icons.close,
                              size: 14,
                              color: Colors.white,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                );
              }),
              if (canAdd)
                InkWell(
                  onTap: onAdd,
                  borderRadius: BorderRadius.circular(12),
                  child: Container(
                    width: 80,
                    height: 80,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: AppTheme.accentBlue),
                      color: const Color(0xFFEFF6FF),
                    ),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(Icons.add, color: AppTheme.accentBlue),
                        const SizedBox(height: 2),
                        Text(
                          addLabel,
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            color: AppTheme.accentBlue,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

