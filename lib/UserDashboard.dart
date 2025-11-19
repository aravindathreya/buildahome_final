import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:percent_indicator/linear_percent_indicator.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:shimmer/shimmer.dart';
import "Payments.dart";
import 'app_theme.dart';
import 'Drawings.dart';
import 'Scheduler.dart';
import 'Gallery.dart';
import 'NotesAndComments.dart';
import 'checklist_categories.dart';
import 'services/data_provider.dart';
import 'AdminDashboard.dart';
import 'RequestDrawing.dart';

class UserDashboardLayout extends StatefulWidget {
  final bool fromAdminDashboard;

  UserDashboardLayout({this.fromAdminDashboard = false});

  @override
  UserDashboardLayoutState createState() => UserDashboardLayoutState();
}

class UserDashboardLayoutState extends State<UserDashboardLayout> {
  String displayName = 'My Home';

  @override
  void initState() {
    super.initState();
    _loadDisplayName();
  }

  _loadDisplayName() async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    String loadedUsername = ' ';
    if (prefs.containsKey("client_name")) {
      loadedUsername = prefs.getString('client_name') ?? ' ';
    } else {
      loadedUsername = prefs.getString('username') ?? ' ';
    }

    String name = _getDisplayName(loadedUsername);
    if (mounted) {
      setState(() {
        displayName = name;
      });
    }
  }

  String _getDisplayName(String username) {
    if (username.isEmpty || username == ' ') {
      return 'Your';
    }
    try {
      String name = username.split('-')[0].trim();
      return name.isNotEmpty ? name : username.trim();
    } catch (e) {
      return username.trim().isNotEmpty ? username.trim() : 'Your';
    }
  }

  @override
  Widget build(BuildContext context) {
    final appTitle = 'buildAhome';
    return MaterialApp(
      title: appTitle,
      theme: AppTheme.darkTheme,
      home: PopScope(
        canPop: !widget.fromAdminDashboard, // Allow pop only if not from admin dashboard
        onPopInvoked: (didPop) {
          if (widget.fromAdminDashboard && !didPop) {
            // Navigate back to admin dashboard when native back button is pressed
            Navigator.pushReplacement(
              context,
              MaterialPageRoute(builder: (context) => AdminDashboard()),
            );
          }
        },
        child: Scaffold(
          backgroundColor: AppTheme.backgroundPrimary,
          body: SafeArea(
            child: Column(
              children: [
                // Enhanced custom header
                Container(
                  padding: EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [
                        AppTheme.backgroundSecondary,
                        AppTheme.backgroundPrimaryLight,
                      ],
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.08),
                        blurRadius: 8,
                        offset: Offset(0, 2),
                      ),
                    ],
                  ),
                  child: Row(
                    children: [
                      if (widget.fromAdminDashboard)
                        InkWell(
                          onTap: () {
                            Navigator.pushReplacement(
                              context,
                              MaterialPageRoute(builder: (context) => AdminDashboard()),
                            );
                          },
                          borderRadius: BorderRadius.circular(12),
                          child: Container(
                            padding: EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              color: AppTheme.backgroundPrimary,
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                color: AppTheme.primaryColorConst.withOpacity(0.3),
                                width: 1,
                              ),
                            ),
                            child: Icon(
                              Icons.arrow_back,
                              color: AppTheme.textPrimary,
                              size: 20,
                            ),
                          ),
                        ),
                      if (widget.fromAdminDashboard) SizedBox(width: 12),
                      Container(
                        padding: EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: AppTheme.primaryColorConst.withOpacity(0.15),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Icon(
                          Icons.home_rounded,
                          color: AppTheme.primaryColorConst,
                          size: 24,
                        ),
                      ),
                      SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              displayName,
                              style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                                color: AppTheme.textPrimary,
                                letterSpacing: 0.5,
                              ),
                            ),
                            Text(
                              'Project Dashboard',
                              style: TextStyle(
                                fontSize: 12,
                                color: AppTheme.textSecondary,
                                fontWeight: FontWeight.w400,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: UserDashboardScreen(),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class UserDashboardScreen extends StatefulWidget {
  @override
  UserDashboardScreenState createState() {
    return UserDashboardScreenState();
  }
}

class UserDashboardScreenState extends State<UserDashboardScreen> {
  List dailyUpdateList = [];
  var username = ' ';
  var updatePostedOnDate = " ";
  var value = " ";
  String? completed;
  dynamic updateResponseBody;
  var blocked = false;
  var bolckReason = '';
  var location = '';
  var expanded = false;
  bool _isLoadingSummary = true;
  bool _isLoadingUpdates = true;
  bool _hasLoadedSummary = false;
  bool _hasLoadedUpdates = false;
  final TextEditingController _quickSearchController = TextEditingController();
  final FocusNode _quickSearchFocusNode = FocusNode();
  final ScrollController _scrollController = ScrollController();
  String _quickSearchQuery = '';

  @override
  void dispose() {
    _quickSearchController.dispose();
    _quickSearchFocusNode.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    // Load cached data (if available) without blocking the transition
    loadDataFromProvider();
    // Fetch fresh data asynchronously and preload project data for non-Client users
    _initializeData();
    
    // Add listener to scroll to top when search field is focused
    _quickSearchFocusNode.addListener(() {
      if (_quickSearchFocusNode.hasFocus) {
        // Wait for the next frame to ensure the scroll controller is attached
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (_scrollController.hasClients) {
            _scrollController.animateTo(
              0.0,
              duration: Duration(milliseconds: 300),
              curve: Curves.easeOut,
            );
          }
        });
      }
    });
  }

  Future<void> _initializeData() async {
    // Reload client/update data
    await reloadData(force: true);
    
    // For non-Client users, preload project data
    SharedPreferences prefs = await SharedPreferences.getInstance();
    final role = prefs.getString('role');
    final projectId = prefs.getString('project_id');
    
    if (role != null && role != 'Client' && projectId != null) {
      // Trigger background loading of project data
      DataProvider().loadProjectDataForNonClient(projectId).catchError((e) {
        print('[UserDashboard] Error preloading project data: $e');
      });
    }
  }

  loadDataFromProvider() async {
    final dataProvider = DataProvider();

    // Load username first
    SharedPreferences prefs = await SharedPreferences.getInstance();
    String loadedUsername = ' ';
    if (prefs.containsKey("client_name")) {
      loadedUsername = prefs.getString('client_name') ?? ' ';
    } else {
      loadedUsername = prefs.getString('username') ?? ' ';
    }

    if (!mounted) return;

    final String nextLocation = dataProvider.clientProjectLocation ?? '';
    final String? nextCompletion = dataProvider.clientProjectCompletion;
    final bool nextBlocked = dataProvider.clientProjectBlocked ?? false;
    final String nextBlockReason = dataProvider.clientProjectBlockReason ?? '';
    final String nextValue = dataProvider.clientProjectValue ?? '';
    final dynamic nextUpdates = dataProvider.clientProjectUpdates;

    List<String> nextDailyUpdates = [];
    String nextUpdateDate = DateFormat("EEEE dd MMMM").format(DateTime.now()).toString();

    // Only process updates if data is loaded (not null)
    if (nextUpdates != null && nextUpdates is List && nextUpdates.isNotEmpty) {
      nextUpdateDate = nextUpdates[0]['date']?.toString() ?? nextUpdateDate;
      for (final update in nextUpdates) {
        final title = update['update_title']?.toString();
        if (title == null || title.isEmpty) continue;
        if (!nextDailyUpdates.contains(title)) {
          nextDailyUpdates.add(title);
        }
      }
      if (nextDailyUpdates.isEmpty) {
        nextDailyUpdates.add('Stay tuned for updates about your home');
      }
    } else if (nextUpdates == null) {
      // Data not loaded yet - keep empty list to show skeleton
      nextDailyUpdates = [];
    } else {
      // Data loaded but empty - show empty state message
      nextDailyUpdates.add('Stay tuned for updates about your home');
    }

    if (!mounted) return;

    setState(() {
      // Load client project data from provider
      location = nextLocation;
      completed = nextCompletion;
      blocked = nextBlocked;
      bolckReason = nextBlockReason;
      value = nextValue;
      username = loadedUsername;
      _isLoadingSummary = false;
      _hasLoadedSummary = true;
    });

    setState(() {
      updateResponseBody = nextUpdates;
      dailyUpdateList = nextDailyUpdates;
      updatePostedOnDate = nextUpdateDate;
      _isLoadingUpdates = false;
      // Only mark as loaded if we have actual data OR if we got empty data (not null)
      // If nextUpdates is null, data hasn't loaded yet, so keep hasLoadedUpdates false to show skeleton
      _hasLoadedUpdates = nextUpdates != null;
    });
  }

  Future<void> reloadData({bool force = false}) async {
    if (!mounted) return;
    setState(() {
      _isLoadingSummary = true;
      _isLoadingUpdates = true;
    });
    await DataProvider().reloadData(force: force);
    await loadDataFromProvider();
    // Section flags are reset inside loadDataFromProvider once data is applied.
  }

  bool get _shouldShowInitialSummarySkeleton => _isLoadingSummary && !_hasLoadedSummary;

  bool get _shouldShowInitialUpdatesSkeleton => _isLoadingUpdates && !_hasLoadedUpdates;

  bool get _shouldShowInitialPageSkeleton => _shouldShowInitialSummarySkeleton && _shouldShowInitialUpdatesSkeleton;

  bool get _isAnySectionLoading => _isLoadingSummary || _isLoadingUpdates;

  List<Map<String, dynamic>> getMenuItems() {
    List<Map<String, dynamic>> menuItems = [];

    menuItems.add({
      'title': 'Payments',
      'icon': Icons.payment,
      'route': () => PaymentTaskWidget(),
    });

    menuItems.add({
      'title': 'Documents',
      'icon': Icons.description,
      'route': () => Documents(),
    });

    menuItems.add({
      'title': 'Scheduler',
      'icon': Icons.calendar_today,
      'route': () => const TaskWidget(),
    });

    menuItems.add({
      'title': 'Gallery',
      'icon': Icons.photo_library,
      'route': () => Gallery(),
    });

    menuItems.add({
      'title': 'Notes & Comments',
      'icon': Icons.note_add,
      'route': () => NotesAndComments(),
    });

    menuItems.add({
      'title': 'Checklist',
      'icon': Icons.checklist,
      'route': () => ChecklistCategoriesLayout(),
    });

    menuItems.add({
      'title': 'Request Drawings',
      'icon': Icons.architecture,
      'route': () => RequestDrawingLayout(),
    });

    return menuItems;
  }

  Widget build(BuildContext context) {
    List<Map<String, dynamic>> menuItems = getMenuItems();
    final quickSearchSection = Padding(
      padding: EdgeInsets.symmetric(horizontal: 0, vertical: 8),
      child: _buildQuickSearchSection(menuItems),
    );

    final dashboardContent = Container(
      decoration: BoxDecoration(
        color: AppTheme.backgroundPrimary,
      ),
      child: ListView(
        controller: _scrollController,
        children: <Widget>[
          AnimatedWidgetSlide(
              direction: SlideDirection.topToBottom, // Specify the slide direction
              duration: Duration(milliseconds: 300), // Adjust the duration as needed
              child: Column(
                children: [
                  // Welcome section with better styling
                ],
              )),
          Container(
            padding: EdgeInsets.symmetric(horizontal: 20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                SizedBox(height: 10),
                if (blocked == true)
                  Column(
                    children: [
                      Container(alignment: Alignment.centerLeft, child: Text("Project blocked", style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.red))),
                      Container(
                          alignment: Alignment.centerLeft,
                          margin: EdgeInsets.only(bottom: 15),
                          child: Text("Reason : " + bolckReason.toString(), style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.red))),
                    ],
                  ),
                // Progress Card with enhanced design
                _buildSummarySection(),
                SizedBox(height: 10),

                Padding(
                  padding: EdgeInsets.only(bottom: 16, top: 8),
                  child: Row(
                    children: [
                      Container(
                        width: 4,
                        height: 24,
                        decoration: BoxDecoration(
                          color: AppTheme.primaryColorConst,
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                      SizedBox(width: 12),
                      Text(
                        'Latest Updates',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: AppTheme.textPrimary,
                          letterSpacing: 0.5,
                        ),
                      ),
                    ],
                  ),
                ),
                _buildUpdatesSection(),
                SizedBox(height: 10),
                quickSearchSection,
                SizedBox(height: 20),
                // Section header for Quick Actions
                Padding(
                  padding: EdgeInsets.only(bottom: 16, top: 8),
                  child: Row(
                    children: [
                      Container(
                        width: 4,
                        height: 24,
                        decoration: BoxDecoration(
                          color: AppTheme.primaryColorConst,
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                      SizedBox(width: 12),
                      Text(
                        'Quick Actions',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: AppTheme.textPrimary,
                          letterSpacing: 0.5,
                        ),
                      ),
                    ],
                  ),
                ),
                AnimatedWidgetSlide(
                    direction: SlideDirection.bottomToTop, // Specify the slide direction
                    duration: Duration(milliseconds: 300), // Adjust the duration as needed
                    child: Column(
                      children: [
                        Container(
                          margin: EdgeInsets.only(bottom: 20),
                          child: GridView.builder(
                            shrinkWrap: true,
                            physics: NeverScrollableScrollPhysics(),
                            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                              crossAxisCount: 3,
                              crossAxisSpacing: 10,
                              mainAxisSpacing: 10,
                              childAspectRatio: 0.85,
                            ),
                            itemCount: menuItems.length,
                            itemBuilder: (BuildContext context, int index) {
                              final item = menuItems[index];
                              return TweenAnimationBuilder<double>(
                                tween: Tween(begin: 0.0, end: 1.0),
                                duration: Duration(milliseconds: 300 + (index * 50)),
                                curve: Curves.easeOutBack,
                                builder: (context, scaleValue, child) {
                                  return Transform.scale(
                                    scale: scaleValue,
                                    child: Material(
                                      color: Colors.transparent,
                                      child: InkWell(
                                        onTap: () async {
                                          await _handleMenuTap(item);
                                        },
                                        borderRadius: BorderRadius.circular(16),
                                        child: Container(
                                          child: Column(
                                            mainAxisAlignment: MainAxisAlignment.center,
                                            children: [
                                              Container(
                                                padding: EdgeInsets.all(14),
                                                decoration: BoxDecoration(
                                                  gradient: LinearGradient(
                                                    begin: Alignment.topLeft,
                                                    end: Alignment.bottomRight,
                                                    colors: [
                                                      AppTheme.primaryColorConst.withOpacity(0.25),
                                                      AppTheme.primaryColorConst.withOpacity(0.15),
                                                    ],
                                                  ),
                                                  shape: BoxShape.circle,
                                                ),
                                                child: Icon(
                                                  item['icon'],
                                                  size: 28,
                                                  color: AppTheme.primaryColorConst,
                                                ),
                                              ),
                                              SizedBox(height: 8),
                                              Padding(
                                                padding: EdgeInsets.symmetric(horizontal: 4),
                                                child: Text(
                                                  item['title'],
                                                  textAlign: TextAlign.center,
                                                  style: TextStyle(
                                                    color: AppTheme.textPrimary,
                                                    fontSize: 12,
                                                    fontWeight: FontWeight.w600,
                                                  ),
                                                  maxLines: 2,
                                                  overflow: TextOverflow.ellipsis,
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                      ),
                                    ),
                                  );
                                },
                              );
                            },
                          ),
                        ),
                      ],
                    )),
                // Latest Updates Section
              ],
            ),
          ),
        ],
      ),
    );

    if (_shouldShowInitialPageSkeleton) {
      return _buildLoadingState();
    }

    return Stack(
      children: [
        dashboardContent,
        if (_isAnySectionLoading) _buildLoadingOverlay(),
      ],
    );
  }

  Widget _buildQuickSearchSection(List<Map<String, dynamic>> menuItems) {
    final searchItems = _buildSearchItems(menuItems);
    final query = _quickSearchQuery.trim();
    final hasQuery = query.isNotEmpty;
    final filteredItems = hasQuery ? searchItems.where((item) => item.matches(query)).toList() : <_DashboardSearchItem>[];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Find what you need',
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w600,
            color: AppTheme.textPrimary,
          ),
        ),
        SizedBox(height: 10),
        Container(
          decoration: BoxDecoration(
            color: AppTheme.backgroundSecondary,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: AppTheme.primaryColorConst.withOpacity(0.1)),
          ),
          child: TextField(
            controller: _quickSearchController,
            focusNode: _quickSearchFocusNode,
            onTap: () async {
              // Scroll to top when search field is tapped
              // Use a small delay to ensure the scroll controller is ready
              await Future.delayed(Duration(milliseconds: 50));
              if (_scrollController.hasClients) {
                print("scrolling to bottom");
                _scrollController.animateTo(
                  _scrollController.position.maxScrollExtent + 110,
                  duration: Duration(milliseconds: 300),
                  curve: Curves.easeOut,
                );
              } else {
                // If controller not attached yet, wait for next frame
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  if (_scrollController.hasClients && mounted) {
                    _scrollController.animateTo(
                      _scrollController.position.maxScrollExtent + 110,
                      duration: Duration(milliseconds: 300),
                      curve: Curves.easeOut,
                    );
                  }
                });
              }
            },
            onChanged: (value) {
              setState(() {
                _quickSearchQuery = value;
              });
            },
            decoration: InputDecoration(
              contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 0),
              prefixIcon: Icon(Icons.search, color: AppTheme.textSecondary),
              suffixIcon: _quickSearchQuery.isNotEmpty
                  ? IconButton(
                      icon: Icon(Icons.close, color: AppTheme.textSecondary),
                      onPressed: _clearQuickSearch,
                    )
                  : null,
              hintText: 'Search payments, gallery, scheduler…',
              border: InputBorder.none,
            ),
          ),
        ),
        AnimatedSwitcher(
          duration: Duration(milliseconds: 200),
          child: hasQuery
              ? Container(
                  key: ValueKey(query),
                  width: double.infinity,
                  margin: EdgeInsets.only(top: 12),
                  padding: EdgeInsets.symmetric(vertical: 6),
                  decoration: BoxDecoration(
                    color: AppTheme.backgroundSecondary.withOpacity(0.7),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: AppTheme.primaryColorConst.withOpacity(0.12)),
                  ),
                  child: filteredItems.isEmpty
                      ? Padding(
                          padding: EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                          child: Text(
                            'No shortcuts match "$query".',
                            style: TextStyle(color: AppTheme.textSecondary, fontSize: 13),
                          ),
                        )
                      : Column(
                          children: filteredItems
                              .map(
                                (item) => ListTile(
                                  dense: true,
                                  leading: Icon(item.icon, color: AppTheme.primaryColorConst),
                                  title: Text(
                                    item.title,
                                    style: TextStyle(
                                      color: AppTheme.textPrimary,
                                      fontWeight: FontWeight.w600,
                                      fontSize: 14,
                                    ),
                                  ),
                                  subtitle: item.subtitle != null
                                      ? Text(
                                          item.subtitle!,
                                          style: TextStyle(color: AppTheme.textSecondary, fontSize: 12),
                                        )
                                      : null,
                                  onTap: () async {
                                    await item.onSelected();
                                    _clearQuickSearch();
                                  },
                                ),
                              )
                              .toList(),
                        ),
                )
              : SizedBox.shrink(),
        ),
      ],
    );
  }

  void _clearQuickSearch() {
    _quickSearchController.clear();
    _quickSearchFocusNode.unfocus();
    setState(() {
      _quickSearchQuery = '';
    });
  }

  List<_DashboardSearchItem> _buildSearchItems(List<Map<String, dynamic>> menuItems) {
    final List<_DashboardSearchItem> items = [];

    for (final item in menuItems) {
      final title = item['title']?.toString() ?? '';
      if (title.isEmpty) continue;
      items.add(
        _DashboardSearchItem(
          title: title,
          icon: item['icon'] as IconData? ?? Icons.circle,
          keywords: [title],
          onSelected: () => _handleMenuTap(item),
        ),
      );
    }

    items.add(
      _DashboardSearchItem(
        title: 'Payments • Project',
        subtitle: 'Track tender milestones',
        icon: Icons.payments_rounded,
        keywords: ['payment', 'tender', 'project'],
        onSelected: () => _openPaymentCategory(PaymentCategory.tender),
      ),
    );

    items.add(
      _DashboardSearchItem(
        title: 'Payments • Non Tender',
        subtitle: 'Monitor custom expenses',
        icon: Icons.receipt_long,
        keywords: ['payment', 'non tender', 'expenses'],
        onSelected: () => _openPaymentCategory(PaymentCategory.nonTender),
      ),
    );

    return items;
  }

  Future<void> _handleMenuTap(Map<String, dynamic> item) async {
    final routeResult = item['route']();
    final widget = routeResult is Future ? await routeResult : routeResult;
    await _navigateToWidget(widget);
  }

  Future<void> _openPaymentCategory(PaymentCategory category) async {
    await _navigateToWidget(PaymentTaskWidget(initialCategory: category));
  }

  Future<void> _navigateToWidget(Widget widget) async {
    await DataProvider().reloadData();
    if (!mounted) return;
    await Navigator.push(
      context,
      PageRouteBuilder(
        pageBuilder: (context, animation, secondaryAnimation) => widget,
        transitionsBuilder: (context, animation, secondaryAnimation, child) {
          return FadeTransition(
            opacity: animation,
            child: SlideTransition(
              position: Tween<Offset>(
                begin: const Offset(0.3, 0.0),
                end: Offset.zero,
              ).animate(CurvedAnimation(
                parent: animation,
                curve: Curves.easeOutCubic,
              )),
              child: child,
            ),
          );
        },
        transitionDuration: Duration(milliseconds: 300),
      ),
    );
    if (!mounted) return;
    reloadData();
  }

  Widget _buildSummarySection() {
    final summaryCard = TweenAnimationBuilder<double>(
      tween: Tween(begin: 0.0, end: 1.0),
      duration: Duration(milliseconds: 600),
      curve: Curves.easeOut,
      child: _buildSummaryCardBody(),
      builder: (context, value, child) {
        return Transform.scale(
          scale: 0.95 + (0.05 * value),
          child: Opacity(
            opacity: value,
            child: child,
          ),
        );
      },
    );

    return _wrapSectionWithLoader(
      isLoading: _isLoadingSummary,
      hasLoaded: _hasLoadedSummary,
      skeleton: _buildSummarySkeleton(),
      borderRadius: BorderRadius.circular(20),
      margin: const EdgeInsets.only(bottom: 20),
      child: summaryCard,
    );
  }

  Widget _buildSummaryCardBody() {
    return Container(
      padding: EdgeInsets.all(24),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        gradient: LinearGradient(
          colors: [
            AppTheme.primaryColorConst.withOpacity(0.1),
            AppTheme.primaryColorConst.withOpacity(0.05),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        border: Border.all(
          color: AppTheme.primaryColorConst.withOpacity(0.2),
          width: 1.5,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: AppTheme.primaryColorConst.withOpacity(0.2),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  Icons.trending_up_rounded,
                  color: AppTheme.primaryColorConst,
                  size: 24,
                ),
              ),
              SizedBox(width: 12),
              if (completed != null) ...[
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        "Construction Progress",
                        style: TextStyle(
                          fontSize: 14,
                          color: AppTheme.textSecondary,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      SizedBox(height: 4),
                      Text(
                        "$completed% Complete",
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: AppTheme.textPrimary,
                          letterSpacing: 0.5,
                        ),
                      ),
                    ],
                  ),
                ),
              ] else ...[
                Expanded(
                  child: _buildCardSkeleton(height: 40, borderRadius: BorderRadius.circular(12)),
                ),
              ],
              Container(
                child: InkWell(
                  onTap: () async {
                    await launchUrl(Uri.parse(location), mode: LaunchMode.externalApplication);
                  },
                  borderRadius: BorderRadius.circular(12),
                  child: Visibility(
                    visible: location.isNotEmpty,
                    child: Container(
                      padding: EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                      decoration: BoxDecoration(
                        color: AppTheme.backgroundSecondary,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            Icons.directions_outlined,
                            color: AppTheme.primaryColorConst,
                            size: 20,
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
          SizedBox(height: 20),
          if (completed != null) ...[
            Container(
              padding: EdgeInsets.only(top: 8, bottom: 8),
              child: LinearPercentIndicator(
                barRadius: Radius.circular(12),
                padding: EdgeInsets.all(0),
                lineHeight: 14.0,
                percent: (double.tryParse(completed!) ?? 0.0) / 100,
                animation: true,
                animationDuration: 1200,
                backgroundColor: AppTheme.backgroundPrimaryLight,
                clipLinearGradient: true,
                linearGradient: LinearGradient(
                  colors: [
                    AppTheme.primaryColorConst,
                    AppTheme.primaryColorConst.withOpacity(0.8),
                  ],
                ),
              ),
            ),
          ] else ...[
            _buildCardSkeleton(height: 14, borderRadius: BorderRadius.circular(12)),
          ],
        ],
      ),
    );
  }

  Widget _buildUpdatesSection() {
    final updatesCard = TweenAnimationBuilder<double>(
      tween: Tween(begin: 0.0, end: 1.0),
      duration: Duration(milliseconds: 700),
      curve: Curves.easeOut,
      child: _buildUpdatesCardBody(context),
      builder: (context, value, child) {
        return Transform.translate(
          offset: Offset(0, 20 * (1 - value)),
          child: Opacity(
            opacity: value,
            child: child,
          ),
        );
      },
    );

    return _wrapSectionWithLoader(
      isLoading: _isLoadingUpdates,
      hasLoaded: _hasLoadedUpdates,
      skeleton: _buildUpdatesSkeleton(),
      borderRadius: BorderRadius.circular(16),
      margin: const EdgeInsets.only(bottom: 20),
      child: updatesCard,
    );
  }

  Widget _buildUpdatesCardBody(BuildContext context) {
    // Show skeleton if data not loaded yet
    if (updateResponseBody == null && !_hasLoadedUpdates) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildCardSkeleton(height: 16, borderRadius: BorderRadius.circular(4)),
          SizedBox(height: 12),
          _buildCardSkeleton(height: 20, borderRadius: BorderRadius.circular(4)),
          SizedBox(height: 12),
          _buildCardSkeleton(height: 60, borderRadius: BorderRadius.circular(4)),
          SizedBox(height: 8),
          _buildCardSkeleton(height: 60, borderRadius: BorderRadius.circular(4)),
        ],
      );
    }
    
    return Container(
      padding: EdgeInsets.all(20),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        gradient: LinearGradient(
          colors: [
            AppTheme.backgroundSecondary,
            AppTheme.backgroundPrimaryLight,
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        border: Border.all(
          color: AppTheme.primaryColorConst.withOpacity(0.3),
          width: 1,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.3),
            blurRadius: 10,
            offset: Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  updatePostedOnDate,
                  style: TextStyle(fontSize: 12, color: AppTheme.textSecondary),
                ),
              ),
            ],
          ),
          if (updateResponseBody != null && updateResponseBody is List && updateResponseBody.length > 0 && updateResponseBody[0] != null && updateResponseBody[0]['tradesmenMap'] != null)
            Container(
              alignment: Alignment.topLeft,
              padding: EdgeInsets.only(top: 12, bottom: 12),
              child: Text(
                parsedUpdateTradesmen(updateResponseBody[0]['tradesmenMap']),
                style: TextStyle(fontSize: 14, color: AppTheme.textPrimary),
              ),
            ),
          if (dailyUpdateList.isNotEmpty)
            ListView.builder(
              physics: NeverScrollableScrollPhysics(),
              shrinkWrap: true,
              itemCount: dailyUpdateList.length,
              itemBuilder: (BuildContext ctxt, int index) {
                return Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Expanded(
                        child: Text(
                          dailyUpdateList[index].toString(),
                          style: TextStyle(fontSize: 14, color: AppTheme.textPrimary),
                        ),
                      )
                    ],
                  ),
                );
              },
            ),
        ],
      ),
    );
  }

  Widget _buildSummarySkeleton() {
    return _buildCardSkeleton(height: 170, borderRadius: BorderRadius.circular(20));
  }

  Widget _buildUpdatesSkeleton() {
    return _buildCardSkeleton(height: 220, borderRadius: BorderRadius.circular(16));
  }

  Widget _wrapSectionWithLoader({
    required bool isLoading,
    required bool hasLoaded,
    required Widget child,
    required Widget skeleton,
    required BorderRadius borderRadius,
    EdgeInsetsGeometry? margin,
  }) {
    Widget withMargin(Widget widget) {
      final padding = margin;
      if (padding == null) return widget;
      return Padding(
        padding: padding,
        child: widget,
      );
    }

    if (isLoading && !hasLoaded) {
      return withMargin(skeleton);
    }

    Widget content = child;

    if (isLoading && hasLoaded) {
      content = Stack(
        children: [
          child,
          Positioned.fill(
            child: IgnorePointer(
              child: ClipRRect(
                borderRadius: borderRadius,
                child: Container(
                  color: AppTheme.backgroundPrimary.withOpacity(0.65),
                  child: Center(
                    child: SizedBox(
                      height: 20,
                      width: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        valueColor: AlwaysStoppedAnimation<Color>(AppTheme.primaryColorConst),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      );
    }

    return withMargin(content);
  }

  Widget _buildCardSkeleton({required double height, required BorderRadius borderRadius}) {
    return Shimmer.fromColors(
      baseColor: AppTheme.backgroundSecondary.withOpacity(0.4),
      highlightColor: Colors.white.withOpacity(0.35),
      child: Container(
        height: height,
        decoration: BoxDecoration(
          color: AppTheme.backgroundSecondary.withOpacity(0.4),
          borderRadius: borderRadius,
        ),
      ),
    );
  }

  Widget _buildLoadingState() {
    final baseColor = AppTheme.textPrimary.withOpacity(0.6);
    final highlightColor = Colors.white.withOpacity(0.35);

    return Container(
      color: AppTheme.backgroundPrimary,
      child: ListView(
        padding: EdgeInsets.symmetric(horizontal: 20, vertical: 24),
        children: [
          _buildSkeletonCard(baseColor, highlightColor, height: 60, margin: EdgeInsets.only(bottom: 16)),
          _buildSkeletonCard(baseColor, highlightColor, height: 170, margin: EdgeInsets.only(bottom: 20)),
          _buildSkeletonCard(baseColor, highlightColor, height: 200, margin: EdgeInsets.only(bottom: 20)),
          _buildSkeletonGrid(baseColor, highlightColor),
        ],
      ),
    );
  }

  Widget _buildSkeletonCard(Color base, Color highlight, {double height = 120, EdgeInsets? margin}) {
    return Shimmer.fromColors(
      baseColor: base,
      highlightColor: highlight,
      child: Container(
        height: height,
        margin: margin ?? EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          color: AppTheme.backgroundSecondary.withOpacity(0.4),
          borderRadius: BorderRadius.circular(18),
        ),
      ),
    );
  }

  Widget _buildSkeletonGrid(Color base, Color highlight) {
    return GridView.builder(
      shrinkWrap: true,
      physics: NeverScrollableScrollPhysics(),
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        crossAxisSpacing: 10,
        mainAxisSpacing: 10,
        childAspectRatio: 0.85,
      ),
      itemCount: 6,
      itemBuilder: (_, __) {
        return Shimmer.fromColors(
          baseColor: base,
          highlightColor: highlight,
          child: Container(
            decoration: BoxDecoration(
              color: AppTheme.backgroundSecondary.withOpacity(0.4),
              borderRadius: BorderRadius.circular(16),
            ),
          ),
        );
      },
    );
  }

  Widget _buildLoadingOverlay() {
    return IgnorePointer(
      ignoring: true,
      child: Align(
        alignment: Alignment.topCenter,
        child: AnimatedOpacity(
          opacity: _isAnySectionLoading ? 1.0 : 0.0,
          duration: Duration(milliseconds: 200),
          child: Container(
            margin: EdgeInsets.only(top: 12),
            padding: EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            decoration: BoxDecoration(
              color: AppTheme.backgroundSecondary.withOpacity(0.9),
              borderRadius: BorderRadius.circular(24),
              border: Border.all(
                color: AppTheme.primaryColorConst.withOpacity(0.2),
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.12),
                  blurRadius: 6,
                  offset: Offset(0, 3),
                ),
              ],
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    valueColor: AlwaysStoppedAnimation<Color>(AppTheme.primaryColorConst),
                  ),
                ),
                SizedBox(width: 10),
                Text(
                  'Loading project data...',
                  style: TextStyle(
                    color: AppTheme.textPrimary,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _DashboardSearchItem {
  final String title;
  final String? subtitle;
  final IconData icon;
  final List<String> keywords;
  final Future<void> Function() onSelected;

  _DashboardSearchItem({
    required this.title,
    required this.icon,
    required this.onSelected,
    this.subtitle,
    List<String>? keywords,
  }) : keywords = keywords ?? [title];

  bool matches(String query) {
    final lower = query.toLowerCase();
    if (title.toLowerCase().contains(lower)) return true;
    if (subtitle != null && subtitle!.toLowerCase().contains(lower)) return true;
    return keywords.any((keyword) => keyword.toLowerCase().contains(lower));
  }
}

enum SlideDirection { leftToRight, rightToLeft, topToBottom, bottomToTop }

class AnimatedWidgetSlide extends StatefulWidget {
  final Widget child;
  final SlideDirection direction;
  final Duration duration;

  AnimatedWidgetSlide({
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
        _slideAnimation = Tween<Offset>(
          begin: const Offset(-1.0, 0.0),
          end: const Offset(0.0, 0.0),
        ).animate(CurvedAnimation(
          parent: _animationController,
          curve: Curves.easeInSine,
        ));
        break;
      case SlideDirection.rightToLeft:
        _slideAnimation = Tween<Offset>(
          begin: const Offset(1.0, 0.0),
          end: const Offset(0.0, 0.0),
        ).animate(CurvedAnimation(
          parent: _animationController,
          curve: Curves.easeInOut,
        ));
        break;
      case SlideDirection.topToBottom:
        _slideAnimation = Tween<Offset>(
          begin: const Offset(0.0, -1.0),
          end: const Offset(0.0, 0.0),
        ).animate(CurvedAnimation(
          parent: _animationController,
          curve: Curves.easeInOut,
        ));
        break;
      case SlideDirection.bottomToTop:
        _slideAnimation = Tween<Offset>(
          begin: const Offset(0.0, 1.0),
          end: const Offset(0.0, 0.0),
        ).animate(CurvedAnimation(
          parent: _animationController,
          curve: Curves.easeInOut,
        ));
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

String parsedUpdateTradesmen(dynamic tradesmenMap) {
  try {
    // Try parsing as JSON Map<String,int>
    final jsonMap = tradesmenMap.toString().trim();
    if (jsonMap == 'null' || jsonMap.isEmpty) {
      return '';
    }
    print("jsonMap: $jsonMap");
    // Try decode as JSON
    if (jsonMap.startsWith('{') && jsonMap.endsWith('}')) {
      final List<String> parsed = jsonMap.substring(1, jsonMap.length - 1).split(',');
      String result = '';
      int index = 0;
      for (final item in parsed) {
        final key = item.split(':')[0].trim();
        final value = item.split(':')[1].trim();
        if (index == parsed.length - 1) {
          result += '$value ${key}s';
        } else if (parsed.length > 2 && index == parsed.length - 2) {
          result += '$value ${key}s and ';
        } else {
          result += '$value ${key}s, ';
        }
        index++;
      }
      return 'Resources: $result';
    }
    return '';
  } catch (e) {
    return tradesmenMap.toString().trim() == 'null' ? '' : tradesmenMap.toString().trim();
  }
}
