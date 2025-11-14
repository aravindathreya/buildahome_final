import 'package:buildahome/AddDailyUpdate.dart';
import 'package:flutter/material.dart';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_spinkit/flutter_spinkit.dart';

import 'package:buildahome/UserHome.dart';
import 'package:intl/intl.dart';
import 'app_theme.dart';
import 'indents_screen.dart';
import 'RequestDrawing.dart';
import 'notifcations.dart';
import 'stock_report.dart';
import 'checklist_categories.dart';
import 'services/data_provider.dart';
import 'widgets/searchable_select.dart';
import 'main.dart';

class AdminDashboard extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final appTitle = 'buildAhome';
    final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();

    return MaterialApp(
      title: appTitle,
      theme: AppTheme.darkTheme,
      home: Scaffold(
        key: _scaffoldKey,
        backgroundColor: AppTheme.backgroundPrimary,
        appBar: AppBar(
          title: Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              InkWell(
                onTap: () {
                  _scaffoldKey.currentState?.openDrawer();
                },
                child: Container(
                  padding: EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: AppTheme.backgroundSecondary,
                    borderRadius: BorderRadius.circular(100),
                  ),
                  child: Image.asset('assets/images/logo.png', height: 30),
                ),
              )
            ],
          ),
          automaticallyImplyLeading: false,
          backgroundColor: AppTheme.backgroundPrimary,
        ),
        drawer: _SimpleDrawer(scaffoldKey: _scaffoldKey),
        body: AdminHome(),
      ),
    );
  }
}

class _SimpleDrawer extends StatelessWidget {
  final GlobalKey<ScaffoldState> scaffoldKey;

  const _SimpleDrawer({required this.scaffoldKey});

  Future<String?> _getUsername() async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    return prefs.getString('username');
  }

  @override
  Widget build(BuildContext context) {
    return Drawer(
      backgroundColor: AppTheme.backgroundSecondary,
      child: SafeArea(
        child: Column(
          children: [
            // Drawer Header
            Container(
              padding: EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: AppTheme.primaryColorConst.withOpacity(0.1),
                border: Border(
                  bottom: BorderSide(
                    color: AppTheme.primaryColorConst.withOpacity(0.3),
                    width: 1,
                  ),
                ),
              ),
              child: Row(
                children: [
                  Container(
                    padding: EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: AppTheme.primaryColorConst.withOpacity(0.2),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(
                      Icons.person,
                      color: AppTheme.primaryColorConst,
                      size: 24,
                    ),
                  ),
                  SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'buildAhome',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            color: AppTheme.textPrimary,
                          ),
                        ),
                        SizedBox(height: 4),
                        FutureBuilder<String?>(
                          future: _getUsername(),
                          builder: (context, snapshot) {
                            return Text(
                              snapshot.data ?? 'User',
                              style: TextStyle(
                                fontSize: 14,
                                color: AppTheme.textSecondary,
                              ),
                            );
                          },
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            
            // Spacer
            Spacer(),
            
            // Logout Button
            Container(
              margin: EdgeInsets.all(20),
              child: Material(
                color: Colors.transparent,
                child: InkWell(
                  onTap: () async {
                    SharedPreferences preferences = await SharedPreferences.getInstance();
                    preferences.clear();
                    DataProvider().clearData();
                    Navigator.pushAndRemoveUntil(
                      context,
                      MaterialPageRoute(builder: (context) => App()),
                      (route) => false,
                    );
                  },
                  borderRadius: BorderRadius.circular(12),
                  child: Container(
                    padding: EdgeInsets.symmetric(vertical: 16, horizontal: 20),
                    decoration: BoxDecoration(
                      color: Colors.red.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: Colors.red.withOpacity(0.3),
                        width: 1.5,
                      ),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          Icons.logout,
                          color: Colors.red,
                          size: 24,
                        ),
                        SizedBox(width: 12),
                        Text(
                          'Logout',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                            color: Colors.red,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class AdminHome extends StatefulWidget {
  @override
  AdminHomeState createState() {
    return AdminHomeState();
  }
}

class AdminHomeState extends State<AdminHome> {
  var currentWidgetContext;
  var currentDate;
  var showTopSection = true;
  var showProjects = false;
  var searchProjectfocusNode = FocusNode();
  var searchProjectTextController = new TextEditingController();
  var currentUserRole = '';
  var currentUserName = '';
  var projects = [];
  var projectsToShow = [];
  bool readOnly = true;
  final TextEditingController _quickSearchController = TextEditingController();
  final FocusNode _quickSearchFocusNode = FocusNode();
  String _quickSearchQuery = '';

  @override
  void dispose() {
    searchProjectfocusNode.dispose();
    searchProjectTextController.dispose();
    _quickSearchController.dispose();
    _quickSearchFocusNode.dispose();
    super.dispose();
  }

  setDate() {
    var now = new DateTime.now();
    var formatter = new DateFormat('d, MMMM');
    currentDate = formatter.format(now);
  }

  setRole() async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    setState(() {
      currentUserRole = prefs.getString('role') ?? '';
      currentUserName = prefs.getString('username') ?? '';
    });
  }

  loadProjects() async {
    // Reload data from data provider
    await DataProvider().reloadData();
    setState(() {
      projects = DataProvider().projects;
      projectsToShow = projects;
    });
  }

  @override
  void initState() {
    super.initState();
    setDate();
    setRole();
    // Load projects from data provider (it should already be loaded on app init)
    setState(() {
      projects = DataProvider().projects;
      projectsToShow = projects;
    });
    // Reload to ensure fresh data
    loadProjects();
  }

  List<Map<String, dynamic>> getMenuItems() {
    List<Map<String, dynamic>> menuItems = [];

     // My Projects (non-Client)
    if (currentUserRole != 'Client') {
      menuItems.add({
        'title': 'Projects',
        'icon': Icons.list,
        'route': () async {
          // Load projects and directly open SearchableSelect
          SharedPreferences prefs = await SharedPreferences.getInstance();
          var userId = prefs.getString('user_id');
          var url = "https://office.buildahome.in/API/projects_access?id=${userId.toString()}";
          var response = await http.get(Uri.parse(url));
          var projects = jsonDecode(response.body);
          
          return SearchableSelect(
            title: 'Select Project',
            items: projects,
            itemLabel: (item) => item['name'] ?? 'Unknown',
            selectedItem: null,
            onItemSelected: (item) {
              // This will be handled after SearchableSelect returns
            },
            defaultVisibleCount: 5,
          );
        },
      });
    }

    // Add Daily Update
    if (currentUserRole == 'Admin' || currentUserRole == 'Project Coordinator' || currentUserRole == 'Project Manager' || currentUserRole == 'Site Engineer') {
      menuItems.add({
        'title': 'Daily Update',
        'icon': Icons.update,
        'route': () => AddDailyUpdate(),
      });
    }

    // Indents (unified screen with tabs)
    if (currentUserRole == 'Admin' || currentUserRole == 'Site Engineer' || currentUserRole == 'Project Coordinator' || currentUserRole == 'Project Manager') {
      menuItems.add({
        'title': 'Indents',
        'icon': Icons.request_quote,
        'route': () => IndentsScreenLayout(),
      });
    }

    // Stock report
    if (currentUserRole != 'Client') {
      menuItems.add({
        'title': 'Stock Report',
        'icon': Icons.inventory,
        'route': () => StockReportLayout(),
      });
    }

    // Checklist (Client only)
    if (currentUserRole == 'Client') {
      menuItems.add({
        'title': 'Checklist',
        'icon': Icons.list,
        'route': () => ChecklistCategoriesLayout(),
      });
    }

    // Request drawing
    if (currentUserRole == 'Admin' || currentUserRole == 'Project Coordinator' || currentUserRole == 'Project Manager' || currentUserRole == 'Site Engineer') {
      menuItems.add({
        'title': 'Request Drawing',
        'icon': Icons.playlist_add_outlined,
        'route': () => RequestDrawingLayout(),
      });
    }

   

    // My Notifications
    menuItems.add({
      'title': 'My Notifications',
      'icon': Icons.notifications_on,
      'route': () => Notifications(),
    });

    // // Log out
    // menuItems.add({
    //   'title': 'Log out',
    //   'icon': Icons.logout,
    //   'route': () async {
    //     SharedPreferences preferences = await SharedPreferences.getInstance();
    //     preferences.clear();
    //     Navigator.pushAndRemoveUntil(
    //       context,
    //       MaterialPageRoute(builder: (context) => App()),
    //       (route) => false,
    //     );
    //   },
    // });

    return menuItems;
  }

  Widget build(BuildContext context) {
    currentWidgetContext = context;
    List<Map<String, dynamic>> menuItems = getMenuItems();
    int totalProjects = projects.length;
    final quickSearch = _buildQuickSearchSection(context, menuItems);

    return Container(
        decoration: BoxDecoration(
          color: AppTheme.backgroundPrimary,
        ),
        height: MediaQuery.of(context).size.height,
        width: MediaQuery.of(context).size.width,
        child: ListView(
          padding: EdgeInsets.all(20),
          children: [
            // Welcome Section with User Info
            TweenAnimationBuilder<double>(
              tween: Tween(begin: 0.0, end: 1.0),
              duration: Duration(milliseconds: 400),
              curve: Curves.easeOut,
              builder: (context, value, child) {
                return Opacity(
                  opacity: value,
                  child: Transform.translate(
                    offset: Offset(0, -20 * (1 - value)),
                    child: Container(
                      margin: EdgeInsets.only(bottom: 25),
                      padding: EdgeInsets.all(24),
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: [
                            AppTheme.backgroundSecondary,
                            AppTheme.backgroundPrimaryLight,
                          ],
                        ),
                        borderRadius: BorderRadius.circular(20),
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
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Container(
                                padding: EdgeInsets.all(14),
                                decoration: BoxDecoration(
                                  color: AppTheme.primaryColorConst.withOpacity(0.2),
                                  borderRadius: BorderRadius.circular(20),
                                ),
                                child: Icon(
                                  Icons.account_circle,
                                  size: 48,
                                  color: AppTheme.primaryColorConst,
                                ),
                              ),
                              SizedBox(width: 16),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      'Welcome back,',
                                      style: TextStyle(
                                        fontSize: 14,
                                        color: AppTheme.textSecondary,
                                        fontWeight: FontWeight.w400,
                                      ),
                                    ),
                                    SizedBox(height: 4),
                                    Text(
                                      currentUserName.isNotEmpty ? currentUserName : 'User',
                                      style: TextStyle(
                                        fontWeight: FontWeight.bold,
                                        fontSize: 18,
                                        color: AppTheme.textPrimary,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              Container(
                                padding: EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                                decoration: BoxDecoration(
                                  color: AppTheme.primaryColorConst.withOpacity(0.15),
                                  borderRadius: BorderRadius.circular(20),
                                  border: Border.all(
                                    color: AppTheme.primaryColorConst.withOpacity(0.3),
                                    width: 1,
                                  ),
                                ),
                                child: Text(
                                  currentUserRole,
                                  style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600,
                                    color: AppTheme.primaryColorConst,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          SizedBox(height: 16),
                          Container(
                            child: Row(
                              children: [
                                Icon(
                                  Icons.calendar_today,
                                  size: 16,
                                  color: AppTheme.textSecondary,
                                ),
                                SizedBox(width: 8),
                                Text(
                                  currentDate,
                                  style: TextStyle(
                                    fontSize: 13,
                                    color: AppTheme.textSecondary,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),

            // Statistics Cards
            if (currentUserRole != 'Client')
              TweenAnimationBuilder<double>(
                tween: Tween(begin: 0.0, end: 1.0),
                duration: Duration(milliseconds: 500),
                curve: Curves.easeOut,
                builder: (context, value, child) {
                  return Opacity(
                    opacity: value,
                    child: Transform.translate(
                      offset: Offset(0, 20 * (1 - value)),
                      child: Row(
                        children: [
                          Expanded(
                            child: _buildStatCard(
                              context,
                              'Total Projects',
                              totalProjects.toString(),
                              Icons.folder_special,
                              AppTheme.primaryColorConst,
                            ),
                          ),
                          SizedBox(width: 12),
                          Expanded(
                            child: _buildStatCard(
                              context,
                              'Active',
                              totalProjects.toString(),
                              Icons.check_circle,
                              Colors.green,
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),

            SizedBox(height: 30),

            quickSearch,

            SizedBox(height: 30),

            // Section Header
            TweenAnimationBuilder<double>(
              tween: Tween(begin: 0.0, end: 1.0),
              duration: Duration(milliseconds: 500),
              curve: Curves.easeOut,
              builder: (context, value, child) {
                return Opacity(
                  opacity: value,
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
                );
              },
            ),

            SizedBox(height: 20),

            // GridView for menu items
            TweenAnimationBuilder<double>(
              tween: Tween(begin: 0.0, end: 1.0),
              duration: Duration(milliseconds: 600),
              curve: Curves.easeOut,
              builder: (context, value, child) {
                return Opacity(
                  opacity: value,
                  child: Transform.translate(
                    offset: Offset(0, 30 * (1 - value)),
                    child: GridView.builder(
                      shrinkWrap: true,
                      physics: NeverScrollableScrollPhysics(),
                      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: 3,
                        crossAxisSpacing: 15,
                        mainAxisSpacing: 15,
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
                                    await _handleMenuTap(context, item);
                                  },
                                  borderRadius: BorderRadius.circular(16),
                                  child: Container(
                                    child: Column(
                                      mainAxisAlignment: MainAxisAlignment.center,
                                      children: [
                                        Container(
                                          padding: EdgeInsets.all(14),
                                          decoration: BoxDecoration(
                                            color: item['title'] == 'Log out' ? Colors.red.withOpacity(0.2) : AppTheme.primaryColorConst.withOpacity(0.2),
                                            shape: BoxShape.circle,
                                          ),
                                          child: Icon(
                                            item['icon'],
                                            size: 24,
                                            color: item['title'] == 'Log out' ? Colors.red : AppTheme.primaryColorConst,
                                          ),
                                        ),
                                        SizedBox(height: 10),
                                        Padding(
                                          padding: EdgeInsets.symmetric(horizontal: 6),
                                          child: Text(
                                            item['title'],
                                            textAlign: TextAlign.center,
                                            style: TextStyle(
                                              color: AppTheme.textPrimary.withOpacity(0.8),
                                              fontSize: 11,
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
                );
              },
            ),

            SizedBox(height: 20),
          ],
        ));
  }

  Widget _buildQuickSearchSection(BuildContext context, List<Map<String, dynamic>> menuItems) {
    final searchItems = _buildSearchItems(context, menuItems);
    final query = _quickSearchQuery.trim();
    final hasQuery = query.isNotEmpty;
    final filteredItems = hasQuery ? searchItems.where((item) => item.matches(query)).toList() : <_DashboardSearchItem>[];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Quick search',
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w600,
            color: AppTheme.textPrimary,
          ),
        ),
        SizedBox(height: 12),
        Container(
          decoration: BoxDecoration(
            color: AppTheme.backgroundSecondary,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: AppTheme.primaryColorConst.withOpacity(0.1)),
          ),
          child: TextField(
            controller: _quickSearchController,
            focusNode: _quickSearchFocusNode,
            onChanged: (value) {
              setState(() {
                _quickSearchQuery = value;
              });
            },
            decoration: InputDecoration(
              prefixIcon: Icon(Icons.search, color: AppTheme.textSecondary),
              suffixIcon: _quickSearchQuery.isNotEmpty
                  ? IconButton(
                      icon: Icon(Icons.close, color: AppTheme.textSecondary),
                      onPressed: _clearQuickSearch,
                    )
                  : null,
              hintText: 'Search actions, screens, indents…',
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
                  padding: EdgeInsets.symmetric(vertical: 8),
                  decoration: BoxDecoration(
                    color: AppTheme.backgroundSecondary.withOpacity(0.7),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: AppTheme.primaryColorConst.withOpacity(0.12)),
                  ),
                  child: filteredItems.isEmpty
                      ? Padding(
                          padding: EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                          child: Text(
                            'No actions match "$query".',
                            style: TextStyle(color: AppTheme.textSecondary, fontSize: 13),
                          ),
                        )
                      : Column(
                          children: filteredItems
                              .map(
                                (item) => ListTile(
                                  leading: Icon(item.icon, color: AppTheme.primaryColorConst),
                                  title: Text(
                                    item.title,
                                    style: TextStyle(color: AppTheme.textPrimary, fontWeight: FontWeight.w600),
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

  List<_DashboardSearchItem> _buildSearchItems(BuildContext context, List<Map<String, dynamic>> menuItems) {
    final List<_DashboardSearchItem> items = [];

    for (final item in menuItems) {
      final title = item['title']?.toString() ?? '';
      if (title.isEmpty) continue;

      items.add(
        _DashboardSearchItem(
          title: title,
          icon: item['icon'] as IconData? ?? Icons.circle,
          keywords: [title],
          onSelected: () async {
            await _handleMenuTap(context, item);
          },
        ),
      );
    }

    final bool hasIndents = menuItems.any((item) => item['title'] == 'Indents');
    if (hasIndents) {
      const indentTitles = [
        {'label': 'Indents • Create', 'tab': 0, 'subtitle': 'Start a new indent'},
        {'label': 'Indents • View', 'tab': 1, 'subtitle': 'Browse open indents'},
        {'label': 'Indents • My Indents', 'tab': 2, 'subtitle': 'Review requests raised by you'},
      ];

      for (final config in indentTitles) {
        items.add(
          _DashboardSearchItem(
            title: config['label'] as String,
            subtitle: config['subtitle'] as String,
            icon: Icons.request_quote,
            keywords: ['indent', 'indents', config['label'] as String],
            onSelected: () async {
              await _handleMenuTap(context, {
                'title': config['label'],
                'icon': Icons.request_quote,
                'route': () => IndentsScreenLayout(initialTab: config['tab'] as int),
              });
            },
          ),
        );
      }
    }

    return items;
  }

  Future<void> _handleMenuTap(BuildContext context, Map<String, dynamic> item) async {
    if (item['title'] == 'Log out') {
      DataProvider().clearData();
      await item['route']();
      return;
    }

    final routeResult = item['route']();
    final widget = routeResult is Future ? await routeResult : routeResult;

    if (item['title'] == 'Projects') {
      final selectedProject = await Navigator.push(
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

      if (selectedProject != null) {
        print('selectedProject: ${selectedProject}');
        SharedPreferences prefs = await SharedPreferences.getInstance();
        await prefs.setString("project_id", selectedProject['id'].toString());
        await prefs.setString("client_name", selectedProject['name'].toString());

        Navigator.pushReplacement(
          context,
          PageRouteBuilder(
            transitionDuration: Duration(milliseconds: 320),
            reverseTransitionDuration: Duration(milliseconds: 240),
            pageBuilder: (context, animation, secondaryAnimation) => Home(fromAdminDashboard: true),
            transitionsBuilder: (context, animation, secondaryAnimation, child) {
              final curvedAnimation = CurvedAnimation(
                parent: animation,
                curve: Curves.easeOutCubic,
                reverseCurve: Curves.easeInCubic,
              );
              return FadeTransition(
                opacity: curvedAnimation,
                child: SlideTransition(
                  position: Tween<Offset>(
                    begin: const Offset(0.05, 0.04),
                    end: Offset.zero,
                  ).animate(curvedAnimation),
                  child: ScaleTransition(
                    scale: Tween<double>(
                      begin: 0.98,
                      end: 1.0,
                    ).animate(curvedAnimation),
                    child: child,
                  ),
                ),
              );
            },
          ),
        );
      } else {
        loadProjects();
      }
      return;
    }

    Navigator.push(
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
    ).then((_) {
      loadProjects();
    });
  }

  Widget _buildStatCard(BuildContext context, String title, String value, IconData icon, Color color) {
    return Container(
      padding: EdgeInsets.all(18),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            AppTheme.backgroundSecondary,
            AppTheme.backgroundPrimaryLight,
          ],
        ),
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.2),
            blurRadius: 8,
            offset: Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Container(
                padding: EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: color.withOpacity(0.2),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  icon,
                  size: 24,
                  color: color,
                ),
              ),
            ],
          ),
          SizedBox(height: 12),
          Text(
            value,
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: AppTheme.textPrimary,
            ),
          ),
          SizedBox(height: 4),
          Text(
            title,
            style: TextStyle(
              fontSize: 13,
              color: AppTheme.textSecondary,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
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

class Dashboard extends StatefulWidget {
  @override
  DashboardState createState() {
    return DashboardState();
  }
}

class DashboardState extends State<Dashboard> {
  var update = "";
  var username = "";
  var date = "";
  var role = "";

  var userId;
  var data;
  var searchData;

  @override
  void initState() {
    super.initState();
    call();
  }

  call() async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    role = prefs.getString('role')!;
    userId = prefs.getString('userId');
    String apiToken = prefs.getString('api_token')!;
    var response = await http.post(Uri.parse("https://office.buildahome.in/API/get_projects_for_user"), body: {"user_id": userId, "role": role, "api_token": apiToken});

    setState(() {
      print(data);
      data = jsonDecode(response.body);
      searchData = data;

      username = prefs.getString('username')!;
    });
  }

  Widget build(BuildContext context) {
    return Container(
        child: ListView(
      padding: EdgeInsets.all(25),
      children: <Widget>[
        Container(
          padding: EdgeInsets.only(bottom: 10),
          margin: EdgeInsets.only(bottom: 10, right: 100),
          child: Text("Projects handled by you", style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
          decoration: BoxDecoration(border: Border(bottom: BorderSide(width: 3))),
        ),
        Container(
            margin: EdgeInsets.only(bottom: 10, top: 10),
            color: Colors.white,
            child: TextFormField(
              onChanged: (text) {
                setState(() {
                  searchData = [];
                  for (int i = 0; i < data.length; i++) {
                    if (text.toLowerCase().trim() == "") {
                      searchData.add(data[i]);
                    } else if (data[i]['name'].toLowerCase().contains(text)) {
                      searchData.add(data[i]);
                    }
                  }
                });
              },
              decoration: InputDecoration(
                hintText: 'Search project',
                contentPadding: EdgeInsets.all(10),
                suffixIcon: InkWell(child: Icon(Icons.search)),
              ),
            )),
        if (searchData == null)
          ListView.builder(
              shrinkWrap: true,
              physics: new BouncingScrollPhysics(),
              scrollDirection: Axis.vertical,
              itemCount: 10,
              itemBuilder: (BuildContext ctxt, int index) {
                return Container(
                    padding: EdgeInsets.all(15),
                    margin: EdgeInsets.only(bottom: 10),
                    decoration: BoxDecoration(
                      color: Colors.grey[200],
                      shape: BoxShape.rectangle,
                      border: Border(
                        bottom: BorderSide(width: 1.0, color: Colors.grey[300]!),
                      ),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        SpinKitRing(
                          color: Color(0xFF03045E),
                          size: 20,
                          lineWidth: 2,
                        ),
                        Container(width: 60, child: Text('', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold))),
                        Container(child: Text('', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)))
                      ],
                    ));
              }),
        ListView.builder(
            shrinkWrap: true,
            physics: new BouncingScrollPhysics(),
            scrollDirection: Axis.vertical,
            itemCount: searchData == null ? 0 : searchData.length,
            itemBuilder: (BuildContext ctxt, int index) {
              return searchData[index]['name'].trim().length > 0
                  ? InkWell(
                      onTap: () async {
                        SharedPreferences prefs = await SharedPreferences.getInstance();
                        await prefs.setString("project_id", searchData[index]['id'].toString());
                        await prefs.setString("client_name", searchData[index]['name'].toString());

                        Navigator.pushReplacement(
                          context,
                          PageRouteBuilder(
                            pageBuilder: (context, animation, secondaryAnimation) => Home(fromAdminDashboard: true),
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
                      },
                      child: Container(
                          padding: EdgeInsets.symmetric(horizontal: 15, vertical: 20),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            shape: BoxShape.rectangle,
                            border: Border(
                              bottom: BorderSide(width: 1.0, color: Colors.grey[300]!),
                            ),
                          ),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: <Widget>[
                              Container(width: 40, child: Text((index + 1).toString() + ".", style: TextStyle(fontSize: 18, fontWeight: FontWeight.w500))),
                              Container(
                                  width: MediaQuery.of(context).size.width * 0.65,
                                  child: Text(searchData[index]['name'].trim(), overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 18, fontWeight: FontWeight.w500)))
                            ],
                          )))
                  : Container();
            })
      ],
    ));
  }
}

class HomeWidget extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container();
  }
}
