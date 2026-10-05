import 'dart:async';
import 'app_theme.dart';
import 'dart:io';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

import 'FullScreenImage.dart';
import 'Payments.dart';
import 'models/payment_proof_item.dart';
import 'services/app_logout.dart';
import 'services/camera_permission.dart';
import 'services/client_portal_service.dart';
import 'widgets/skeleton_loader.dart';

class UploadPaymentProofScreen extends StatefulWidget {
  /// When true, loads tender + non-tender payments and lists pending rows.
  final bool showPendingPayments;

  /// When true, render only the body (no scaffold / back header) for embedding
  /// inside Payments / other tabs.
  final bool embedded;

  /// When false (e.g. Payments → Previous payment), hide upload controls and
  /// show proofs with bill association only. Upload stays available when the
  /// client opens this screen from a payment-pending task.
  final bool allowUpload;

  const UploadPaymentProofScreen({
    super.key,
    this.showPendingPayments = false,
    this.embedded = false,
    this.allowUpload = true,
  });

  @override
  State<UploadPaymentProofScreen> createState() =>
      _UploadPaymentProofScreenState();
}

class _UploadPaymentProofScreenState extends State<UploadPaymentProofScreen>
    with WidgetsBindingObserver {
  static const Color _navyStart = AppTheme.navy;
  static const Color _navyEnd = AppTheme.navySoft;
  static Color get _pageBg => AppTheme.darkBackgroundPrimary;
  static Color get _cardBorder => AppTheme.border;
  static Color get _textPrimary => AppTheme.darkTextPrimary;
  static Color get _textSecondary => AppTheme.darkTextSecondary;
  static const Color _rejectBorder = Color(0xFFDC2626);
  static const Color _rejectOverlay = Color(0x4DDC2626);
  static const Color _rejectText = Color(0xFFB91C1C);
  static const Color _rejectMuted = Color(0xFF991B1B);
  static const Duration _snapshotPollInterval = Duration(seconds: 30);

  final _portal = ClientPortalService();
  final _picker = ImagePicker();
  final _currency = NumberFormat.currency(
    locale: 'en_IN',
    symbol: '₹ ',
    decimalDigits: 0,
  );

  bool _loading = true;
  bool _uploading = false;
  bool _noProject = false;
  bool _refreshInFlight = false;
  String? _error;
  String _title = 'Upload proof';
  String _projectId = '';
  String _clientName = '';
  bool _canUpload = true;
  List<PaymentProofItem> _items = [];
  List<PaymentProofPendingTask> _pendingStageTasks = [];
  Timer? _pollTimer;
  String? _removingUrl;
  String? _apiToken;
  Map<String, String> _imageHeaders = const {};

  bool _pendingLoading = false;
  String? _pendingError;
  List<PendingPaymentRow> _pendingPayments = [];
  double _pendingTotal = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _load();
    if (widget.showPendingPayments) {
      unawaited(_loadPendingPayments());
    }
    _pollTimer = Timer.periodic(_snapshotPollInterval, (_) {
      _refreshQuietly();
    });
  }

  Future<void> _loadPendingPayments() async {
    if (!mounted) return;
    setState(() {
      _pendingLoading = true;
      _pendingError = null;
    });
    try {
      final prefs = await SharedPreferences.getInstance();
      final projectId = prefs.getString('project_id')?.trim() ?? '';
      if (projectId.isEmpty) {
        throw Exception('Project not selected.');
      }
      final snapshot = await fetchProjectPaymentsSnapshot(projectId);
      if (!mounted) return;
      setState(() {
        _pendingPayments = snapshot.pendingPaymentRows;
        _pendingTotal = snapshot.totalOutstanding;
        _pendingLoading = false;
        _pendingError = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _pendingLoading = false;
        _pendingError =
            e.toString().replaceFirst('Exception: ', '').trim();
      });
    }
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _refreshQuietly();
    }
  }

  Future<void> _load({bool showSpinner = true}) async {
    if (_refreshInFlight && !showSpinner) return;
    _refreshInFlight = true;
    if (showSpinner) {
      setState(() {
        _loading = true;
        _error = null;
        _noProject = false;
      });
    }
    try {
      final token = await _portal.currentApiToken();
      final headers = await _portal.authenticatedImageHeaders();
      final payload = await _portal.getPaymentProof();
      if (!mounted) return;
      setState(() {
        _apiToken = token;
        _imageHeaders = headers;
        _applyPayload(payload);
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      if (_handleAuthOrNoProject(e)) return;
      if (!showSpinner) return;
      setState(() {
        _loading = false;
        _error = _messageOf(e);
      });
    } finally {
      _refreshInFlight = false;
    }
  }

  Future<void> _refreshQuietly() async {
    if (!mounted || _uploading || _loading || _noProject || _removingUrl != null) {
      return;
    }
    await _load(showSpinner: false);
  }

  void _applyPayload(Map<String, dynamic> payload) {
    final section = _portal.sectionOf(payload);
    final source = section.isNotEmpty ? section : payload;
    final project = source['project'] is Map
        ? Map<String, dynamic>.from(source['project'] as Map)
        : <String, dynamic>{};

    _title = source['title']?.toString().trim().isNotEmpty == true
        ? source['title'].toString()
        : 'Upload proof';
    _projectId = project['project_id']?.toString() ?? '';
    _clientName = project['client_name']?.toString() ?? '';
    _canUpload = source['can_upload'] != false;
    _items = PaymentProofItem.listFromPayload(
      payload,
      resolveUrl: (url) => _portal.serveUrl(url, apiToken: _apiToken),
    );
    _pendingStageTasks = PaymentProofItem.pendingTasksFromPayload(payload);
    _error = null;
    _noProject = false;
  }

  bool get _uploadEnabled => widget.allowUpload && _canUpload;

  List<PaymentProofStageSection> get _gallerySections =>
      PaymentProofItem.buildGallerySections(
        items: _items,
        pendingTasks: _pendingStageTasks,
      );

  String _messageOf(Object e) =>
      e.toString().replaceFirst('Exception: ', '').trim();

  bool _handleAuthOrNoProject(Object e) {
    final isUnauthorized = e is ClientPortalApiException
        ? e.isUnauthorized
        : _messageOf(e).toLowerCase().contains('unauthorized') ||
            _messageOf(e).toLowerCase().contains('not authenticated');
    if (isUnauthorized) {
      // ignore: unawaited_futures
      AppLogout.logoutAndGoToLogin(context: context);
      return true;
    }

    final isNoProject = e is ClientPortalApiException
        ? e.isNotFound
        : _messageOf(e).toLowerCase().contains('no project');
    if (isNoProject) {
      setState(() {
        _loading = false;
        _uploading = false;
        _noProject = true;
        _error = null;
        _items = [];
      });
      return true;
    }
    return false;
  }

  Future<void> _takePhoto({int? stageTaskId}) async {
    if (_uploading || !_uploadEnabled) return;
    if (!await ensureCameraPermission(context)) return;
    if (!mounted) return;
    try {
      final picked = await _picker.pickImage(
        source: ImageSource.camera,
        maxWidth: 1920,
        maxHeight: 1920,
        imageQuality: 80,
      );
      if (picked == null) return;
      await _uploadFiles([File(picked.path)], stageTaskId: stageTaskId);
    } catch (e) {
      _showError(_messageOf(e));
    }
  }

  Future<void> _chooseFromGalleryOrFiles({int? stageTaskId}) async {
    if (_uploading || !_uploadEnabled) return;
    final choice = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: AppTheme.darkBackgroundSecondary,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: const Color(0xFFCBD5E1),
                    borderRadius: BorderRadius.circular(99),
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  'Choose payment proof',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                    color: _textPrimary,
                  ),
                ),
                const SizedBox(height: 12),
                ListTile(
                  leading: const Icon(Icons.photo_library_outlined,
                      color: _navyStart),
                  title: const Text('Gallery'),
                  subtitle: const Text('PNG or JPG screenshots'),
                  onTap: () => Navigator.pop(context, 'gallery'),
                ),
                ListTile(
                  leading:
                      const Icon(Icons.folder_open_outlined, color: _navyStart),
                  title: const Text('Files'),
                  subtitle: const Text('PNG, JPG, or PDF'),
                  onTap: () => Navigator.pop(context, 'files'),
                ),
              ],
            ),
          ),
        );
      },
    );

    if (choice == 'gallery') {
      await _pickFromGallery(stageTaskId: stageTaskId);
    } else if (choice == 'files') {
      await _pickFromFiles(stageTaskId: stageTaskId);
    }
  }

  Future<void> _pickFromGallery({int? stageTaskId}) async {
    try {
      final picked = await _picker.pickMultiImage(
        maxWidth: 1920,
        maxHeight: 1920,
        imageQuality: 80,
      );
      if (picked.isEmpty) return;
      await _uploadFiles(
        picked.map((x) => File(x.path)).toList(),
        stageTaskId: stageTaskId,
      );
    } catch (e) {
      _showError(_messageOf(e));
    }
  }

  Future<void> _pickFromFiles({int? stageTaskId}) async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: const ['png', 'jpg', 'jpeg', 'pdf'],
        allowMultiple: true,
        withData: false,
      );
      if (result == null || result.files.isEmpty) return;
      final files = result.files
          .where((f) => f.path != null && f.path!.isNotEmpty)
          .map((f) => File(f.path!))
          .toList();
      if (files.isEmpty) {
        _showError('Select at least one payment image or PDF to upload');
        return;
      }
      await _uploadFiles(files, stageTaskId: stageTaskId);
    } catch (e) {
      _showError(_messageOf(e));
    }
  }

  Future<void> _uploadFiles(List<File> files, {int? stageTaskId}) async {
    if (files.isEmpty || _uploading) return;
    setState(() {
      _uploading = true;
      _error = null;
    });
    try {
      final result = await _portal.uploadPaymentProofs(
        files,
        stageTaskId: stageTaskId,
      );
      if (!mounted) return;
      setState(() => _applyPayload(result));
      if (!PaymentProofItem.payloadHasFileRecords(result)) {
        await _load(showSpinner: false);
      }
      final count = result['saved_count'] is num
          ? (result['saved_count'] as num).toInt()
          : files.length;
      final message = result['message']?.toString().trim();
      _showSuccess(
        (message != null && message.isNotEmpty)
            ? message
            : '$count payment proof${count == 1 ? '' : 's'} uploaded successfully.',
      );
    } catch (e) {
      if (!mounted) return;
      if (_handleAuthOrNoProject(e)) return;
      if (ClientPortalService.isStalePaymentProofStageError(e)) {
        await _load(showSpinner: false);
        if (!mounted) return;
        if (_items.isNotEmpty) {
          _showSuccess('Payment proof uploaded successfully.');
        }
        return;
      }
      _showError(_messageOf(e));
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
  }

  void _showSuccess(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: const Color(0xFF16A34A),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  void _showError(String message) {
    setState(() => _error = message);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: const Color(0xFFDC2626),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  Future<void> _openItem(PaymentProofItem item) async {
    if (item.isPdf) {
      final uri = Uri.tryParse(item.url);
      if (uri == null) return;
      try {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      } catch (_) {
        _showError('Could not open PDF');
      }
      if (mounted) await _refreshQuietly();
      return;
    }

    final imageUrls = _items
        .where((e) => !e.isPdf)
        .map((e) => e.url)
        .where((e) => e.isNotEmpty)
        .toList();
    final initial = imageUrls.indexOf(item.url);
    if (!mounted) return;
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => FullScreenImage(
          item.url,
          imageUrls: imageUrls.isEmpty ? [item.url] : imageUrls,
          initialIndex: initial < 0 ? 0 : initial,
        ),
      ),
    );
    if (mounted) await _refreshQuietly();
  }

  Future<void> _removeItem(PaymentProofItem item) async {
    if (!item.canRemove || _uploading || _removingUrl != null) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Remove this proof?'),
          content: Text(
            item.isRejected
                ? 'This rejected file will be removed. You can upload a correct bill afterwards.'
                : 'This file will be removed from your payment proofs.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context, true),
              style: TextButton.styleFrom(foregroundColor: _rejectText),
              child: const Text('Remove'),
            ),
          ],
        );
      },
    );
    if (confirmed != true || !mounted) return;

    setState(() => _removingUrl = item.url);
    try {
      final result = await _portal.deletePaymentProof(
        index: item.index,
        filename: item.filename.isEmpty ? null : item.filename,
        url: item.url,
      );
      if (!mounted) return;
      if (result['section'] is Map ||
          PaymentProofItem.payloadHasFileRecords(result)) {
        setState(() => _applyPayload(result));
      } else {
        setState(() {
          _items = _items.where((e) => e.url != item.url).toList();
        });
        await _load(showSpinner: false);
      }
    } catch (e) {
      if (!mounted) return;
      if (_handleAuthOrNoProject(e)) return;
      _showError(_messageOf(e));
      await _load(showSpinner: false);
    } finally {
      if (mounted) setState(() => _removingUrl = null);
    }
  }

  String get _subtitle {
    if (_projectId.isEmpty && _clientName.isEmpty) return '';
    if (_projectId.isEmpty) return _clientName;
    if (_clientName.isEmpty) return 'Project: $_projectId';
    return 'Project: $_projectId — $_clientName';
  }

  @override
  Widget build(BuildContext context) {
    if (widget.embedded) {
      return ColoredBox(
        color: _pageBg,
        child: SizedBox.expand(child: _buildBody()),
      );
    }
    return Scaffold(
      backgroundColor: _pageBg,
      body: Column(
        children: [
          _buildHeader(),
          Expanded(child: _buildBody()),
        ],
      ),
    );
  }

  Widget _buildHeader() {
    return Container(
      width: double.infinity,
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [_navyStart, _navyEnd],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(4, 4, 12, 18),
          child: Row(
            children: [
              IconButton(
                onPressed: () => Navigator.pop(context),
                icon: const Icon(Icons.arrow_back_rounded, color: Colors.white),
              ),
              const SizedBox(width: 4),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _title,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    if (_subtitle.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(
                        _subtitle,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.88),
                          fontSize: 12.5,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildBody() {
    if (_loading) {
      return const SkeletonListLoader(cardCount: 4);
    }
    if (_noProject) {
      return _NoProjectBlockedState();
    }

    return RefreshIndicator(
      color: _navyStart,
      onRefresh: _uploading
          ? () async {}
          : () async {
              await Future.wait([
                _refreshQuietly(),
                if (widget.showPendingPayments) _loadPendingPayments(),
              ]);
            },
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 28),
        children: [
          if (widget.showPendingPayments) ...[
            _buildPendingPaymentsSection(),
            const SizedBox(height: 22),
          ],
          if (widget.allowUpload) ...[
            Text(
              'Upload screenshots or photos of your payment (UPI, bank transfer, cheque, or receipt). You can add more than one file.',
              style: TextStyle(
                color: _textSecondary,
                fontSize: 13.5,
                height: 1.4,
              ),
            ),
            const SizedBox(height: 14),
          ] else ...[
            Text(
              'Previous payment screenshots and the bills they were applied to.',
              style: TextStyle(
                color: _textSecondary,
                fontSize: 13.5,
                height: 1.4,
              ),
            ),
            const SizedBox(height: 14),
          ],
          if (_error != null) ...[
            _ErrorBanner(message: _error!),
            const SizedBox(height: 14),
          ],
          if (widget.allowUpload) ...[
            _UploadZone(
              enabled: _uploadEnabled && !_uploading,
              uploading: _uploading,
              onTakePhoto: _takePhoto,
              onChooseFiles: _chooseFromGalleryOrFiles,
            ),
            const SizedBox(height: 22),
          ],
          if (_items.isEmpty) ...[
            Text(
              widget.allowUpload ? 'Uploaded proofs' : 'Previous payment',
              style: TextStyle(
                color: _textPrimary,
                fontSize: 15.5,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 12),
            const _EmptyProofsState(),
          ] else ...[
            ..._buildProofSections(),
          ],
        ],
      ),
    );
  }

  /// Gallery-style stage cards (like Timeline Gallery). Flat grid only when
  /// there are no pending stage tasks and no per-proof stage/bill linkage.
  /// From Payments (view-only), keep a flat grid so each screenshot shows its
  /// bill association inline.
  List<Widget> _buildProofSections() {
    if (!widget.allowUpload) {
      return [
        Text(
          'Previous payment',
          style: TextStyle(
            color: _textPrimary,
            fontSize: 15.5,
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          'Each screenshot shows the NT / non-NT bills it was applied to.',
          style: TextStyle(
            color: _textSecondary,
            fontSize: 12.5,
            height: 1.35,
          ),
        ),
        const SizedBox(height: 12),
        _ProofGrid(
          items: _items,
          imageHeaders: _imageHeaders,
          removingUrl: null,
          onTap: _openItem,
          onRemove: (_) async {},
          allowRemove: false,
        ),
      ];
    }

    final useGallery = _pendingStageTasks.isNotEmpty ||
        _items.any((e) => e.billStages.isNotEmpty || e.stageTaskId != null);
    if (!useGallery) {
      return [
        Text(
          'Uploaded proofs',
          style: TextStyle(
            color: _textPrimary,
            fontSize: 15.5,
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 12),
        _ProofGrid(
          items: _items,
          imageHeaders: _imageHeaders,
          removingUrl: _removingUrl,
          onTap: _openItem,
          onRemove: _removeItem,
        ),
      ];
    }

    final sections = _gallerySections;
    final widgets = <Widget>[
      Text(
        'Proofs by stage',
        style: TextStyle(
          color: _textPrimary,
          fontSize: 15.5,
          fontWeight: FontWeight.w800,
        ),
      ),
      const SizedBox(height: 4),
      Text(
        'Open a stage to view or upload screenshots — same layout as the project gallery.',
        style: TextStyle(
          color: _textSecondary,
          fontSize: 12.5,
          height: 1.35,
        ),
      ),
      const SizedBox(height: 14),
    ];

    for (var i = 0; i < sections.length; i++) {
      final section = sections[i];
      widgets.add(
        _ProofStageSectionCard(
          section: section,
          imageHeaders: _imageHeaders,
          onOpen: () => _openStageSection(section),
        ),
      );
      if (i != sections.length - 1) {
        widgets.add(const SizedBox(height: 14));
      }
    }
    return widgets;
  }

  Future<void> _openStageSection(PaymentProofStageSection section) async {
    final result = await Navigator.of(context).push<Map<String, dynamic>?>(
      MaterialPageRoute(
        builder: (_) => _ProofStageDetailScreen(
          sectionKey: section.key,
          title: section.label,
          subtitle: section.subtitle.isNotEmpty
              ? section.subtitle
              : (section.isTask
                  ? 'Upload payment proof for this stage'
                  : section.isNt
                      ? 'NT bill stage'
                      : section.isAwaiting
                          ? 'Not linked to a stage yet'
                          : 'Non-NT bill stage'),
          kind: section.kind,
          stageTaskId: section.stageTaskId,
          initialItems: List<PaymentProofItem>.from(section.items),
          allItems: _items,
          imageHeaders: _imageHeaders,
          canUpload: _uploadEnabled && !section.isAwaiting,
          portal: _portal,
          onOpenItem: _openItem,
          proofsSectionTitle:
              widget.allowUpload ? 'Screenshots' : 'Previous payment',
        ),
      ),
    );
    if (!mounted) return;
    if (result != null) {
      setState(() => _applyPayload(result));
    } else {
      await _refreshQuietly();
    }
  }

  Widget _buildPendingPaymentsSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                'Pending payments',
                style: TextStyle(
                  color: _textPrimary,
                  fontSize: 15.5,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
            if (!_pendingLoading && _pendingTotal > 0)
              Text(
                _currency.format(_pendingTotal),
                style: const TextStyle(
                  color: Color(0xFFDC2626),
                  fontSize: 14.5,
                  fontWeight: FontWeight.w800,
                ),
              ),
          ],
        ),
        const SizedBox(height: 6),
        Text(
          'Clear these dues by uploading payment proof below.',
          style: TextStyle(
            color: _textSecondary,
            fontSize: 13,
            height: 1.35,
          ),
        ),
        const SizedBox(height: 12),
        if (_pendingLoading)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 18),
            child: Center(
              child: SizedBox(
                width: 22,
                height: 22,
                child: CircularProgressIndicator(strokeWidth: 2.4),
              ),
            ),
          )
        else if (_pendingError != null)
          _ErrorBanner(message: _pendingError!)
        else if (_pendingPayments.isEmpty)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: AppTheme.darkBackgroundSecondary,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: _cardBorder),
            ),
            child: Text(
              'No pending tender or non-tender payments.',
              style: TextStyle(
                color: _textSecondary,
                fontSize: 13.5,
                fontWeight: FontWeight.w600,
              ),
            ),
          )
        else
          Container(
            width: double.infinity,
            decoration: BoxDecoration(
              color: AppTheme.darkBackgroundSecondary,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: _cardBorder),
            ),
            child: Column(
              children: [
                for (var i = 0; i < _pendingPayments.length; i++) ...[
                  if (i > 0) Divider(height: 1, color: AppTheme.border),
                  _PendingPaymentTile(
                    row: _pendingPayments[i],
                    amountText: _pendingPayments[i].amount > 0
                        ? _currency.format(_pendingPayments[i].amount)
                        : '—',
                  ),
                ],
              ],
            ),
          ),
      ],
    );
  }
}

class _PendingPaymentTile extends StatelessWidget {
  final PendingPaymentRow row;
  final String amountText;

  const _PendingPaymentTile({
    required this.row,
    required this.amountText,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  row.name,
                  style: TextStyle(
                    color: _UploadPaymentProofScreenState._textPrimary,
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  row.isTender ? 'Tender' : 'Non-tender',
                  style: TextStyle(
                    color: _UploadPaymentProofScreenState._textSecondary,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Text(
            amountText,
            style: TextStyle(
              color: _UploadPaymentProofScreenState._textPrimary,
              fontSize: 14,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }
}

class _ProofGrid extends StatelessWidget {
  final List<PaymentProofItem> items;
  final Map<String, String> imageHeaders;
  final String? removingUrl;
  final Future<void> Function(PaymentProofItem item) onTap;
  final Future<void> Function(PaymentProofItem item) onRemove;
  final bool allowRemove;

  const _ProofGrid({
    required this.items,
    required this.imageHeaders,
    required this.removingUrl,
    required this.onTap,
    required this.onRemove,
    this.allowRemove = true,
  });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        const gap = 12.0;
        final width = (constraints.maxWidth - gap) / 2;
        return Wrap(
          spacing: gap,
          runSpacing: gap,
          children: [
            for (final item in items)
              SizedBox(
                width: width,
                child: _ProofCard(
                  item: item,
                  imageHeaders: imageHeaders,
                  removing: removingUrl == item.url,
                  onTap: () => onTap(item),
                  onRemove: allowRemove && item.canRemove
                      ? () => onRemove(item)
                      : null,
                ),
              ),
          ],
        );
      },
    );
  }
}

class _ProofStageSectionCard extends StatelessWidget {
  final PaymentProofStageSection section;
  final Map<String, String> imageHeaders;
  final VoidCallback onOpen;

  const _ProofStageSectionCard({
    required this.section,
    required this.imageHeaders,
    required this.onOpen,
  });

  Color get _accent {
    if (section.isTask) return const Color(0xFF1D4ED8);
    if (section.isNt) return const Color(0xFF0F766E);
    if (section.isAwaiting) return const Color(0xFF64748B);
    return const Color(0xFF7C3AED);
  }

  String get _kindLabel {
    if (section.isTask) return 'Stage';
    if (section.isNt) return 'NT';
    if (section.isAwaiting) return 'Other';
    return 'Non-NT';
  }

  @override
  Widget build(BuildContext context) {
    final previews = section.items.take(4).toList();
    return Material(
      color: AppTheme.darkBackgroundSecondary,
      borderRadius: BorderRadius.circular(20),
      child: InkWell(
        onTap: onOpen,
        borderRadius: BorderRadius.circular(20),
        child: Ink(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            border:
                Border.all(color: _UploadPaymentProofScreenState._cardBorder),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    height: 44,
                    width: 44,
                    decoration: BoxDecoration(
                      color: _accent.withValues(alpha: 0.14),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Icon(
                      section.isAwaiting
                          ? Icons.photo_library_outlined
                          : Icons.flag_outlined,
                      color: _accent,
                      size: 22,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          section.label,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: _UploadPaymentProofScreenState._textPrimary,
                            fontWeight: FontWeight.w800,
                            fontSize: 15.5,
                          ),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          section.items.isEmpty
                              ? 'No screenshots yet'
                              : '${section.items.length} screenshot${section.items.length == 1 ? '' : 's'}',
                          style: TextStyle(
                            color:
                                _UploadPaymentProofScreenState._textSecondary,
                            fontWeight: FontWeight.w600,
                            fontSize: 12.5,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                    decoration: BoxDecoration(
                      color: _accent.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Text(
                      _kindLabel,
                      style: TextStyle(
                        color: _accent,
                        fontSize: 11,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  const SizedBox(width: 4),
                  Icon(
                    Icons.chevron_right_rounded,
                    color: _UploadPaymentProofScreenState._textSecondary,
                  ),
                ],
              ),
              const SizedBox(height: 14),
              if (previews.isEmpty)
                Container(
                  height: 88,
                  width: double.infinity,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: AppTheme.darkBackgroundPrimaryLight,
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Text(
                    'Tap to upload for this stage',
                    style: TextStyle(
                      color: _UploadPaymentProofScreenState._textSecondary,
                      fontWeight: FontWeight.w600,
                      fontSize: 13,
                    ),
                  ),
                )
              else
                SizedBox(
                  height: 72,
                  child: Row(
                    children: [
                      for (var i = 0; i < 4; i++) ...[
                        if (i > 0) const SizedBox(width: 8),
                        Expanded(
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(12),
                            child: i < previews.length
                                ? (previews[i].isPdf
                                    ? Container(
                                        color: AppTheme
                                            .darkBackgroundPrimaryLight,
                                        child: const Icon(
                                          Icons.picture_as_pdf_rounded,
                                          color: Color(0xFFDC2626),
                                        ),
                                      )
                                    : CachedNetworkImage(
                                        imageUrl: previews[i].url,
                                        httpHeaders: imageHeaders,
                                        fit: BoxFit.cover,
                                        height: 72,
                                        placeholder: (_, __) =>
                                            const SkeletonImage(radius: 0),
                                        errorWidget: (_, __, ___) =>
                                            const ColoredBox(
                                          color: Color(0xFF1F2937),
                                          child: Icon(
                                            Icons.broken_image_outlined,
                                            color: Color(0xFF94A3B8),
                                          ),
                                        ),
                                      ))
                                : ColoredBox(
                                    color: AppTheme.darkBackgroundPrimaryLight,
                                  ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ProofStageDetailScreen extends StatefulWidget {
  final String sectionKey;
  final String title;
  final String subtitle;
  final String kind;
  final int? stageTaskId;
  final List<PaymentProofItem> initialItems;
  final List<PaymentProofItem> allItems;
  final Map<String, String> imageHeaders;
  final bool canUpload;
  final String proofsSectionTitle;
  final ClientPortalService portal;
  final Future<void> Function(PaymentProofItem item) onOpenItem;

  const _ProofStageDetailScreen({
    required this.sectionKey,
    required this.title,
    required this.subtitle,
    required this.kind,
    required this.stageTaskId,
    required this.initialItems,
    required this.allItems,
    required this.imageHeaders,
    required this.canUpload,
    this.proofsSectionTitle = 'Screenshots',
    required this.portal,
    required this.onOpenItem,
  });

  @override
  State<_ProofStageDetailScreen> createState() =>
      _ProofStageDetailScreenState();
}

class _ProofStageDetailScreenState extends State<_ProofStageDetailScreen> {
  late List<PaymentProofItem> _items = List.of(widget.initialItems);
  late List<PaymentProofItem> _allItems = List.of(widget.allItems);
  Map<String, dynamic>? _lastPayload;
  bool _uploading = false;
  String? _removingUrl;
  final _picker = ImagePicker();

  Future<void> _refresh() async {
    try {
      final payload = await widget.portal.getPaymentProof();
      if (!mounted) return;
      _apply(payload);
    } catch (_) {}
  }

  void _apply(Map<String, dynamic> payload) {
    final tokenItems = PaymentProofItem.listFromPayload(payload);
    final tasks = PaymentProofItem.pendingTasksFromPayload(payload);
    final sections = PaymentProofItem.buildGallerySections(
      items: tokenItems,
      pendingTasks: tasks,
    );
    PaymentProofStageSection? match;
    for (final section in sections) {
      if (section.key == widget.sectionKey) {
        match = section;
        break;
      }
    }
    setState(() {
      _lastPayload = payload;
      _allItems = tokenItems;
      _items = match?.items ?? const [];
    });
  }

  Future<void> _upload(List<File> files) async {
    if (files.isEmpty || _uploading) return;
    setState(() => _uploading = true);
    try {
      final result = await widget.portal.uploadPaymentProofs(
        files,
        stageTaskId: widget.stageTaskId,
      );
      if (!mounted) return;
      _apply(result);
      if (!PaymentProofItem.payloadHasFileRecords(result)) {
        await _refresh();
      }
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Payment proof uploaded successfully.'),
          backgroundColor: Color(0xFF16A34A),
          behavior: SnackBarBehavior.floating,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('$e'.replaceFirst('Exception: ', '')),
          backgroundColor: const Color(0xFFDC2626),
          behavior: SnackBarBehavior.floating,
        ),
      );
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
  }

  Future<void> _takePhoto() async {
    if (!widget.canUpload || _uploading) return;
    if (!await ensureCameraPermission(context)) return;
    if (!mounted) return;
    final picked = await _picker.pickImage(
      source: ImageSource.camera,
      maxWidth: 1920,
      maxHeight: 1920,
      imageQuality: 80,
    );
    if (picked == null) return;
    await _upload([File(picked.path)]);
  }

  Future<void> _chooseFiles() async {
    if (!widget.canUpload || _uploading) return;
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['png', 'jpg', 'jpeg', 'pdf'],
      allowMultiple: true,
      withData: false,
    );
    if (result == null || result.files.isEmpty) return;
    final files = result.files
        .where((f) => f.path != null && f.path!.isNotEmpty)
        .map((f) => File(f.path!))
        .toList();
    if (files.isEmpty) return;
    await _upload(files);
  }

  Future<void> _remove(PaymentProofItem item) async {
    if (!item.canRemove || _uploading || _removingUrl != null) return;
    setState(() => _removingUrl = item.url);
    try {
      final result = await widget.portal.deletePaymentProof(
        index: item.index,
        filename: item.filename.isEmpty ? null : item.filename,
        url: item.url,
      );
      if (!mounted) return;
      _apply(result);
      if (!PaymentProofItem.payloadHasFileRecords(result)) {
        await _refresh();
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('$e'.replaceFirst('Exception: ', '')),
          backgroundColor: const Color(0xFFDC2626),
          behavior: SnackBarBehavior.floating,
        ),
      );
    } finally {
      if (mounted) setState(() => _removingUrl = null);
    }
  }

  Future<void> _open(PaymentProofItem item) async {
    if (item.isPdf) {
      await widget.onOpenItem(item);
      return;
    }
    final imageUrls = _allItems
        .where((e) => !e.isPdf)
        .map((e) => e.url)
        .where((e) => e.isNotEmpty)
        .toList();
    final initial = imageUrls.indexOf(item.url);
    if (!mounted) return;
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => FullScreenImage(
          item.url,
          imageUrls: imageUrls.isEmpty ? [item.url] : imageUrls,
          initialIndex: initial < 0 ? 0 : initial,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _UploadPaymentProofScreenState._pageBg,
      appBar: AppBar(
        backgroundColor: _UploadPaymentProofScreenState._navyStart,
        foregroundColor: Colors.white,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              widget.title,
              style: const TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w800,
              ),
            ),
            Text(
              widget.subtitle,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w500,
                color: Colors.white.withValues(alpha: 0.85),
              ),
            ),
          ],
        ),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded),
          onPressed: () => Navigator.pop(context, _lastPayload),
        ),
      ),
      body: RefreshIndicator(
        color: _UploadPaymentProofScreenState._navyStart,
        onRefresh: _refresh,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 28),
          children: [
            if (widget.canUpload) ...[
              _UploadZone(
                enabled: widget.canUpload && !_uploading,
                uploading: _uploading,
                onTakePhoto: _takePhoto,
                onChooseFiles: _chooseFiles,
              ),
              const SizedBox(height: 18),
            ],
            Text(
              widget.proofsSectionTitle,
              style: TextStyle(
                color: _UploadPaymentProofScreenState._textPrimary,
                fontSize: 15.5,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 12),
            if (_items.isEmpty)
              const _EmptyProofsState()
            else
              _ProofGrid(
                items: _items,
                imageHeaders: widget.imageHeaders,
                removingUrl: widget.canUpload ? _removingUrl : null,
                onTap: _open,
                onRemove: _remove,
                allowRemove: widget.canUpload,
              ),
          ],
        ),
      ),
    );
  }
}

class _UploadZone extends StatelessWidget {
  final bool enabled;
  final bool uploading;
  final VoidCallback onTakePhoto;
  final VoidCallback onChooseFiles;

  const _UploadZone({
    required this.enabled,
    required this.uploading,
    required this.onTakePhoto,
    required this.onChooseFiles,
  });

  @override
  Widget build(BuildContext context) {
    return Opacity(
      opacity: enabled || uploading ? 1 : 0.55,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: AppTheme.darkBackgroundSecondary,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: _UploadPaymentProofScreenState._cardBorder),
        ),
        child: Column(
          children: [
            if (uploading) ...[
              LinearProgressIndicator(
                minHeight: 4,
                color: _UploadPaymentProofScreenState._navyEnd,
                backgroundColor: AppTheme.darkBackgroundPrimaryLight,
              ),
              const SizedBox(height: 12),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                  const SizedBox(width: 10),
                  Text(
                    'Uploading…',
                    style: TextStyle(
                      fontWeight: FontWeight.w700,
                      color: _UploadPaymentProofScreenState._textPrimary,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
            ],
            Row(
              children: [
                Expanded(
                  child: _PrimaryActionButton(
                    icon: Icons.photo_camera_outlined,
                    label: 'Take photo',
                    onTap: enabled ? onTakePhoto : null,
                    filled: true,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _PrimaryActionButton(
                    icon: Icons.photo_library_outlined,
                    label: 'Gallery / files',
                    onTap: enabled ? onChooseFiles : null,
                    filled: false,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Text(
              'PNG, JPG, or PDF · Multiple files allowed',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 12,
                color: _UploadPaymentProofScreenState._textSecondary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PrimaryActionButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback? onTap;
  final bool filled;

  const _PrimaryActionButton({
    required this.icon,
    required this.label,
    required this.onTap,
    required this.filled,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Ink(
          height: 52,
          decoration: BoxDecoration(
            gradient: filled
                ? const LinearGradient(
                    colors: [
                      _UploadPaymentProofScreenState._navyStart,
                      _UploadPaymentProofScreenState._navyEnd,
                    ],
                  )
                : null,
            color: filled ? null : AppTheme.darkBackgroundPrimaryLight,
            borderRadius: BorderRadius.circular(14),
            border: filled
                ? null
                : Border.all(color: AppTheme.border),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                icon,
                size: 20,
                color: filled ? Colors.white : AppTheme.darkTextPrimary,
              ),
              const SizedBox(width: 8),
              Flexible(
                child: Text(
                  label,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: filled ? Colors.white : AppTheme.darkTextPrimary,
                    fontWeight: FontWeight.w800,
                    fontSize: 13,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ProofCard extends StatelessWidget {
  final PaymentProofItem item;
  final VoidCallback onTap;
  final VoidCallback? onRemove;
  final bool removing;
  final Map<String, String> imageHeaders;

  const _ProofCard({
    required this.item,
    required this.onTap,
    this.onRemove,
    this.removing = false,
    this.imageHeaders = const {},
  });

  @override
  Widget build(BuildContext context) {
    final rejected = item.isRejected;
    final rejectText = item.rejectionDisplayText;
    return Material(
      color: rejected ? const Color(0xFF3F1D24) : AppTheme.darkBackgroundSecondary,
      borderRadius: BorderRadius.circular(16),
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(16),
            child: Ink(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: rejected
                      ? _UploadPaymentProofScreenState._rejectBorder
                      : _UploadPaymentProofScreenState._cardBorder,
                  width: rejected ? 1.8 : 1,
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  AspectRatio(
                    aspectRatio: 1,
                    child: ClipRRect(
                      borderRadius: const BorderRadius.vertical(
                        top: Radius.circular(14.5),
                      ),
                      child: Stack(
                        fit: StackFit.expand,
                        children: [
                          item.isPdf
                              ? Container(
                                  color: AppTheme.darkBackgroundPrimaryLight,
                                  child: const Column(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      Icon(Icons.picture_as_pdf_rounded,
                                          size: 42, color: Color(0xFFDC2626)),
                                      SizedBox(height: 8),
                                      _PdfTag(),
                                    ],
                                  ),
                                )
                              : CachedNetworkImage(
                                  imageUrl: item.url,
                                  httpHeaders: imageHeaders,
                                  fit: BoxFit.cover,
                                  placeholder: (context, url) =>
                                      const SkeletonImage(radius: 0),
                                  errorWidget: (context, url, error) =>
                                      const Center(
                                    child: Icon(Icons.broken_image_outlined,
                                        color: Color(0xFF94A3B8)),
                                  ),
                                ),
                          if (rejected)
                            const ColoredBox(
                              color:
                                  _UploadPaymentProofScreenState._rejectOverlay,
                            ),
                          if (item.showNotABillBadge)
                            Positioned(
                              left: 8,
                              top: 8,
                              right: 44,
                              child: Align(
                                alignment: Alignment.topLeft,
                                child: Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 8,
                                    vertical: 4,
                                  ),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFFDC2626),
                                    borderRadius: BorderRadius.circular(99),
                                  ),
                                  child: Text(
                                    item.notABillBadgeText,
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 11,
                                      fontWeight: FontWeight.w800,
                                      height: 1.2,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                  Padding(
                    padding: EdgeInsets.fromLTRB(
                      10,
                      10,
                      10,
                      rejectText.isNotEmpty ||
                              item.clearedBillsText.isNotEmpty ||
                              item.allocationHeading.isNotEmpty
                          ? 6
                          : 12,
                    ),
                    child: Text(
                      item.displayAmount,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: rejected
                            ? _UploadPaymentProofScreenState._rejectMuted
                            : _UploadPaymentProofScreenState._textPrimary,
                        fontWeight: FontWeight.w800,
                        fontSize: 15,
                      ),
                    ),
                  ),
                  if (item.allocationHeading.isNotEmpty)
                    Padding(
                      padding: EdgeInsets.fromLTRB(
                        10,
                        0,
                        10,
                        item.clearedBillsText.isNotEmpty ||
                                rejectText.isNotEmpty
                            ? 4
                            : 12,
                      ),
                      child: Text(
                        item.allocationHeading,
                        textAlign: TextAlign.left,
                        style: TextStyle(
                          color: rejected
                              ? _UploadPaymentProofScreenState._rejectMuted
                              : _UploadPaymentProofScreenState._textSecondary,
                          fontWeight: FontWeight.w700,
                          fontSize: 11.5,
                          height: 1.3,
                        ),
                      ),
                    ),
                  if (item.clearedBillsText.isNotEmpty)
                    Padding(
                      padding: EdgeInsets.fromLTRB(
                        10,
                        0,
                        10,
                        rejectText.isNotEmpty ? 6 : 12,
                      ),
                      child: Text(
                        item.clearedBillsText,
                        textAlign: TextAlign.left,
                        style: TextStyle(
                          color: rejected
                              ? _UploadPaymentProofScreenState._rejectMuted
                              : const Color(0xFF94A3B8),
                          fontWeight: FontWeight.w700,
                          fontSize: 12,
                          height: 1.35,
                        ),
                      ),
                    ),
                  if (rejectText.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(10, 0, 10, 12),
                      child: Text(
                        rejectText,
                        textAlign: TextAlign.left,
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: _UploadPaymentProofScreenState._rejectText,
                          fontWeight: FontWeight.w700,
                          fontSize: 12,
                          height: 1.35,
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
          if (onRemove != null)
            Positioned(
              top: 4,
              right: 4,
              child: Material(
                color: AppTheme.darkBackgroundSecondary,
                elevation: 3,
                shape: const CircleBorder(),
                child: InkWell(
                  customBorder: const CircleBorder(),
                  onTap: removing ? null : onRemove,
                  child: SizedBox(
                    width: 32,
                    height: 32,
                    child: Center(
                      child: removing
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(
                              Icons.close_rounded,
                              size: 20,
                              color: Color(0xFFDC2626),
                            ),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _PdfTag extends StatelessWidget {
  const _PdfTag();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: const Color(0xFFFEE2E2),
        borderRadius: BorderRadius.circular(99),
      ),
      child: const Text(
        'PDF',
        style: TextStyle(
          color: Color(0xFFB91C1C),
          fontSize: 11,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }
}

class _EmptyProofsState extends StatelessWidget {
  const _EmptyProofsState();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 36, horizontal: 18),
      decoration: BoxDecoration(
        color: AppTheme.darkBackgroundSecondary,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _UploadPaymentProofScreenState._cardBorder),
      ),
      child: Column(
        children: [
          const Icon(Icons.receipt_long_outlined,
              size: 56, color: Color(0xFF94A3B8)),
          const SizedBox(height: 12),
          Text(
            'No payment proof uploaded yet',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: _UploadPaymentProofScreenState._textSecondary,
              fontWeight: FontWeight.w700,
              fontSize: 14,
            ),
          ),
        ],
      ),
    );
  }
}

class _NoProjectBlockedState extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.home_work_outlined,
                size: 72, color: Color(0xFF94A3B8)),
            const SizedBox(height: 16),
            Text(
              'No project linked to this client',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w800,
                color: _UploadPaymentProofScreenState._textPrimary,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Your account is not linked to a project yet. Please contact buildAhome support.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 14,
                height: 1.4,
                color: _UploadPaymentProofScreenState._textSecondary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ErrorBanner extends StatelessWidget {
  final String message;

  const _ErrorBanner({required this.message});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFFEF2F2),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFFECACA)),
      ),
      child: Text(
        message,
        style: const TextStyle(
          color: Color(0xFFB91C1C),
          fontWeight: FontWeight.w600,
          fontSize: 13,
        ),
      ),
    );
  }
}
