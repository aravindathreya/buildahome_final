import 'package:flutter/material.dart';

import '../app_theme.dart';
import '../documents_v1/documents_v1_home_screen.dart';
import '../models/workflow_document.dart';
import '../services/workflow_document_service.dart';
import '../widgets/skeleton_loader.dart';
import 'client_portal_document_ui.dart';

/// Documents tab inside KYC & Documents — searchable category list with badges.
class ClientPortalDocumentsTab extends StatefulWidget {
  const ClientPortalDocumentsTab({super.key});

  @override
  State<ClientPortalDocumentsTab> createState() =>
      _ClientPortalDocumentsTabState();
}

class _ClientPortalDocumentsTabState extends State<ClientPortalDocumentsTab> {
  final _searchCtrl = TextEditingController();
  bool _loading = true;
  String? _error;
  WorkflowDocumentLibrary? _library;

  @override
  void initState() {
    super.initState();
    _load();
    _searchCtrl.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final library = await WorkflowDocumentService().fetchLibrary();
      if (!mounted) return;
      setState(() {
        _loading = false;
        _library = library;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = e.toString().replaceFirst('Exception: ', '');
      });
    }
  }

  void _openCategory(WorkflowDocumentCategory category) {
    final journeyKey = category.clientJourneyKey ?? category.id;
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ClientJourneyDocumentsScreen(
          title: category.label,
          journeyKey: journeyKey,
          clientMode: true,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const SkeletonListLoader(cardCount: 6);
    }
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(_error!, textAlign: TextAlign.center),
              const SizedBox(height: 12),
              ElevatedButton(onPressed: _load, child: const Text('Retry')),
            ],
          ),
        ),
      );
    }

    final library = _library;
    final categoryCards = library == null
        ? <Widget>[]
        : buildDocumentCategoryCards(
            context: context,
            library: library,
            searchQuery: _searchCtrl.text,
            onCategoryTap: _openCategory,
          );

    return RefreshIndicator(
      color: ClientPortalDocTheme.accentBlue,
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 28),
        children: [
          ClientPortalSearchBar(
            controller: _searchCtrl,
            hint: 'Search documents…',
          ),
          const SizedBox(height: 18),
          const ClientPortalSectionHeading(label: 'Document Categories'),
          if (categoryCards.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 32),
              child: Text(
                library == null || library.documentsTabCategories.isEmpty
                    ? 'No document categories available yet.'
                    : 'No categories match your search.',
                textAlign: TextAlign.center,
                style: TextStyle(color: AppTheme.getTextSecondary(context)),
              ),
            )
          else
            ...categoryCards,
        ],
      ),
    );
  }
}
