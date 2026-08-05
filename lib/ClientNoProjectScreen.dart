import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'app_theme.dart';
import 'NavMenu.dart';
import 'widgets/skeleton_loader.dart';

/// Base URL for sales SOP API
const String _salesSopBaseUrl = 'http://192.168.1.11:5000';

class ClientNoProjectScreen extends StatefulWidget {
  const ClientNoProjectScreen({Key? key}) : super(key: key);

  @override
  State<ClientNoProjectScreen> createState() => _ClientNoProjectScreenState();
}

class _ClientNoProjectScreenState extends State<ClientNoProjectScreen> {
  bool _loading = true;
  String? _error;
  bool _notFound = false;
  Map<String, dynamic>? _project;
  List? _assignedSeniorArchitects;
  List? _assignedArchitects;
  List? _clientKycDocuments;
  String? _clientKycComment;
  Map<String, dynamic>? _siteInspectionBooking;

  @override
  void initState() {
    super.initState();
    _fetchSalesSopDetails();
  }

  Future<void> _fetchSalesSopDetails() async {
    setState(() {
      _loading = true;
      _error = null;
      _notFound = false;
      _project = null;
      _assignedSeniorArchitects = null;
      _assignedArchitects = null;
      _clientKycDocuments = null;
      _clientKycComment = null;
      _siteInspectionBooking = null;
    });

    try {
      final prefs = await SharedPreferences.getInstance();
      final userId = prefs.getString('user_id') ?? prefs.getString('userId');
      final apiToken = prefs.getString('api_token');

      if (userId == null || userId.isEmpty) {
        setState(() {
          _loading = false;
          _error = 'User not found. Please log in again.';
        });
        return;
      }

      if (apiToken == null || apiToken.isEmpty) {
        setState(() {
          _loading = false;
          _error = 'Not authenticated. Please log in again.';
        });
        return;
      }

      // First try without id: backend resolves Sales SOP by client (e.g. by phone) when role is Client
      var uri = Uri.parse('$_salesSopBaseUrl/api/sales_sop_details').replace(
        queryParameters: {'api_token': apiToken},
      );

      var response = await http.get(
        uri,
        headers: {'X-Api-Token': apiToken},
      ).timeout(const Duration(seconds: 15));

      // If backend requires id, retry with user_id (backend may resolve Client by user_id or phone)
      if (response.statusCode == 400) {
        uri = Uri.parse('$_salesSopBaseUrl/api/sales_sop_details').replace(
          queryParameters: {'id': userId, 'api_token': apiToken},
        );
        response = await http.get(
          uri,
          headers: {'X-Api-Token': apiToken},
        ).timeout(const Duration(seconds: 15));
      }

      if (!mounted) return;

      if (response.statusCode == 200) {
        final decoded = jsonDecode(response.body) as Map?;
        if (decoded != null && decoded['success'] == true) {
          Map<String, dynamic>? project;
          if (decoded['project'] is Map) {
            project = Map<String, dynamic>.from(decoded['project'] as Map);
          }
          List senior = [];
          if (decoded['assigned_senior_architects'] is List) {
            senior = List.from(decoded['assigned_senior_architects'] as List);
          }
          List arch = [];
          if (decoded['assigned_architects'] is List) {
            arch = List.from(decoded['assigned_architects'] as List);
          }
          List kycDocs = [];
          if (decoded['client_kyc_documents'] is List) {
            kycDocs = List.from(decoded['client_kyc_documents'] as List);
          }
          final kycComment = decoded['client_kyc_comment']?.toString();
          Map<String, dynamic>? sib;
          if (decoded['site_inspection_booking'] is Map) {
            sib = Map<String, dynamic>.from(decoded['site_inspection_booking'] as Map);
          }

          setState(() {
            _loading = false;
            _project = project;
            _assignedSeniorArchitects = senior;
            _assignedArchitects = arch;
            _clientKycDocuments = kycDocs;
            _clientKycComment = kycComment;
            _siteInspectionBooking = sib;
          });
          return;
        }
      }

      if (response.statusCode == 404) {
        setState(() {
          _loading = false;
          _notFound = true;
        });
        return;
      }

      String message = 'Unable to load details (${response.statusCode})';
      try {
        final body = jsonDecode(response.body);
        if (body is Map && body['message'] != null) {
          message = body['message'].toString();
        }
      } catch (_) {}

      setState(() {
        _loading = false;
        _error = message;
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
    return Scaffold(
      backgroundColor: AppTheme.getBackgroundPrimary(context),
      drawer: NavMenuWidget(),
      appBar: AppBar(
        backgroundColor: AppTheme.getBackgroundSecondary(context),
        foregroundColor: AppTheme.navy,
        elevation: 0,
        title: const Text(
          'Project Dashboard',
          style: TextStyle(
            color: AppTheme.navy,
            fontSize: 18,
            fontWeight: FontWeight.w800,
          ),
        ),
        iconTheme: const IconThemeData(color: AppTheme.navy),
        actionsIconTheme: const IconThemeData(color: AppTheme.navy),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh, color: AppTheme.navy),
            onPressed: _loading ? null : _fetchSalesSopDetails,
          ),
        ],
      ),
      body: SafeArea(
        child: _buildBody(),
      ),
    );
  }

  Widget _buildBody() {
    if (_loading) {
      return const SkeletonListLoader(cardCount: 4);
    }

    if (_error != null) {
      return Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.error_outline, size: 64, color: Colors.red),
              SizedBox(height: 16),
              Text('Error loading data', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: AppTheme.getTextPrimary(context))),
              SizedBox(height: 8),
              Text(_error!, textAlign: TextAlign.center, style: TextStyle(color: AppTheme.getTextSecondary(context))),
              SizedBox(height: 24),
              ElevatedButton.icon(
                onPressed: _fetchSalesSopDetails,
                icon: Icon(Icons.refresh),
                label: Text('Retry'),
                style: ElevatedButton.styleFrom(backgroundColor: AppTheme.getPrimaryColor(context)),
              ),
            ],
          ),
        ),
      );
    }

    if (_notFound || _project == null) {
      return Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.home_work_outlined, size: 80, color: AppTheme.getPrimaryColor(context).withOpacity(0.5)),
              SizedBox(height: 24),
              Text('No Project Assigned', style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: AppTheme.getTextPrimary(context))),
              SizedBox(height: 12),
              Text('Please contact your administrator to get linked to a project.', textAlign: TextAlign.center, style: TextStyle(fontSize: 16, color: AppTheme.getTextSecondary(context))),
            ],
          ),
        ),
      );
    }

    return SingleChildScrollView(
      child: Padding(
        padding: EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _buildStatusCard(),
            SizedBox(height: 24),
            _buildNavigationGrid(),
          ],
        ),
      ),
    );
  }

  Widget _buildStatusCard() {
    final p = _project!;
    final statusLabel = _statusLabel(p);
    final statusColor = _statusColor(context, p);

    final steps = [
      {'label': 'Elevation', 'completed': p['finalize_elevation_completed'] == true},
      {'label': 'Costing', 'completed': p['send_costing_completed'] == true},
      {'label': 'Approved', 'completed': p['is_approved'] == true},
      {'label': 'Converted', 'completed': p['is_converted'] == true},
    ];

    int completedCount = steps.where((s) => s['completed'] == true).length;
    double progress = completedCount / steps.length;

    return Container(
      padding: EdgeInsets.all(24),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [statusColor.withOpacity(0.15), statusColor.withOpacity(0.05)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: statusColor.withOpacity(0.3), width: 2),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: EdgeInsets.all(12),
                decoration: BoxDecoration(color: statusColor.withOpacity(0.2), borderRadius: BorderRadius.circular(12)),
                child: Icon(_statusIcon(p), color: statusColor, size: 28),
              ),
              SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Project Status', style: TextStyle(color: AppTheme.getTextSecondary(context), fontSize: 14, fontWeight: FontWeight.w500)),
                    SizedBox(height: 4),
                    Text(statusLabel, style: TextStyle(color: statusColor, fontSize: 24, fontWeight: FontWeight.bold)),
                  ],
                ),
              ),
            ],
          ),
          SizedBox(height: 20),
          Row(
            children: [
              Expanded(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(10),
                  child: LinearProgressIndicator(
                    value: progress,
                    backgroundColor: AppTheme.getTextSecondary(context).withOpacity(0.3),
                    valueColor: AlwaysStoppedAnimation<Color>(statusColor),
                    minHeight: 8,
                  ),
                ),
              ),
              SizedBox(width: 12),
              Text('${(progress * 100).toInt()}%', style: TextStyle(color: AppTheme.getTextPrimary(context), fontWeight: FontWeight.bold, fontSize: 16)),
            ],
          ),
          SizedBox(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: steps.map((step) {
              return Expanded(
                child: Column(
                  children: [
                    Icon(
                      step['completed'] == true ? Icons.check_circle : Icons.radio_button_unchecked,
                      size: 24,
                      color: step['completed'] == true ? statusColor : AppTheme.getTextSecondary(context).withOpacity(0.6),
                    ),
                    SizedBox(height: 6),
                    Text(
                      step['label'] as String,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: step['completed'] == true ? AppTheme.getTextPrimary(context) : AppTheme.getTextSecondary(context),
                        fontSize: 11,
                        fontWeight: step['completed'] == true ? FontWeight.w600 : FontWeight.normal,
                      ),
                    ),
                  ],
                ),
              );
            }).toList(),
          ),
        ],
      ),
    );
  }

  Widget _buildNavigationGrid() {
    final p = _project!;
    List<Widget> cards = [];

    cards.add(_buildNavCard(
      icon: Icons.info_outline,
      label: 'Project\nInfo',
      color: AppTheme.getPrimaryColor(context),
      onTap: () => _showProjectInfo(),
    ));

    if (_clientKycDocuments != null && _clientKycDocuments!.isNotEmpty) {
      cards.add(_buildNavCard(
        icon: Icons.folder_outlined,
        label: 'Client KYC\nDocuments',
        color: AppTheme.getPrimaryColor(context),
        badge: '${_clientKycDocuments!.length}',
        onTap: () => _showKycDocuments(),
      ));
    }

    cards.add(_buildDocumentNavCard(
      icon: Icons.article_outlined,
      label: 'Proposal',
      color: AppTheme.getPrimaryColor(context),
      url: p['proposal_url'],
    ));

    cards.add(_buildDocumentNavCard(
      icon: Icons.receipt_long_outlined,
      label: 'Payment\nScreenshot',
      color: AppTheme.getPrimaryColor(context),
      url: p['payment_screenshot_url'],
    ));

    cards.add(_buildInAppDocumentNavCard(
      icon: Icons.square_foot_outlined,
      label: 'Area\nStatement',
      color: AppTheme.getPrimaryColor(context),
      url: p['area_statement_url'],
    ));

    cards.add(_buildInAppDocumentNavCard(
      icon: Icons.calculate_outlined,
      label: 'Costing\nSheet',
      color: AppTheme.getPrimaryColor(context),
      url: p['costing_sheet_url'],
    ));

    if (p['public_link_url'] != null) {
      cards.add(_buildNavCard(
        icon: Icons.cloud_upload_outlined,
        label: 'Upload\nDocuments',
        color: AppTheme.getPrimaryColor(context),
        onTap: () => _openUrl(p['public_link_url'].toString()),
      ));
    }

    if (_siteInspectionBooking != null) {
      cards.add(_buildNavCard(
        icon: Icons.event_outlined,
        label: 'Site\nInspection',
        color: AppTheme.getPrimaryColor(context),
        onTap: () => _showSiteInspection(),
      ));
    }

    if (p['site_inspection_url'] != null) {
      cards.add(_buildNavCard(
        icon: Icons.calendar_month_outlined,
        label: 'Book Site\nVisit',
        color: AppTheme.getPrimaryColor(context),
        onTap: () => _openUrl(p['site_inspection_url'].toString()),
      ));
    }

    if (p['location'] != null && p['location'].toString().isNotEmpty) {
      cards.add(_buildNavCard(
        icon: Icons.location_on_outlined,
        label: 'Project\nLocation',
        color: AppTheme.getPrimaryColor(context),
        onTap: () => _openUrl(p['location'].toString()),
      ));
    }

    cards.add(_buildNavCard(
      icon: Icons.payments_outlined,
      label: 'Financial\nDetails',
      color: AppTheme.getPrimaryColor(context),
      onTap: () => _showFinancialDetails(),
    ));

    if ((_assignedSeniorArchitects != null && _assignedSeniorArchitects!.isNotEmpty) ||
        (_assignedArchitects != null && _assignedArchitects!.isNotEmpty)) {
      cards.add(_buildNavCard(
        icon: Icons.groups_outlined,
        label: 'Project\nTeam',
        color: AppTheme.getPrimaryColor(context),
        onTap: () => _showTeam(),
      ));
    }

    return GridView.count(
      shrinkWrap: true,
      physics: NeverScrollableScrollPhysics(),
      crossAxisCount: 3,
      mainAxisSpacing: 12,
      crossAxisSpacing: 12,
      children: cards,
    );
  }

  Widget _buildNavCard({
    required IconData icon,
    required String label,
    required Color color,
    required VoidCallback onTap,
    String? badge,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        decoration: BoxDecoration(
          color: AppTheme.getBackgroundSecondary(context),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: color.withOpacity(0.3), width: 1.5),
          boxShadow: [BoxShadow(color: AppTheme.getTextPrimary(context).withOpacity(0.06), blurRadius: 8, offset: Offset(0, 2))],
        ),
        child: Stack(
          children: [
            Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  padding: EdgeInsets.all(12),
                  decoration: BoxDecoration(color: color.withOpacity(0.15), borderRadius: BorderRadius.circular(12)),
                  child: Icon(icon, color: color, size: 28),
                ),
                SizedBox(height: 8),
                Padding(
                  padding: EdgeInsets.symmetric(horizontal: 4),
                  child: Text(
                    label,
                    textAlign: TextAlign.center,
                    style: TextStyle(color: AppTheme.getTextPrimary(context), fontSize: 12, fontWeight: FontWeight.w600, height: 1.2),
                  ),
                ),
              ],
            ),
            if (badge != null)
              Positioned(
                top: 8,
                right: 8,
                child: Container(
                  padding: EdgeInsets.all(4),
                  decoration: BoxDecoration(color: color, shape: BoxShape.circle),
                  child: Text(badge, style: TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold)),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildDocumentNavCard({
    required IconData icon,
    required String label,
    required Color color,
    String? url,
  }) {
    final hasDocument = url != null && url.toString().trim().isNotEmpty;
    return InkWell(
      onTap: () {
        if (hasDocument) {
          _showDocumentViewer(label, url!.trim());
        } else {
          _showNotUploaded(label);
        }
      },
      borderRadius: BorderRadius.circular(16),
      child: Container(
        decoration: BoxDecoration(
          color: AppTheme.getBackgroundSecondary(context),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: color.withOpacity(0.3), width: 1.5),
          boxShadow: [BoxShadow(color: AppTheme.getTextPrimary(context).withOpacity(0.06), blurRadius: 8, offset: Offset(0, 2))],
        ),
        child: Stack(
          children: [
            Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  padding: EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: hasDocument ? color.withOpacity(0.15) : AppTheme.getTextSecondary(context).withOpacity(0.15),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(icon, color: hasDocument ? color : AppTheme.getTextSecondary(context), size: 28),
                ),
                SizedBox(height: 8),
                Padding(
                  padding: EdgeInsets.symmetric(horizontal: 4),
                  child: Text(
                    label,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: hasDocument ? AppTheme.getTextPrimary(context) : AppTheme.getTextSecondary(context),
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      height: 1.2,
                    ),
                  ),
                ),
              ],
            ),
            if (hasDocument)
              Positioned(top: 8, right: 8, child: Container(padding: EdgeInsets.all(4), decoration: BoxDecoration(color: color, shape: BoxShape.circle), child: Icon(Icons.check, color: Colors.white, size: 12)))
            else
              Positioned(top: 8, right: 8, child: Container(padding: EdgeInsets.all(4), decoration: BoxDecoration(color: AppTheme.getTextSecondary(context), shape: BoxShape.circle), child: Icon(Icons.close, color: Colors.white, size: 12))),
          ],
        ),
      ),
    );
  }

  Widget _buildInAppDocumentNavCard({
    required IconData icon,
    required String label,
    required Color color,
    String? url,
  }) {
    final hasDocument = url != null && url.toString().trim().isNotEmpty;
    return InkWell(
      onTap: () {
        if (hasDocument) {
          _showInAppDocument(label, url!.trim());
        } else {
          _showNotUploaded(label);
        }
      },
      borderRadius: BorderRadius.circular(16),
      child: Container(
        decoration: BoxDecoration(
          color: AppTheme.getBackgroundSecondary(context),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: color.withOpacity(0.3), width: 1.5),
          boxShadow: [BoxShadow(color: AppTheme.getTextPrimary(context).withOpacity(0.06), blurRadius: 8, offset: Offset(0, 2))],
        ),
        child: Stack(
          children: [
            Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  padding: EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: hasDocument ? color.withOpacity(0.15) : AppTheme.getTextSecondary(context).withOpacity(0.15),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(icon, color: hasDocument ? color : AppTheme.getTextSecondary(context), size: 28),
                ),
                SizedBox(height: 8),
                Padding(
                  padding: EdgeInsets.symmetric(horizontal: 4),
                  child: Text(
                    label,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: hasDocument ? AppTheme.getTextPrimary(context) : AppTheme.getTextSecondary(context),
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      height: 1.2,
                    ),
                  ),
                ),
              ],
            ),
            if (hasDocument)
              Positioned(top: 8, right: 8, child: Container(padding: EdgeInsets.all(4), decoration: BoxDecoration(color: color, shape: BoxShape.circle), child: Icon(Icons.check, color: Colors.white, size: 12)))
            else
              Positioned(top: 8, right: 8, child: Container(padding: EdgeInsets.all(4), decoration: BoxDecoration(color: AppTheme.getTextSecondary(context), shape: BoxShape.circle), child: Icon(Icons.close, color: Colors.white, size: 12))),
          ],
        ),
      ),
    );
  }

  void _showProjectInfo() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => _ProjectInfoSheet(project: _project!, clientKycComment: _clientKycComment),
    );
  }

  void _showKycDocuments() {
    if (_clientKycDocuments == null || _clientKycDocuments!.isEmpty) return;
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => _KycDocumentsSheet(
        documents: _clientKycDocuments!,
        onDocumentTap: (doc) {
          Navigator.pop(context);
          _showDocument(doc);
        },
      ),
    );
  }

  void _showDocument(Map doc) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => _SingleDocumentSheet(document: doc, onOpenUrl: (url) => _openUrl(url)),
    );
  }

  void _showDocumentViewer(String title, String url) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => _DocumentViewerSheet(title: title, url: url, onOpen: () => _openUrl(url)),
    );
  }

  void _showInAppDocument(String title, String url) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => _InAppDocumentScreen(title: title, url: url),
      ),
    );
  }

  void _showNotUploaded(String documentName) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(documentName),
        content: Text('This document has not been uploaded yet.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: Text('OK')),
        ],
      ),
    );
  }

  void _showSiteInspection() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => _SiteInspectionSheet(inspection: _siteInspectionBooking),
    );
  }

  void _showFinancialDetails() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => _FinancialSheet(project: _project!),
    );
  }

  void _showTeam() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => _TeamSheet(seniorArchitects: _assignedSeniorArchitects, architects: _assignedArchitects),
    );
  }

  Future<void> _openUrl(String url) async {
    final trimmed = url.trim();
    if (trimmed.isEmpty) return;
    final uri = Uri.tryParse(trimmed);
    if (uri == null) return;
    try {
      await launchUrl(uri, mode: LaunchMode.platformDefault);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not open link'), backgroundColor: Colors.red),
        );
      }
    }
  }

  String _statusLabel(Map p) {
    if (p['is_converted'] == true) return 'Converted';
    if (p['is_approved'] == true) return 'Approved';
    if (p['send_costing_completed'] == true) return 'Costing Sent';
    if (p['finalize_elevation_completed'] == true) return 'Elevation Finalized';
    return 'In Progress';
  }

  Color _statusColor(BuildContext context, Map p) {
    final primary = AppTheme.getPrimaryColor(context);
    if (p['is_converted'] == true) return primary;
    if (p['is_approved'] == true) return primary;
    if (p['send_costing_completed'] == true) return primary;
    if (p['finalize_elevation_completed'] == true) return primary;
    return AppTheme.getTextSecondary(context).withOpacity(0.7);
  }

  IconData _statusIcon(Map p) {
    if (p['is_converted'] == true) return Icons.check_circle;
    if (p['is_approved'] == true) return Icons.verified;
    if (p['send_costing_completed'] == true) return Icons.calculate;
    if (p['finalize_elevation_completed'] == true) return Icons.architecture;
    return Icons.pending;
  }
}

// --- Sheet widgets ---

class _ProjectInfoSheet extends StatelessWidget {
  final Map<String, dynamic> project;
  final String? clientKycComment;

  const _ProjectInfoSheet({required this.project, this.clientKycComment});

  @override
  Widget build(BuildContext context) {
    final primary = AppTheme.getPrimaryColor(context);
    return DraggableScrollableSheet(
      initialChildSize: 0.9,
      minChildSize: 0.5,
      maxChildSize: 0.95,
      builder: (context, scrollController) {
        return Container(
          decoration: BoxDecoration(
            color: AppTheme.getBackgroundPrimary(context),
            borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
          ),
          child: Column(
            children: [
              _buildSheetHeader(context, Icons.info_outline, 'Project Information', primary),
              Expanded(
                child: ListView(
                  controller: scrollController,
                  padding: EdgeInsets.all(16),
                  children: [
                    _buildInfoCard(context, 'Project ID', project['project_id']?.toString(), Icons.tag),
                    _buildInfoCard(context, 'Client Name', project['client_name'], Icons.person),
                    _buildInfoCard(context, 'Phone', project['phone'], Icons.phone),
                    _buildInfoCard(context, 'Email', project['email'], Icons.email),
                    _buildInfoCard(context, 'Package', project['package'], Icons.inventory_2),
                    if (project['total_built_up_area'] != null) _buildInfoCard(context, 'Built-up Area', '${project['total_built_up_area']} sq.ft', Icons.square_foot),
                    if (project['no_of_floors'] != null) _buildInfoCard(context, 'No. of Floors', project['no_of_floors'].toString(), Icons.layers),
                    _buildInfoCard(context, 'Created By', project['created_by'], Icons.account_circle),
                    _buildInfoCard(context, 'Created At', project['created_at'], Icons.calendar_today),
                    if (project['initial_discussion_comments'] != null && project['initial_discussion_comments'].toString().isNotEmpty)
                      _buildInfoCard(context, 'Comments', project['initial_discussion_comments'], Icons.comment),
                    if (clientKycComment != null && clientKycComment!.trim().isNotEmpty)
                      _buildInfoCard(context, 'Client KYC Comment', clientKycComment!, Icons.comment_outlined),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildSheetHeader(BuildContext context, IconData icon, String title, Color color) {
    return Container(
      padding: EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.getBackgroundSecondary(context),
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: Column(
        children: [
          Container(width: 40, height: 4, decoration: BoxDecoration(color: AppTheme.getTextSecondary(context).withOpacity(0.5), borderRadius: BorderRadius.circular(2))),
          SizedBox(height: 16),
          Row(
            children: [
              Container(
                padding: EdgeInsets.all(10),
                decoration: BoxDecoration(color: color.withOpacity(0.15), borderRadius: BorderRadius.circular(10)),
                child: Icon(icon, color: color, size: 24),
              ),
              SizedBox(width: 12),
              Expanded(child: Text(title, style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: AppTheme.getTextPrimary(context)))),
              IconButton(icon: Icon(Icons.close, color: AppTheme.getTextPrimary(context)), onPressed: () => Navigator.pop(context)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildInfoCard(BuildContext context, String label, String? value, IconData icon) {
    if (value == null || value.isEmpty) return SizedBox.shrink();
    final primary = AppTheme.getPrimaryColor(context);
    return Container(
      margin: EdgeInsets.only(bottom: 12),
      padding: EdgeInsets.all(16),
      decoration: BoxDecoration(color: AppTheme.getBackgroundSecondary(context), borderRadius: BorderRadius.circular(12)),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 20, color: primary),
          SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: TextStyle(fontSize: 12, color: AppTheme.getTextSecondary(context))),
                SizedBox(height: 4),
                Text(value, style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: AppTheme.getTextPrimary(context))),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _KycDocumentsSheet extends StatelessWidget {
  final List documents;
  final void Function(Map doc) onDocumentTap;

  const _KycDocumentsSheet({required this.documents, required this.onDocumentTap});

  @override
  Widget build(BuildContext context) {
    final primary = AppTheme.getPrimaryColor(context);
    final list = documents.where((e) => e is Map).cast<Map>().toList();
    return DraggableScrollableSheet(
      initialChildSize: 0.6,
      minChildSize: 0.4,
      maxChildSize: 0.9,
      builder: (context, scrollController) {
        return Container(
          decoration: BoxDecoration(
            color: AppTheme.getBackgroundPrimary(context),
            borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
          ),
          child: Column(
            children: [
              _buildSheetHeader(context, Icons.folder_outlined, 'Client KYC Documents', primary),
              Expanded(
                child: ListView.builder(
                  controller: scrollController,
                  padding: EdgeInsets.fromLTRB(16, 0, 16, 24),
                  itemCount: list.length,
                  itemBuilder: (context, index) {
                    final doc = list[index];
                    final label = doc['document_label'] ?? doc['document_type'] ?? 'Document';
                    final uploadedAt = doc['uploaded_at_display']?.toString() ?? '';
                    return Card(
                      margin: EdgeInsets.only(bottom: 10),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      color: AppTheme.getBackgroundSecondary(context),
                      child: InkWell(
                        onTap: () => onDocumentTap(doc),
                        borderRadius: BorderRadius.circular(12),
                        child: Padding(
                          padding: EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                          child: Row(
                            children: [
                              Container(
                                padding: EdgeInsets.all(10),
                                decoration: BoxDecoration(
                                  color: primary.withOpacity(0.15),
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: Icon(Icons.description_outlined, color: primary, size: 24),
                              ),
                              SizedBox(width: 14),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      label,
                                      style: TextStyle(
                                        fontSize: 16,
                                        fontWeight: FontWeight.w600,
                                        color: AppTheme.getTextPrimary(context),
                                      ),
                                    ),
                                    if (uploadedAt.isNotEmpty)
                                      Padding(
                                        padding: EdgeInsets.only(top: 4),
                                        child: Text(
                                          'Uploaded: $uploadedAt',
                                          style: TextStyle(fontSize: 12, color: AppTheme.getTextSecondary(context)),
                                        ),
                                      ),
                                  ],
                                ),
                              ),
                              Icon(Icons.chevron_right, color: AppTheme.getTextSecondary(context)),
                            ],
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildSheetHeader(BuildContext context, IconData icon, String title, Color color) {
    return Container(
      padding: EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.getBackgroundSecondary(context),
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: Column(
        children: [
          Container(width: 40, height: 4, decoration: BoxDecoration(color: AppTheme.getTextSecondary(context).withOpacity(0.5), borderRadius: BorderRadius.circular(2))),
          SizedBox(height: 16),
          Row(
            children: [
              Container(
                padding: EdgeInsets.all(10),
                decoration: BoxDecoration(color: color.withOpacity(0.15), borderRadius: BorderRadius.circular(10)),
                child: Icon(icon, color: color, size: 24),
              ),
              SizedBox(width: 12),
              Expanded(child: Text(title, style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: AppTheme.getTextPrimary(context)))),
              IconButton(icon: Icon(Icons.close, color: AppTheme.getTextPrimary(context)), onPressed: () => Navigator.pop(context)),
            ],
          ),
        ],
      ),
    );
  }
}

class _SingleDocumentSheet extends StatelessWidget {
  final Map document;
  final void Function(String url) onOpenUrl;

  const _SingleDocumentSheet({required this.document, required this.onOpenUrl});

  @override
  Widget build(BuildContext context) {
    final label = document['document_label'] ?? document['document_type'] ?? 'Document';
    final uploadedAt = document['uploaded_at_display'] ?? '';
    final viewUrl = document['view_url']?.toString();
    final downloadUrl = document['download_url']?.toString();
    final primary = AppTheme.getPrimaryColor(context);
    return DraggableScrollableSheet(
      initialChildSize: 0.4,
      minChildSize: 0.3,
      maxChildSize: 0.6,
      builder: (context, scrollController) {
        return Container(
          decoration: BoxDecoration(
            color: AppTheme.getBackgroundPrimary(context),
            borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
          ),
          child: Column(
            children: [
              Container(
                padding: EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: AppTheme.getBackgroundSecondary(context),
                  borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
                ),
                child: Column(
                  children: [
                    Container(width: 40, height: 4, decoration: BoxDecoration(color: AppTheme.getTextSecondary(context).withOpacity(0.5), borderRadius: BorderRadius.circular(2))),
                    SizedBox(height: 16),
                    Row(
                      children: [
                        Container(
                          padding: EdgeInsets.all(10),
                          decoration: BoxDecoration(color: primary.withOpacity(0.15), borderRadius: BorderRadius.circular(10)),
                          child: Icon(Icons.description, color: primary, size: 24),
                        ),
                        SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(label, style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: AppTheme.getTextPrimary(context))),
                              if (uploadedAt.isNotEmpty) Text('Uploaded: $uploadedAt', style: TextStyle(fontSize: 12, color: AppTheme.getTextSecondary(context))),
                            ],
                          ),
                        ),
                        IconButton(icon: Icon(Icons.close, color: AppTheme.getTextPrimary(context)), onPressed: () => Navigator.pop(context)),
                      ],
                    ),
                  ],
                ),
              ),
              Expanded(
                child: Padding(
                  padding: EdgeInsets.all(16),
                  child: Column(
                    children: [
                      if (viewUrl != null && viewUrl.isNotEmpty)
                        SizedBox(
                          width: double.infinity,
                          child: ElevatedButton.icon(
                            onPressed: () {
                              Navigator.pop(context);
                              onOpenUrl(viewUrl);
                            },
                            icon: Icon(Icons.visibility),
                            label: Text('View Document'),
                            style: ElevatedButton.styleFrom(backgroundColor: primary, foregroundColor: Colors.white, padding: EdgeInsets.all(16)),
                          ),
                        ),
                      SizedBox(height: 12),
                      if (downloadUrl != null && downloadUrl.isNotEmpty)
                        SizedBox(
                          width: double.infinity,
                          child: OutlinedButton.icon(
                            onPressed: () {
                              Navigator.pop(context);
                              onOpenUrl(downloadUrl);
                            },
                            icon: Icon(Icons.download),
                            label: Text('Download Document'),
                            style: OutlinedButton.styleFrom(foregroundColor: primary, side: BorderSide(color: primary), padding: EdgeInsets.all(16)),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _DocumentViewerSheet extends StatelessWidget {
  final String title;
  final String url;
  final VoidCallback onOpen;

  const _DocumentViewerSheet({required this.title, required this.url, required this.onOpen});

  @override
  Widget build(BuildContext context) {
    final primary = AppTheme.getPrimaryColor(context);
    return DraggableScrollableSheet(
      initialChildSize: 0.4,
      minChildSize: 0.3,
      maxChildSize: 0.6,
      builder: (context, scrollController) {
        return Container(
          decoration: BoxDecoration(
            color: AppTheme.getBackgroundPrimary(context),
            borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
          ),
          child: Column(
            children: [
              Container(
                padding: EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: AppTheme.getBackgroundSecondary(context),
                  borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
                ),
                child: Column(
                  children: [
                    Container(width: 40, height: 4, decoration: BoxDecoration(color: AppTheme.getTextSecondary(context).withOpacity(0.5), borderRadius: BorderRadius.circular(2))),
                    SizedBox(height: 16),
                    Row(
                      children: [
                        Container(
                          padding: EdgeInsets.all(10),
                          decoration: BoxDecoration(color: primary.withOpacity(0.15), borderRadius: BorderRadius.circular(10)),
                          child: Icon(Icons.article, color: primary, size: 24),
                        ),
                        SizedBox(width: 12),
                        Expanded(child: Text(title, style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: AppTheme.getTextPrimary(context)))),
                        IconButton(icon: Icon(Icons.close, color: AppTheme.getTextPrimary(context)), onPressed: () => Navigator.pop(context)),
                      ],
                    ),
                  ],
                ),
              ),
              Expanded(
                child: Padding(
                  padding: EdgeInsets.all(16),
                  child: Column(
                    children: [
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton.icon(
                          onPressed: () {
                            Navigator.pop(context);
                            onOpen();
                          },
                          icon: Icon(Icons.open_in_new),
                          label: Text('Open Document'),
                          style: ElevatedButton.styleFrom(backgroundColor: primary, foregroundColor: Colors.white, padding: EdgeInsets.all(16)),
                        ),
                      ),
                      SizedBox(height: 12),
                      Text('This will open the document in your browser or app', textAlign: TextAlign.center, style: TextStyle(fontSize: 12, color: AppTheme.getTextSecondary(context))),
                    ],
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _SiteInspectionSheet extends StatelessWidget {
  final Map<String, dynamic>? inspection;

  const _SiteInspectionSheet({this.inspection});

  @override
  Widget build(BuildContext context) {
    if (inspection == null) {
      return Container(
        height: 200,
        decoration: BoxDecoration(color: AppTheme.getBackgroundPrimary(context), borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
        child: Center(child: Text('No inspection data', style: TextStyle(color: AppTheme.getTextSecondary(context)))),
      );
    }
    final primary = AppTheme.getPrimaryColor(context);
    return DraggableScrollableSheet(
      initialChildSize: 0.6,
      minChildSize: 0.4,
      maxChildSize: 0.85,
      builder: (context, scrollController) {
        return Container(
          decoration: BoxDecoration(color: AppTheme.getBackgroundPrimary(context), borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
          child: Column(
            children: [
              _buildSheetHeader(context, primary),
              Expanded(
                child: ListView(
                  controller: scrollController,
                  padding: EdgeInsets.all(16),
                  children: [
                    _buildInfoCard(context, Icons.location_on_outlined, 'Presence Type', inspection!['presence_type']?.toString().replaceAll('_', ' ').toUpperCase() ?? 'N/A'),
                    if (inspection!['slot1_display'] != null) _buildInfoCard(context, Icons.schedule_outlined, 'Slot 1', inspection!['slot1_display']),
                    if (inspection!['slot2_display'] != null) _buildInfoCard(context, Icons.schedule_outlined, 'Slot 2', inspection!['slot2_display']),
                    if (inspection!['slot3_display'] != null) _buildInfoCard(context, Icons.schedule_outlined, 'Slot 3', inspection!['slot3_display']),
                    if (inspection!['submitted_at_display'] != null) _buildInfoCard(context, Icons.check_circle_outline, 'Submitted', inspection!['submitted_at_display']),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildSheetHeader(BuildContext context, Color primary) {
    return Container(
      padding: EdgeInsets.all(16),
      decoration: BoxDecoration(color: AppTheme.getBackgroundSecondary(context), borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      child: Column(
        children: [
          Container(width: 40, height: 4, decoration: BoxDecoration(color: AppTheme.getTextSecondary(context).withOpacity(0.5), borderRadius: BorderRadius.circular(2))),
          SizedBox(height: 16),
          Row(
            children: [
              Container(padding: EdgeInsets.all(10), decoration: BoxDecoration(color: primary.withOpacity(0.15), borderRadius: BorderRadius.circular(10)), child: Icon(Icons.event, color: primary, size: 24)),
              SizedBox(width: 12),
              Expanded(child: Text('Site Inspection', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: AppTheme.getTextPrimary(context)))),
              IconButton(icon: Icon(Icons.close, color: AppTheme.getTextPrimary(context)), onPressed: () => Navigator.pop(context)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildInfoCard(BuildContext context, IconData icon, String label, String value) {
    final primary = AppTheme.getPrimaryColor(context);
    return Container(
      margin: EdgeInsets.only(bottom: 12),
      padding: EdgeInsets.all(16),
      decoration: BoxDecoration(color: AppTheme.getBackgroundSecondary(context), borderRadius: BorderRadius.circular(12)),
      child: Row(
        children: [
          Icon(icon, color: primary, size: 24),
          SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: TextStyle(fontSize: 12, color: AppTheme.getTextSecondary(context))),
                SizedBox(height: 4),
                Text(value, style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: AppTheme.getTextPrimary(context))),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _FinancialSheet extends StatelessWidget {
  final Map<String, dynamic> project;

  const _FinancialSheet({required this.project});

  String _formatNumber(dynamic value) {
    if (value == null) return '0';
    if (value is num) {
      if (value >= 10000000) return '${(value / 10000000).toStringAsFixed(2)} Cr';
      if (value >= 100000) return '${(value / 100000).toStringAsFixed(2)} L';
      if (value >= 1000) return '${(value / 1000).toStringAsFixed(2)} K';
      return value.toStringAsFixed(0);
    }
    return value.toString();
  }

  @override
  Widget build(BuildContext context) {
    final primary = AppTheme.getPrimaryColor(context);
    return DraggableScrollableSheet(
      initialChildSize: 0.6,
      minChildSize: 0.4,
      maxChildSize: 0.85,
      builder: (context, scrollController) {
        return Container(
          decoration: BoxDecoration(color: AppTheme.getBackgroundPrimary(context), borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
          child: Column(
            children: [
              _buildSheetHeader(context, primary),
              Expanded(
                child: ListView(
                  controller: scrollController,
                  padding: EdgeInsets.all(16),
                  children: [
                    Row(
                      children: [
                        Expanded(child: _buildFinancialCard(context, 'Total Value', '₹${_formatNumber(project['value'])}', Icons.currency_rupee)),
                        SizedBox(width: 12),
                        Expanded(child: _buildFinancialCard(context, 'Received', '₹${_formatNumber(project['amount_received'])}', Icons.check_circle_outline)),
                      ],
                    ),
                    SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(child: _buildFinancialCard(context, 'Percentage', '${project['amount_received_percentage'] ?? 0}%', Icons.percent)),
                        SizedBox(width: 12),
                        Expanded(child: _buildFinancialCard(context, 'Discount', '₹${_formatNumber(project['discount_offered'])}', Icons.local_offer_outlined)),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildSheetHeader(BuildContext context, Color primary) {
    return Container(
      padding: EdgeInsets.all(16),
      decoration: BoxDecoration(color: AppTheme.getBackgroundSecondary(context), borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      child: Column(
        children: [
          Container(width: 40, height: 4, decoration: BoxDecoration(color: AppTheme.getTextSecondary(context).withOpacity(0.5), borderRadius: BorderRadius.circular(2))),
          SizedBox(height: 16),
          Row(
            children: [
              Container(padding: EdgeInsets.all(10), decoration: BoxDecoration(color: primary.withOpacity(0.15), borderRadius: BorderRadius.circular(10)), child: Icon(Icons.payments_outlined, color: primary, size: 24)),
              SizedBox(width: 12),
              Expanded(child: Text('Financial Details', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: AppTheme.getTextPrimary(context)))),
              IconButton(icon: Icon(Icons.close, color: AppTheme.getTextPrimary(context)), onPressed: () => Navigator.pop(context)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildFinancialCard(BuildContext context, String label, String value, IconData icon) {
    final primary = AppTheme.getPrimaryColor(context);
    return Container(
      padding: EdgeInsets.all(16),
      decoration: BoxDecoration(color: primary.withOpacity(0.1), borderRadius: BorderRadius.circular(12), border: Border.all(color: primary.withOpacity(0.3))),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: primary, size: 24),
          SizedBox(height: 12),
          Text(label, style: TextStyle(fontSize: 12, color: AppTheme.getTextSecondary(context))),
          SizedBox(height: 4),
          Text(value, style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: AppTheme.getTextPrimary(context))),
        ],
      ),
    );
  }
}

class _TeamSheet extends StatelessWidget {
  final List? seniorArchitects;
  final List? architects;

  const _TeamSheet({this.seniorArchitects, this.architects});

  @override
  Widget build(BuildContext context) {
    final primary = AppTheme.getPrimaryColor(context);
    return DraggableScrollableSheet(
      initialChildSize: 0.5,
      minChildSize: 0.3,
      maxChildSize: 0.75,
      builder: (context, scrollController) {
        return Container(
          decoration: BoxDecoration(color: AppTheme.getBackgroundPrimary(context), borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
          child: Column(
            children: [
              Container(
                padding: EdgeInsets.all(16),
                decoration: BoxDecoration(color: AppTheme.getBackgroundSecondary(context), borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
                child: Column(
                  children: [
                    Container(width: 40, height: 4, decoration: BoxDecoration(color: AppTheme.getTextSecondary(context).withOpacity(0.5), borderRadius: BorderRadius.circular(2))),
                    SizedBox(height: 16),
                    Row(
                      children: [
                        Container(padding: EdgeInsets.all(10), decoration: BoxDecoration(color: primary.withOpacity(0.15), borderRadius: BorderRadius.circular(10)), child: Icon(Icons.groups_outlined, color: primary, size: 24)),
                        SizedBox(width: 12),
                        Expanded(child: Text('Project Team', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: AppTheme.getTextPrimary(context)))),
                        IconButton(icon: Icon(Icons.close, color: AppTheme.getTextPrimary(context)), onPressed: () => Navigator.pop(context)),
                      ],
                    ),
                  ],
                ),
              ),
              Expanded(
                child: ListView(
                  controller: scrollController,
                  padding: EdgeInsets.all(16),
                  children: [
                    if (seniorArchitects != null && seniorArchitects!.isNotEmpty) ...[
                      Text('Senior Architects', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: AppTheme.getTextSecondary(context))),
                      SizedBox(height: 12),
                      ...seniorArchitects!.map((a) {
                        final name = a is Map ? (a['name'] ?? 'Unknown') : 'Unknown';
                        return _buildMemberCard(context, name);
                      }).toList(),
                    ],
                    if (architects != null && architects!.isNotEmpty) ...[
                      SizedBox(height: 16),
                      Text('Architects', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: AppTheme.getTextSecondary(context))),
                      SizedBox(height: 12),
                      ...architects!.map((a) {
                        final name = a is Map ? (a['name'] ?? 'Unknown') : 'Unknown';
                        return _buildMemberCard(context, name);
                      }).toList(),
                    ],
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildMemberCard(BuildContext context, String name) {
    final primary = AppTheme.getPrimaryColor(context);
    return Container(
      margin: EdgeInsets.only(bottom: 8),
      padding: EdgeInsets.all(12),
      decoration: BoxDecoration(color: AppTheme.getBackgroundSecondary(context), borderRadius: BorderRadius.circular(12)),
      child: Row(
        children: [
          CircleAvatar(backgroundColor: primary.withOpacity(0.2), radius: 20, child: Icon(Icons.person, color: primary, size: 20)),
          SizedBox(width: 12),
          Text(name, style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: AppTheme.getTextPrimary(context))),
        ],
      ),
    );
  }
}

class _InAppDocumentScreen extends StatefulWidget {
  final String title;
  final String url;

  const _InAppDocumentScreen({required this.title, required this.url});

  @override
  State<_InAppDocumentScreen> createState() => _InAppDocumentScreenState();
}

class _InAppDocumentScreenState extends State<_InAppDocumentScreen> {
  late final WebViewController _controller;
  bool _loading = true;
  String? _loadError;

  @override
  void initState() {
    super.initState();
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setNavigationDelegate(
        NavigationDelegate(
          onPageStarted: (_) {
            if (mounted) setState(() { _loading = true; _loadError = null; });
          },
          onPageFinished: (_) {
            if (mounted) setState(() => _loading = false);
          },
          onWebResourceError: (e) {
            if (mounted) setState(() {
              _loading = false;
              _loadError = e.description ?? 'Failed to load document';
            });
          },
        ),
      )
      ..loadRequest(Uri.parse(widget.url));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.getBackgroundPrimary(context),
      appBar: AppBar(
        backgroundColor: AppTheme.getBackgroundSecondary(context),
        foregroundColor: AppTheme.navy,
        elevation: 0,
        title: Text(
          widget.title,
          style: const TextStyle(
            color: AppTheme.navy,
            fontSize: 18,
            fontWeight: FontWeight.w800,
          ),
        ),
        iconTheme: const IconThemeData(color: AppTheme.navy),
        actionsIconTheme: const IconThemeData(color: AppTheme.navy),
        actions: [
          IconButton(
            icon: Icon(Icons.open_in_new),
            onPressed: () async {
              final uri = Uri.tryParse(widget.url);
              if (uri != null) {
                try {
                  await launchUrl(uri, mode: LaunchMode.platformDefault);
                } catch (_) {}
              }
            },
            tooltip: 'Open in browser',
          ),
        ],
      ),
      body: Stack(
        children: [
          WebViewWidget(controller: _controller),
          if (_loading)
            Container(
              color: AppTheme.getBackgroundPrimary(context),
              child: const SkeletonListLoader(showSummary: false, cardCount: 3),
            ),
          if (_loadError != null && !_loading)
            Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.error_outline, size: 48, color: Colors.red),
                    SizedBox(height: 16),
                    Text(_loadError!, textAlign: TextAlign.center, style: TextStyle(color: AppTheme.getTextSecondary(context))),
                    SizedBox(height: 16),
                    TextButton.icon(
                      onPressed: () async {
                        final uri = Uri.tryParse(widget.url);
                        if (uri != null) {
                          try {
                            await launchUrl(uri, mode: LaunchMode.platformDefault);
                          } catch (_) {}
                        }
                      },
                      icon: Icon(Icons.open_in_new),
                      label: Text('Open in browser instead'),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}
