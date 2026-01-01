import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'app_theme.dart';
import 'widgets/dark_mode_toggle.dart';

class UserPickerScreen {
  static Future<dynamic> show(BuildContext context, {int? projectId}) async {
    final searchController = TextEditingController();
    List<dynamic> users = [];
    bool loading = true;
    String? error;
    
    // Load users
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
        height: MediaQuery.of(context).size.height * 0.8,
        decoration: BoxDecoration(
          color: AppTheme.getBackgroundSecondary(context),
          borderRadius: BorderRadius.only(
            topLeft: Radius.circular(20),
            topRight: Radius.circular(20),
          ),
        ),
        child: StatefulBuilder(
          builder: (context, setModalState) {
            final query = searchController.text.toLowerCase().trim();
            final filtered = query.isEmpty
                ? users
                : users.where((user) {
                    final name = user['name']?.toString().toLowerCase() ?? 
                                 user['user_name']?.toString().toLowerCase() ?? '';
                    return name.contains(query);
                  }).toList();

            return Column(
              children: [
                Container(
                  padding: EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: AppTheme.getBackgroundPrimary(context),
                    borderRadius: BorderRadius.only(
                      topLeft: Radius.circular(20),
                      topRight: Radius.circular(20),
                    ),
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: 4,
                        height: 20,
                        decoration: BoxDecoration(
                          color: AppTheme.getPrimaryColor(context),
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                      SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          'Select User',
                          style: TextStyle(
                            color: AppTheme.getTextPrimary(context),
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      DarkModeToggle(showLabel: false),
                      SizedBox(width: 8),
                      IconButton(
                        icon: Icon(Icons.close, color: AppTheme.getTextSecondary(context)),
                        onPressed: () {
                          searchController.clear();
                          Navigator.pop(context);
                        },
                      ),
                    ],
                  ),
                ),
                Container(
                  padding: EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: AppTheme.getBackgroundPrimary(context),
                    boxShadow: [
                      BoxShadow(
                        color: Theme.of(context).brightness == Brightness.dark 
                            ? Colors.black.withOpacity(0.3)
                            : Colors.black.withOpacity(0.05),
                        blurRadius: 4,
                        offset: Offset(0, 2),
                      ),
                    ],
                  ),
                  child: TextField(
                    controller: searchController,
                    style: TextStyle(color: AppTheme.getTextPrimary(context), fontSize: 14),
                    onChanged: (value) {
                      setModalState(() {});
                    },
                    decoration: InputDecoration(
                      hintText: 'Search users by name...',
                      hintStyle: TextStyle(color: AppTheme.getTextSecondary(context)),
                      prefixIcon: Icon(Icons.search, color: AppTheme.getPrimaryColor(context)),
                      suffixIcon: searchController.text.isNotEmpty
                          ? IconButton(
                              icon: Icon(Icons.clear, color: AppTheme.getTextSecondary(context), size: 20),
                              onPressed: () {
                                searchController.clear();
                                setModalState(() {});
                              },
                            )
                          : null,
                      filled: true,
                      fillColor: AppTheme.getBackgroundSecondary(context),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide(
                          color: AppTheme.getPrimaryColor(context).withOpacity(0.2),
                        ),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide(
                          color: AppTheme.getPrimaryColor(context).withOpacity(0.2),
                        ),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide(
                          color: AppTheme.getPrimaryColor(context),
                          width: 2,
                        ),
                      ),
                      contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                    ),
                  ),
                ),
                Expanded(
                  child: loading
                      ? Center(
                          child: error != null
                              ? Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Icon(Icons.error_outline, size: 48, color: AppTheme.getTextSecondary(context)),
                                    SizedBox(height: 16),
                                    Text(
                                      error,
                                      style: TextStyle(
                                        color: AppTheme.getTextSecondary(context),
                                        fontSize: 14,
                                      ),
                                    ),
                                  ],
                                )
                              : CircularProgressIndicator(
                                  valueColor: AlwaysStoppedAnimation<Color>(AppTheme.getPrimaryColor(context)),
                                ),
                        )
                      : users.isEmpty
                          ? Center(
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(Icons.person_off, size: 48, color: AppTheme.getTextSecondary(context)),
                                  SizedBox(height: 16),
                                  Text(
                                    'No users available',
                                    style: TextStyle(
                                      color: AppTheme.getTextSecondary(context),
                                      fontSize: 14,
                                    ),
                                  ),
                                ],
                              ),
                            )
                          : filtered.isEmpty
                              ? Center(
                                  child: Column(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      Icon(Icons.search_off, size: 48, color: AppTheme.getTextSecondary(context)),
                                      SizedBox(height: 16),
                                      Text(
                                        'No users match your search',
                                        style: TextStyle(
                                          color: AppTheme.getTextSecondary(context),
                                          fontSize: 14,
                                        ),
                                      ),
                                    ],
                                  ),
                                )
                              : ListView.builder(
                                  padding: EdgeInsets.all(16),
                                  itemCount: filtered.length,
                                  itemBuilder: (context, index) {
                                    final user = filtered[index];
                                    final userName = user['user_name']?.toString() ?? 
                                                    user['name']?.toString() ?? 'Unknown User';
                                    
                                    return Container(
                                      margin: EdgeInsets.only(bottom: 8),
                                      decoration: BoxDecoration(
                                        color: AppTheme.getBackgroundPrimary(context),
                                        borderRadius: BorderRadius.circular(10),
                                        border: Border.all(
                                          color: AppTheme.getPrimaryColor(context).withOpacity(0.2),
                                          width: 1,
                                        ),
                                      ),
                                      child: Material(
                                        color: Colors.transparent,
                                        child: InkWell(
                                          onTap: () {
                                            searchController.clear();
                                            Navigator.pop(context, user);
                                          },
                                          borderRadius: BorderRadius.circular(10),
                                          child: Padding(
                                            padding: EdgeInsets.all(12),
                                            child: Row(
                                              children: [
                                                Container(
                                                  padding: EdgeInsets.all(6),
                                                  decoration: BoxDecoration(
                                                    color: AppTheme.getPrimaryColor(context).withOpacity(0.15),
                                                    borderRadius: BorderRadius.circular(6),
                                                  ),
                                                  child: Icon(
                                                    Icons.person,
                                                    color: AppTheme.getPrimaryColor(context),
                                                    size: 16,
                                                  ),
                                                ),
                                                SizedBox(width: 12),
                                                Expanded(
                                                  child: Text(
                                                    userName,
                                                    style: TextStyle(
                                                      color: AppTheme.getTextPrimary(context),
                                                      fontSize: 14,
                                                      fontWeight: FontWeight.w600,
                                                    ),
                                                  ),
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
