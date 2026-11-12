import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../app_theme.dart';
import '../client_portal/client_portal_document_ui.dart';
import '../models/workflow_document.dart';
import '../services/receipts_agreements_service.dart';
import '../widgets/skeleton_loader.dart';
import '../widgets/workflow_document_viewer.dart';

/// Receipts and Agreements for the selected project: the same files as the
/// ERP page (Project > Projects > Receipts and Agreements), newest first.
class ReceiptsAgreementsScreen extends StatefulWidget {
  final String? projectId;
  final bool clientMode;
  final ReceiptsAgreementsResult? initial;

  const ReceiptsAgreementsScreen({
    super.key,
    this.projectId,
    this.clientMode = false,
    this.initial,
  });

  @override
  State<ReceiptsAgreementsScreen> createState() =>
      _ReceiptsAgreementsScreenState();
}

class _ReceiptsAgreementsScreenState extends State<ReceiptsAgreementsScreen> {
  bool _loading = true;
  String? _error;
  ReceiptsAgreementsResult? _result;

  @override
  void initState() {
    super.initState();
    if (widget.initial != null) {
      _result = widget.initial;
      _loading = false;
    }
    _load(force: widget.initial != null);
  }

  Future<String> _projectId() async {
    final given = (widget.projectId ?? '').trim();
    if (given.isNotEmpty) return given;
    final prefs = await SharedPreferences.getInstance();
    return (prefs.getString('project_id') ?? '').trim();
  }

  Future<void> _load({bool force = false}) async {
    if (_result == null && mounted) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }
    try {
      final pid = await _projectId();
      final result =
          await ReceiptsAgreementsService.instance.fetch(pid, force: force);
      if (!mounted) return;
      setState(() {
        _result = result;
        _loading = false;
        _error = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        if (_result == null) {
          _error = e.toString().replaceFirst('Exception: ', '');
        }
      });
    }
  }

  void _open(WorkflowDocumentUpload doc) {
    openWorkflowDocument(context, doc, clientMode: widget.clientMode);
  }

  @override
  Widget build(BuildContext context) {
    final result = _result;
    final groups = result?.nonEmptyGroups ?? const <ReceiptsAgreementsGroup>[];

    Widget body;
    if (_loading && result == null) {
      body = const SkeletonListLoader(cardCount: 6);
    } else if (_error != null && result == null) {
      body = _StatePane(
        icon: Icons.wifi_off_rounded,
        message: _error!,
        actionLabel: 'Retry',
        onAction: () => _load(force: true),
      );
    } else if (result != null && !result.canView) {
      body = const _StatePane(
        icon: Icons.lock_outline_rounded,
        message: 'You do not have access to Receipts and Agreements.',
      );
    } else if (groups.isEmpty) {
      body = _StatePane(
        icon: Icons.receipt_long_outlined,
        message: 'No receipts or agreements uploaded yet.',
        actionLabel: 'Refresh',
        onAction: () => _load(force: true),
      );
    } else {
      body = TabBarView(
        children: [
          for (final group in groups)
            RefreshIndicator(
              color: ClientPortalDocTheme.accentBlue,
              onRefresh: () => _load(force: true),
              child: ListView.separated(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.fromLTRB(20, 14, 20, 28),
                itemCount: group.documents.length,
                separatorBuilder: (_, __) => const SizedBox(height: 8),
                itemBuilder: (context, index) {
                  final doc = group.documents[index];
                  return ClientPortalDocumentRow(
                    document: doc,
                    onTap: () => _open(doc),
                  );
                },
              ),
            ),
        ],
      );
    }

    final showTabs = groups.isNotEmpty && (result?.canView ?? false);
    return DefaultTabController(
      key: ValueKey(groups.map((g) => g.id).join('|')),
      length: showTabs ? groups.length : 0,
      child: Scaffold(
        backgroundColor: AppTheme.getBackgroundPrimary(context),
        appBar: AppBar(
          backgroundColor: AppTheme.getBackgroundSecondary(context),
          foregroundColor: AppTheme.darkTextPrimary,
          elevation: 0,
          title: Text(
            'Receipts and Agreements',
            style: TextStyle(
              color: AppTheme.darkTextPrimary,
              fontSize: 17,
              fontWeight: FontWeight.w800,
            ),
          ),
          actions: [
            IconButton(
              icon: const Icon(Icons.refresh_rounded),
              onPressed: _loading ? null : () => _load(force: true),
            ),
          ],
          bottom: showTabs
              ? TabBar(
                  isScrollable: groups.length > 2,
                  indicatorColor: ClientPortalDocTheme.accentBlue,
                  labelColor: AppTheme.darkTextPrimary,
                  unselectedLabelColor: AppTheme.getTextSecondary(context),
                  tabs: [
                    for (final group in groups)
                      Tab(text: '${group.label} (${group.documents.length})'),
                  ],
                )
              : null,
        ),
        body: SafeArea(child: body),
      ),
    );
  }
}

class _StatePane extends StatelessWidget {
  final IconData icon;
  final String message;
  final String? actionLabel;
  final VoidCallback? onAction;

  const _StatePane({
    required this.icon,
    required this.message,
    this.actionLabel,
    this.onAction,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 56, color: AppTheme.getTextSecondary(context)),
            const SizedBox(height: 16),
            Text(
              message,
              textAlign: TextAlign.center,
              style: TextStyle(color: AppTheme.getTextSecondary(context)),
            ),
            if (actionLabel != null && onAction != null) ...[
              const SizedBox(height: 16),
              OutlinedButton(onPressed: onAction, child: Text(actionLabel!)),
            ],
          ],
        ),
      ),
    );
  }
}