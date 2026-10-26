import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

/// Vehicle types from server (/API/get_vehicle_types), cached in memory and
/// SharedPreferences; falls back to the hardcoded list when offline.
class VehicleTypes {
  static const List<String> fallback = [
    'Truck', 'Tempo', 'Tractor', 'Pickup', 'Other',
  ];
  static const String _url = "https://office.buildahome.in/API/get_vehicle_types";
  static const String _prefsKey = 'vehicle_types_cache';

  static List<String> types = List<String>.from(fallback);
  static bool _loaded = false;
  static Future<List<String>>? _inFlight;

  static Future<List<String>> load({bool force = false}) {
    if (_loaded && !force) return Future.value(types);
    return _inFlight ??= _load().whenComplete(() => _inFlight = null);
  }

  static bool _apply(dynamic res) {
    if (res is! Map || res['vehicle_types'] is! List) return false;
    final list = (res['vehicle_types'] as List)
        .map((e) => e.toString().trim())
        .where((e) => e.isNotEmpty)
        .toSet()
        .toList();
    if (list.isEmpty) return false;
    types = list;
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
      print('[VehicleTypes] Error loading vehicle types: $e');
    }
    return types;
  }
}
