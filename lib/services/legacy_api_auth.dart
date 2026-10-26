import 'package:shared_preferences/shared_preferences.dart';

/// Query suffix (`&api_token=...`) for legacy project APIs that now check the
/// mobile login token. Empty when the user has no token saved.
Future<String> legacyApiTokenQuery() async {
  final prefs = await SharedPreferences.getInstance();
  final token = (prefs.getString('api_token') ?? '').trim();
  if (token.isEmpty) return '';
  return '&api_token=${Uri.encodeQueryComponent(token)}';
}
