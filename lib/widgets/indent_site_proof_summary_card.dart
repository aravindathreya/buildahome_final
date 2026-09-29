import 'package:flutter/material.dart';

import '../app_theme.dart';
import '../indent_task_material.dart';

/// Shared Upload site proof front for My Tasks and Approved POs.
/// Renders Indent / Item / Vendor only (no step-counter subtitle).
class IndentSiteProofSummaryCard extends StatelessWidget {
  final String title;
  final String? indentId;
  final String? itemText;
  final String? vendorName;
  final String buttonLabel;
  final VoidCallback? onPressed;
  final String? subtitle;
  final Widget? trailingButton;

  const IndentSiteProofSummaryCard({
    super.key,
    this.title = 'Upload site proof for approved PO',
    this.indentId,
    this.itemText,
    this.vendorName,
    this.buttonLabel = 'Start site proof',
    this.onPressed,
    this.subtitle,
    this.trailingButton,
  });

  /// Build from a workflow / My Tasks payload (spawn_meta aware).
  factory IndentSiteProofSummaryCard.fromTask({
    Key? key,
    required Map task,
    required String buttonLabel,
    required VoidCallback? onPressed,
    String title = 'Upload site proof for approved PO',
    String? subtitle,
    Widget? trailingButton,
  }) {
    final meta = _spawnMeta(task);
    final indent = (task['indent_id'] ?? meta['indent_id'] ?? '')
        .toString()
        .trim();
    final material = (meta['material'] ?? '').toString().trim();
    final qtyLabel = (meta['quantity_label'] ?? '').toString().trim();
    var item = material.isEmpty
        ? ''
        : (qtyLabel.isEmpty ? material : '$material ($qtyLabel)');
    if (item.isEmpty) {
      item = (indentTaskMaterialLabel(task) ?? '').trim();
    }
    final vendor = (meta['vendor_name'] ?? task['vendor_name'] ?? '')
        .toString()
        .trim();
    return IndentSiteProofSummaryCard(
      key: key,
      title: title,
      indentId: indent.isEmpty ? null : indent,
      itemText: item.isEmpty ? null : item,
      vendorName: vendor.isEmpty ? null : vendor,
      buttonLabel: buttonLabel,
      onPressed: onPressed,
      subtitle: subtitle,
      trailingButton: trailingButton,
    );
  }

  static Map<String, dynamic> _spawnMeta(Map task) {
    final direct = task['spawn_meta'];
    if (direct is Map) {
      return Map<String, dynamic>.from(direct);
    }
    final result = task['workflow_item_result'];
    if (result is Map && result['spawn_meta'] is Map) {
      return Map<String, dynamic>.from(result['spawn_meta'] as Map);
    }
    return <String, dynamic>{};
  }

  static const Color _ink = Color(0xFF1B254B);
  static const Color _muted = Color(0xFF8A94A6);

  static Widget _infoRow(IconData icon, String label, String value) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 15, color: _muted),
        const SizedBox(width: 6),
        Text(
          '$label: ',
          style: const TextStyle(
            color: _muted,
            fontSize: 12,
            fontWeight: FontWeight.w600,
          ),
        ),
        Expanded(
          child: Text(
            value,
            style: const TextStyle(
              color: _ink,
              fontSize: 12.5,
              fontWeight: FontWeight.w700,
              height: 1.3,
            ),
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final indent = (indentId ?? '').trim();
    final item = (itemText ?? '').trim();
    final vendor = (vendorName ?? '').trim();
    final sub = (subtitle ?? '').trim();

    return Container(
      width: double.infinity,
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
            title,
            style: const TextStyle(
              color: _ink,
              fontSize: 14,
              fontWeight: FontWeight.w800,
            ),
          ),
          if (indent.isNotEmpty) ...[
            const SizedBox(height: 8),
            _infoRow(
              Icons.tag,
              'Indent',
              indent.startsWith('#') ? indent : '#$indent',
            ),
          ],
          if (item.isNotEmpty) ...[
            const SizedBox(height: 6),
            _infoRow(Icons.inventory_2_outlined, 'Item', item),
          ],
          if (vendor.isNotEmpty) ...[
            const SizedBox(height: 6),
            _infoRow(Icons.local_shipping_outlined, 'Vendor', vendor),
          ],
          if (sub.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              sub,
              style: TextStyle(
                color: AppTheme.getTextSecondary(context),
                fontSize: 12.5,
                fontWeight: FontWeight.w600,
                height: 1.35,
              ),
            ),
          ],
          if (onPressed != null) ...[
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: onPressed,
                icon: const Icon(Icons.pin_drop_outlined, size: 18),
                label: Text(buttonLabel),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.primaryColorConst,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
              ),
            ),
          ],
          if (trailingButton != null) ...[
            const SizedBox(height: 10),
            trailingButton!,
          ],
        ],
      ),
    );
  }
}
