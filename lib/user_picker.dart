import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'app_theme.dart';
import 'widgets/skeleton_loader.dart';

class UserPickerScreen {
  static const Color _navy = AppTheme.navy;
  static const Color _muted = AppTheme.mutedGrey;
  static const Color _border = AppTheme.border;
  static const Color _softShadow = AppTheme.softShadow;

  static Future<dynamic> show(BuildContext context, {int? projectId}) async {
    final searchController = TextEditingController();
    List<dynamic> users = [];
    bool loading = true;
    String? error;

    try {
      Uri uri;

      if (projectId != null) {
        uri = Uri.parse("https://office1.buildahome.in/api/project_team").replace(
          queryParameters: {'project_id': projectId.toString()},
        );
      } else {
        uri = Uri.parse("https://office.buildahome.in/API/get_all_users");
      }

      final response = await http.get(uri).timeout(const Duration(seconds: 20));

      if (response.statusCode == 200) {
        final decoded = jsonDecode(response.body);
        List<dynamic> userList = [];

        if (decoded is List) {
          userList = decoded;
        } else if (decoded is Map) {
          if (decoded['data'] != null && decoded['data'] is List) {
            userList = decoded['data'];
          } else if (decoded['users'] != null && decoded['users'] is List) {
            userList = decoded['users'];
          } else if (decoded['team'] != null && decoded['team'] is List) {
            userList = decoded['team'];
          } else if (decoded['success'] == true) {
            for (var key in decoded.keys) {
              if (decoded[key] is List) {
                userList = decoded[key];
                break;
              }
            }
          }
        }

        users = userList;
        loading = false;
      } else {
        throw Exception('Unable to load users (code ${response.statusCode})');
      }
    } catch (e) {
      loading = false;
      error = 'Unable to load users. Please try again.';
    }

    return await showModalBottomSheet<dynamic>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (context) => Container(
        height: MediaQuery.of(context).size.height * 0.82,
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.only(
            topLeft: Radius.circular(24),
            topRight: Radius.circular(24),
          ),
          boxShadow: [
            BoxShadow(
              color: _softShadow,
              blurRadius: 24,
              offset: Offset(0, -4),
            ),
          ],
        ),
        child: StatefulBuilder(
          builder: (context, setModalState) {
            final query = searchController.text.toLowerCase().trim();
            final filtered = query.isEmpty
                ? users
                : users.where((user) {
                    final name = user['name']?.toString().toLowerCase() ??
                        user['user_name']?.toString().toLowerCase() ??
                        '';
                    return name.contains(query);
                  }).toList();

            return Column(
              children: [
                const SizedBox(height: 10),
                Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: const Color(0xFFD7DEE8),
                    borderRadius: BorderRadius.circular(999),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 16, 12, 8),
                  child: Row(
                    children: [
                      Container(
                        width: 36,
                        height: 36,
                        decoration: BoxDecoration(
                          color: const Color(0xFFEEF2FF),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: const Icon(Icons.person_search_rounded,
                            color: _navy, size: 20),
                      ),
                      const SizedBox(width: 12),
                      const Expanded(
                        child: Text(
                          'Select User',
                          style: TextStyle(
                            color: _navy,
                            fontSize: 18,
                            fontWeight: FontWeight.w800,
                            letterSpacing: -0.2,
                          ),
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.close_rounded, color: _muted),
                        onPressed: () {
                          searchController.clear();
                          Navigator.pop(context);
                        },
                      ),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 4, 20, 12),
                  child: TextField(
                    controller: searchController,
                    style: const TextStyle(
                      color: _navy,
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                    onChanged: (_) => setModalState(() {}),
                    decoration: InputDecoration(
                      hintText: 'Search users by name...',
                      hintStyle: const TextStyle(
                        color: _muted,
                        fontWeight: FontWeight.w500,
                      ),
                      prefixIcon:
                          const Icon(Icons.search_rounded, color: _muted),
                      suffixIcon: searchController.text.isNotEmpty
                          ? IconButton(
                              icon: const Icon(Icons.clear_rounded,
                                  color: _muted, size: 20),
                              onPressed: () {
                                searchController.clear();
                                setModalState(() {});
                              },
                            )
                          : null,
                      filled: true,
                      fillColor: const Color(0xFFF7F8FB),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(14),
                        borderSide: const BorderSide(color: _border),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(14),
                        borderSide: const BorderSide(color: _border),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(14),
                        borderSide:
                            const BorderSide(color: _navy, width: 1.4),
                      ),
                      contentPadding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 14),
                    ),
                  ),
                ),
                Expanded(
                  child: loading
                      ? (error != null
                          ? Center(
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  const Icon(Icons.error_outline,
                                      size: 48, color: _muted),
                                  const SizedBox(height: 16),
                                  Text(
                                    error,
                                    style: const TextStyle(
                                      color: _muted,
                                      fontSize: 14,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ],
                              ),
                            )
                          : const SkeletonSheetLoader(itemCount: 6))
                      : users.isEmpty
                          ? const Center(
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(Icons.person_off_rounded,
                                      size: 48, color: _muted),
                                  SizedBox(height: 16),
                                  Text(
                                    'No users available',
                                    style: TextStyle(
                                      color: _muted,
                                      fontSize: 14,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ],
                              ),
                            )
                          : filtered.isEmpty
                              ? const Center(
                                  child: Column(
                                    mainAxisAlignment:
                                        MainAxisAlignment.center,
                                    children: [
                                      Icon(Icons.search_off_rounded,
                                          size: 48, color: _muted),
                                      SizedBox(height: 16),
                                      Text(
                                        'No users match your search',
                                        style: TextStyle(
                                          color: _muted,
                                          fontSize: 14,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                    ],
                                  ),
                                )
                              : ListView.builder(
                                  padding: const EdgeInsets.fromLTRB(
                                      20, 4, 20, 24),
                                  itemCount: filtered.length,
                                  itemBuilder: (context, index) {
                                    final user = filtered[index];
                                    final userName =
                                        user['user_name']?.toString() ??
                                            user['name']?.toString() ??
                                            'Unknown User';

                                    return Container(
                                      margin:
                                          const EdgeInsets.only(bottom: 10),
                                      decoration: BoxDecoration(
                                        color: Colors.white,
                                        borderRadius:
                                            BorderRadius.circular(14),
                                        border: Border.all(color: _border),
                                        boxShadow: const [
                                          BoxShadow(
                                            color: _softShadow,
                                            blurRadius: 10,
                                            offset: Offset(0, 3),
                                          ),
                                        ],
                                      ),
                                      child: Material(
                                        color: Colors.transparent,
                                        child: InkWell(
                                          onTap: () {
                                            searchController.clear();
                                            Navigator.pop(context, user);
                                          },
                                          borderRadius:
                                              BorderRadius.circular(14),
                                          child: Padding(
                                            padding: const EdgeInsets.all(14),
                                            child: Row(
                                              children: [
                                                Container(
                                                  width: 40,
                                                  height: 40,
                                                  decoration: BoxDecoration(
                                                    color: const Color(
                                                        0xFFEEF2FF),
                                                    borderRadius:
                                                        BorderRadius.circular(
                                                            12),
                                                  ),
                                                  child: const Icon(
                                                    Icons.person_rounded,
                                                    color: _navy,
                                                    size: 20,
                                                  ),
                                                ),
                                                const SizedBox(width: 12),
                                                Expanded(
                                                  child: Text(
                                                    userName,
                                                    style: const TextStyle(
                                                      color: _navy,
                                                      fontSize: 14.5,
                                                      fontWeight:
                                                          FontWeight.w700,
                                                    ),
                                                  ),
                                                ),
                                                const Icon(
                                                  Icons.chevron_right_rounded,
                                                  color: _muted,
                                                ),
                                              ],
                                            ),
                                          ),
                                        ),
                                      ),
                                    );
                                  },
                                ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}
