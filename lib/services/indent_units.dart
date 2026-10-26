import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

/// Indent units from server (/API/get_indent_units), cached in memory and
/// SharedPreferences; falls back to the hardcoded list when offline.
class IndentUnits {
  static const List<String> fallback = [
    'Bags', 'CFT', 'CUM', 'Load', 'Kg', 'MT', 'Nos', 'Box',
    'SFT', 'RFT', 'LS', 'PCs', 'Ltrs', 'Others',
  ];
  static const String _url = "https://office.buildahome.in/API/get_indent_units";
  static const String _prefsKey = 'indent_units_cache';

  static List<String> units = List<String>.from(fallback);
  static Map<String, List<String>> materialUnits = {};
  static bool _loaded = false;
  static Future<List<String>>? _inFlight;

  static Future<List<String>> load({bool force = false}) {
    if (_loaded && !force) return Future.value(units);
    return _inFlight ??= _load().whenComplete(() => _inFlight = null);
  }

  static bool _apply(dynamic res) {
    if (res is! Map || res['units'] is! List) return false;
    final list = (res['units'] as List)
        .map((e) => e.toString().trim())
        .where((e) => e.isNotEmpty)
        .toSet()
        .toList();
    if (list.isEmpty) return false;
    units = list;
    final mu = res['material_units'];
    if (mu is Map) {
      materialUnits = mu.map((k, v) => MapEntry(k.toString(),
          v is List ? v.map((e) => e.toString()).toList() : <String>[]));
    }
    return true;
  }

  static Future<List<String>> _load() async {
    SharedPreferences? prefs;
    try {
      prefs = await SharedPreferences.getInstance();
      final cached = prefs.getString(_prefsKey);
      if (cached != null) _apply(jsonDecode(cached));
    } catch (_) {}
    try {
      final response = await http
          .get(Uri.parse(_url))
          .timeout(const Duration(seconds: 15));
      if (response.statusCode == 200 && _apply(jsonDecode(response.body))) {
        _loaded = true;
        await prefs?.setString(_prefsKey, response.body);
      }
    } catch (e) {
      print('[IndentUnits] Error loading units: $e');
    }
    return units;
  }
}
