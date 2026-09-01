import 'dart:io';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:url_launcher/url_launcher.dart';

import 'FullScreenImage.dart';
import 'Skin2/loginPage.dart';
import 'services/client_portal_service.dart';
import 'widgets/skeleton_loader.dart';

class UploadPaymentProofScreen extends StatefulWidget {
  const UploadPaymentProofScreen({super.key});

  @override
  State<UploadPaymentProofScreen> createState() =>
      _UploadPaymentProofScreenState();
}

class _UploadPaymentProofScreenState extends State<UploadPaymentProofScreen> {
  static const Color _navyStart = Color(0xFF224A7A);
  static const Color _navyEnd = Color(0xFF2B66AC);
  static const Color _pageBg = Color(0xFFEEF2F6);
  static const Color _cardBorder = Color(0xFFE2E8F0);
  static const Color _textPrimary = Color(0xFF334155);
  static const Color _textSecondary = Color(0xFF475569);

  final _portal = ClientPortalService();
  final _picker = ImagePicker();

  bool _loading = true;
  bool _uploading = false;
  bool _noProject = false;
  String? _error;
  String _title = 'Upload payment proof';
  String _projectId = '';
  String _clientName = '';
  bool _canUpload = true;
  List<_PaymentProofItem> _items = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
      _noProject = false;
    });
    try {
      final payload = await _portal.getPaymentProof();
      if (!mounted) return;
      _applySection(payload);
      setState(() => _loading = false);
    } catch (e) {
      if (!mounted) return;
      if (_handleAuthOrNoProject(e)) return;
      setState(() {
        _loading = false;
        _error = _messageOf(e);
      });
    }
  }

  void _applySection(Map<String, dynamic> payload) {
    final section = _portal.sectionOf(payload);
    final project = section['project'] is Map
        ? Map<String, dynamic>.from(section['project'] as Map)
        : <String, dynamic>{};

    _title = section['title']?.toString().trim().isNotEmpty == true
        ? section['title'].toString()
        : 'Upload payment proof';
    _projectId = project['project_id']?.toString() ?? '';
    _clientName = project['client_name']?.toString() ?? '';
    _canUpload = section['can_upload'] != false;
    _items = _parseItems(section);
    _error = null;
    _noProject = false;
  }

  List<_PaymentProofItem> _parseItems(Map<String, dynamic> section) {
    final rawItems = section['payment_proof_items'];
    if (rawItems is List && rawItems.isNotEmpty) {
      return rawItems.whereType<Map>().map((raw) {
        final map = Map<String, dynamic>.from(raw);
        final url = _portal.serveUrl(map['url']?.toString() ?? '');
        final isPdf = map['is_pdf'] == true || _looksLikePdf(url);
        return _PaymentProofItem(
          url: url,
          label: map['label']?.toString().trim().isNotEmpty == true
              ? map['label'].toString()
              : (isPdf ? 'Payment proof' : 'Payment proof'),
          isPdf: isPdf,
        );
      }).where((item) => item.url.isNotEmpty).toList();
    }

    final urls = section['payment_screenshot_urls'];
    if (urls is! List) return [];
    final parsed = urls
        .map((e) => e?.toString() ?? '')
        .where((e) => e.trim().isNotEmpty)
        .map(_portal.serveUrl)
        .toList();
    return [
      for (var i = 0; i < parsed.length; i++)
        _PaymentProofItem(
          url: parsed[i],
          label: parsed.length == 1
              ? 'Payment proof'
              : 'Payment proof ${i + 1}',
          isPdf: _looksLikePdf(parsed[i]),
        ),
    ];
  }

  bool _looksLikePdf(String url) {
    final lower = url.toLowerCase();
    return lower.contains('.pdf') || lower.contains('application/pdf');
  }

  String _messageOf(Object e) =>
      e.toString().replaceFirst('Exception: ', '').trim();

  bool _handleAuthOrNoProject(Object e) {
    final isUnauthorized = e is ClientPortalApiException
        ? e.isUnauthorized
        : _messageOf(e).toLowerCase().contains('unauthorized') ||
            _messageOf(e).toLowerCase().contains('not authenticated');
    if (isUnauthorized) {
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => LoginScreenNew()),
        (route) => false,
      );
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

  Future<void> _takePhoto() async {
    if (_uploading || !_canUpload) return;
    try {
      final picked = await _picker.pickImage(
        source: ImageSource.camera,
        maxWidth: 1920,
        maxHeight: 1920,
        imageQuality: 80,
      );
      if (picked == null) return;
      await _uploadFiles([File(picked.path)]);
    } catch (e) {
      _showError(_messageOf(e));
    }
  }

  Future<void> _chooseFromGalleryOrFiles() async {
    if (_uploading || !_canUpload) return;
    final choice = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: Colors.white,
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
                const Text(
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
      await _pickFromGallery();
    } else if (choice == 'files') {
      await _pickFromFiles();
    }
  }

  Future<void> _pickFromGallery() async {
    try {
      final picked = await _picker.pickMultiImage(
        maxWidth: 1920,
        maxHeight: 1920,
        imageQuality: 80,
      );
      if (picked.isEmpty) return;
      await _uploadFiles(picked.map((x) => File(x.path)).toList());
    } catch (e) {
      _showError(_messageOf(e));
    }
  }

  Future<void> _pickFromFiles() async {
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
      await _uploadFiles(files);
    } catch (e) {
      _showError(_messageOf(e));
    }
  }

  Future<void> _uploadFiles(List<File> files) async {
    if (files.isEmpty || _uploading) return;
    setState(() {
      _uploading = true;
      _error = null;
    });
    try {
      final result = await _portal.uploadPaymentProofs(files);
      if (!mounted) return;
      if (result['section'] is Map) {
        _applySection(result);
      } else {
        await _load();
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
        await _load();
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

  Future<void> _openItem(_PaymentProofItem item) async {
    if (item.isPdf) {
      final uri = Uri.tryParse(item.url);
      if (uri == null) return;
      try {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      } catch (_) {
        _showError('Could not open PDF');
      }
      return;
    }

    final imageUrls = _items
        .where((e) => !e.isPdf)
        .map((e) => e.url)
        .where((e) => e.isNotEmpty)
        .toList();
    final initial = imageUrls.indexOf(item.url);
    if (!mounted) return;
    Navigator.push(
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

  String get _subtitle {
    if (_projectId.isEmpty && _clientName.isEmpty) return '';
    if (_projectId.isEmpty) return _clientName;
    if (_clientName.isEmpty) return 'Project: $_projectId';
    return 'Project: $_projectId — $_clientName';
  }

  @override
  Widget build(BuildContext context) {
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
      onRefresh: _uploading ? () async {} : _load,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 28),
        children: [
          const Text(
            'Upload screenshots or photos of your payment (UPI, bank transfer, cheque, or receipt). You can add more than one file.',
            style: TextStyle(
              color: _textSecondary,
              fontSize: 13.5,
              height: 1.4,
            ),
          ),
          const SizedBox(height: 14),
          if (_error != null) ...[
            _ErrorBanner(message: _error!),
            const SizedBox(height: 14),
          ],
          _UploadZone(
            enabled: _canUpload && !_uploading,
            uploading: _uploading,
            onTakePhoto: _takePhoto,
            onChooseFiles: _chooseFromGalleryOrFiles,
          ),
          const SizedBox(height: 22),
          const Text(
            'Uploaded proofs',
            style: TextStyle(
              color: _textPrimary,
              fontSize: 15.5,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 12),
          if (_items.isEmpty)
            const _EmptyProofsState()
          else
            GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: _items.length,
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 2,
                crossAxisSpacing: 12,
                mainAxisSpacing: 12,
                childAspectRatio: 0.92,
              ),
              itemBuilder: (context, index) {
                final item = _items[index];
                return _ProofCard(
                  item: item,
                  onTap: () => _openItem(item),
                );
              },
            ),
        ],
      ),
    );
  }
}

class _PaymentProofItem {
  final String url;
  final String label;
  final bool isPdf;

  const _PaymentProofItem({
    required this.url,
    required this.label,
    required this.isPdf,
  });
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
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: _UploadPaymentProofScreenState._cardBorder),
        ),
        child: Column(
          children: [
            if (uploading) ...[
              const LinearProgressIndicator(
                minHeight: 4,
                color: _UploadPaymentProofScreenState._navyEnd,
                backgroundColor: Color(0xFFDEE7F3),
              ),
              const SizedBox(height: 12),
              const Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                  SizedBox(width: 10),
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
            const Text(
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
            color: filled ? null : const Color(0xFFEEF4FB),
            borderRadius: BorderRadius.circular(14),
            border: filled
                ? null
                : Border.all(color: const Color(0xFFC5D6EA)),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                icon,
                size: 20,
                color: filled
                    ? Colors.white
                    : _UploadPaymentProofScreenState._navyStart,
              ),
              const SizedBox(width: 8),
              Flexible(
                child: Text(
                  label,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: filled
                        ? Colors.white
                        : _UploadPaymentProofScreenState._navyStart,
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
  final _PaymentProofItem item;
  final VoidCallback onTap;

  const _ProofCard({required this.item, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Ink(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: _UploadPaymentProofScreenState._cardBorder,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                child: ClipRRect(
                  borderRadius:
                      const BorderRadius.vertical(top: Radius.circular(16)),
                  child: item.isPdf
                      ? Container(
                          color: const Color(0xFFF8FAFC),
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
                          fit: BoxFit.cover,
                          placeholder: (context, url) =>
                              const SkeletonImage(radius: 0),
                          errorWidget: (context, url, error) => const Center(
                            child: Icon(Icons.broken_image_outlined,
                                color: Color(0xFF94A3B8)),
                          ),
                        ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(10, 10, 10, 12),
                child: Text(
                  item.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: _UploadPaymentProofScreenState._textPrimary,
                    fontWeight: FontWeight.w700,
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
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _UploadPaymentProofScreenState._cardBorder),
      ),
      child: const Column(
        children: [
          Icon(Icons.receipt_long_outlined, size: 56, color: Color(0xFF94A3B8)),
          SizedBox(height: 12),
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
    return const Center(
      child: Padding(
        padding: EdgeInsets.all(28),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.home_work_outlined, size: 72, color: Color(0xFF94A3B8)),
            SizedBox(height: 16),
            Text(
              'No project linked to this client',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w800,
                color: _UploadPaymentProofScreenState._textPrimary,
              ),
            ),
            SizedBox(height: 8),
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
