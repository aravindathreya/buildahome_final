/// Resolves indent material (+ qty/unit when present) for task card fronts.
/// Uses only existing task / spawn_meta fields — does not invent data.
String? indentTaskMaterialLabel(Map task) {
  String pick(dynamic value) {
    final text = value?.toString().trim() ?? '';
    if (text.isEmpty) return '';
    final lower = text.toLowerCase();
    if (lower == 'null' || lower == 'none' || text == '—') return '';
    return text;
  }

  Map<String, dynamic> _spawnMeta() {
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

  final meta = _spawnMeta();

  var material = pick(task['material']);
  if (material.isEmpty) material = pick(meta['material']);
  if (material.isEmpty) {
    final indents = task['workflow_project_indents'];
    if (indents is List && indents.isNotEmpty) {
      final first = indents.first;
      if (first is Map) {
        material = pick(first['material']);
      }
    }
  }
  if (material.isEmpty) {
    final note = [
      task['note'],
      task['s_note'],
      task['description'],
    ].whereType<Object>().map((e) => e.toString()).join('\n');
    final match = RegExp(
      r'Material:\s*(.+)',
      caseSensitive: false,
    ).firstMatch(note);
    if (match != null) {
      material = pick(match.group(1));
    }
  }
  if (material.isEmpty) return null;

  var qtyLabel = pick(task['quantity_label']);
  if (qtyLabel.isEmpty) qtyLabel = pick(meta['quantity_label']);
  if (qtyLabel.isEmpty) {
    // Prefer spawn_meta / task vendor qty — never invent indent-level aggregate
    // when this card is vendor-scoped (split POs).
    final qty = pick(meta['quantity']).isNotEmpty
        ? pick(meta['quantity'])
        : pick(task['quantity']);
    final unit = pick(meta['unit']).isNotEmpty
        ? pick(meta['unit'])
        : pick(task['unit']);
    final vendorScoped = pick(meta['vendor_id']).isNotEmpty ||
        pick(task['vendor_id']).isNotEmpty;
    if (qty.isEmpty && unit.isEmpty && !vendorScoped) {
      final indents = task['workflow_project_indents'];
      if (indents is List && indents.isNotEmpty && indents.first is Map) {
        final first = Map<String, dynamic>.from(indents.first as Map);
        final q = pick(first['quantity']);
        final u = pick(first['unit']);
        qtyLabel = '$q $u'.trim();
      }
    } else {
      qtyLabel = '$qty $unit'.trim();
    }
  }

  if (qtyLabel.isEmpty) return material;
  return '$material ($qtyLabel)';
}
