import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';
import 'package:percent_indicator/linear_percent_indicator.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app_theme.dart';

class TaskWidget extends StatelessWidget {
  const TaskWidget({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final canPop = Navigator.of(context).canPop();
    return Scaffold(
      backgroundColor: AppTheme.backgroundPrimary,
      appBar: AppBar(
        backgroundColor: AppTheme.backgroundSecondary,
        automaticallyImplyLeading: true,
        title: Text(
          'Schedule',
          style: theme.textTheme.headlineSmall?.copyWith(fontSize: 20),
        ),
        leading: canPop
            ? IconButton(
                icon: const Icon(Icons.arrow_back_ios_new_rounded),
                onPressed: () => Navigator.of(context).maybePop(),
              )
            : null,
      ),
      body: const TaskScreenClass(),
    );
  }
}

enum TaskStatusFilter { all, inProgress, completed, upcoming }

class TaskScreenClass extends StatefulWidget {
  const TaskScreenClass({super.key});

  @override
  TaskScreen createState() => TaskScreen();
}

class TaskScreen extends State<TaskScreenClass> {
  List<dynamic>? _tasks;
  bool _isLoading = false;
  String? _errorMessage;
  TaskStatusFilter _selectedFilter = TaskStatusFilter.all;
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    _loadTasks();
  }

  Future<void> _loadTasks() async {
    if (!mounted) return;
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final prefs = await SharedPreferences.getInstance();
      final projectId = prefs.getString('project_id');
      if (projectId == null) {
        throw Exception('Project not selected. Please reopen the project and try again.');
      }

      final response = await http.get(Uri.parse('https://office.buildahome.in/API/get_all_tasks?project_id=$projectId&nt_toggle=0'));
      if (response.statusCode != 200) {
        throw Exception('Unable to fetch schedule right now.');
      }

      final decoded = jsonDecode(response.body);
      if (!mounted) return;
      setState(() {
        _tasks = decoded is List ? decoded : [];
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _errorMessage = e.toString();
      });
    } finally {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
      });
    }
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final stats = _computeStats(_tasks);
    final filteredTasks = _filterTasks(_tasks);
    final showFilteredEmpty = !_isLoading && _errorMessage == null && (_tasks?.isNotEmpty ?? false) && filteredTasks.isEmpty;

    return RefreshIndicator(
      color: AppTheme.primaryColorConst,
      onRefresh: _loadTasks,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(20, 24, 20, 32),
        children: [
          _buildHeader(theme),
          const SizedBox(height: 16),
          if (_tasks != null && _tasks!.isNotEmpty) ...[
            _buildSummaryCards(stats),
            const SizedBox(height: 16),
            _buildFilterChips(),
            const SizedBox(height: 16),
            _buildSearchBar(),
            const SizedBox(height: 20),
          ],
          if (_errorMessage != null) _buildErrorCard(_errorMessage!),
          if (_isLoading && (_tasks == null || _tasks!.isEmpty)) _buildSkeletonLoader(),
          if (!_isLoading && _errorMessage == null && (_tasks == null || _tasks!.isEmpty)) _buildEmptyState(),
          if (showFilteredEmpty) _buildFilteredEmptyState(isSearchEmpty: _isSearching),
          if (!_isLoading && filteredTasks.isNotEmpty)
            ...List.generate(filteredTasks.length, (index) {
              final task = filteredTasks[index];
              return AnimatedWidgetSlide(
                direction: index % 2 == 0 ? SlideDirection.leftToRight : SlideDirection.rightToLeft,
                duration: const Duration(milliseconds: 450),
                child: TaskItem(
                  task['task_name'].toString(),
                  task['start_date'].toString(),
                  task['end_date'].toString(),
                  task['sub_tasks'].toString(),
                  task['progress'].toString(),
                  task['s_note'].toString(),
                ),
              );
            }),
        ],
      ),
    );
  }

  Widget _buildHeader(ThemeData theme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Home construction schedule',
          style: theme.textTheme.headlineSmall?.copyWith(
            color: AppTheme.textPrimary,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          'Preview milestone timelines, monitor progress and stay aligned with buildAhome.',
          style: theme.textTheme.bodyMedium?.copyWith(color: AppTheme.textSecondary),
        ),
      ],
    );
  }

  Widget _buildSummaryCards(Map<String, int> stats) {
    final cards = [
      _SummaryCard(
        title: 'Total tasks',
        subtitle: 'Overall milestones',
        value: (stats['total'] ?? 0).toString(),
        icon: Icons.view_timeline,
        gradient: const [Color(0xFFE3F2FD), Color(0xFFC5E1F5)],
      ),
      _SummaryCard(
        title: 'In progress',
        subtitle: 'Actively tracked',
        value: (stats['inProgress'] ?? 0).toString(),
        icon: Icons.run_circle_outlined,
        valueColor: Colors.orange[700],
        gradient: const [Color(0xFFFFF3E0), Color(0xFFFFE0B2)],
      ),
      _SummaryCard(
        title: 'Upcoming',
        subtitle: 'Yet to begin',
        value: (stats['pending'] ?? 0).toString(),
        icon: Icons.pending_actions,
        valueColor: Colors.red[600],
        gradient: const [Color(0xFFFFEBEE), Color(0xFFFFCDD2)],
      ),
      _SummaryCard(
        title: 'Completed',
        subtitle: 'Signed off',
        value: (stats['completed'] ?? 0).toString(),
        icon: Icons.verified,
        valueColor: Colors.green[700],
        gradient: const [Color(0xFFE8F5E9), Color(0xFFC8E6C9)],
      ),
    ];

    return Wrap(
      spacing: 16,
      runSpacing: 16,
      children: cards,
    );
  }

  Widget _buildFilterChips() {
    return Wrap(
      spacing: 12,
      runSpacing: 12,
      children: TaskStatusFilter.values.map((filter) {
        final isSelected = _selectedFilter == filter;
        return ChoiceChip(
          label: Text(_filterLabel(filter)),
          selected: isSelected,
          selectedColor: AppTheme.primaryColorConst,
          backgroundColor: AppTheme.backgroundSecondary,
          labelStyle: TextStyle(
            color: isSelected ? Colors.white : AppTheme.textPrimary,
            fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
          ),
          onSelected: (value) {
            if (!value) return;
            setState(() => _selectedFilter = filter);
          },
        );
      }).toList(),
    );
  }

  Widget _buildSearchBar() {
    return TextField(
      controller: _searchController,
      onChanged: (value) => setState(() => _searchQuery = value),
      decoration: InputDecoration(
        hintText: 'Search tasks, notes or dates',
        prefixIcon: Icon(Icons.search, color: AppTheme.textSecondary),
        suffixIcon: _searchQuery.isEmpty
            ? null
            : IconButton(
                icon: Icon(Icons.close, color: AppTheme.textSecondary),
                onPressed: () {
                  _searchController.clear();
                  setState(() => _searchQuery = '');
                },
              ),
        filled: true,
        fillColor: AppTheme.backgroundSecondary,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide.none,
        ),
      ),
    );
  }

  Widget _buildSkeletonLoader() {
    final width = MediaQuery.of(context).size.width;
    final summaryWidth = (width - 56) / 2;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _skeletonBar(width: 220, height: 20),
        const SizedBox(height: 8),
        _skeletonBar(width: width * 0.65, height: 14),
        const SizedBox(height: 24),
        Wrap(
          spacing: 16,
          runSpacing: 16,
          children: List.generate(
            3,
            (_) => Container(
              width: summaryWidth,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: AppTheme.backgroundSecondary,
                borderRadius: BorderRadius.circular(18),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _skeletonBar(width: 120, height: 14),
                  const SizedBox(height: 10),
                  _skeletonBar(width: 60, height: 24),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(height: 20),
        ...List.generate(3, (_) => _buildSkeletonCard()),
      ],
    );
  }

  Widget _buildSkeletonCard() {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppTheme.backgroundSecondary,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              _skeletonBar(width: 40, height: 40, radius: 14),
              const SizedBox(width: 12),
              Expanded(child: _skeletonBar(height: 18)),
            ],
          ),
          const SizedBox(height: 12),
          _skeletonBar(width: 140, height: 12),
          const SizedBox(height: 8),
          _skeletonBar(width: double.infinity, height: 10),
        ],
      ),
    );
  }

  Widget _skeletonBar({double? width, double height = 14, double radius = 10}) {
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: AppTheme.backgroundPrimaryLight,
        borderRadius: BorderRadius.circular(radius),
      ),
    );
  }

  Widget _buildErrorCard(String message) {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.red[50],
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.red.withOpacity(0.2)),
      ),
      child: Row(
        children: [
          Icon(Icons.error_outline, color: Colors.red[500]),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              message,
              style: TextStyle(color: Colors.red[700]),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState() {
    return Container(
      padding: const EdgeInsets.all(32),
      decoration: BoxDecoration(
        color: AppTheme.backgroundSecondary,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        children: [
          Icon(Icons.event_available, color: AppTheme.primaryColorConst, size: 32),
          const SizedBox(height: 12),
          Text(
            'No scheduled tasks yet',
            style: TextStyle(color: AppTheme.textPrimary, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 4),
          Text(
            'Tasks assigned to your project will appear here automatically.',
            textAlign: TextAlign.center,
            style: TextStyle(color: AppTheme.textSecondary, fontSize: 13),
          ),
        ],
      ),
    );
  }

  Widget _buildFilteredEmptyState({bool isSearchEmpty = false}) {
    return Container(
      padding: const EdgeInsets.all(28),
      decoration: BoxDecoration(
        color: AppTheme.backgroundSecondary,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppTheme.primaryColorConst.withOpacity(0.08)),
      ),
      child: Column(
        children: [
          Icon(Icons.inbox_outlined, size: 36, color: AppTheme.textSecondary),
          const SizedBox(height: 10),
          Text(
            isSearchEmpty ? 'No tasks match your search' : 'No tasks for this view',
            style: TextStyle(fontWeight: FontWeight.w600, color: AppTheme.textPrimary),
          ),
          const SizedBox(height: 6),
          Text(
            isSearchEmpty ? 'Try a different keyword or clear the search.' : 'Try switching to a different filter to see other milestones.',
            textAlign: TextAlign.center,
            style: TextStyle(color: AppTheme.textSecondary),
          ),
        ],
      ),
    );
  }

  Map<String, int> _computeStats(List<dynamic>? tasks) {
    if (tasks == null) return {'total': 0, 'completed': 0, 'inProgress': 0, 'pending': 0};
    int completed = 0;
    int inProgress = 0;
    int pending = 0;
    for (final task in tasks) {
      final ratio = _taskProgress(task);
      if (ratio >= 0.99) {
        completed++;
      } else if (ratio <= 0.01) {
        pending++;
      } else {
        inProgress++;
      }
    }
    return {
      'total': tasks.length,
      'completed': completed,
      'inProgress': inProgress,
      'pending': pending,
    };
  }

  List<dynamic> _filterTasks(List<dynamic>? tasks) {
    if (tasks == null) return [];
    List<dynamic> filtered;
    switch (_selectedFilter) {
      case TaskStatusFilter.all:
        filtered = tasks;
        break;
      case TaskStatusFilter.inProgress:
        filtered = tasks.where((task) => _taskProgress(task) > 0.01 && _taskProgress(task) < 0.99).toList();
        break;
      case TaskStatusFilter.completed:
        filtered = tasks.where((task) => _taskProgress(task) >= 0.99).toList();
        break;
      case TaskStatusFilter.upcoming:
        filtered = tasks.where((task) => _taskProgress(task) <= 0.01).toList();
        break;
    }

    if (!_isSearching) return filtered;
    final query = _searchQuery.trim().toLowerCase();
    return filtered.where((task) {
      final name = task['task_name']?.toString().toLowerCase() ?? '';
      final note = task['s_note']?.toString().toLowerCase() ?? '';
      final dates = '${task['start_date'] ?? ''} ${task['end_date'] ?? ''}'.toLowerCase();
      return name.contains(query) || note.contains(query) || dates.contains(query);
    }).toList();
  }

  bool get _isSearching => _searchQuery.trim().isNotEmpty;

  double _taskProgress(dynamic task) {
    final total = task['sub_tasks']?.toString().split('^') ?? [];
    final done = task['progress']?.toString().split('|') ?? [];
    if (total.length <= 1) return 0;
    final ratio = (done.length - 1) / (total.length - 1);
    if (ratio.isNaN) return 0;
    return ratio.clamp(0.0, 1.0);
  }

  String _filterLabel(TaskStatusFilter filter) {
    switch (filter) {
      case TaskStatusFilter.all:
        return 'All';
      case TaskStatusFilter.inProgress:
        return 'In progress';
      case TaskStatusFilter.completed:
        return 'Completed';
      case TaskStatusFilter.upcoming:
        return 'Upcoming';
    }
  }
}

class _SummaryCard extends StatelessWidget {
  final String title;
  final String subtitle;
  final String value;
  final IconData icon;
  final List<Color> gradient;
  final Color? valueColor;

  const _SummaryCard({
    required this.title,
    required this.subtitle,
    required this.value,
    required this.icon,
    required this.gradient,
    this.valueColor,
  });

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.of(context).size.width;
    final targetWidth = (width - 56) / 2;
    return Container(
      width: targetWidth < 120 ? double.infinity : targetWidth,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        gradient: LinearGradient(colors: gradient),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppTheme.primaryColorConst.withOpacity(0.04)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 8,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.8),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Icon(icon, color: AppTheme.primaryColorConst),
              ),
              const Spacer(),
              Text(
                value,
                style: TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                  color: valueColor ?? AppTheme.textPrimary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            title,
            style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 4),
          Text(
            subtitle,
            style: TextStyle(color: AppTheme.textSecondary, fontSize: 12),
          ),
        ],
      ),
    );
  }
}

class TaskItem extends StatefulWidget {
  final String _taskName;
  final String _startDate;
  final String _endDate;
  final String _subTasks;
  final String _progressStr;
  final String note;

  TaskItem(this._taskName, this._startDate, this._endDate, this._subTasks, this._progressStr, this.note);

  @override
  TaskItemWidget createState() => TaskItemWidget(_taskName, _startDate, _endDate, _progressStr, _subTasks, note);
}

class TaskItemWidget extends State<TaskItem> {
  String _taskName;
  String _startDate;
  String _endDate;
  String _subTasks;
  String _progressStr;
  String note;

  bool _expanded = false;
  late List<String> notes;

  TaskItemWidget(this._taskName, this._startDate, this._endDate, this._progressStr, this._subTasks, this.note);

  @override
  void initState() {
    super.initState();
    notes = note.split("|");
  }

  double _progress() {
    final total = _subTasks.split("^");
    final done = _progressStr.split("|");
    final percent = (done.length - 1) / (total.length - 1);
    if (percent.isNaN) return 0;
    return percent.clamp(0.0, 1.0);
  }

  @override
  Widget build(BuildContext context) {
    final progressValue = _progress();
    final isCompleted = progressValue >= 0.99;
    final isUpcoming = progressValue <= 0.01;
    final statusLabel = isCompleted
        ? 'Completed'
        : isUpcoming
            ? 'Upcoming'
            : 'In progress';
    final statusColor = isCompleted
        ? Colors.green[600]!
        : isUpcoming
            ? Colors.red[600]!
            : Colors.orange[600]!;
    final statusIcon = isCompleted ? Icons.check : (isUpcoming ? Icons.pending : Icons.run_circle);

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 8),
      decoration: BoxDecoration(
        color: AppTheme.backgroundSecondary,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppTheme.primaryColorConst.withOpacity(0.06)),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(20),
          onTap: () => setState(() => _expanded = !_expanded),
          child: Padding(
            padding: const EdgeInsets.all(18),
            child: Column(
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: statusColor.withOpacity(0.12),
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: Icon(statusIcon, color: statusColor, size: 20),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            _taskName,
                            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            _formatDateRange(_startDate, _endDate),
                            style: TextStyle(color: AppTheme.textSecondary, fontSize: 13),
                          ),
                        ],
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                      decoration: BoxDecoration(
                        color: statusColor.withOpacity(0.15),
                        borderRadius: BorderRadius.circular(30),
                      ),
                      child: Text(
                        statusLabel,
                        style: TextStyle(color: statusColor, fontSize: 12, fontWeight: FontWeight.w600),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Icon(_expanded ? Icons.expand_less : Icons.expand_more, color: AppTheme.textSecondary),
                  ],
                ),
                AnimatedSize(
                  duration: const Duration(milliseconds: 250),
                  curve: Curves.easeInOut,
                  child: _expanded
                      ? Padding(
                          padding: const EdgeInsets.only(top: 16),
                          child: Column(
                            children: [
                              _buildProgressSection(progressValue),
                              const SizedBox(height: 12),
                              _buildSubTaskList(),
                            ],
                          ),
                        )
                      : const SizedBox(),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildProgressSection(double progressValue) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppTheme.backgroundPrimaryLight,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Progress', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
          const SizedBox(height: 8),
          LinearPercentIndicator(
            lineHeight: 10,
            percent: progressValue,
            animation: true,
            animationDuration: 600,
            barRadius: const Radius.circular(8),
            backgroundColor: Colors.grey[300],
            progressColor: AppTheme.primaryColorConst,
          ),
          const SizedBox(height: 6),
          Text('${(progressValue * 100).round()}% complete', style: TextStyle(color: AppTheme.textSecondary, fontSize: 12)),
        ],
      ),
    );
  }

  Widget _buildSubTaskList() {
    final subTasks = _subTasks.split("^");
    final entries = subTasks.where((element) => element.trim().isNotEmpty).toList();
    if (entries.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: AppTheme.backgroundSecondary,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppTheme.primaryColorConst.withOpacity(0.05)),
        ),
        child: Text(
          'No sub-tasks defined for this milestone.',
          style: TextStyle(color: AppTheme.textSecondary, fontSize: 13),
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppTheme.primaryColorConst.withOpacity(0.05)),
      ),
      child: Column(
        children: List.generate(entries.length, (index) {
          final parts = entries[index].split("|");
          if (parts.length < 3) return const SizedBox.shrink();
          final taskLabel = parts[0];
          final start = _formatInlineDate(parts[1]);
          final end = _formatInlineDate(parts[2]);
          final noteLine = notes.length > index && notes[index].trim().isNotEmpty ? notes[index].trim() : null;
          return Padding(
            padding: EdgeInsets.only(top: index == 0 ? 0 : 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(Icons.radio_button_checked, size: 18, color: AppTheme.primaryColorConst.withOpacity(0.7)),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '$taskLabel',
                            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                          ),
                          Text(
                            '$start • $end',
                            style: TextStyle(color: AppTheme.textSecondary, fontSize: 12),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                if (noteLine != null)
                  Padding(
                    padding: const EdgeInsets.only(left: 26, top: 4),
                    child: Text(
                      'buildAhome: $noteLine',
                      style: TextStyle(color: AppTheme.textSecondary, fontSize: 12),
                    ),
                  ),
              ],
            ),
          );
        }),
      ),
    );
  }

  String _formatDateRange(String start, String end) {
    final startLabel = _formatInlineDate(start);
    final endLabel = _formatInlineDate(end);
    if (startLabel == null && endLabel == null) return 'Schedule not set';
    if (startLabel != null && endLabel != null) return '$startLabel • $endLabel';
    return startLabel ?? endLabel!;
  }

  String? _formatInlineDate(String raw) {
    if (raw.trim().isEmpty) return null;
    try {
      final date = DateTime.parse(raw);
      return DateFormat('dd MMM').format(date);
    } catch (_) {
      return null;
    }
  }
}

enum SlideDirection { leftToRight, rightToLeft, topToBottom, bottomToTop }

class AnimatedWidgetSlide extends StatefulWidget {
  final Widget child;
  final SlideDirection direction;
  final Duration duration;

  const AnimatedWidgetSlide({
    super.key,
    required this.child,
    required this.direction,
    required this.duration,
  });

  @override
  _AnimatedWidgetSlideState createState() => _AnimatedWidgetSlideState();
}

class _AnimatedWidgetSlideState extends State<AnimatedWidgetSlide> with SingleTickerProviderStateMixin {
  late AnimationController _animationController;
  late Animation<Offset> _slideAnimation;

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      vsync: this,
      duration: widget.duration,
    );

    switch (widget.direction) {
      case SlideDirection.leftToRight:
        _slideAnimation = Tween<Offset>(begin: const Offset(-1.0, 0.0), end: Offset.zero).animate(CurvedAnimation(parent: _animationController, curve: Curves.easeIn));
        break;
      case SlideDirection.rightToLeft:
        _slideAnimation = Tween<Offset>(begin: const Offset(1.0, 0.0), end: Offset.zero).animate(CurvedAnimation(parent: _animationController, curve: Curves.easeIn));
        break;
      case SlideDirection.topToBottom:
        _slideAnimation = Tween<Offset>(begin: const Offset(0.0, -1.0), end: Offset.zero).animate(CurvedAnimation(parent: _animationController, curve: Curves.easeInOut));
        break;
      case SlideDirection.bottomToTop:
        _slideAnimation = Tween<Offset>(begin: const Offset(0.0, 1.0), end: Offset.zero).animate(CurvedAnimation(parent: _animationController, curve: Curves.easeInOut));
        break;
    }

    _animationController.forward();
  }

  @override
  Widget build(BuildContext context) {
    return SlideTransition(
      position: _slideAnimation,
      child: widget.child,
    );
  }

  @override
  void dispose() {
    _animationController.dispose();
    super.dispose();
  }
}

