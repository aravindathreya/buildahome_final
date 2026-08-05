import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

import 'app_theme.dart';
import 'services/client_portal_service.dart';
import 'widgets/skeleton_loader.dart';

/// Client Portal hub — pre-construction documents, design, site prep & inspection.
class ClientPortalScreen extends StatefulWidget {
  const ClientPortalScreen({super.key});

  @override
  State<ClientPortalScreen> createState() => _ClientPortalScreenState();
}

class _ClientPortalScreenState extends State<ClientPortalScreen> {
  final _portal = ClientPortalService();

  bool _loading = true;
  String? _error;
  Map<String, dynamic>? _project;
  bool _tutorialDone = false;

  @override
  void initState() {
    super.initState();
    _bootstrap();
  }

  Future<void> _bootstrap() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final prefs = await SharedPreferences.getInstance();
      _tutorialDone = prefs.getBool('client_portal_tutorial_done') ?? false;

      // Prefer project section; fall back to full portal payload.
      Map<String, dynamic> payload;
      try {
        payload = await _portal.getProject();
      } catch (_) {
        payload = await _portal.getPortal(sections: const ['project']);
      }

      final section = _portal.sectionOf(payload);
      // Section may be the project object itself, or nested under `project`.
      Map<String, dynamic> project = section;
      if (section['project'] is Map) {
        project = Map<String, dynamic>.from(section['project'] as Map);
      } else if (payload['project'] is Map) {
        project = Map<String, dynamic>.from(payload['project'] as Map);
      } else if (payload['sections'] is Map &&
          (payload['sections'] as Map)['project'] is Map) {
        project = Map<String, dynamic>.from(
          (payload['sections'] as Map)['project'] as Map,
        );
      }

      if (!mounted) return;

      if (project.isEmpty) {
        final msg = payload['message']?.toString() ?? '';
        if (msg.toLowerCase().contains('no project')) {
          setState(() {
            _loading = false;
            _project = null;
            _error = null;
          });
          return;
        }
      }

      final name = project['client_name']?.toString();
      if (name != null && name.isNotEmpty) {
        await prefs.setString('client_name', name);
      }

      // Tutorial flag may also come from API.
      final apiTutorial = project['tutorial_completed'] == true ||
          section['tutorial_completed'] == true ||
          payload['tutorial_completed'] == true;
      if (apiTutorial) _tutorialDone = true;

      setState(() {
        _loading = false;
        _project = project.isEmpty ? <String, dynamic>{'client_name': 'Your project'} : project;
      });
    } catch (e) {
      if (!mounted) return;
      final msg = e.toString().replaceFirst('Exception: ', '');
      if (msg.toLowerCase().contains('no project')) {
        setState(() {
          _loading = false;
          _project = null;
          _error = null;
        });
        return;
      }
      setState(() {
        _loading = false;
        _error = msg;
      });
    }
  }

  Future<void> _completeTutorial() async {
    try {
      await _portal.completeTutorial();
      if (!mounted) return;
      setState(() => _tutorialDone = true);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Welcome tour completed')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(e.toString().replaceFirst('Exception: ', '')),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.getBackgroundPrimary(context),
      appBar: AppBar(
        backgroundColor: AppTheme.getBackgroundSecondary(context),
        foregroundColor: AppTheme.navy,
        elevation: 0,
        title: const Text(
          'Client Portal',
          style: TextStyle(
            color: AppTheme.navy,
            fontSize: 18,
            fontWeight: FontWeight.w800,
          ),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_rounded),
            onPressed: _loading ? null : _bootstrap,
          ),
        ],
      ),
      body: SafeArea(child: _buildBody()),
    );
  }

  Widget _buildBody() {
    if (_loading) return const SkeletonListLoader(cardCount: 5);
    if (_error != null) {
      return _ErrorState(message: _error!, onRetry: _bootstrap);
    }
    if (_project == null) {
      return const _NoProjectState();
    }

    final p = _project!;
    return RefreshIndicator(
      color: AppTheme.navy,
      onRefresh: _bootstrap,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 28),
        children: [
          _ProjectHeader(project: p),
          if (!_tutorialDone) ...[
            const SizedBox(height: 14),
            _TutorialBanner(onComplete: _completeTutorial),
          ],
          const SizedBox(height: 22),
          const Text(
            'Your journey',
            style: TextStyle(
              fontSize: 15.5,
              fontWeight: FontWeight.w800,
              color: AppTheme.navy,
            ),
          ),
          const SizedBox(height: 12),
          ..._portalSections.map((section) {
            return Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: _PortalNavTile(
                icon: section.icon,
                title: section.title,
                subtitle: section.subtitle,
                onTap: () => _openSection(section),
              ),
            );
          }),
        ],
      ),
    );
  }

  void _openSection(_PortalSectionMeta section) {
    Widget page;
    switch (section.id) {
      case 'documents':
        page = const _DocumentsKycScreen();
        break;
      case 'floor_plan':
        page = const _FloorPlanElevationScreen();
        break;
      case 'design':
        page = const _DesignElementScreen();
        break;
      case 'site_prep':
        page = const _SitePreparationScreen();
        break;
      case 'demolition':
        page = const _DemolitionScreen();
        break;
      case 'inspection':
        page = const _SiteInspectionScreen();
        break;
      case 'all_docs':
        page = const _AllDocumentsScreen();
        break;
      default:
        return;
    }
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => page),
    ).then((_) => _bootstrap());
  }
}

class _PortalSectionMeta {
  final String id;
  final String title;
  final String subtitle;
  final IconData icon;

  const _PortalSectionMeta({
    required this.id,
    required this.title,
    required this.subtitle,
    required this.icon,
  });
}

const _portalSections = <_PortalSectionMeta>[
  _PortalSectionMeta(
    id: 'documents',
    title: 'KYC & Documents',
    subtitle: 'Upload ID proofs and leave a note',
    icon: Icons.folder_shared_outlined,
  ),
  _PortalSectionMeta(
    id: 'floor_plan',
    title: 'Floor Plan & Elevation',
    subtitle: 'View drawings and framing plans',
    icon: Icons.architecture_outlined,
  ),
  _PortalSectionMeta(
    id: 'design',
    title: 'Design Elements',
    subtitle: 'Vastu, elevation refs & bylaws',
    icon: Icons.auto_awesome_outlined,
  ),
  _PortalSectionMeta(
    id: 'site_prep',
    title: 'Site Preparation',
    subtitle: 'Demolition & borewell questionnaire',
    icon: Icons.construction_outlined,
  ),
  _PortalSectionMeta(
    id: 'demolition',
    title: 'Demolition Details',
    subtitle: 'Completion date and comments',
    icon: Icons.domain_disabled_outlined,
  ),
  _PortalSectionMeta(
    id: 'inspection',
    title: 'Site Inspection',
    subtitle: 'Book a slot or view your report',
    icon: Icons.event_available_outlined,
  ),
  _PortalSectionMeta(
    id: 'all_docs',
    title: 'All Documents',
    subtitle: 'Proposal, costing, agreements & more',
    icon: Icons.library_books_outlined,
  ),
];

// ── Shared chrome ───────────────────────────────────────────────────────────

class _ErrorState extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;

  const _ErrorState({required this.message, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.wifi_off_rounded,
                size: 56, color: AppTheme.getTextSecondary(context)),
            const SizedBox(height: 16),
            Text(
              'Something went wrong',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w800,
                color: AppTheme.getTextPrimary(context),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              message,
              textAlign: TextAlign.center,
              style: TextStyle(color: AppTheme.getTextSecondary(context)),
            ),
            const SizedBox(height: 20),
            ElevatedButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh),
              label: const Text('Retry'),
              style: ElevatedButton.styleFrom(backgroundColor: AppTheme.navy),
            ),
          ],
        ),
      ),
    );
  }
}

class _NoProjectState extends StatelessWidget {
  const _NoProjectState();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.home_work_outlined,
                size: 72,
                color: AppTheme.getPrimaryColor(context).withOpacity(0.45)),
            const SizedBox(height: 20),
            Text(
              'No project linked',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w800,
                color: AppTheme.getTextPrimary(context),
              ),
            ),
            const SizedBox(height: 10),
            Text(
              'Your account is not linked to a project yet. Please contact buildAhome support.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 15,
                height: 1.4,
                color: AppTheme.getTextSecondary(context),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ProjectHeader extends StatelessWidget {
  final Map<String, dynamic> project;

  const _ProjectHeader({required this.project});

  @override
  Widget build(BuildContext context) {
    final name = project['client_name']?.toString() ?? 'Your project';
    final package = project['package']?.toString();
    final location = project['location']?.toString();
    final status = _statusLabel(project);

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppTheme.border),
        boxShadow: const [
          BoxShadow(color: AppTheme.softShadow, blurRadius: 12, offset: Offset(0, 4)),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: const Color(0xFFEEF2FF),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(Icons.home_outlined, color: AppTheme.navy),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      name,
                      style: const TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w800,
                        color: AppTheme.navy,
                      ),
                    ),
                    if (package != null && package.isNotEmpty)
                      Text(
                        package,
                        style: TextStyle(
                          fontSize: 13,
                          color: AppTheme.getTextSecondary(context),
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                  ],
                ),
              ),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  color: const Color(0xFFECFDF5),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  status,
                  style: const TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF059669),
                  ),
                ),
              ),
            ],
          ),
          if (location != null && location.isNotEmpty) ...[
            const SizedBox(height: 12),
            Row(
              children: [
                Icon(Icons.place_outlined,
                    size: 16, color: AppTheme.getTextSecondary(context)),
                const SizedBox(width: 4),
                Expanded(
                  child: Text(
                    location,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 12.5,
                      color: AppTheme.getTextSecondary(context),
                    ),
                  ),
                ),
              ],
            ),
          ],
          const SizedBox(height: 14),
          _ProgressRow(project: project),
        ],
      ),
    );
  }

  String _statusLabel(Map p) {
    if (p['is_converted'] == true) return 'Converted';
    if (p['is_approved'] == true) return 'Approved';
    if (p['send_costing_completed'] == true) return 'Costing';
    if (p['finalize_elevation_completed'] == true) return 'Elevation';
    return 'In progress';
  }
}

class _ProgressRow extends StatelessWidget {
  final Map<String, dynamic> project;
  const _ProgressRow({required this.project});

  @override
  Widget build(BuildContext context) {
    final steps = [
      project['finalize_elevation_completed'] == true,
      project['send_costing_completed'] == true,
      project['is_approved'] == true,
      project['is_converted'] == true,
    ];
    final labels = ['Elevation', 'Costing', 'Approved', 'Converted'];
    final done = steps.where((e) => e).length;

    return Column(
      children: [
        Row(
          children: [
            Expanded(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: LinearProgressIndicator(
                  value: done / steps.length,
                  minHeight: 6,
                  backgroundColor: const Color(0xFFE8ECF1),
                  valueColor:
                      const AlwaysStoppedAnimation<Color>(AppTheme.navy),
                ),
              ),
            ),
            const SizedBox(width: 10),
            Text(
              '$done/${steps.length}',
              style: const TextStyle(
                fontWeight: FontWeight.w700,
                fontSize: 12.5,
                color: AppTheme.navy,
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        Row(
          children: List.generate(steps.length, (i) {
            final active = steps[i];
            return Expanded(
              child: Column(
                children: [
                  Icon(
                    active
                        ? Icons.check_circle_rounded
                        : Icons.radio_button_unchecked,
                    size: 18,
                    color: active
                        ? AppTheme.navy
                        : AppTheme.getTextSecondary(context).withOpacity(0.5),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    labels[i],
                    style: TextStyle(
                      fontSize: 10.5,
                      fontWeight: active ? FontWeight.w700 : FontWeight.w500,
                      color: active
                          ? AppTheme.navy
                          : AppTheme.getTextSecondary(context),
                    ),
                  ),
                ],
              ),
            );
          }),
        ),
      ],
    );
  }
}

class _TutorialBanner extends StatelessWidget {
  final VoidCallback onComplete;
  const _TutorialBanner({required this.onComplete});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF1B254B), Color(0xFF2F3F73)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'New here?',
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w800,
                    fontSize: 15,
                  ),
                ),
                SizedBox(height: 4),
                Text(
                  'Mark the welcome tour as done when you are ready.',
                  style: TextStyle(color: Color(0xFFD6DCF0), fontSize: 12.5),
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          TextButton(
            onPressed: onComplete,
            style: TextButton.styleFrom(
              backgroundColor: Colors.white,
              foregroundColor: AppTheme.navy,
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
            child: const Text(
              'Got it',
              style: TextStyle(fontWeight: FontWeight.w800),
            ),
          ),
        ],
      ),
    );
  }
}

class _PortalNavTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  const _PortalNavTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: AppTheme.border),
          ),
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: const Color(0xFFF0F4FF),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon, color: AppTheme.navy, size: 22),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        fontSize: 14.5,
                        fontWeight: FontWeight.w800,
                        color: AppTheme.navy,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: TextStyle(
                        fontSize: 12.5,
                        color: AppTheme.getTextSecondary(context),
                      ),
                    ),
                  ],
                ),
              ),
              Icon(Icons.chevron_right_rounded,
                  color: AppTheme.getTextSecondary(context)),
            ],
          ),
        ),
      ),
    );
  }
}

class _PortalScaffold extends StatelessWidget {
  final String title;
  final Widget body;
  final List<Widget>? actions;

  const _PortalScaffold({
    required this.title,
    required this.body,
    this.actions,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.getBackgroundPrimary(context),
      appBar: AppBar(
        backgroundColor: AppTheme.getBackgroundSecondary(context),
        foregroundColor: AppTheme.navy,
        elevation: 0,
        title: Text(
          title,
          style: const TextStyle(
            color: AppTheme.navy,
            fontSize: 17,
            fontWeight: FontWeight.w800,
          ),
        ),
        actions: actions,
      ),
      body: SafeArea(child: body),
    );
  }
}

Future<void> _openExternal(BuildContext context, String? url) async {
  final trimmed = url?.trim() ?? '';
  if (trimmed.isEmpty) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Document not available yet')),
    );
    return;
  }
  final resolved = trimmed.startsWith('http')
      ? trimmed
      : ClientPortalService().serveUrl(trimmed);
  final uri = Uri.tryParse(resolved);
  if (uri == null) return;
  try {
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  } catch (_) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Could not open document'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }
}

Widget _emptyDocHint(BuildContext context, String label) {
  return Container(
    width: double.infinity,
    padding: const EdgeInsets.all(18),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(14),
      border: Border.all(color: AppTheme.border),
    ),
    child: Column(
      children: [
        Icon(Icons.insert_drive_file_outlined,
            size: 36, color: AppTheme.getTextSecondary(context)),
        const SizedBox(height: 8),
        Text(
          '$label not uploaded yet',
          style: TextStyle(
            fontWeight: FontWeight.w700,
            color: AppTheme.getTextSecondary(context),
          ),
        ),
      ],
    ),
  );
}

Widget _docTile(
  BuildContext context, {
  required String title,
  String? url,
  IconData icon = Icons.description_outlined,
}) {
  final available = url != null && url.trim().isNotEmpty;
  return ListTile(
    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(12),
      side: const BorderSide(color: AppTheme.border),
    ),
    tileColor: Colors.white,
    leading: Container(
      width: 40,
      height: 40,
      decoration: BoxDecoration(
        color: available ? const Color(0xFFECFDF5) : const Color(0xFFF3F4F6),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Icon(
        icon,
        color: available ? const Color(0xFF059669) : AppTheme.mutedGrey,
        size: 20,
      ),
    ),
    title: Text(
      title,
      style: TextStyle(
        fontWeight: FontWeight.w700,
        fontSize: 14,
        color: available ? AppTheme.navy : AppTheme.mutedGrey,
      ),
    ),
    subtitle: Text(
      available ? 'Tap to open' : 'Not available yet',
      style: const TextStyle(fontSize: 12),
    ),
    trailing: Icon(
      available ? Icons.open_in_new_rounded : Icons.lock_outline,
      size: 18,
      color: AppTheme.mutedGrey,
    ),
    onTap: available ? () => _openExternal(context, url) : null,
  );
}

// ── 1. Documents / KYC ──────────────────────────────────────────────────────

class _DocumentsKycScreen extends StatefulWidget {
  const _DocumentsKycScreen();

  @override
  State<_DocumentsKycScreen> createState() => _DocumentsKycScreenState();
}

class _DocumentsKycScreenState extends State<_DocumentsKycScreen> {
  final _portal = ClientPortalService();
  final _commentCtrl = TextEditingController();

  bool _loading = true;
  bool _saving = false;
  String? _error;
  Map<String, dynamic> _data = {};
  List _kycDocs = [];
  List _docTypes = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _commentCtrl.dispose();
    super.dispose();
  }

  String _labelForDocKey(String key) {
    switch (key) {
      case 'aadhar':
        return 'Aadhaar';
      case 'pan_card':
        return 'PAN card';
      case 'custom':
        return 'Other document';
      default:
        return key
            .split('_')
            .map((p) => p.isEmpty ? p : '${p[0].toUpperCase()}${p.substring(1)}')
            .join(' ');
    }
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final result = await _portal.getDocuments();
      final data = _portal.sectionOf(result);
      _commentCtrl.text = data['client_kyc_comment']?.toString() ?? '';

      final existing = data['existing'] is List
          ? List.from(data['existing'] as List)
          : (data['client_kyc_documents'] is List
              ? List.from(data['client_kyc_documents'] as List)
              : []);

      final mandatory = data['mandatory_docs'] is List
          ? List.from(data['mandatory_docs'] as List)
          : <dynamic>[];
      final uploaded = data['uploaded_types'] is List
          ? List.from(data['uploaded_types'] as List)
          : <dynamic>[];

      // Prefer API document_types; else build from mandatory + custom.
      List docTypes;
      if (data['document_types'] is List &&
          (data['document_types'] as List).isNotEmpty) {
        docTypes = List.from(data['document_types'] as List);
      } else {
        final keys = <String>{
          ...mandatory.map((e) => e.toString()),
          'custom',
        };
        docTypes = keys
            .map((k) => {'key': k, 'label': _labelForDocKey(k)})
            .toList();
      }

      if (!mounted) return;
      setState(() {
        _loading = false;
        _data = data;
        _kycDocs = existing;
        _docTypes = docTypes;
        // Keep uploaded types on data for UI badges.
        _data['uploaded_types'] = uploaded;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = e.toString().replaceFirst('Exception: ', '');
      });
    }
  }

  Future<void> _upload(String docKey) async {
    final picked = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['pdf', 'jpg', 'jpeg', 'png', 'webp'],
      withData: false,
    );
    if (picked == null || picked.files.isEmpty) return;
    final path = picked.files.first.path;
    if (path == null) return;

    setState(() => _saving = true);
    try {
      final result = await _portal.uploadDocument(
        docKey: docKey,
        file: File(path),
        customDocName: docKey == 'custom' ? 'custom' : null,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            result['message']?.toString() ?? 'Uploaded successfully',
          ),
        ),
      );
      // Prefer updated section from response when present.
      if (result['section'] is Map) {
        final data = Map<String, dynamic>.from(result['section'] as Map);
        _commentCtrl.text = data['client_kyc_comment']?.toString() ??
            _commentCtrl.text;
        setState(() {
          _data = data;
          _kycDocs = data['existing'] is List
              ? List.from(data['existing'] as List)
              : _kycDocs;
        });
      } else {
        await _load();
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(e.toString().replaceFirst('Exception: ', '')),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _saveComment() async {
    setState(() => _saving = true);
    try {
      await _portal.saveComment(_commentCtrl.text.trim());
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Comment saved')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(e.toString().replaceFirst('Exception: ', '')),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return _PortalScaffold(
      title: 'KYC & Documents',
      body: _loading
          ? const SkeletonListLoader(cardCount: 4)
          : _error != null
              ? _ErrorState(message: _error!, onRetry: _load)
              : ListView(
                  padding: const EdgeInsets.all(20),
                  children: [
                    const Text(
                      'Upload documents',
                      style: TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 15,
                        color: AppTheme.navy,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Share Aadhaar or other KYC files requested by your team.',
                      style: TextStyle(
                        color: AppTheme.getTextSecondary(context),
                        fontSize: 13,
                      ),
                    ),
                    const SizedBox(height: 14),
                    ..._docTypes.map((raw) {
                      final map = raw is Map
                          ? Map<String, dynamic>.from(raw)
                          : <String, dynamic>{
                              'key': raw.toString(),
                              'label': raw.toString(),
                            };
                      final key = map['key']?.toString() ??
                          map['doc_key']?.toString() ??
                          'custom';
                      final label = map['label']?.toString() ??
                          map['name']?.toString() ??
                          key;
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: OutlinedButton.icon(
                          onPressed: _saving ? null : () => _upload(key),
                          icon: const Icon(Icons.upload_file_outlined),
                          label: Text('Upload $label'),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: AppTheme.navy,
                            side: const BorderSide(color: AppTheme.border),
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                        ),
                      );
                    }),
                    const SizedBox(height: 18),
                    const Text(
                      'Uploaded KYC',
                      style: TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 15,
                        color: AppTheme.navy,
                      ),
                    ),
                    const SizedBox(height: 10),
                    if (_kycDocs.isEmpty)
                      _emptyDocHint(context, 'KYC documents')
                    else
                      ..._kycDocs.map((raw) {
                        final doc = raw is Map
                            ? Map<String, dynamic>.from(raw)
                            : <String, dynamic>{};
                        final title = doc['document_label']?.toString() ??
                            doc['document_type']?.toString() ??
                            doc['doc_type']?.toString() ??
                            doc['name']?.toString() ??
                            'Document';
                        final url = doc['view_url']?.toString() ??
                            doc['download_url']?.toString() ??
                            doc['url']?.toString() ??
                            doc['file_url']?.toString();
                        return Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: _docTile(context, title: title, url: url),
                        );
                      }),
                    const SizedBox(height: 22),
                    const Text(
                      'Your comment',
                      style: TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 15,
                        color: AppTheme.navy,
                      ),
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: _commentCtrl,
                      maxLines: 4,
                      decoration: InputDecoration(
                        hintText: 'Any notes for the team…',
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
                    ElevatedButton(
                      onPressed: _saving ? null : _saveComment,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppTheme.navy,
                        foregroundColor: Colors.white,
                        minimumSize: const Size.fromHeight(48),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      child: Text(_saving ? 'Saving…' : 'Save comment'),
                    ),
                    if (_data['demolition_contact'] != null ||
                        _data['borewell_contact'] != null) ...[
                      const SizedBox(height: 22),
                      const Text(
                        'Contacts',
                        style: TextStyle(
                          fontWeight: FontWeight.w800,
                          fontSize: 15,
                          color: AppTheme.navy,
                        ),
                      ),
                      const SizedBox(height: 8),
                      if (_data['demolition_contact'] != null)
                        _infoLine('Demolition',
                            _data['demolition_contact'].toString()),
                      if (_data['borewell_contact'] != null)
                        _infoLine(
                            'Borewell', _data['borewell_contact'].toString()),
                    ],
                  ],
                ),
    );
  }

  Widget _infoLine(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Text(
        '$label: $value',
        style: const TextStyle(fontSize: 13.5, color: AppTheme.navy),
      ),
    );
  }
}

// ── 3. Floor plan & elevation ───────────────────────────────────────────────

class _FloorPlanElevationScreen extends StatefulWidget {
  const _FloorPlanElevationScreen();

  @override
  State<_FloorPlanElevationScreen> createState() =>
      _FloorPlanElevationScreenState();
}

class _FloorPlanElevationScreenState extends State<_FloorPlanElevationScreen> {
  final _portal = ClientPortalService();
  bool _loading = true;
  String? _error;
  Map<String, dynamic> _data = {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final result = await _portal.getFloorPlanElevation();
      if (!mounted) return;
      setState(() {
        _loading = false;
        _data = _portal.sectionOf(result);
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = e.toString().replaceFirst('Exception: ', '');
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final status = _data['final_status']?.toString() ??
        (_data['finalize_elevation_completed'] == true ? 'finalized' : 'pending');
    return _PortalScaffold(
      title: 'Floor Plan & Elevation',
      actions: [
        IconButton(onPressed: _load, icon: const Icon(Icons.refresh_rounded)),
      ],
      body: _loading
          ? const SkeletonListLoader(cardCount: 3)
          : _error != null
              ? _ErrorState(message: _error!, onRetry: _load)
              : ListView(
                  padding: const EdgeInsets.all(20),
                  children: [
                    Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: status == 'finalized'
                            ? const Color(0xFFECFDF5)
                            : const Color(0xFFFFF7ED),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            status == 'finalized'
                                ? Icons.verified_rounded
                                : Icons.hourglass_bottom_rounded,
                            color: status == 'finalized'
                                ? const Color(0xFF059669)
                                : const Color(0xFFEA580C),
                          ),
                          const SizedBox(width: 10),
                          Text(
                            status == 'finalized'
                                ? 'Elevation finalized'
                                : 'Drawings in progress',
                            style: const TextStyle(
                              fontWeight: FontWeight.w700,
                              color: AppTheme.navy,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                    _docTile(context,
                        title: 'Floor plan',
                        url: _data['floor_plan_url']?.toString(),
                        icon: Icons.map_outlined),
                    const SizedBox(height: 8),
                    _docTile(context,
                        title: 'Elevation',
                        url: _data['elevation_url']?.toString(),
                        icon: Icons.apartment_outlined),
                    const SizedBox(height: 8),
                    _docTile(context,
                        title: 'Framing drawing',
                        url: _data['framing_drawing_url']?.toString(),
                        icon: Icons.grid_on_outlined),
                  ],
                ),
    );
  }
}

// ── 4. Design element ───────────────────────────────────────────────────────

class _DesignElementScreen extends StatefulWidget {
  const _DesignElementScreen();

  @override
  State<_DesignElementScreen> createState() => _DesignElementScreenState();
}

class _DesignElementScreenState extends State<_DesignElementScreen> {
  final _portal = ClientPortalService();
  bool _loading = true;
  String? _error;
  Map<String, dynamic> _data = {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final result = await _portal.getDesignElement();
      if (!mounted) return;
      setState(() {
        _loading = false;
        _data = _portal.sectionOf(result);
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = e.toString().replaceFirst('Exception: ', '');
      });
    }
  }

  List _asList(dynamic value) => value is List ? List.from(value) : [];

  Widget _docGroup(String title, List items) {
    if (items.isEmpty) {
      return Padding(
        padding: const EdgeInsets.only(bottom: 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title,
                style: const TextStyle(
                    fontWeight: FontWeight.w800, color: AppTheme.navy)),
            const SizedBox(height: 8),
            _emptyDocHint(context, title),
          ],
        ),
      );
    }
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title,
              style: const TextStyle(
                  fontWeight: FontWeight.w800, color: AppTheme.navy)),
          const SizedBox(height: 8),
          ...items.map((raw) {
            final doc = raw is Map
                ? Map<String, dynamic>.from(raw)
                : <String, dynamic>{'url': raw.toString()};
            final label = doc['name']?.toString() ??
                doc['title']?.toString() ??
                doc['label']?.toString() ??
                doc['document_label']?.toString() ??
                title;
            final url = doc['view_url']?.toString() ??
                doc['download_url']?.toString() ??
                doc['url']?.toString() ??
                doc['file_url']?.toString();
            return Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: _docTile(context, title: label, url: url),
            );
          }),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return _PortalScaffold(
      title: 'Design Elements',
      actions: [
        IconButton(onPressed: _load, icon: const Icon(Icons.refresh_rounded)),
      ],
      body: _loading
          ? const SkeletonListLoader(cardCount: 3)
          : _error != null
              ? _ErrorState(message: _error!, onRetry: _load)
              : ListView(
                  padding: const EdgeInsets.all(20),
                  children: [
                    _docGroup('Vastu design',
                        _asList(_data['vastu_design_docs'])),
                    _docGroup(
                        'Elevation references',
                        _asList(_data['elevation_reference_design_docs'])),
                    _docGroup(
                        'Bylaws', _asList(_data['bylaws_design_docs'])),
                  ],
                ),
    );
  }
}

// ── 5. Site preparation ─────────────────────────────────────────────────────

class _SitePreparationScreen extends StatefulWidget {
  const _SitePreparationScreen();

  @override
  State<_SitePreparationScreen> createState() => _SitePreparationScreenState();
}

class _SitePreparationScreenState extends State<_SitePreparationScreen> {
  final _portal = ClientPortalService();
  bool _loading = true;
  bool _saving = false;
  String? _error;
  bool? _demolitionRequired;
  bool? _borewellRequired;
  bool _readonly = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final result = await _portal.getSitePreparation();
      final data = _portal.sectionOf(result);
      if (!mounted) return;
      setState(() {
        _loading = false;
        _demolitionRequired = _asBool(data['demolition_required']);
        _borewellRequired = _asBool(data['borewell_required']);
        _readonly = data['readonly'] == true ||
            data['questionnaire_readonly'] == true;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = e.toString().replaceFirst('Exception: ', '');
      });
    }
  }

  bool? _asBool(dynamic value) {
    if (value == null) return null;
    if (value is bool) return value;
    final s = value.toString().toLowerCase();
    if (s == 'true' || s == '1' || s == 'yes') return true;
    if (s == 'false' || s == '0' || s == 'no') return false;
    return null;
  }

  Future<void> _save() async {
    if (_demolitionRequired == null || _borewellRequired == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please answer both questions')),
      );
      return;
    }
    setState(() => _saving = true);
    try {
      final result = await _portal.saveSitePreparation(
        demolitionRequired: _demolitionRequired!,
        borewellRequired: _borewellRequired!,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            result['message']?.toString() ?? 'Questionnaire saved',
          ),
        ),
      );
      await _load();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(e.toString().replaceFirst('Exception: ', '')),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _defer() async {
    setState(() => _saving = true);
    try {
      await _portal.deferSitePreparation();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Questionnaire deferred')),
      );
      Navigator.pop(context);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(e.toString().replaceFirst('Exception: ', '')),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Widget _yesNo(String label, bool? value, ValueChanged<bool?> onChanged) {
    return Container(
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
          Text(label,
              style: const TextStyle(
                  fontWeight: FontWeight.w700, color: AppTheme.navy)),
          const SizedBox(height: 8),
          Row(
            children: [
              ChoiceChip(
                label: const Text('Yes'),
                selected: value == true,
                onSelected: _readonly ? null : (_) => onChanged(true),
                selectedColor: const Color(0xFFDBEAFE),
                labelStyle: TextStyle(
                  fontWeight: FontWeight.w700,
                  color: value == true ? AppTheme.navy : AppTheme.mutedGrey,
                ),
              ),
              const SizedBox(width: 8),
              ChoiceChip(
                label: const Text('No'),
                selected: value == false,
                onSelected: _readonly ? null : (_) => onChanged(false),
                selectedColor: const Color(0xFFDBEAFE),
                labelStyle: TextStyle(
                  fontWeight: FontWeight.w700,
                  color: value == false ? AppTheme.navy : AppTheme.mutedGrey,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return _PortalScaffold(
      title: 'Site Preparation',
      body: _loading
          ? const SkeletonListLoader(cardCount: 3)
          : _error != null
              ? _ErrorState(message: _error!, onRetry: _load)
              : ListView(
                  padding: const EdgeInsets.all(20),
                  children: [
                    Text(
                      _readonly
                          ? 'Your answers are locked. Contact support to change them.'
                          : 'Tell us what your site needs before we start.',
                      style: TextStyle(
                        color: AppTheme.getTextSecondary(context),
                        fontSize: 13.5,
                      ),
                    ),
                    const SizedBox(height: 16),
                    _yesNo(
                      'Is demolition required?',
                      _demolitionRequired,
                      (v) => setState(() => _demolitionRequired = v),
                    ),
                    _yesNo(
                      'Is a borewell required?',
                      _borewellRequired,
                      (v) => setState(() => _borewellRequired = v),
                    ),
                    if (!_readonly) ...[
                      const SizedBox(height: 8),
                      ElevatedButton(
                        onPressed: _saving ? null : _save,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppTheme.navy,
                          foregroundColor: Colors.white,
                          minimumSize: const Size.fromHeight(48),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        child: Text(_saving ? 'Saving…' : 'Save answers'),
                      ),
                      const SizedBox(height: 8),
                      TextButton(
                        onPressed: _saving ? null : _defer,
                        child: const Text('I will answer later'),
                      ),
                    ],
                  ],
                ),
    );
  }
}

// ── 6. Demolition ───────────────────────────────────────────────────────────

class _DemolitionScreen extends StatefulWidget {
  const _DemolitionScreen();

  @override
  State<_DemolitionScreen> createState() => _DemolitionScreenState();
}

class _DemolitionScreenState extends State<_DemolitionScreen> {
  final _portal = ClientPortalService();
  final _commentCtrl = TextEditingController();

  bool _loading = true;
  bool _saving = false;
  String? _error;
  bool _required = false;
  DateTime? _completionDate;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _commentCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final result = await _portal.getDemolition();
      final data = _portal.sectionOf(result);
      final dateRaw = data['demolition_completion_date']?.toString();
      DateTime? parsed;
      if (dateRaw != null && dateRaw.isNotEmpty) {
        parsed = DateTime.tryParse(dateRaw);
      }
      if (!mounted) return;
      final reqRaw = data['demolition_required']?.toString().toLowerCase();
      setState(() {
        _loading = false;
        _required = data['demolition_required'] == true ||
            reqRaw == 'true' ||
            reqRaw == 'yes' ||
            reqRaw == '1';
        _completionDate = parsed;
        _commentCtrl.text = data['demolition_comment']?.toString() ?? '';
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = e.toString().replaceFirst('Exception: ', '');
      });
    }
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _completionDate ?? DateTime.now().add(const Duration(days: 7)),
      firstDate: DateTime.now().subtract(const Duration(days: 30)),
      lastDate: DateTime.now().add(const Duration(days: 365 * 2)),
    );
    if (picked != null) setState(() => _completionDate = picked);
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      await _portal.saveDemolition(
        demolitionRequired: _required,
        completionDate: _completionDate == null
            ? null
            : DateFormat('yyyy-MM-dd').format(_completionDate!),
        comment: _commentCtrl.text.trim(),
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Demolition details saved')),
      );
      Navigator.pop(context);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(e.toString().replaceFirst('Exception: ', '')),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return _PortalScaffold(
      title: 'Demolition',
      body: _loading
          ? const SkeletonListLoader(cardCount: 3)
          : _error != null
              ? _ErrorState(message: _error!, onRetry: _load)
              : ListView(
                  padding: const EdgeInsets.all(20),
                  children: [
                    SwitchListTile.adaptive(
                      value: _required,
                      onChanged: (v) => setState(() => _required = v),
                      title: const Text(
                        'Demolition required',
                        style: TextStyle(
                          fontWeight: FontWeight.w700,
                          color: AppTheme.navy,
                        ),
                      ),
                      activeColor: AppTheme.navy,
                      contentPadding: EdgeInsets.zero,
                    ),
                    const SizedBox(height: 8),
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text(
                        'Completion date',
                        style: TextStyle(
                          fontWeight: FontWeight.w700,
                          color: AppTheme.navy,
                        ),
                      ),
                      subtitle: Text(
                        _completionDate == null
                            ? 'Not set'
                            : DateFormat('dd MMM yyyy').format(_completionDate!),
                      ),
                      trailing: const Icon(Icons.calendar_today_outlined),
                      onTap: _pickDate,
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: _commentCtrl,
                      maxLines: 4,
                      decoration: InputDecoration(
                        labelText: 'Comment',
                        filled: true,
                        fillColor: Colors.white,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    ElevatedButton(
                      onPressed: _saving ? null : _save,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppTheme.navy,
                        foregroundColor: Colors.white,
                        minimumSize: const Size.fromHeight(48),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      child: Text(_saving ? 'Saving…' : 'Save'),
                    ),
                  ],
                ),
    );
  }
}

// ── 7. Site inspection ──────────────────────────────────────────────────────

class _SiteInspectionScreen extends StatefulWidget {
  const _SiteInspectionScreen();

  @override
  State<_SiteInspectionScreen> createState() => _SiteInspectionScreenState();
}

class _SiteInspectionScreenState extends State<_SiteInspectionScreen> {
  final _portal = ClientPortalService();
  final _virtualCtrl = TextEditingController();

  bool _loading = true;
  bool _saving = false;
  String? _error;
  Map<String, dynamic> _data = {};

  String _presenceType = 'at_site';
  bool _siteCleaned = false;
  File? _proofFile;

  final List<_SlotDraft> _slots = [
    _SlotDraft(),
    _SlotDraft(),
    _SlotDraft(),
  ];

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _virtualCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final result = await _portal.getSiteInspection();
      if (!mounted) return;
      setState(() {
        _loading = false;
        _data = _portal.sectionOf(result);
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = e.toString().replaceFirst('Exception: ', '');
      });
    }
  }

  Future<void> _pickSlotDate(int index) async {
    final min = DateTime.now().add(const Duration(hours: 48));
    final picked = await showDatePicker(
      context: context,
      initialDate: min,
      firstDate: DateTime(min.year, min.month, min.day),
      lastDate: DateTime.now().add(const Duration(days: 120)),
    );
    if (picked != null) setState(() => _slots[index].date = picked);
  }

  Future<void> _pickProof() async {
    final picked = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['jpg', 'jpeg', 'png', 'webp', 'pdf'],
    );
    if (picked == null || picked.files.isEmpty) return;
    final path = picked.files.first.path;
    if (path == null) return;
    setState(() => _proofFile = File(path));
  }

  Future<void> _submit() async {
    for (final slot in _slots) {
      if (slot.date == null || slot.period == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Please choose 3 complete slots')),
        );
        return;
      }
    }

    final keys = _slots
        .map((s) =>
            '${DateFormat('yyyy-MM-dd').format(s.date!)}|${s.period}')
        .toSet();
    if (keys.length != 3) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('All 3 slots must be unique')),
      );
      return;
    }

    final min = DateTime.now().add(const Duration(hours: 48));
    for (final slot in _slots) {
      if (slot.date!.isBefore(DateTime(min.year, min.month, min.day))) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text('Slots must be at least 48 hours ahead')),
        );
        return;
      }
    }

    if (_presenceType == 'virtually' && _virtualCtrl.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('Add virtual meeting details (Zoom / Meet link)')),
      );
      return;
    }

    if (!_siteCleaned) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please confirm the site is cleaned')),
      );
      return;
    }

    setState(() => _saving = true);
    try {
      final result = await _portal.submitSiteInspection(
        presenceType: _presenceType,
        virtualConnectionDetails: _virtualCtrl.text.trim(),
        slot1Date: DateFormat('yyyy-MM-dd').format(_slots[0].date!),
        slot1Period: _slots[0].period!,
        slot2Date: DateFormat('yyyy-MM-dd').format(_slots[1].date!),
        slot2Period: _slots[1].period!,
        slot3Date: DateFormat('yyyy-MM-dd').format(_slots[2].date!),
        slot3Period: _slots[2].period!,
        siteCleanedConfirmed: _siteCleaned,
        siteCleanedProof: _proofFile,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            result['message']?.toString() ??
                'Site inspection request submitted',
          ),
        ),
      );
      if (result['section'] is Map) {
        setState(() {
          _data = Map<String, dynamic>.from(result['section'] as Map);
        });
      } else {
        await _load();
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(e.toString().replaceFirst('Exception: ', '')),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final canSubmit = _data['can_submit'] == true;
    final accepted = _data['accepted_slot'];
    final booking = _data['site_inspection_booking'] is Map
        ? Map<String, dynamic>.from(_data['site_inspection_booking'] as Map)
        : (_data['booking'] is Map
            ? Map<String, dynamic>.from(_data['booking'] as Map)
            : <String, dynamic>{});

    return _PortalScaffold(
      title: 'Site Inspection',
      actions: [
        IconButton(onPressed: _load, icon: const Icon(Icons.refresh_rounded)),
      ],
      body: _loading
          ? const SkeletonListLoader(cardCount: 4)
          : _error != null
              ? _ErrorState(message: _error!, onRetry: _load)
              : ListView(
                  padding: const EdgeInsets.all(20),
                  children: [
                    if (accepted != null) ...[
                      Container(
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: const Color(0xFFECFDF5),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Text(
                          'Accepted slot: $accepted',
                          style: const TextStyle(
                            fontWeight: FontWeight.w700,
                            color: Color(0xFF059669),
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                    ],
                    if (booking.isNotEmpty) ...[
                      const Text(
                        'Current booking',
                        style: TextStyle(
                          fontWeight: FontWeight.w800,
                          color: AppTheme.navy,
                        ),
                      ),
                      const SizedBox(height: 8),
                      ...[
                        if (booking['presence_type'] != null)
                          'Presence: ${booking['presence_type']}',
                        if (booking['slot1_display'] != null)
                          'Slot 1: ${booking['slot1_display']}',
                        if (booking['slot2_display'] != null)
                          'Slot 2: ${booking['slot2_display']}',
                        if (booking['slot3_display'] != null)
                          'Slot 3: ${booking['slot3_display']}',
                      ].map((line) => Padding(
                            padding: const EdgeInsets.only(bottom: 4),
                            child: Text(
                              line,
                              style: TextStyle(
                                fontSize: 13,
                                color: AppTheme.getTextSecondary(context),
                              ),
                            ),
                          )),
                      // Fallback for unexpected booking shapes.
                      if (booking['slot1_display'] == null)
                        ...booking.entries
                            .where((e) =>
                                e.value != null &&
                                e.value.toString().trim().isNotEmpty)
                            .take(6)
                            .map((e) => Padding(
                                  padding: const EdgeInsets.only(bottom: 4),
                                  child: Text(
                                    '${e.key}: ${e.value}',
                                    style: TextStyle(
                                      fontSize: 13,
                                      color:
                                          AppTheme.getTextSecondary(context),
                                    ),
                                  ),
                                )),
                      const SizedBox(height: 12),
                    ],
                    _docTile(
                      context,
                      title: 'Inspection report',
                      url: _data['site_inspection_report_url']?.toString() ??
                          _data['inspection_report_url']?.toString(),
                      icon: Icons.assignment_outlined,
                    ),
                    const SizedBox(height: 8),
                    _docTile(
                      context,
                      title: 'Site cleaned proof',
                      url: _data['site_cleaned_proof_url']?.toString(),
                      icon: Icons.cleaning_services_outlined,
                    ),
                    if (canSubmit) ...[
                      const SizedBox(height: 22),
                      const Text(
                        'Book inspection',
                        style: TextStyle(
                          fontWeight: FontWeight.w800,
                          fontSize: 15,
                          color: AppTheme.navy,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        'Choose 3 unique slots, each at least 48 hours from now.',
                        style: TextStyle(
                          fontSize: 12.5,
                          color: AppTheme.getTextSecondary(context),
                        ),
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Expanded(
                            child: ChoiceChip(
                              label: const Center(child: Text('At site')),
                              selected: _presenceType == 'at_site',
                              onSelected: (_) =>
                                  setState(() => _presenceType = 'at_site'),
                              selectedColor: const Color(0xFFDBEAFE),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: ChoiceChip(
                              label: const Center(child: Text('Virtually')),
                              selected: _presenceType == 'virtually',
                              onSelected: (_) =>
                                  setState(() => _presenceType = 'virtually'),
                              selectedColor: const Color(0xFFDBEAFE),
                            ),
                          ),
                        ],
                      ),
                      if (_presenceType == 'virtually') ...[
                        const SizedBox(height: 12),
                        TextField(
                          controller: _virtualCtrl,
                          decoration: InputDecoration(
                            labelText: 'Virtual connection details',
                            hintText: 'Zoom / Google Meet link',
                            filled: true,
                            fillColor: Colors.white,
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                        ),
                      ],
                      const SizedBox(height: 16),
                      ...List.generate(3, (i) {
                        final slot = _slots[i];
                        return Container(
                          margin: const EdgeInsets.only(bottom: 10),
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: AppTheme.border),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Slot ${i + 1}',
                                style: const TextStyle(
                                  fontWeight: FontWeight.w800,
                                  color: AppTheme.navy,
                                ),
                              ),
                              ListTile(
                                contentPadding: EdgeInsets.zero,
                                title: Text(
                                  slot.date == null
                                      ? 'Pick date'
                                      : DateFormat('dd MMM yyyy')
                                          .format(slot.date!),
                                ),
                                trailing:
                                    const Icon(Icons.calendar_today_outlined),
                                onTap: () => _pickSlotDate(i),
                              ),
                              Wrap(
                                spacing: 8,
                                children: [
                                  for (final period in const [
                                    {'key': 'morning', 'label': '10 AM'},
                                    {'key': 'afternoon', 'label': '1 PM'},
                                    {'key': 'evening', 'label': '4 PM'},
                                  ])
                                    ChoiceChip(
                                      label: Text(period['label']!),
                                      selected: slot.period == period['key'],
                                      onSelected: (_) => setState(
                                          () => slot.period = period['key']),
                                      selectedColor: const Color(0xFFDBEAFE),
                                    ),
                                ],
                              ),
                            ],
                          ),
                        );
                      }),
                      CheckboxListTile(
                        value: _siteCleaned,
                        onChanged: (v) =>
                            setState(() => _siteCleaned = v ?? false),
                        contentPadding: EdgeInsets.zero,
                        title: const Text(
                          'I confirm the site is cleaned',
                          style: TextStyle(fontWeight: FontWeight.w600),
                        ),
                        activeColor: AppTheme.navy,
                        controlAffinity: ListTileControlAffinity.leading,
                      ),
                      OutlinedButton.icon(
                        onPressed: _pickProof,
                        icon: const Icon(Icons.attach_file),
                        label: Text(
                          _proofFile == null
                              ? 'Attach site cleaned proof'
                              : 'Proof attached',
                        ),
                      ),
                      const SizedBox(height: 12),
                      ElevatedButton(
                        onPressed: _saving ? null : _submit,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppTheme.navy,
                          foregroundColor: Colors.white,
                          minimumSize: const Size.fromHeight(48),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        child:
                            Text(_saving ? 'Submitting…' : 'Submit booking'),
                      ),
                    ] else ...[
                      const SizedBox(height: 16),
                      Text(
                        'A booking has already been submitted. You cannot resubmit.',
                        style: TextStyle(
                          color: AppTheme.getTextSecondary(context),
                        ),
                      ),
                    ],
                  ],
                ),
    );
  }
}

class _SlotDraft {
  DateTime? date;
  String? period;
}

// ── 8. All documents ────────────────────────────────────────────────────────

class _AllDocumentsScreen extends StatefulWidget {
  const _AllDocumentsScreen();

  @override
  State<_AllDocumentsScreen> createState() => _AllDocumentsScreenState();
}

class _AllDocumentsScreenState extends State<_AllDocumentsScreen> {
  final _portal = ClientPortalService();
  bool _loading = true;
  String? _error;
  Map<String, dynamic> _data = {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final result = await _portal.getAllDocuments();
      if (!mounted) return;
      setState(() {
        _loading = false;
        _data = _portal.sectionOf(result);
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = e.toString().replaceFirst('Exception: ', '');
      });
    }
  }

  List<String> _urls(dynamic value) {
    if (value is List) {
      return value
          .map((e) {
            if (e is Map) {
              return (e['view_url'] ?? e['url'] ?? e['download_url'])
                      ?.toString()
                      .trim() ??
                  '';
            }
            return e?.toString().trim() ?? '';
          })
          .where((e) => e.isNotEmpty)
          .toList();
    }
    final single = value?.toString().trim() ?? '';
    return single.isEmpty ? <String>[] : [single];
  }

  Map<String, dynamic> get _docs {
    if (_data['documents'] is Map) {
      return Map<String, dynamic>.from(_data['documents'] as Map);
    }
    return _data;
  }

  @override
  Widget build(BuildContext context) {
    final docs = _docs;
    final proposalUrls = [
      ..._urls(docs['proposal_urls']),
      ..._urls(docs['proposal_url']),
    ];
    final paymentUrls = _urls(docs['payment_screenshot_urls'] ??
        docs['payment_screenshot_url']);
    final kyc = _data['client_kyc_documents'] is List
        ? List.from(_data['client_kyc_documents'] as List)
        : (_data['existing'] is List
            ? List.from(_data['existing'] as List)
            : []);

    return _PortalScaffold(
      title: 'All Documents',
      actions: [
        IconButton(onPressed: _load, icon: const Icon(Icons.refresh_rounded)),
      ],
      body: _loading
          ? const SkeletonListLoader(cardCount: 6)
          : _error != null
              ? _ErrorState(message: _error!, onRetry: _load)
              : ListView(
                  padding: const EdgeInsets.all(20),
                  children: [
                    if (proposalUrls.isEmpty)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: _docTile(context, title: 'Proposal', url: null),
                      )
                    else
                      ...proposalUrls.asMap().entries.map((e) => Padding(
                            padding: const EdgeInsets.only(bottom: 8),
                            child: _docTile(
                              context,
                              title: proposalUrls.length == 1
                                  ? 'Proposal'
                                  : 'Proposal ${e.key + 1}',
                              url: e.value,
                            ),
                          )),
                    ...paymentUrls.asMap().entries.map((e) => Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: _docTile(
                            context,
                            title: paymentUrls.length == 1
                                ? 'Payment screenshot'
                                : 'Payment screenshot ${e.key + 1}',
                            url: e.value,
                            icon: Icons.payments_outlined,
                          ),
                        )),
                    if (paymentUrls.isEmpty)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: _docTile(context,
                            title: 'Payment screenshot',
                            url: null,
                            icon: Icons.payments_outlined),
                      ),
                    ...[
                      {
                        'title': 'Costing sheet',
                        'url': docs['costing_sheet_url'],
                        'icon': Icons.calculate_outlined,
                      },
                      {
                        'title': 'Floor plan',
                        'url': docs['floor_plan_url'],
                        'icon': Icons.map_outlined,
                      },
                      {
                        'title': 'Elevation',
                        'url': docs['elevation_url'],
                        'icon': Icons.apartment_outlined,
                      },
                      {
                        'title': 'Area statement',
                        'url': docs['area_statement_url'],
                        'icon': Icons.square_foot_outlined,
                      },
                      {
                        'title': 'Inspection report',
                        'url': docs['site_inspection_report_url'],
                        'icon': Icons.assignment_outlined,
                      },
                      {
                        'title': 'Drafting agreement',
                        'url': docs['drafting_agreement_url'],
                        'icon': Icons.gavel_outlined,
                      },
                      {
                        'title': 'Soil test report',
                        'url': docs['soil_test_report_url'],
                        'icon': Icons.science_outlined,
                      },
                      {
                        'title': 'Framing drawing',
                        'url': docs['framing_drawing_url'],
                        'icon': Icons.grid_on_outlined,
                      },
                      {
                        'title': 'Booking form',
                        'url': docs['booking_form_url'],
                        'icon': Icons.edit_document,
                      },
                    ].map((entry) => Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: _docTile(
                            context,
                            title: entry['title'] as String,
                            url: entry['url']?.toString(),
                            icon: entry['icon'] as IconData,
                          ),
                        )),
                    const SizedBox(height: 10),
                    const Text(
                      'Client KYC',
                      style: TextStyle(
                        fontWeight: FontWeight.w800,
                        color: AppTheme.navy,
                      ),
                    ),
                    const SizedBox(height: 8),
                    if (kyc.isEmpty)
                      _emptyDocHint(context, 'KYC documents')
                    else
                      ...kyc.map((raw) {
                        final doc = raw is Map
                            ? Map<String, dynamic>.from(raw)
                            : <String, dynamic>{};
                        final title = doc['document_label']?.toString() ??
                            doc['document_type']?.toString() ??
                            doc['doc_type']?.toString() ??
                            doc['name']?.toString() ??
                            'KYC document';
                        final url = doc['view_url']?.toString() ??
                            doc['download_url']?.toString() ??
                            doc['url']?.toString() ??
                            doc['file_url']?.toString();
                        return Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: _docTile(context, title: title, url: url),
                        );
                      }),
                  ],
                ),
    );
  }
}
