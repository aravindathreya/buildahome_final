import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'app_theme.dart';
import 'widgets/dark_mode_toggle.dart';

class ViewAllTasksScreen extends StatefulWidget {
  final List<dynamic> tasks;
  final VoidCallback? onTaskUpdated;
  
  const ViewAllTasksScreen({Key? key, required this.tasks, this.onTaskUpdated}) : super(key: key);

  @override
  _ViewAllTasksScreenState createState() => _ViewAllTasksScreenState();
}

class _ViewAllTasksScreenState extends State<ViewAllTasksScreen> {
  List<dynamic> _tasks = [];
  bool _isUpdating = false;
  bool _isDeleting = false;
  bool _isLoading = false;
  String? _currentUserId;
  String? _currentRole;
  // Comments state
  Map<String, List<dynamic>> _taskComments = {};
  Set<String> _loadingCommentTaskIds = {};
  Set<String> _expandedCommentsTaskIds = {};

  @override
  void initState() {
    super.initState();
    _tasks = List.from(widget.tasks);
    _loadCurrentUserId();
    _loadCurrentRole();
    _loadAllTasks();
  }

  Future<void> _loadCurrentUserId() async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    setState(() {
      _currentUserId = prefs.getString('userId') ?? prefs.getString('user_id');
    });
  }

  Future<void> _loadCurrentRole() async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    setState(() {
      _currentRole = prefs.getString('role');
    });
  }

  // Check if user can modify tasks (only non-Client users)
  bool get _canModifyTasks => _currentRole != null && _currentRole != 'Client';

  Future<void> _loadAllTasks() async {
    if (_isLoading) return;
    
    setState(() {
      _isLoading = true;
    });

    try {
      SharedPreferences prefs = await SharedPreferences.getInstance();
      String? userId = prefs.getString('userId') ?? prefs.getString('user_id');
      String? role = prefs.getString('role');
      String? apiToken = prefs.getString('api_token');
      
      List<dynamic> allFetchedTasks = [];
      Map<int, dynamic> taskMap = {};
      
      // For non-Client users, fetch tasks from all sources
      if (role != null && role != 'Client') {
        // First, try fetching without any filters to get all tasks
        try {
          Uri uri = Uri.parse("https://office.buildahome.in/API/get_tasks");
          var response = await http.get(uri).timeout(const Duration(seconds: 15));
          
          if (response.statusCode == 200) {
            final decoded = jsonDecode(response.body);
            List<dynamic> fetchedTasks = [];
            
            if (decoded is Map && decoded['success'] == true && decoded['tasks'] != null) {
              fetchedTasks = decoded['tasks'] is List ? decoded['tasks'] : [];
            } else if (decoded is Map && decoded['tasks'] != null) {
              fetchedTasks = decoded['tasks'] is List ? decoded['tasks'] : [];
            } else if (decoded is List) {
              fetchedTasks = decoded;
            }
            
            allFetchedTasks.addAll(fetchedTasks);
          }
        } catch (e) {
          print('[ViewAllTasksScreen] Error fetching all tasks without filters: $e');
        }
        
        // Also fetch tasks for the user (as backup/complement)
        if (userId != null && userId.isNotEmpty) {
          try {
            Uri uri = Uri.parse("https://office.buildahome.in/API/get_tasks").replace(
              queryParameters: {
                'user_id': userId,
                'assigned_to': userId,
              },
            );
            var response = await http.get(uri).timeout(const Duration(seconds: 15));
            
            if (response.statusCode == 200) {
              final decoded = jsonDecode(response.body);
              List<dynamic> fetchedTasks = [];
              
              if (decoded is Map && decoded['success'] == true && decoded['tasks'] != null) {
                fetchedTasks = decoded['tasks'] is List ? decoded['tasks'] : [];
              } else if (decoded is Map && decoded['tasks'] != null) {
                fetchedTasks = decoded['tasks'] is List ? decoded['tasks'] : [];
              } else if (decoded is List) {
                fetchedTasks = decoded;
              }
              
              allFetchedTasks.addAll(fetchedTasks);
            }
          } catch (e) {
            print('[ViewAllTasksScreen] Error fetching user tasks: $e');
          }
        }
        
        // Fetch user's projects and then fetch tasks for each project
        if (userId != null && userId.isNotEmpty && apiToken != null) {
          try {
            // Get user's projects
            var projectsResponse = await http.post(
              Uri.parse("https://office.buildahome.in/API/get_projects_for_user"),
              body: {
                'user_id': userId,
                'api_token': apiToken,
              },
            ).timeout(const Duration(seconds: 15));
            
            if (projectsResponse.statusCode == 200) {
              final projectsDecoded = jsonDecode(projectsResponse.body);
              List<dynamic> userProjects = [];
              
              if (projectsDecoded is List) {
                userProjects = projectsDecoded;
              } else if (projectsDecoded is Map && projectsDecoded['projects'] != null) {
                userProjects = projectsDecoded['projects'] is List ? projectsDecoded['projects'] : [];
              }
              
              // Extract project IDs
              List<String> projectIds = [];
              for (var project in userProjects) {
                if (project is Map && project['id'] != null) {
                  projectIds.add(project['id'].toString());
                }
              }
              
              // Fetch tasks for each project
              for (String projectId in projectIds) {
                try {
                  Uri projectUri = Uri.parse("https://office.buildahome.in/API/get_tasks").replace(
                    queryParameters: {'project_id': projectId},
                  );
                  var projectResponse = await http.get(projectUri).timeout(const Duration(seconds: 10));
                  
                  if (projectResponse.statusCode == 200) {
                    final projectDecoded = jsonDecode(projectResponse.body);
                    List<dynamic> projectTasks = [];
                    
                    if (projectDecoded is Map && projectDecoded['success'] == true && projectDecoded['tasks'] != null) {
                      projectTasks = projectDecoded['tasks'] is List ? projectDecoded['tasks'] : [];
                    } else if (projectDecoded is Map && projectDecoded['tasks'] != null) {
                      projectTasks = projectDecoded['tasks'] is List ? projectDecoded['tasks'] : [];
                    } else if (projectDecoded is List) {
                      projectTasks = projectDecoded;
                    }
                    
                    // Add tasks to map (deduplicate by ID)
                    for (var task in projectTasks) {
                      if (task is Map && task['id'] != null) {
                        int taskId = int.tryParse(task['id'].toString()) ?? 0;
                        if (taskId > 0) {
                          taskMap[taskId] = task;
                        }
                      }
                    }
                    
                    // Update UI incrementally as we get more tasks
                    if (mounted) {
                      List<dynamic> currentTasks = taskMap.values.toList();
                      currentTasks.sort((a, b) {
                        if (a is! Map || b is! Map) return 0;
                        String aDate = (a['created_at'] ?? '').toString();
                        String bDate = (b['created_at'] ?? '').toString();
                        return bDate.compareTo(aDate);
                      });
                      
                      setState(() {
                        _tasks = currentTasks;
                      });
                    }
                  }
                } catch (e) {
                  // Continue with other projects if one fails
                  print('[ViewAllTasksScreen] Error fetching tasks for project $projectId: $e');
                }
              }
            }
          } catch (e) {
            print('[ViewAllTasksScreen] Error fetching projects: $e');
          }
        }
      } else {
        // For Clients, fetch tasks for their project
        String? projectId = prefs.getString('project_id');
        if (projectId != null && projectId.isNotEmpty) {
          Uri uri = Uri.parse("https://office.buildahome.in/API/get_tasks").replace(
            queryParameters: {'project_id': projectId},
          );
          var response = await http.get(uri).timeout(const Duration(seconds: 20));
          
          if (response.statusCode == 200) {
            final decoded = jsonDecode(response.body);
            List<dynamic> fetchedTasks = [];
            
            if (decoded is Map && decoded['success'] == true && decoded['tasks'] != null) {
              fetchedTasks = decoded['tasks'] is List ? decoded['tasks'] : [];
            } else if (decoded is Map && decoded['tasks'] != null) {
              fetchedTasks = decoded['tasks'] is List ? decoded['tasks'] : [];
            } else if (decoded is List) {
              fetchedTasks = decoded;
            }
            
            allFetchedTasks.addAll(fetchedTasks);
          }
        }
      }
      
      // Deduplicate tasks by ID (for tasks fetched in initial calls that weren't already added)
      // Note: Project-specific tasks are already in taskMap, so we only need to add initial calls
      for (var task in allFetchedTasks) {
        if (task is Map && task['id'] != null) {
          int taskId = int.tryParse(task['id'].toString()) ?? 0;
          if (taskId > 0 && !taskMap.containsKey(taskId)) {
            taskMap[taskId] = task;
          }
        }
      }
      
      // Sort by creation date (newest first)
      List<dynamic> allTasks = taskMap.values.toList();
      allTasks.sort((a, b) {
        if (a is! Map || b is! Map) return 0;
        String aDate = (a['created_at'] ?? '').toString();
        String bDate = (b['created_at'] ?? '').toString();
        return bDate.compareTo(aDate);
      });
      
      if (mounted) {
        setState(() {
          _tasks = allTasks;
          _isLoading = false;
        });
      }
    } catch (e) {
      print('[ViewAllTasksScreen] Error loading all tasks: $e');
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
        // If fetch fails, keep the initial tasks that were passed
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                Icon(Icons.warning, color: Colors.white, size: 20),
                SizedBox(width: 8),
                Expanded(
                  child: Text('Could not load all tasks. Showing available tasks.'),
                ),
              ],
            ),
            backgroundColor: Colors.orange,
            duration: Duration(seconds: 3),
          ),
        );
      }
    }
  }

  String _formatDateTime(String dateTimeStr) {
    try {
      // Parse the datetime string - assume it's in UTC format from the API
      DateTime dateTimeUtc;
      
      // Parse the datetime string
      final parsed = DateTime.parse(dateTimeStr);
      
      // Convert to UTC if not already
      if (parsed.isUtc) {
        dateTimeUtc = parsed;
      } else {
        // Treat as UTC if no timezone info
        dateTimeUtc = DateTime.utc(
          parsed.year,
          parsed.month,
          parsed.day,
          parsed.hour,
          parsed.minute,
          parsed.second,
        );
      }
      
      // Convert UTC to IST (UTC+5:30)
      final dateTimeIst = dateTimeUtc.add(Duration(hours: 5, minutes: 30));
      
      // Get current UTC time and convert to IST for comparison
      final nowUtc = DateTime.now().toUtc();
      final nowIst = nowUtc.add(Duration(hours: 5, minutes: 30));
      
      // Calculate difference in IST
      final difference = nowIst.difference(dateTimeIst);
      
      if (difference.inDays == 0) {
        // Today - show time only
        final formatter = DateFormat('h:mm a');
        return formatter.format(dateTimeIst);
      } else if (difference.inDays == 1) {
        return 'Yesterday';
      } else if (difference.inDays < 7) {
        // This week - show day name
        final formatter = DateFormat('EEE');
        return formatter.format(dateTimeIst);
      } else {
        // Older - show date
        final formatter = DateFormat('MMM d');
        return formatter.format(dateTimeIst);
      }
    } catch (e) {
      return dateTimeStr;
    }
  }

  Color _getStatusColor(String status) {
    switch (status.toLowerCase()) {
      case 'completed':
        return Color(0xFF10B981); // Green
      case 'in_progress':
        return Color(0xFF2196F3); // Blue
      case 'cancelled':
        return Color(0xFFEF4444); // Red
      default:
        return Color(0xFFD97706); // Darker amber/yellow
    }
  }

  IconData _getStatusIcon(String status) {
    switch (status.toLowerCase()) {
      case 'completed':
        return Icons.check_circle;
      case 'in_progress':
        return Icons.work;
      case 'cancelled':
        return Icons.cancel;
      default:
        return Icons.pending;
    }
  }

  Future<void> _updateTaskStatus(int taskId, String newStatus) async {
    if (_isUpdating) return;
    
    setState(() {
      _isUpdating = true;
    });

    try {
      SharedPreferences prefs = await SharedPreferences.getInstance();
      String? apiToken = prefs.getString('api_token');

      if (apiToken == null) {
        throw Exception('Missing credentials. Please log in again.');
      }

      final uri = Uri.parse("https://office.buildahome.in/API/update_task_status");
      final response = await http.post(
        uri,
        body: {
          'task_id': taskId.toString(),
          'status': newStatus,
          'api_token': apiToken,
        },
      ).timeout(const Duration(seconds: 20));

      if (response.statusCode == 200) {
        final decoded = jsonDecode(response.body);
        if (decoded is Map && decoded['success'] == true) {
          setState(() {
            _isUpdating = false;
          });

          if (mounted) {
            // Call onTaskUpdated to refresh tasks on AdminDashboard
            widget.onTaskUpdated?.call();
            
            // Navigate back to AdminDashboard after a short delay
            Future.delayed(Duration(milliseconds: 300), () {
              if (mounted) {
                Navigator.pop(context);
              }
            });
          }
        } else {
          throw Exception(decoded['message'] ?? 'Failed to update task status');
        }
      } else {
        throw Exception('Unable to update task status (code ${response.statusCode})');
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isUpdating = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: [
              Icon(Icons.error, color: Colors.white),
              SizedBox(width: 8),
              Expanded(
                child: Text(e.toString().replaceAll('Exception: ', '')),
              ),
            ],
          ),
          backgroundColor: Colors.red,
          duration: Duration(seconds: 3),
        ),
      );
    }
  }

  Future<void> _deleteTask(int taskId) async {
    if (_isDeleting) return;
    
    // Show confirmation dialog
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppTheme.getBackgroundSecondary(context),
        title: Text('Delete Task', style: TextStyle(color: AppTheme.getTextPrimary(context))),
        content: Text('Are you sure you want to delete this task? This action cannot be undone.', style: TextStyle(color: AppTheme.getTextPrimary(context))),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text('Cancel', style: TextStyle(color: AppTheme.getTextPrimary(context))),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: Text('Delete'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    setState(() {
      _isDeleting = true;
    });

    try {
      SharedPreferences prefs = await SharedPreferences.getInstance();
      String? apiToken = prefs.getString('api_token');

      if (apiToken == null) {
        throw Exception('Missing credentials. Please log in again.');
      }

      final uri = Uri.parse("https://office.buildahome.in/API/delete_task");
      final response = await http.post(
        uri,
        body: {
          'task_id': taskId.toString(),
          'api_token': apiToken,
        },
      ).timeout(const Duration(seconds: 20));

      if (response.statusCode == 200) {
        final decoded = jsonDecode(response.body);
        if (decoded is Map && decoded['success'] == true) {
          setState(() {
            _tasks.removeWhere((t) => t['id']?.toString() == taskId.toString());
            _isDeleting = false;
          });

          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Row(
                  children: [
                    Icon(Icons.check_circle, color: Colors.white),
                    SizedBox(width: 8),
                    Text('Task deleted successfully'),
                  ],
                ),
                backgroundColor: Colors.green,
                duration: Duration(seconds: 2),
              ),
            );
            widget.onTaskUpdated?.call();
          }
        } else {
          throw Exception(decoded['message'] ?? 'Failed to delete task');
        }
      } else {
        throw Exception('Unable to delete task (code ${response.statusCode})');
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isDeleting = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: [
              Icon(Icons.error, color: Colors.white),
              SizedBox(width: 8),
              Expanded(
                child: Text(e.toString().replaceAll('Exception: ', '')),
              ),
            ],
          ),
          backgroundColor: Colors.red,
          duration: Duration(seconds: 3),
        ),
      );
    }
  }

  Future<void> _fetchComments(String taskId) async {
    if (_loadingCommentTaskIds.contains(taskId)) return;

    setState(() {
      _loadingCommentTaskIds.add(taskId);
    });

    try {
      final uri = Uri.parse("https://office.buildahome.in/API/view_task_comments?erp_task_id=$taskId");
      final response = await http.get(uri).timeout(const Duration(seconds: 15));

      if (response.statusCode == 200) {
        final decoded = jsonDecode(response.body);
        if (decoded['success'] == true) {
          setState(() {
            _taskComments[taskId] = decoded['comments'] ?? [];
          });
        }
      }
    } catch (e) {
      print('[ViewAllTasksScreen] Error fetching comments: $e');
    } finally {
      if (mounted) {
        setState(() {
          _loadingCommentTaskIds.remove(taskId);
        });
      }
    }
  }

  Future<void> _addComment(String taskId, String note) async {
    if (note.trim().isEmpty) return;

    try {
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) => Center(child: CircularProgressIndicator()),
      );

      final response = await http.post(
        Uri.parse("https://office.buildahome.in/API/add_task_comment"),
        body: {
          'erp_task_id': taskId,
          'note': note.trim(),
          'added_by': _currentUserId ?? '',
        },
      ).timeout(const Duration(seconds: 15));

      Navigator.pop(context); // Close loading dialog

      if (response.statusCode == 201 || response.statusCode == 200) {
        final decoded = jsonDecode(response.body);
        if (decoded['success'] == true) {
          _fetchComments(taskId); // Refresh comments
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Comment added successfully'), backgroundColor: Colors.green),
          );
        } else {
          throw Exception(decoded['message'] ?? 'Failed to add comment');
        }
      } else {
        throw Exception('Server error: ${response.statusCode}');
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: ${e.toString()}'), backgroundColor: Colors.red),
        );
      }
    }
  }

  Future<void> _deleteComment(int commentId, String taskId) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppTheme.getBackgroundSecondary(context),
        title: Text('Delete Comment', style: TextStyle(color: AppTheme.getTextPrimary(context))),
        content: Text('Are you sure you want to delete this comment?', style: TextStyle(color: AppTheme.getTextPrimary(context))),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text('Cancel', style: TextStyle(color: AppTheme.getTextPrimary(context))),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: Text('Delete'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    try {
      final response = await http.post(
        Uri.parse("https://office.buildahome.in/API/delete_task_comment"),
        body: {'comment_id': commentId.toString()},
      ).timeout(const Duration(seconds: 15));

      if (response.statusCode == 200) {
        final decoded = jsonDecode(response.body);
        if (decoded['success'] == true) {
          _fetchComments(taskId); // Refresh comments
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Comment deleted successfully'), backgroundColor: Colors.green),
          );
        } else {
          throw Exception(decoded['message'] ?? 'Failed to delete comment');
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: ${e.toString()}'), backgroundColor: Colors.red),
        );
      }
    }
  }

  void _showAddCommentDialog(String taskId) {
    final TextEditingController _commentController = TextEditingController();
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppTheme.getBackgroundSecondary(context),
        title: Text('Add Comment', style: TextStyle(color: AppTheme.getTextPrimary(context))),
        content: TextField(
          controller: _commentController,
          style: TextStyle(color: AppTheme.getTextPrimary(context)),
          decoration: InputDecoration(
            hintText: 'Enter your comment here...',
            hintStyle: TextStyle(color: AppTheme.getTextSecondary(context)),
            filled: true,
            fillColor: AppTheme.getBackgroundPrimaryLight(context),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: AppTheme.getPrimaryColor(context).withOpacity(0.3)),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: AppTheme.getPrimaryColor(context).withOpacity(0.3)),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: AppTheme.getPrimaryColor(context), width: 2),
            ),
          ),
          maxLines: 3,
          autofocus: true,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('Cancel', style: TextStyle(color: AppTheme.getTextPrimary(context))),
          ),
          ElevatedButton(
            onPressed: () {
              final note = _commentController.text;
              Navigator.pop(context);
              _addComment(taskId, note);
            },
            style: ElevatedButton.styleFrom(backgroundColor: AppTheme.getPrimaryColor(context)),
            child: Text('Add Comment', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  Widget _buildStatusDropdown(String taskIdStr, String currentStatus, {VoidCallback? onStatusChanged}) {
    final taskId = int.tryParse(taskIdStr) ?? 0;
    final statuses = [
      {'value': 'pending', 'label': 'Pending', 'color': Color(0xFFD97706), 'icon': Icons.pending}, // Darker amber/yellow
      {'value': 'in_progress', 'label': 'In Progress', 'color': Color(0xFF2196F3), 'icon': Icons.work}, // Blue
      {'value': 'completed', 'label': 'Completed', 'color': Color(0xFF10B981), 'icon': Icons.check_circle}, // Green
      {'value': 'cancelled', 'label': 'Cancelled', 'color': Color(0xFFEF4444), 'icon': Icons.cancel}, // Red
    ];

    final currentStatusData = statuses.firstWhere(
      (s) => s['value'] == currentStatus,
      orElse: () => statuses[0],
    );
    final currentColor = currentStatusData['color'] as Color;
    final currentIcon = currentStatusData['icon'] as IconData;

    return Container(
      decoration: BoxDecoration(
        color: AppTheme.getBackgroundPrimaryLight(context),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(
          color: AppTheme.getPrimaryColor(context).withOpacity(0.15),
          width: 1,
        ),
      ),
      child: DropdownButtonFormField<String>(
        value: currentStatus,
        decoration: InputDecoration(
          contentPadding: EdgeInsets.symmetric(horizontal: 6, vertical: 4),
          border: InputBorder.none,
          enabledBorder: InputBorder.none,
          focusedBorder: InputBorder.none,
        ),
        icon: Icon(Icons.arrow_drop_down, color: AppTheme.getTextSecondary(context), size: 16),
        dropdownColor: AppTheme.getBackgroundPrimaryLight(context),
        style: TextStyle(
          color: AppTheme.getTextPrimary(context),
          fontSize: 11,
        ),
        items: statuses.map((statusData) {
          final status = statusData['value'] as String;
          final label = statusData['label'] as String;
          final color = statusData['color'] as Color;
          final icon = statusData['icon'] as IconData;
          
          return DropdownMenuItem<String>(
            value: status,
            child: Row(
              children: [
                Icon(icon, size: 12, color: color),
                SizedBox(width: 6),
                Text(
                  label,
                  style: TextStyle(
                    color: AppTheme.getTextPrimary(context),
                    fontSize: 11,
                  ),
                ),
              ],
            ),
          );
        }).toList(),
        onChanged: _isUpdating ? null : (String? newStatus) {
          if (newStatus != null && newStatus != currentStatus) {
            onStatusChanged?.call();
            _updateTaskStatus(taskId, newStatus);
          }
        },
        selectedItemBuilder: (BuildContext context) {
          return statuses.map((statusData) {
            final label = statusData['label'] as String;
            return Row(
              children: [
                Icon(currentIcon, size: 12, color: currentColor),
                SizedBox(width: 6),
                Text(
                  label,
                  style: TextStyle(
                    color: AppTheme.getTextPrimary(context),
                    fontSize: 11,
                  ),
                ),
              ],
            );
          }).toList();
        },
      ),
    );
  }

  Widget _buildCommentsSection(String taskId) {
    final comments = _taskComments[taskId] ?? [];
    final isLoading = _loadingCommentTaskIds.contains(taskId);
    final isExpanded = _expandedCommentsTaskIds.contains(taskId);

    return Container(
      decoration: BoxDecoration(
        color: AppTheme.getBackgroundPrimary(context).withOpacity(0.4),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: AppTheme.getPrimaryColor(context).withOpacity(0.1),
          width: 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          // Header - Icon only with better styling
          InkWell(
            onTap: () {
              setState(() {
                if (isExpanded) {
                  _expandedCommentsTaskIds.remove(taskId);
                } else {
                  _expandedCommentsTaskIds.add(taskId);
                  _fetchComments(taskId);
                }
              });
            },
            borderRadius: BorderRadius.circular(8),
            child: Padding(
              padding: EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                    Container(
                      padding: EdgeInsets.all(6),
                      decoration: BoxDecoration(
                        color: AppTheme.getPrimaryColor(context).withOpacity(0.1),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Icon(Icons.comment_outlined, size: 16, color: AppTheme.getPrimaryColor(context)),
                    ),
                  if (comments.isNotEmpty) ...[
                    SizedBox(width: 8),
                    Container(
                      padding: EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                      decoration: BoxDecoration(
                        color: AppTheme.getPrimaryColor(context),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text(
                        '${comments.length}',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ],
                  Spacer(),
                  if (isExpanded)
                    GestureDetector(
                      onTap: () => _showAddCommentDialog(taskId),
                      child: Container(
                        padding: EdgeInsets.all(4),
                        decoration: BoxDecoration(
                          color: AppTheme.getPrimaryColor(context).withOpacity(0.1),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Icon(Icons.add_comment_outlined, size: 16, color: AppTheme.getPrimaryColor(context)),
                      ),
                    ),
                  SizedBox(width: 6),
                  Icon(
                    isExpanded ? Icons.expand_less : Icons.expand_more,
                    color: AppTheme.getTextSecondary(context).withOpacity(0.6),
                    size: 18,
                  ),
                ],
              ),
            ),
          ),

          // Content
          if (isExpanded) ...[
            if (isLoading && comments.isEmpty)
              Padding(
                padding: EdgeInsets.all(8),
                child: Center(child: SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2))),
              )
            else if (comments.isEmpty)
              Padding(
                padding: EdgeInsets.all(8),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'No comments',
                      style: TextStyle(color: AppTheme.getTextSecondary(context), fontSize: 10),
                    ),
                    SizedBox(height: 4),
                    TextButton(
                      onPressed: () => _showAddCommentDialog(taskId),
                      style: TextButton.styleFrom(
                        foregroundColor: AppTheme.getPrimaryColor(context),
                        padding: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        minimumSize: Size.zero,
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                      child: Text('Add comment', style: TextStyle(fontSize: 10)),
                    ),
                  ],
                ),
              )
            else
              Padding(
                padding: EdgeInsets.fromLTRB(10, 0, 10, 10),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    ...comments.take(1).map((comment) {
                      final commentId = comment['id'] as int?;
                      final note = comment['note']?.toString() ?? '';
                      final addedByName = comment['added_by_name']?.toString() ?? 'User';
                      final addedBy = comment['added_by']?.toString();
                      final addedAt = comment['added_at']?.toString() ?? '';
                      final isMyComment = _currentUserId != null && addedBy == _currentUserId;

                      return Container(
                        margin: EdgeInsets.only(bottom: 6),
                        padding: EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: AppTheme.getBackgroundPrimary(context),
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(
                            color: AppTheme.getPrimaryColor(context).withOpacity(0.1),
                            width: 1,
                          ),
                        ),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Row(
                                    children: [
                                      Text(
                                        addedByName,
                                        style: TextStyle(
                                          fontWeight: FontWeight.w700,
                                          fontSize: 10,
                                          color: AppTheme.getPrimaryColor(context),
                                        ),
                                      ),
                                      SizedBox(width: 6),
                                      Text(
                                        _formatDateTime(addedAt),
                                        style: TextStyle(
                                          fontSize: 9,
                                          color: AppTheme.getTextSecondary(context).withOpacity(0.7),
                                        ),
                                      ),
                                    ],
                                  ),
                                  SizedBox(height: 4),
                                  Text(
                                    note,
                                    style: TextStyle(
                                      fontSize: 11,
                                      color: AppTheme.getTextPrimary(context).withOpacity(0.85),
                                      height: 1.3,
                                    ),
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ],
                              ),
                            ),
                            if (isMyComment && commentId != null)
                              GestureDetector(
                                onTap: () => _deleteComment(commentId, taskId),
                                child: Container(
                                  padding: EdgeInsets.all(4),
                                  child: Icon(Icons.delete_outline, size: 14, color: Colors.red.withOpacity(0.7)),
                                ),
                              ),
                          ],
                        ),
                      );
                    }).toList(),
                    if (comments.length > 1)
                      Padding(
                        padding: EdgeInsets.only(top: 2),
                        child: Text(
                          '+${comments.length - 1} more comments',
                          style: TextStyle(
                            fontSize: 10,
                            color: AppTheme.getTextSecondary(context).withOpacity(0.7),
                            fontStyle: FontStyle.italic,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
          ],
        ],
      ),
    );
  }

  Widget _buildInfoChip({required IconData icon, required String label, required bool isPrimary}) {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      decoration: BoxDecoration(
        color: isPrimary 
            ? AppTheme.getPrimaryColor(context).withOpacity(0.08)
            : Colors.transparent,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            icon,
            size: 13,
            color: isPrimary 
                ? AppTheme.getPrimaryColor(context)
                : AppTheme.getTextSecondary(context).withOpacity(0.7),
          ),
          SizedBox(width: 5),
          Text(
            label,
            style: TextStyle(
              color: isPrimary
                  ? AppTheme.getTextPrimary(context)
                  : AppTheme.getTextSecondary(context).withOpacity(0.8),
              fontSize: 11,
              fontWeight: isPrimary ? FontWeight.w600 : FontWeight.w500,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }

  Widget _buildTaskCard(Map<String, dynamic> task) {
    final taskId = task['id']?.toString() ?? '';
    final taskUserId = task['user_id']?.toString() ?? '';
    final projectName = task['project_name']?.toString() ?? '';
    final assignedToName = task['assigned_to_name']?.toString() ?? '';
    final status = task['status']?.toString() ?? 'pending';
    final note = task['note']?.toString() ?? '';
    final createdAt = task['created_at']?.toString() ?? '';
    final statusColor = _getStatusColor(status);
    final statusIcon = _getStatusIcon(status);
    final isCreatedByMe = _currentUserId != null && taskUserId == _currentUserId;

    return Container(
      margin: EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: AppTheme.getBackgroundSecondary(context),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: statusColor.withOpacity(0.25),
          width: 1.5,
        ),
        boxShadow: [
          BoxShadow(
            color: statusColor.withOpacity(0.08),
            blurRadius: 8,
            offset: Offset(0, 2),
          ),
          BoxShadow(
            color: Theme.of(context).brightness == Brightness.dark 
                ? Colors.black.withOpacity(0.3)
                : Colors.black.withOpacity(0.03),
            blurRadius: 4,
            offset: Offset(0, 1),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          // Header Section with better hierarchy
          Container(
            padding: EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: statusColor.withOpacity(0.06),
              borderRadius: BorderRadius.only(
                topLeft: Radius.circular(12),
                topRight: Radius.circular(12),
              ),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Status indicator - more prominent
                Container(
                  width: 4,
                  height: 48,
                  decoration: BoxDecoration(
                    color: statusColor,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Task #$taskId',
                                  style: TextStyle(
                                    color: AppTheme.getTextPrimary(context),
                                    fontSize: 15,
                                    fontWeight: FontWeight.w800,
                                    letterSpacing: -0.3,
                                    height: 1.2,
                                  ),
                                ),
                                if (note.isNotEmpty) ...[
                                  SizedBox(height: 6),
                                  Text(
                                    note,
                                    style: TextStyle(
                                      color: AppTheme.getTextPrimary(context).withOpacity(0.75),
                                      fontSize: 12,
                                      fontWeight: FontWeight.w500,
                                      height: 1.4,
                                    ),
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ],
                              ],
                            ),
                          ),
                          SizedBox(width: 8),
                          Container(
                            padding: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                            decoration: BoxDecoration(
                              color: statusColor.withOpacity(0.12),
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(
                                color: statusColor.withOpacity(0.3),
                                width: 1,
                              ),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(statusIcon, size: 14, color: statusColor),
                                SizedBox(width: 5),
                                Text(
                                  status.toUpperCase(),
                                  style: TextStyle(
                                    color: statusColor,
                                    fontSize: 10,
                                    fontWeight: FontWeight.w800,
                                    letterSpacing: 0.8,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          if (_canModifyTasks) ...[
                            SizedBox(width: 6),
                            PopupMenuButton<String>(
                              icon: Icon(Icons.more_vert, color: AppTheme.getTextSecondary(context).withOpacity(0.6), size: 20),
                              padding: EdgeInsets.zero,
                              constraints: BoxConstraints(),
                              onSelected: (value) async {
                                if (value == 'delete') {
                                  _deleteTask(int.tryParse(taskId) ?? 0);
                                } else if (value == 'change_status') {
                                  await showDialog(
                                    context: context,
                                    builder: (dialogContext) => AlertDialog(
                                      backgroundColor: AppTheme.getBackgroundSecondary(context),
                                      title: Text('Change Status', style: TextStyle(color: AppTheme.getTextPrimary(context))),
                                      content: _buildStatusDropdown(taskId, status, onStatusChanged: () {
                                        Navigator.pop(dialogContext);
                                      }),
                                      actions: [
                                        TextButton(
                                          onPressed: () => Navigator.pop(dialogContext),
                                          child: Text('Cancel', style: TextStyle(color: AppTheme.getTextPrimary(context))),
                                        ),
                                      ],
                                    ),
                                  );
                                }
                              },
                              itemBuilder: (context) => [
                                PopupMenuItem(
                                  value: 'change_status',
                                  child: Row(
                                    children: [
                                      Icon(Icons.edit, size: 16, color: AppTheme.getTextPrimary(context)),
                                      SizedBox(width: 8),
                                      Text('Change Status', style: TextStyle(color: AppTheme.getTextPrimary(context), fontSize: 13)),
                                    ],
                                  ),
                                ),
                                if (isCreatedByMe)
                                  PopupMenuItem(
                                    value: 'delete',
                                    child: Row(
                                      children: [
                                        Icon(Icons.delete, size: 16, color: Colors.red),
                                        SizedBox(width: 8),
                                        Text('Delete Task', style: TextStyle(color: Colors.red, fontSize: 13)),
                                      ],
                                    ),
                                  ),
                              ],
                            ),
                          ],
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          
          // Info Section with better hierarchy
          if (projectName.isNotEmpty || assignedToName.isNotEmpty || createdAt.isNotEmpty)
            Padding(
              padding: EdgeInsets.fromLTRB(14, 10, 14, 12),
              child: Container(
                padding: EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                decoration: BoxDecoration(
                  color: AppTheme.getBackgroundPrimary(context).withOpacity(0.5),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: AppTheme.getPrimaryColor(context).withOpacity(0.08),
                    width: 1,
                  ),
                ),
                child: Wrap(
                  spacing: 12,
                  runSpacing: 8,
                  children: [
                    if (projectName.isNotEmpty)
                      _buildInfoChip(
                        icon: Icons.folder_outlined,
                        label: projectName,
                        isPrimary: true,
                      ),
                    if (assignedToName.isNotEmpty)
                      _buildInfoChip(
                        icon: Icons.person_outline,
                        label: assignedToName,
                        isPrimary: true,
                      ),
                    if (createdAt.isNotEmpty)
                      _buildInfoChip(
                        icon: Icons.access_time,
                        label: _formatDateTime(createdAt),
                        isPrimary: false,
                      ),
                  ],
                ),
              ),
            ),
          
          // Comments Section - cleaner design
          Padding(
            padding: EdgeInsets.fromLTRB(14, 0, 14, 12),
            child: _buildCommentsSection(taskId),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        elevation: 0,
        leading: IconButton(
          icon: Icon(Icons.arrow_back),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          'All Tasks',
        ),
        actions: [
          DarkModeToggle(showLabel: false),
          SizedBox(width: 8),
        ],
      ),
      body: _isLoading && _tasks.isEmpty
          ? Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  CircularProgressIndicator(
                    valueColor: AlwaysStoppedAnimation<Color>(AppTheme.primaryColorConst),
                  ),
                  SizedBox(height: 16),
                  Text(
                    'Loading all tasks...',
                    style: TextStyle(
                      color: AppTheme.getTextSecondary(context),
                      fontSize: 14,
                    ),
                  ),
                ],
              ),
            )
          : _tasks.isEmpty
              ? RefreshIndicator(
                  onRefresh: () async {
                    await _loadAllTasks();
                    widget.onTaskUpdated?.call();
                  },
                  color: AppTheme.getPrimaryColor(context),
                  child: SingleChildScrollView(
                    physics: AlwaysScrollableScrollPhysics(),
                    padding: EdgeInsets.all(20),
                    child: Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Container(
                            padding: EdgeInsets.all(20),
                            decoration: BoxDecoration(
                              color: AppTheme.getPrimaryColor(context).withOpacity(0.15),
                              shape: BoxShape.circle,
                            ),
                            child: Icon(
                              Icons.task_alt,
                              size: 56,
                              color: AppTheme.getPrimaryColor(context),
                            ),
                          ),
                          SizedBox(height: 20),
                          Text(
                            'No tasks found',
                            style: TextStyle(
                              color: AppTheme.getTextPrimary(context),
                              fontSize: 18,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          SizedBox(height: 8),
                          Text(
                            'Pull down to refresh',
                            style: TextStyle(
                              color: AppTheme.getTextSecondary(context),
                              fontSize: 14,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                )
              : RefreshIndicator(
                  onRefresh: () async {
                    await _loadAllTasks();
                    widget.onTaskUpdated?.call();
                  },
                  color: AppTheme.getPrimaryColor(context),
                  child: ListView(
                    padding: EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    children: _tasks.map((task) {
                      if (task is Map<String, dynamic>) {
                        return _buildTaskCard(task);
                      }
                      return SizedBox.shrink();
                    }).toList(),
                  ),
                ),
    );
  }
}

