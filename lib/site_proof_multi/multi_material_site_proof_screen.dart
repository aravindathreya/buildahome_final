import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';

import '../app_theme.dart';
import '../models/approved_po.dart';
import '../models/multi_material_site_proof.dart';
import '../services/location_service.dart';
import '../services/multi_material_site_proof_service.dart';
import '../widgets/themed_scaffold.dart';

enum _WizardPhase {
  select,
  materialDetail,
  measurement,
  vehicle,
  review,
  success,
}

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

/// Multi-material site-proof wizard (separate from single-material flow).
class MultiMaterialSiteProofScreen extends StatefulWidget {
  final String indentId;
  final String itemRunId;
  final Map<String, dynamic> task;
  final ApprovedPo? approvedPo;
  final Future<void> Function() onChanged;

  const MultiMaterialSiteProofScreen({
    super.key,
    required this.indentId,
    required this.itemRunId,
    required this.task,
    required this.onChanged,
    this.approvedPo,
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
  final _materialCommentController = TextEditingController();

  MultiMaterialSiteProofSession? _session;
  final Map<String, _MaterialDraft> _drafts = {};
  List<String> _selectedOrder = [];
  int _materialIndex = 0;
  _WizardPhase _phase = _WizardPhase.select;
  String _vehicleType = 'Truck';
  final List<_LocalMedia> _vehiclePhotos = [];
  final List<_LocalMedia> _measurementPhotos = [];

  bool _loading = true;
  bool _busy = false;
  String? _error;
  String? _materialValidation;

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
    _bootstrap();
  }

  @override
  void dispose() {
    _searchController.dispose();
    _measurementController.dispose();
    _measurementUnitController.dispose();
    _vehicleNumberController.dispose();
    _driverNameController.dispose();
    _driverPhoneController.dispose();
    _vehicleCommentController.dispose();
    _siteCommentController.dispose();
    _materialCommentController.dispose();
    super.dispose();
  }

  String get _itemRunId {
    final fromSession = _session?.itemRunId.toString() ?? '';
    if (fromSession.isNotEmpty && fromSession != '0') return fromSession;
    return widget.itemRunId.trim();
  }

  String get _subtitle {
    final po = widget.approvedPo;
    final parts = <String>[];
    final poNo = (po?.displayPoNumber() ??
            _session?.poNumber ??
            '')
        .trim();
    if (poNo.isNotEmpty) parts.add(poNo);
    final project = (po?.projectName ?? _session?.projectName ?? '').trim();
    if (project.isNotEmpty) parts.add(project);
    final indent = widget.indentId.trim();
    if (indent.isNotEmpty) parts.add('#$indent');
    return parts.join(' · ');
  }

  List<MultiMaterialLine> get _materials => _session?.materials ?? const [];

  List<MultiMaterialLine> get _filteredMaterials {
    final q = _searchController.text.trim().toLowerCase();
    if (q.isEmpty) return _materials;
    return _materials
        .where((m) =>
            m.material.toLowerCase().contains(q) ||
            m.unit.toLowerCase().contains(q))
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
    return _drafts.putIfAbsent(
      key,
      () => _MaterialDraft(materialKey: key),
    );
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
      );
      if (!mounted) return;
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
      // Backend did not provide site coords — do not hard-block the wizard.
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
      if (selected) {
        if (!_selectedOrder.contains(line.materialKey)) {
          _selectedOrder.add(line.materialKey);
        }
      } else {
        _selectedOrder.remove(line.materialKey);
      }
    });
  }

  Future<void> _continueFromSelect() async {
    if (!_onSite && _siteConfigured) {
      _snack(_locationError ?? 'You must be on site to continue.', error: true);
      return;
    }
    if (_selectedOrder.isEmpty) {
      _snack('Select at least one material.', error: true);
      return;
    }
    setState(() {
      _materialIndex = 0;
      _phase = _WizardPhase.materialDetail;
      _materialValidation = null;
      _loadMaterialEditors();
    });
  }

  void _loadMaterialEditors() {
    final materials = _selectedMaterials;
    if (_materialIndex < 0 || _materialIndex >= materials.length) return;
    final line = materials[_materialIndex];
    final draft = _draftFor(line.materialKey);
    if (draft.quantityReceivedToday.isEmpty &&
        line.quantityReceivedToday.isNotEmpty) {
      draft.quantityReceivedToday = line.quantityReceivedToday;
    }
    _materialCommentController.text = draft.comment;
  }

  String? _validateMaterialDraft(MultiMaterialLine line, _MaterialDraft draft) {
    final qtyText = draft.quantityReceivedToday.trim();
    final qty = double.tryParse(qtyText.replaceAll(',', ''));
    if (qtyText.isEmpty || qty == null) {
      return 'Enter quantity received today.';
    }
    if (qty <= 0) {
      return 'Quantity must be greater than zero.';
    }
    final remaining = line.remainingAsNumber;
    if (remaining != null && qty > remaining + 0.0001) {
      return 'Quantity cannot exceed remaining (${line.remainingQuantity} ${line.unit}).';
    }
    final minPhotos = line.effectiveMinPhotos;
    if (draft.photos.length < minPhotos) {
      return minPhotos == 1
          ? 'Add at least one photo for this material.'
          : 'Add at least $minPhotos photos for this material.';
    }
    if (line.requireVideo && draft.videos.isEmpty) {
      return 'Add a video for this material.';
    }
    if (draft.photos.length > line.effectiveMaxPhotos) {
      return 'You can add at most ${line.effectiveMaxPhotos} photos.';
    }
    return null;
  }

  Future<void> _saveAndNextMaterial() async {
    final materials = _selectedMaterials;
    if (_materialIndex >= materials.length) return;
    final line = materials[_materialIndex];
    final draft = _draftFor(line.materialKey);
    draft.comment = _materialCommentController.text.trim();

    final validation = _validateMaterialDraft(line, draft);
    if (validation != null) {
      setState(() => _materialValidation = validation);
      return;
    }

    setState(() {
      _busy = true;
      _materialValidation = null;
    });
    try {
      await _service.saveMaterial(
        itemRunId: _itemRunId,
        materialKey: line.materialKey,
        quantityReceivedToday: draft.quantityReceivedToday.trim(),
        comment: draft.comment,
      );

      final pendingFiles = <File>[
        ...draft.photos.map((p) => p.file),
        ...draft.videos.map((v) => v.file),
      ];
      if (pendingFiles.isNotEmpty) {
        await _service.uploadMaterialFiles(
          itemRunId: _itemRunId,
          materialKey: line.materialKey,
          files: pendingFiles,
        );
      }

      draft.savedToServer = true;
      if (!mounted) return;

      if (_materialIndex < materials.length - 1) {
        setState(() {
          _busy = false;
          _materialIndex += 1;
          _loadMaterialEditors();
        });
      } else {
        setState(() {
          _busy = false;
          _phase = _WizardPhase.measurement;
        });
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _busy = false);
      _snack(e.toString().replaceFirst('Exception: ', ''), error: true);
    }
  }

  Future<void> _continueFromMeasurement() async {
    setState(() => _busy = true);
    try {
      final fields = MultiMaterialCommonFields(
        measurement: _measurementController.text.trim(),
        measurementUnit: _measurementUnitController.text.trim(),
        siteComment: _siteCommentController.text.trim(),
        vehicleNumber: _vehicleNumberController.text.trim(),
        vehicleType: _vehicleType,
        driverName: _driverNameController.text.trim(),
        driverPhone: _driverPhoneController.text.trim(),
        vehicleComment: _vehicleCommentController.text.trim(),
      );
      await _service.saveCommon(itemRunId: _itemRunId, fields: fields);
      if (!mounted) return;
      setState(() {
        _busy = false;
        _phase = _WizardPhase.vehicle;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _busy = false);
      _snack(e.toString().replaceFirst('Exception: ', ''), error: true);
    }
  }

  Future<void> _continueFromVehicle() async {
    final vehicleNo = _vehicleNumberController.text.trim();
    if (vehicleNo.isEmpty) {
      _snack('Vehicle number is required.', error: true);
      return;
    }
    setState(() => _busy = true);
    try {
      final fields = MultiMaterialCommonFields(
        measurement: _measurementController.text.trim(),
        measurementUnit: _measurementUnitController.text.trim(),
        siteComment: _siteCommentController.text.trim(),
        vehicleNumber: vehicleNo,
        vehicleType: _vehicleType,
        driverName: _driverNameController.text.trim(),
        driverPhone: _driverPhoneController.text.trim(),
        vehicleComment: _vehicleCommentController.text.trim(),
      );
      await _service.saveCommon(itemRunId: _itemRunId, fields: fields);
      if (_vehiclePhotos.isNotEmpty) {
        await _service.uploadVehicleFiles(
          itemRunId: _itemRunId,
          files: _vehiclePhotos.map((p) => p.file).toList(),
        );
      }
      if (!mounted) return;
      setState(() {
        _busy = false;
        _phase = _WizardPhase.review;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _busy = false);
      _snack(e.toString().replaceFirst('Exception: ', ''), error: true);
    }
  }

  Future<void> _submit() async {
    setState(() => _busy = true);
    try {
      final result = await _service.submit(itemRunId: _itemRunId);
      await widget.onChanged();
      if (!mounted) return;
      setState(() {
        _busy = false;
        _submitResult = result;
        _phase = _WizardPhase.success;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _busy = false);
      _snack(e.toString().replaceFirst('Exception: ', ''), error: true);
    }
  }

  Future<_LocalMedia?> _capturePhoto() async {
    final picked = await ImagePicker().pickImage(
      source: ImageSource.camera,
      imageQuality: 88,
    );
    if (picked == null) return null;
    final capturedAt = DateTime.now();
    final timestamp = DateFormat('yyyyMMdd_HHmmss').format(capturedAt);
    final stampedName = 'live_$timestamp.jpg';
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
    final picked = await ImagePicker().pickVideo(
      source: ImageSource.camera,
      maxDuration: const Duration(seconds: 60),
    );
    if (picked == null) return null;
    final timestamp = DateFormat('yyyyMMdd_HHmmss').format(DateTime.now());
    final name = 'video_$timestamp.mp4';
    final path =
        '${Directory.systemTemp.path}${Platform.pathSeparator}$name';
    final copied = await File(picked.path).copy(path);
    return _LocalMedia(file: copied, isVideo: true);
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
      case _WizardPhase.materialDetail:
        if (_materialIndex > 0) {
          setState(() {
            _materialIndex -= 1;
            _materialValidation = null;
            _loadMaterialEditors();
          });
        } else {
          setState(() => _phase = _WizardPhase.select);
        }
        break;
      case _WizardPhase.measurement:
        setState(() {
          _phase = _WizardPhase.materialDetail;
          _materialIndex = _selectedMaterials.length - 1;
          _loadMaterialEditors();
        });
        break;
      case _WizardPhase.vehicle:
        setState(() => _phase = _WizardPhase.measurement);
        break;
      case _WizardPhase.review:
        setState(() => _phase = _WizardPhase.vehicle);
        break;
      case _WizardPhase.success:
        Navigator.of(context).pop();
        break;
    }
  }

  int get _totalWizardSteps {
    // materials N + measurement + vehicle + review
    final n = _selectedOrder.isEmpty ? 1 : _selectedOrder.length;
    return n + 3;
  }

  int get _currentWizardStep {
    switch (_phase) {
      case _WizardPhase.select:
        return 0;
      case _WizardPhase.materialDetail:
        return _materialIndex + 1;
      case _WizardPhase.measurement:
        return _selectedOrder.length + 1;
      case _WizardPhase.vehicle:
        return _selectedOrder.length + 2;
      case _WizardPhase.review:
      case _WizardPhase.success:
        return _selectedOrder.length + 3;
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
        if (_phase != _WizardPhase.select &&
            _phase != _WizardPhase.success &&
            _selectedOrder.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: Center(
              child: Text(
                '${_currentWizardStep} of $_totalWizardSteps',
                style: const TextStyle(
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
      case _WizardPhase.materialDetail:
        return _buildMaterialDetailPhase();
      case _WizardPhase.measurement:
        return _buildMeasurementPhase();
      case _WizardPhase.vehicle:
        return _buildVehiclePhase();
      case _WizardPhase.review:
        return _buildReviewPhase();
      case _WizardPhase.success:
        return _buildSuccessPhase();
    }
  }

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
                    'Materials (${_materials.length})',
                    style: const TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w800,
                      color: AppTheme.navy,
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
              const SizedBox(height: 10),
              TextField(
                controller: _searchController,
                onChanged: (_) => setState(() {}),
                decoration: InputDecoration(
                  hintText: 'Search materials',
                  prefixIcon: const Icon(Icons.search),
                  filled: true,
                  fillColor: Colors.white,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: const BorderSide(color: AppTheme.border),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: const BorderSide(color: AppTheme.border),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              ..._filteredMaterials.map(_buildMaterialSelectTile),
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
                    : 'Continue ($selectedCount material${selectedCount == 1 ? '' : 's'}) →',
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

  Widget _buildMaterialSelectTile(MultiMaterialLine line) {
    final draft = _draftFor(line.materialKey);
    final selected = draft.selected;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Material(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: () => _toggleMaterial(line, !selected),
          child: Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: selected
                    ? const Color(0xFF93C5FD)
                    : AppTheme.border,
                width: selected ? 1.5 : 1,
              ),
              color: selected ? const Color(0xFFEFF6FF) : Colors.white,
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Checkbox(
                  value: selected,
                  onChanged: (v) => _toggleMaterial(line, v),
                ),
                if ((line.thumbnailUrl ?? '').isNotEmpty) ...[
                  ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: Image.network(
                      line.thumbnailUrl!,
                      width: 48,
                      height: 48,
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => _thumbPlaceholder(),
                    ),
                  ),
                  const SizedBox(width: 10),
                ] else ...[
                  _thumbPlaceholder(),
                  const SizedBox(width: 10),
                ],
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        line.material,
                        style: const TextStyle(
                          fontWeight: FontWeight.w800,
                          fontSize: 16,
                          color: AppTheme.navy,
                        ),
                      ),
                      const SizedBox(height: 6),
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
        ),
      ),
    );
  }

  Widget _thumbPlaceholder() {
    return Container(
      width: 48,
      height: 48,
      decoration: BoxDecoration(
        color: const Color(0xFFF1F5F9),
        borderRadius: BorderRadius.circular(8),
      ),
      child: const Icon(Icons.inventory_2_outlined, color: AppTheme.mutedGrey),
    );
  }

  Widget _buildMaterialDetailPhase() {
    final materials = _selectedMaterials;
    if (materials.isEmpty) {
      return const Center(child: Text('No materials selected.'));
    }
    final line = materials[_materialIndex];
    final draft = _draftFor(line.materialKey);
    final remainingAfter =
        _remainingAfterThis(line, draft.quantityReceivedToday);
    final qty = double.tryParse(
          draft.quantityReceivedToday.trim().replaceAll(',', ''),
        ) ??
        0;
    final remaining = line.remainingAsNumber;
    final fullyReceived =
        remaining != null && qty > 0 && (remaining - qty).abs() < 0.0001;

    return Column(
      children: [
        Expanded(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
            children: [
              Align(
                alignment: Alignment.centerRight,
                child: Text(
                  '${_materialIndex + 1} of ${materials.length}',
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    color: AppTheme.mutedGrey,
                  ),
                ),
              ),
              const SizedBox(height: 8),
              _MaterialSummaryCard(line: line),
              const SizedBox(height: 16),
              const Text(
                'Quantity received today *',
                style: TextStyle(
                  fontWeight: FontWeight.w700,
                  color: AppTheme.navy,
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
                    _materialValidation = null;
                  });
                },
              ),
              if (remainingAfter != null) ...[
                const SizedBox(height: 10),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    _Pill(
                      label: 'Remaining after this: $remainingAfter',
                      color: const Color(0xFF065F46),
                      bg: const Color(0xFFECFDF5),
                    ),
                    if (fullyReceived)
                      const _Pill(
                        label: 'Fully received',
                        color: Color(0xFF065F46),
                        bg: Color(0xFFECFDF5),
                      ),
                  ],
                ),
              ],
              if (_materialValidation != null) ...[
                const SizedBox(height: 10),
                Text(
                  _materialValidation!,
                  style: const TextStyle(
                    color: Color(0xFFB91C1C),
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
              const SizedBox(height: 20),
              _MediaSection(
                title: 'Photos (Max ${line.effectiveMaxPhotos}) *',
                items: draft.photos,
                addLabel: 'Add photo',
                onAdd: () async {
                  if (draft.photos.length >= line.effectiveMaxPhotos) {
                    _snack(
                      'Max ${line.effectiveMaxPhotos} photos allowed.',
                      error: true,
                    );
                    return;
                  }
                  final media = await _capturePhoto();
                  if (media == null || !mounted) return;
                  setState(() {
                    draft.photos.add(media);
                    _materialValidation = null;
                  });
                },
                onRemove: (i) => setState(() => draft.photos.removeAt(i)),
              ),
              const SizedBox(height: 16),
              _MediaSection(
                title: line.requireVideo ? 'Video *' : 'Video (Optional)',
                items: draft.videos,
                addLabel: 'Add video',
                maxItems: 1,
                onAdd: () async {
                  if (draft.videos.isNotEmpty) {
                    _snack('Only one video per material.', error: true);
                    return;
                  }
                  final media = await _recordVideo();
                  if (media == null || !mounted) return;
                  setState(() {
                    draft.videos.add(media);
                    _materialValidation = null;
                  });
                },
                onRemove: (i) => setState(() => draft.videos.removeAt(i)),
              ),
              const SizedBox(height: 16),
              const Text(
                'Comment (Optional)',
                style: TextStyle(
                  fontWeight: FontWeight.w700,
                  color: AppTheme.navy,
                ),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _materialCommentController,
                maxLines: 3,
                decoration: _inputDecoration('Enter comment...'),
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
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: const Text('Back'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                flex: 2,
                child: ElevatedButton(
                  onPressed: _busy ? null : _saveAndNextMaterial,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.accentBlue,
                    foregroundColor: Colors.white,
                    minimumSize: const Size.fromHeight(48),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: Text(
                    _materialIndex < materials.length - 1
                        ? 'Save & Next →'
                        : 'Save & Continue →',
                    style: const TextStyle(fontWeight: FontWeight.w800),
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildMeasurementPhase() {
    return Column(
      children: [
        Expanded(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
            children: [
              const _SectionHeader(
                icon: Icons.straighten,
                title: 'Site Measurement',
                subtitle: 'Capture measurement details (if required)',
              ),
              const SizedBox(height: 16),
              const Text(
                'Measurement (Optional)',
                style: TextStyle(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _measurementController,
                decoration: _inputDecoration('e.g. Area levelled'),
              ),
              const SizedBox(height: 12),
              const Text(
                'Unit',
                style: TextStyle(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _measurementUnitController,
                decoration: _inputDecoration('Sq. ft'),
              ),
              const SizedBox(height: 16),
              _MediaSection(
                title: 'Measurement Photo (Optional)',
                items: _measurementPhotos,
                addLabel: 'Add photo',
                maxItems: 3,
                onAdd: () async {
                  final media = await _capturePhoto();
                  if (media == null || !mounted) return;
                  setState(() => _measurementPhotos.add(media));
                },
                onRemove: (i) =>
                    setState(() => _measurementPhotos.removeAt(i)),
              ),
              const SizedBox(height: 16),
              const Text(
                'Comment (Optional)',
                style: TextStyle(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _siteCommentController,
                maxLines: 3,
                decoration: _inputDecoration('Comment'),
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
                child: ElevatedButton(
                  onPressed: _busy ? null : _continueFromMeasurement,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.accentBlue,
                    foregroundColor: Colors.white,
                    minimumSize: const Size.fromHeight(48),
                  ),
                  child: const Text(
                    'Continue →',
                    style: TextStyle(fontWeight: FontWeight.w800),
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildVehiclePhase() {
    return Column(
      children: [
        Expanded(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
            children: [
              const _SectionHeader(
                icon: Icons.local_shipping_outlined,
                title: 'Vehicle Information',
                subtitle: 'Enter the vehicle details for this delivery',
              ),
              const SizedBox(height: 16),
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
              const SizedBox(height: 12),
              const Text(
                'Vehicle type',
                style: TextStyle(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 8),
              DropdownButtonFormField<String>(
                value: _vehicleTypes.contains(_vehicleType)
                    ? _vehicleType
                    : _vehicleTypes.first,
                items: _vehicleTypes
                    .map(
                      (t) => DropdownMenuItem(value: t, child: Text(t)),
                    )
                    .toList(),
                onChanged: (v) {
                  if (v == null) return;
                  setState(() => _vehicleType = v);
                },
                decoration: _inputDecoration(null),
              ),
              const SizedBox(height: 12),
              const Text(
                'Driver name',
                style: TextStyle(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _driverNameController,
                decoration: _inputDecoration('Driver name'),
              ),
              const SizedBox(height: 12),
              const Text(
                'Driver phone number',
                style: TextStyle(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _driverPhoneController,
                keyboardType: TextInputType.phone,
                decoration: _inputDecoration('Phone number'),
              ),
              const SizedBox(height: 16),
              _MediaSection(
                title: 'Vehicle photo (Optional)',
                items: _vehiclePhotos,
                addLabel: 'Add photo',
                maxItems: 3,
                onAdd: () async {
                  final media = await _capturePhoto();
                  if (media == null || !mounted) return;
                  setState(() => _vehiclePhotos.add(media));
                },
                onRemove: (i) => setState(() => _vehiclePhotos.removeAt(i)),
              ),
              const SizedBox(height: 16),
              const Text(
                'Comment (Optional)',
                style: TextStyle(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _vehicleCommentController,
                maxLines: 3,
                decoration: _inputDecoration('Comment'),
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
                child: ElevatedButton(
                  onPressed: _busy ? null : _continueFromVehicle,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.accentBlue,
                    foregroundColor: Colors.white,
                    minimumSize: const Size.fromHeight(48),
                  ),
                  child: const Text(
                    'Continue →',
                    style: TextStyle(fontWeight: FontWeight.w800),
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildReviewPhase() {
    final materials = _selectedMaterials;
    final commentCount = [
      if (_siteCommentController.text.trim().isNotEmpty) 1,
      if (_vehicleCommentController.text.trim().isNotEmpty) 1,
      ...materials.map((m) {
        final c = _draftFor(m.materialKey).comment.trim();
        return c.isNotEmpty ? 1 : 0;
      }),
    ].fold<int>(0, (a, b) => a + b);

    return Column(
      children: [
        Expanded(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
            children: [
              const Text(
                'Review & Submit',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w800,
                  color: AppTheme.navy,
                ),
              ),
              const SizedBox(height: 16),
              _ReviewCard(
                title: 'Materials (${materials.length} items)',
                onEdit: () => setState(() {
                  _phase = _WizardPhase.materialDetail;
                  _materialIndex = 0;
                  _loadMaterialEditors();
                }),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: materials.map((line) {
                    final draft = _draftFor(line.materialKey);
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Text(
                        '✓ ${line.material}\n'
                        '  ${draft.quantityReceivedToday} / ${line.orderedQuantity} ${line.unit}\n'
                        '  ${draft.photos.length} photos · ${draft.videos.length} video',
                        style: const TextStyle(
                          height: 1.4,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    );
                  }).toList(),
                ),
              ),
              _ReviewCard(
                title: 'Measurement',
                onEdit: () =>
                    setState(() => _phase = _WizardPhase.measurement),
                child: Text(
                  _measurementController.text.trim().isEmpty
                      ? 'Not provided'
                      : '${_measurementController.text.trim()}'
                          '${_measurementUnitController.text.trim().isEmpty ? '' : ' (${_measurementUnitController.text.trim()})'}',
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
              ),
              _ReviewCard(
                title: 'Vehicle Details',
                onEdit: () => setState(() => _phase = _WizardPhase.vehicle),
                child: Text(
                  [
                    _vehicleNumberController.text.trim(),
                    _vehicleType,
                    if (_driverNameController.text.trim().isNotEmpty)
                      'Driver: ${_driverNameController.text.trim()}',
                  ].where((e) => e.isNotEmpty).join('\n'),
                  style: const TextStyle(
                    fontWeight: FontWeight.w600,
                    height: 1.4,
                  ),
                ),
              ),
              _ReviewCard(
                title: 'Additional Comments',
                onEdit: null,
                child: Text(
                  commentCount == 0
                      ? 'No comments'
                      : '$commentCount comment${commentCount == 1 ? '' : 's'} added',
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
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
                  onPressed: _busy ? null : _submit,
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
              color: AppTheme.navy,
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
                'Some material quantities are still pending. Another delivery / site-proof cycle may be required.',
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
          SizedBox(
            width: double.infinity,
            height: 52,
            child: ElevatedButton(
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

  InputDecoration _inputDecoration(String? hint) {
    return InputDecoration(
      hintText: hint,
      filled: true,
      fillColor: Colors.white,
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
            ElevatedButton(
              onPressed: onRetry,
              child: const Text('Retry'),
            ),
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

class _MaterialSummaryCard extends StatelessWidget {
  final MultiMaterialLine line;

  const _MaterialSummaryCard({required this.line});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppTheme.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            line.material,
            style: const TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w800,
              color: AppTheme.navy,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Unit: ${line.unit}',
            style: const TextStyle(
              color: AppTheme.mutedGrey,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              _Stat('Ordered', '${line.orderedQuantity} ${line.unit}'),
              _Stat(
                'Already received',
                '${line.previouslyReceivedQuantity} ${line.unit}',
              ),
              _Stat('Remaining', '${line.remainingQuantity} ${line.unit}'),
            ],
          ),
        ],
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  final String label;
  final String value;

  const _Stat(this.label, this.value);

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: const TextStyle(
              fontSize: 11,
              color: AppTheme.mutedGrey,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            value.trim(),
            style: const TextStyle(
              fontWeight: FontWeight.w800,
              fontSize: 13,
              color: AppTheme.navy,
            ),
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
        _RoundIconButton(
          icon: Icons.remove,
          onPressed: () => _bump(-1),
        ),
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
                fillColor: Colors.white,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
          ),
        ),
        _RoundIconButton(
          icon: Icons.add,
          onPressed: () => _bump(1),
        ),
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

class _Pill extends StatelessWidget {
  final String label;
  final Color color;
  final Color bg;

  const _Pill({
    required this.label,
    required this.color,
    required this.bg,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontWeight: FontWeight.w700,
          fontSize: 12.5,
        ),
      ),
    );
  }
}

class _MediaSection extends StatelessWidget {
  final String title;
  final List<_LocalMedia> items;
  final String addLabel;
  final Future<void> Function() onAdd;
  final ValueChanged<int> onRemove;
  final int? maxItems;

  const _MediaSection({
    required this.title,
    required this.items,
    required this.addLabel,
    required this.onAdd,
    required this.onRemove,
    this.maxItems,
  });

  @override
  Widget build(BuildContext context) {
    final canAdd = maxItems == null || items.length < maxItems!;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: const TextStyle(
            fontWeight: FontWeight.w700,
            color: AppTheme.navy,
          ),
        ),
        const SizedBox(height: 8),
        SizedBox(
          height: 88,
          child: ListView(
            scrollDirection: Axis.horizontal,
            children: [
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
                                width: 88,
                                height: 88,
                                color: const Color(0xFF0F172A),
                                child: const Icon(
                                  Icons.play_circle_fill,
                                  color: Colors.white,
                                  size: 36,
                                ),
                              )
                            : Image.file(
                                item.file,
                                width: 88,
                                height: 88,
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
                    width: 88,
                    height: 88,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: AppTheme.accentBlue,
                        style: BorderStyle.solid,
                      ),
                      color: const Color(0xFFEFF6FF),
                    ),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(Icons.add, color: AppTheme.accentBlue),
                        const SizedBox(height: 4),
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

class _SectionHeader extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;

  const _SectionHeader({
    required this.icon,
    required this.title,
    required this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            color: const Color(0xFFEFF6FF),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(icon, color: AppTheme.accentBlue),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w800,
                  color: AppTheme.navy,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                subtitle,
                style: const TextStyle(
                  color: AppTheme.mutedGrey,
                  fontWeight: FontWeight.w600,
                  height: 1.3,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _ReviewCard extends StatelessWidget {
  final String title;
  final Widget child;
  final VoidCallback? onEdit;

  const _ReviewCard({
    required this.title,
    required this.child,
    required this.onEdit,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppTheme.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 15,
                  ),
                ),
              ),
              if (onEdit != null)
                TextButton(
                  onPressed: onEdit,
                  child: const Text('Edit'),
                ),
            ],
          ),
          const SizedBox(height: 6),
          child,
        ],
      ),
    );
  }
}
