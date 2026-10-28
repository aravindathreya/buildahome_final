import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

/// One server-controlled dimension (e.g. label "8mm Dia TMT Bar", short "08mm Dia").
class IndentDimension {
  final String label;
  final String shortLabel;
  const IndentDimension(this.label, this.shortLabel);

  factory IndentDimension.fromJson(Map m) {
    final label = (m['label'] ?? '').toString().trim();
    final short = (m['short_label'] ?? '').toString().trim();
    return IndentDimension(label, short.isEmpty ? label : short);
  }
}

/// Dimensions per material from /API/get_indent_dimensions, cached in memory.
/// Any failure returns [] so the screen falls back to plain quantity entry.
class IndentDimensions {
  static const String _url =
      "https://office.buildahome.in/API/get_indent_dimensions";
  static final Map<String, List<IndentDimension>> _cache = {};

  static List<IndentDimension> parse(dynamic res) {
    if (res is! Map || res['dimensions'] is! List) return [];
    return (res['dimensions'] as List)
        .whereType<Map>()
        .map((m) => IndentDimension.fromJson(m))
        .where((d) => d.label.isNotEmpty)
        .toList();
  }

  static Future<List<IndentDimension>> forMaterial(String material) async {
    final key = material.trim().toLowerCase();
    if (key.isEmpty) return [];
    final cached = _cache[key];
    if (cached != null) return cached;
    try {
      final uri = Uri.parse(_url).replace(queryParameters: {'material': material});
      final response =
          await http.get(uri).timeout(const Duration(seconds: 10));
      if (response.statusCode != 200) return [];
      final list = parse(jsonDecode(response.body));
      debugPrint('[IndentDimensions] material="$material" status=${response.statusCode} count=${list.length}');
      _cache[key] = list;
      return list;
    } catch (e) {
      print('[IndentDimensions] Error loading dimensions: $e');
      return [];
    }
  }

  static String formatNumber(double v) {
    if (v == v.roundToDouble()) return v.toInt().toString();
    var s = v.toStringAsFixed(3);
    s = s.replaceFirst(RegExp(r'0+$'), '');
    return s.replaceFirst(RegExp(r'\.$'), '');
  }

  /// Sum of valid positive quantities.
  static double total(List<String> quantities) {
    double t = 0;
    for (final q in quantities) {
      final v = double.tryParse(q.trim());
      if (v != null && v > 0) t += v;
    }
    return t;
  }

  /// "8mm Dia TMT Bar: 100 Kg; 10mm Dia TMT Bar: 50 Kg"
  static String breakdown(List<String> labels, List<String> quantities, String unit) {
    final parts = <String>[];
    for (var i = 0; i < labels.length && i < quantities.length; i++) {
      final v = double.tryParse(quantities[i].trim()) ?? 0;
      parts.add('${labels[i]}: ${formatNumber(v)} $unit');
    }
    return parts.join('; ');
  }
}
