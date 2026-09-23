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
/// 2) Per-material photo/video, then shared photo/video/measurement/comments
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

  MultiMaterialSiteProofSession? _session;
  final Map<String, _MaterialDraft> _drafts = {};
  List<String> _selectedOrder = [];
  _WizardPhase _phase = _WizardPhase.select;
  String _vehicleType = 'Truck';
  final List<_LocalMedia> _commonPhotos = [];
  final List<_LocalMedia> _commonVideos = [];
  final List<_LocalMedia> _vehiclePhotos = [];

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
      _phase = _WizardPhase.evidence;
    });
  }

  Future<void> _submitAll() async {
    if (_vehicleNumberController.text.trim().isEmpty) {
      _snack('Vehicle number is required.', error: true);
      return;
    }

    final hasAnyPhoto = _selectedMaterials.any(
          (line) => _draftFor(line.materialKey).photos.isNotEmpty,
        ) ||
        _commonPhotos.isNotEmpty ||
        _vehiclePhotos.isNotEmpty;
    if (!hasAnyPhoto) {
      _snack(
        'Add at least one photo (on a material or below).',
        error: true,
      );
      return;
    }

    setState(() => _busy = true);
    try {
      // 1) Save each material + its media
      for (final line in _selectedMaterials) {
        final draft = _draftFor(line.materialKey);
        await _service.saveMaterial(
          itemRunId: _itemRunId,
          materialKey: line.materialKey,
          quantityReceivedToday: draft.quantityReceivedToday.trim(),
          comment: draft.comment,
        );
        final materialFiles = <File>[
          ...draft.photos.map((p) => p.file),
          ...draft.videos.map((v) => v.file),
        ];
        if (materialFiles.isNotEmpty) {
          await _service.uploadMaterialFiles(
            itemRunId: _itemRunId,
            materialKey: line.materialKey,
            files: materialFiles,
          );
        }
        draft.savedToServer = true;
      }

      // 2) Delivery-level common fields
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

      // 3) Common / vehicle media (attach to vehicle upload endpoint)
      final commonFiles = <File>[
        ..._commonPhotos.map((p) => p.file),
        ..._commonVideos.map((v) => v.file),
        ..._vehiclePhotos.map((p) => p.file),
      ];
      if (commonFiles.isNotEmpty) {
        await _service.uploadVehicleFiles(
          itemRunId: _itemRunId,
          files: commonFiles,
        );
      }

      // 4) Submit
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
              ..._filteredMaterials.map(_buildSelectCard),
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
                            color: AppTheme.navy,
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

  // ─── STEP 2: per-material media + shared fields ──────────────────────────

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
                  color: AppTheme.navy,
                ),
              ),
              const SizedBox(height: 4),
              const Text(
                'Add photo/video next to each material if needed. Scroll down for delivery photo, video, measurement and comments.',
                style: TextStyle(
                  color: AppTheme.mutedGrey,
                  fontWeight: FontWeight.w600,
                  height: 1.35,
                ),
              ),
              const SizedBox(height: 16),
              ...materials.map(_buildMaterialEvidenceCard),
              const SizedBox(height: 8),
              const Divider(height: 32),
              const Text(
                'Delivery proof (optional extras)',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                  color: AppTheme.navy,
                ),
              ),
              const SizedBox(height: 12),
              _MediaRow(
                title: 'Add photo',
                items: _commonPhotos,
                addLabel: 'Add photo',
                onAdd: () async {
                  final media = await _capturePhoto();
                  if (media == null || !mounted) return;
                  setState(() => _commonPhotos.add(media));
                },
                onRemove: (i) => setState(() => _commonPhotos.removeAt(i)),
              ),
              const SizedBox(height: 14),
              _MediaRow(
                title: 'Add video',
                items: _commonVideos,
                addLabel: 'Add video',
                maxItems: 2,
                onAdd: () async {
                  final media = await _recordVideo();
                  if (media == null || !mounted) return;
                  setState(() => _commonVideos.add(media));
                },
                onRemove: (i) => setState(() => _commonVideos.removeAt(i)),
              ),
              const SizedBox(height: 20),
              const Text(
                'Measurement (Optional)',
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
                  color: AppTheme.navy,
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
              const SizedBox(height: 20),
              const Text(
                'Comments',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                  color: AppTheme.navy,
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
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
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
                        color: AppTheme.navy,
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
          const SizedBox(height: 12),
          _MediaRow(
            title: 'Photos (optional)',
            items: draft.photos,
            addLabel: 'Photo',
            maxItems: line.effectiveMaxPhotos,
            onAdd: () async {
              if (draft.photos.length >= line.effectiveMaxPhotos) {
                _snack(
                  'Max ${line.effectiveMaxPhotos} photos for ${line.material}.',
                  error: true,
                );
                return;
              }
              final media = await _capturePhoto();
              if (media == null || !mounted) return;
              setState(() => draft.photos.add(media));
            },
            onRemove: (i) => setState(() => draft.photos.removeAt(i)),
          ),
          const SizedBox(height: 10),
          _MediaRow(
            title: 'Video (optional)',
            items: draft.videos,
            addLabel: 'Video',
            maxItems: 1,
            onAdd: () async {
              if (draft.videos.isNotEmpty) {
                _snack('Only one video per material.', error: true);
                return;
              }
              final media = await _recordVideo();
              if (media == null || !mounted) return;
              setState(() => draft.videos.add(media));
            },
            onRemove: (i) => setState(() => draft.videos.removeAt(i)),
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
      _measurementController.clear();
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
                fillColor: Colors.white,
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
            fontSize: 13,
          ),
        ),
        const SizedBox(height: 8),
        SizedBox(
          height: 80,
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
                                width: 80,
                                height: 80,
                                color: const Color(0xFF0F172A),
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
