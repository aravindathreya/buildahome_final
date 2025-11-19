import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import "ShowAlert.dart";
import 'projects.dart';
import 'widgets/material.dart';
import 'package:intl/intl.dart';
import 'app_theme.dart';

class StockReportLayout extends StatelessWidget {
  const StockReportLayout({super.key});

  @override
  Widget build(BuildContext context) {
    return Theme(
      data: AppTheme.darkTheme,
      child: Scaffold(
        backgroundColor: AppTheme.backgroundPrimary,
        appBar: AppBar(
          automaticallyImplyLeading: true,
          title: Text(
            'Stock Report',
            style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600),
          ),
        ),
        body: const SafeArea(child: StockReport()),
      ),
    );
  }
}

class StockReport extends StatefulWidget {
  const StockReport({super.key});

  @override
  StockReportState createState() => StockReportState();
}

class StockReportState extends State<StockReport> {
  String? userId;
  String? userName;
  String projectName = 'Select project';
  String? projectId;
  List<TextEditingController> materialsTextController = [TextEditingController()];
  List<TextEditingController> quantitiesTextController = [TextEditingController()];

  @override
  void initState() {
    super.initState();
    _loadUser();
  }

  Future<void> _loadUser() async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    userId = prefs.getString('user_id');
    userName = prefs.getString('username');
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final formattedDate = DateFormat("EEEE, dd MMMM yyyy").format(DateTime.now());

    return ListView(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
      children: [
        Text(
          'Stock Report',
          style: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 6),
        Text(
          formattedDate,
          style: theme.textTheme.bodyMedium?.copyWith(color: AppTheme.textSecondary),
        ),
        const SizedBox(height: 24),
        _buildSelectionTile(
          context: context,
          label: 'Project',
          value: projectName,
          icon: Icons.home_work_outlined,
          onTap: () async {
            final projectDetails = await showDialog<String>(
              context: context,
              builder: (BuildContext context) => ProjectsModal(userId ?? ''),
            );
            if (!mounted) return;
            setState(() {
              if (projectDetails != null) {
                projectName = projectDetails.split("|")[0];
                projectId = projectDetails.split("|")[1];
              } else {
                projectName = 'Select project';
                projectId = null;
              }
            });
          },
        ),
        const SizedBox(height: 20),
        ...List.generate(materialsTextController.length, (index) => _buildEntryCard(context, index)),
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            onPressed: _addEntry,
            icon: const Icon(Icons.add),
            label: const Text('Add another material'),
          ),
        ),
        const SizedBox(height: 16),
        SizedBox(
          width: double.infinity,
          child: ElevatedButton(
            onPressed: () => _submitReport(context),
            child: const Text('Submit report'),
          ),
        ),
      ],
    );
  }

  @override
  void dispose() {
    for (final controller in materialsTextController) {
      controller.dispose();
    }
    for (final controller in quantitiesTextController) {
      controller.dispose();
    }
    super.dispose();
  }

  Widget _buildSelectionTile({
    required BuildContext context,
    required String label,
    required String value,
    required IconData icon,
    required VoidCallback onTap,
  }) {
    final theme = Theme.of(context);
    final isPlaceholder = value == 'Select project';

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: AppTheme.backgroundSecondary,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppTheme.primaryColorConst.withOpacity(0.15)),
        ),
        child: Row(
          children: [
            Icon(icon, color: AppTheme.primaryColorConst),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: theme.textTheme.bodySmall?.copyWith(color: AppTheme.textSecondary),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    value,
                    style: theme.textTheme.bodyLarge?.copyWith(
                      color: isPlaceholder ? AppTheme.textSecondary : AppTheme.textPrimary,
                      fontWeight: isPlaceholder ? FontWeight.w500 : FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
            Icon(Icons.chevron_right, color: AppTheme.textSecondary),
          ],
        ),
      ),
    );
  }

  Widget _buildEntryCard(BuildContext context, int index) {
    final theme = Theme.of(context);

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.backgroundSecondary,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppTheme.primaryColorConst.withOpacity(0.15)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                'Entry ${index + 1}',
                style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
              ),
              const Spacer(),
              if (materialsTextController.length > 1)
                IconButton(
                  tooltip: 'Remove entry',
                  icon: const Icon(Icons.delete_outline),
                  onPressed: () => _removeEntry(index),
                ),
            ],
          ),
          const SizedBox(height: 12),
          _buildMaterialPicker(context, index),
          const SizedBox(height: 12),
          TextField(
            controller: quantitiesTextController[index],
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: const InputDecoration(
              labelText: 'Quantity',
              hintText: 'Enter quantity',
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMaterialPicker(BuildContext context, int index) {
    final theme = Theme.of(context);
    final currentValue = materialsTextController[index].text;
    final isPlaceholder = currentValue.isEmpty;
    final displayValue = isPlaceholder ? 'Tap to select material' : currentValue;

    return InkWell(
      onTap: () async {
        final materialDetails = await showDialog<String>(
          context: context,
          builder: (BuildContext context) => Materials(),
        );
        if (!mounted) return;
        if (materialDetails != null) {
          setState(() {
            materialsTextController[index].text = materialDetails;
          });
        }
      },
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        decoration: BoxDecoration(
          color: AppTheme.backgroundPrimary,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppTheme.primaryColorConst.withOpacity(0.2)),
        ),
        child: Row(
          children: [
            Icon(Icons.inventory_2_outlined, color: AppTheme.primaryColorConst),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                displayValue,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: isPlaceholder ? AppTheme.textSecondary : AppTheme.textPrimary,
                  fontWeight: isPlaceholder ? FontWeight.w500 : FontWeight.w600,
                ),
              ),
            ),
            Icon(Icons.search, color: AppTheme.textSecondary),
          ],
        ),
      ),
    );
  }

  void _addEntry() {
    setState(() {
      materialsTextController.add(TextEditingController());
      quantitiesTextController.add(TextEditingController());
    });
  }

  void _removeEntry(int index) {
    if (materialsTextController.length <= 1) return;
    setState(() {
      final materialController = materialsTextController.removeAt(index);
      final quantityController = quantitiesTextController.removeAt(index);
      materialController.dispose();
      quantityController.dispose();
    });
  }

  Future<void> _submitReport(BuildContext context) async {
    showDialog(
      barrierDismissible: false,
      context: context,
      builder: (_) => ShowAlert("Submitting your stock report...", true),
    );

    if (projectId == null || projectName == 'Select project') {
      Navigator.of(context, rootNavigator: true).pop();
      _showSimpleDialog(context, "Please select a project");
      return;
    }

    if (materialsTextController.isEmpty) {
      Navigator.of(context, rootNavigator: true).pop();
      _showSimpleDialog(context, "Please add at least one entry");
      return;
    }

    final List<String> stockReportEntries = [];
    for (var i = 0; i < materialsTextController.length; i++) {
      if (materialsTextController[i].text.trim().isEmpty) {
        Navigator.of(context, rootNavigator: true).pop();
        _showSimpleDialog(context, "Material cannot be empty");
        return;
      }
      if (quantitiesTextController[i].text.trim().isEmpty) {
        Navigator.of(context, rootNavigator: true).pop();
        _showSimpleDialog(context, "Quantity cannot be empty");
        return;
      }
      stockReportEntries.add('${materialsTextController[i].text}|${quantitiesTextController[i].text}');
    }

    final formattedDate = DateFormat('EEEE d MMMM yyyy H:m').format(DateTime.now());
    final response = await http.post(
      Uri.parse('https://office.buildahome.in/API/update_stock_report'),
      body: {
        'project_id': projectId,
        'timestamp': formattedDate,
        'stock_report_entries': stockReportEntries.join('^'),
        'user_id': userId,
        'user_name': userName ?? '',
      },
    );

    if (!mounted) return;

    if (response.statusCode != 200) {
      Navigator.of(context, rootNavigator: true).pop();
      showDialog(
        context: context,
        builder: (BuildContext context) => ShowAlert("Something went wrong", false),
      );
      return;
    }

    Navigator.of(context, rootNavigator: true).pop();
    showDialog(
      context: context,
      builder: (BuildContext context) => ShowAlert("Stock report submitted successfully", false),
    );

    setState(() {
      projectName = 'Select project';
      projectId = null;
      _resetEntries();
    });
  }

  void _resetEntries() {
    for (final controller in materialsTextController) {
      controller.dispose();
    }
    for (final controller in quantitiesTextController) {
      controller.dispose();
    }
    materialsTextController = [TextEditingController()];
    quantitiesTextController = [TextEditingController()];
  }

  void _showSimpleDialog(BuildContext context, String message) {
    showDialog(
      context: context,
      builder: (BuildContext context) => AlertDialog(
        content: Text(message),
      ),
    );
  }
}
