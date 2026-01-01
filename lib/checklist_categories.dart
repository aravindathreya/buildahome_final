import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import 'app_theme.dart';
import 'widgets/dark_mode_toggle.dart';
import 'checklist_items.dart';

class ChecklistCategoriesLayout extends StatelessWidget {
  const ChecklistCategoriesLayout({super.key});

  @override
  Widget build(BuildContext context) {
    final canPop = Navigator.of(context).canPop();
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        backgroundColor: Theme.of(context).colorScheme.surface,
        actions: [
          DarkModeToggle(showLabel: false),
          SizedBox(width: 8),
        ],
        automaticallyImplyLeading: canPop,
        leading: canPop
            ? IconButton(
                icon: const Icon(Icons.arrow_back_ios_new_rounded),
                onPressed: () => Navigator.of(context).maybePop(),
              )
            : null,
        title: const Text('Checklist'),
      ),
      body: const ChecklistCategories(),
    );
  }
}

class ChecklistCategories extends StatefulWidget {
  const ChecklistCategories({super.key});

  @override
  ChecklistCategoriesState createState() {
    return ChecklistCategoriesState();
  }
}

class ChecklistCategoriesState extends State<ChecklistCategories> {
  List<dynamic> categories = [];
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    call();
  }

  Future<void> call() async {
    setState(() {
      _isLoading = true;
    });
    try {
      var url = 'https://office.buildahome.in/API/get_checklist_categories';
      var response = await http.get(Uri.parse(url));
      var parsed = jsonDecode(response.body)['categories'];
      if (!mounted) return;
      setState(() {
        categories = List<String>.from(parsed);
      });
    } catch (err) {
      debugPrint('Failed to load checklist categories: $err');
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return RefreshIndicator(
      color: AppTheme.getPrimaryColor(context),
      onRefresh: call,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 24, 16, 32),
        children: [
          Text(
            'Select a category',
            style: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 8),
          Text(
            'Checklists keep track of work-front readiness across project stages.',
            style: theme.textTheme.bodyMedium?.copyWith(color: AppTheme.getTextSecondary(context)),
          ),
          const SizedBox(height: 24),
          if (_isLoading && categories.isEmpty)
            ...List.generate(4, (_) => _buildSkeleton())
          else if (categories.isEmpty)
            _buildEmptyState()
          else
            ...List.generate(categories.length, (index) => _buildCategoryTile(categories[index])),
        ],
      ),
    );
  }

  Widget _buildCategoryTile(String category) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.getPrimaryColor(context).withOpacity(0.08)),
      ),
      child: ListTile(
        onTap: () {
          Navigator.push(context, MaterialPageRoute(builder: (context) => ChecklistItemsLayout(category)));
        },
        leading: Icon(Icons.check_circle_outline, color: AppTheme.getPrimaryColor(context)),
        trailing: const Icon(Icons.arrow_forward_ios, size: 16),
        title: Text(
          category,
          style: TextStyle(fontWeight: FontWeight.w600, color: AppTheme.getTextPrimary(context)),
        ),
      ),
    );
  }

  Widget _buildSkeleton() {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      height: 64,
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(12),
      ),
    );
  }

  Widget _buildEmptyState() {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        children: [
          Icon(Icons.fact_check_outlined, color: AppTheme.getPrimaryColor(context), size: 32),
          const SizedBox(height: 12),
          Text(
            'No checklist categories available',
            style: TextStyle(fontWeight: FontWeight.w600, color: AppTheme.getTextPrimary(context)),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}
