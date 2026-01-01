import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'UserDashboard.dart';
import 'app_theme.dart';
import "Scheduler.dart";
import "Payments.dart";
import "Gallery.dart";
import 'Drawings.dart';
import 'NotesAndComments.dart';
import 'po_bills.dart';
import 'Dpr.dart';
import 'checklist_categories.dart';
import 'services/data_provider.dart';

class Home extends StatelessWidget {
  final bool fromAdminDashboard;
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();

  Home({Key? key, this.fromAdminDashboard = false}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    // Reset project data if opened from AdminDashboard
    if (fromAdminDashboard) {
      DataProvider().resetProjectData();
    }
    
    return Scaffold(
      key: _scaffoldKey,
      backgroundColor: AppTheme.getBackgroundPrimary(context),
      body: UserDashboardLayout(fromAdminDashboard: fromAdminDashboard),
    );
  }
}

class chipSetNavigation extends StatefulWidget {
  @override
  chipSetNavigationState createState() {
    return chipSetNavigationState();
  }
}

class chipSetNavigationState extends State<chipSetNavigation> {
  var activeTab = 'My Home';
  var tabsList = ['My Home', "Scheduler", "Payments", "Non tender payments", "Gallery", "Documents"];
  @override
  void initState() {
    super.initState();
  }

  var activeDecoration = BoxDecoration(
    color: Color(0xFF000055),
  );

  var inactiveDecoration = BoxDecoration(color: const Color.fromARGB(255, 0, 0, 0), borderRadius: BorderRadius.circular(2));

  @override
  Widget build(BuildContext context) {
    return ListView(
      shrinkWrap: true,
      scrollDirection: Axis.horizontal,
      children: [
        for (var i = 0; i < tabsList.length; i++)
          InkWell(
            onTap: () {
              setState(() {
                activeTab = tabsList[i];
              });
              print(i);
              UserHomeScreenState().pageController.animateToPage(i, duration: Duration(milliseconds: 100), curve: Curves.elasticInOut);
            },
            child: Container(
                padding: EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                margin: EdgeInsets.symmetric(horizontal: 5, vertical: 5),
                decoration: tabsList[i] == activeTab ? activeDecoration : inactiveDecoration,
                child: Text(
                  tabsList[i],
                  style: TextStyle(
                    color: tabsList[i] == activeTab ? Colors.white : Colors.black,
                    fontSize: 16,
                  ),
                )),
          )
      ],
    );
  }
}

class UserHomeScreen extends StatefulWidget {
  @override
  UserHomeScreenState createState() {
    return UserHomeScreenState();
  }
}

class UserHomeScreenState extends State<UserHomeScreen> {
  var role = "";
  var activeTabIndex;
  var pageController = new PageController();
  var activeTab = 'My Home';
  var tabsList = [
    "Scheduler",
    "Gallery",
    "Documents",
    "ChatBox",
    "Payments",
    "Non tender payments",
  ];
  var widgetList = [
    UserDashboardScreen(),
    const TaskWidget(),
    Gallery(),
    Documents(),
    NotesAndComments(),
    PaymentTaskWidget(),
    PaymentTaskWidget(initialCategory: PaymentCategory.nonTender),
  ];

  var blocked = false;
  var block_reason = '';

  var activeDecoration = BoxDecoration(color: Color(0xFF000055), borderRadius: BorderRadius.circular(5));

  var inactiveDecoration = BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(5), border: Border.all(color: Color.fromARGB(255, 100, 100, 100)));

  void setUserRole() async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    role = prefs.getString('role')!;
    if (role == 'Architect' || role == 'Senior Architect') {
      setState(() {
        activeTab = 'Documents';
        tabsList = [
          "Documents",
          "ChatBox",
        ];
        widgetList = [
          Documents(),
          NotesAndComments(),
        ];
      });
    }

    if (role != 'Client') {
      setState(() {
        tabsList.add("PO and bills");
        widgetList.add(POAndBills());

        tabsList.insert(1, "DPR Updates");
        widgetList.insert(1, DprScreen());

        tabsList.insert(2, "Checklist");
        widgetList.insert(2, ChecklistCategories());
      });
    }
  }

  set_project_status() async {
    // Load project status from data provider
    final dataProvider = DataProvider();
    setState(() {
      blocked = dataProvider.clientProjectBlocked ?? false;
      block_reason = dataProvider.clientProjectBlockReason ?? '';
      
      if (blocked && role == 'Client') {
        tabsList = [
          'Home',
          "Payments",
          "Non tender payments",
        ];
        widgetList = [
          UserDashboardScreen(),
          PaymentTaskWidget(),
          PaymentTaskWidget(initialCategory: PaymentCategory.nonTender),
        ];
      }
    });
  }

  @override
  void initState() {
    super.initState();
    setUserRole();
    // Reload data to ensure fresh status
    DataProvider().reloadData().then((_) {
      set_project_status();
    });
  }

  Widget build(BuildContext context) {
    return Container(
      height: MediaQuery.of(context).size.height,
      width: MediaQuery.of(context).size.width,
      child: Stack(
        alignment: Alignment.bottomCenter,
        children: [
          UserDashboardScreen(),
          Container(
              decoration: BoxDecoration(color: const Color.fromARGB(255, 223, 223, 223)),
              padding: EdgeInsets.only(top: 15, bottom: 1),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: [
                  Container(
                    height: 50,
                    child: Column(
                      children: [
                        Icon(
                          Icons.home_rounded,
                          size: 25,
                          color: Color.fromARGB(255, 46, 46, 46),
                        ),
                        Text(
                          'Home',
                          style: TextStyle(color: const Color.fromARGB(255, 46, 46, 46), fontSize: 12),
                        )
                      ],
                    ),
                  ),
                  InkWell(
                      onTap: () {
                        Navigator.push(
                          context,
                          PageRouteBuilder(
                            pageBuilder: (context, animation, secondaryAnimation) => TaskWidget(),
                            transitionsBuilder: (context, animation, secondaryAnimation, child) {
                              return SlideTransition(
                                position: Tween<Offset>(
                                  begin: const Offset(1.0, 0.0),
                                  end: Offset.zero,
                                ).animate(animation),
                                child: child,
                              );
                            },
                          ),
                        );
                      },
                      child: Container(
                        height: 50,
                        child: Column(
                          children: [
                            Icon(
                              Icons.alarm,
                              size: 20,
                              color: const Color.fromARGB(255, 100, 100, 100),
                            ),
                            Text('Schedule', style: TextStyle(color: Color.fromARGB(255, 100, 100, 100), fontSize: 12))
                          ],
                        ),
                      )),
                  InkWell(
                      onTap: () {
                        Navigator.push(
                          context,
                          PageRouteBuilder(
                            pageBuilder: (context, animation, secondaryAnimation) => Gallery(),
                            transitionsBuilder: (context, animation, secondaryAnimation, child) {
                              return SlideTransition(
                                position: Tween<Offset>(
                                  begin: const Offset(2.0, 0.0),
                                  end: Offset.zero,
                                ).animate(animation),
                                child: child,
                              );
                            },
                          ),
                        );
                      },
                      child: Container(
                        height: 50,
                        child: Column(
                          children: [
                            Icon(
                              Icons.photo_library,
                              size: 20,
                              color: Color.fromARGB(255, 100, 100, 100),
                            ),
                            Text(
                              'Gallery',
                              style: TextStyle(color: Color.fromARGB(255, 100, 100, 100), fontSize: 12),
                            )
                          ],
                        ),
                      )),
                  InkWell(
                      onTap: () {
                        Navigator.push(
                          context,
                          PageRouteBuilder(
                            pageBuilder: (context, animation, secondaryAnimation) => NotesAndComments(),
                            transitionsBuilder: (context, animation, secondaryAnimation, child) {
                              return SlideTransition(
                                position: Tween<Offset>(
                                  begin: const Offset(1.0, 0.0),
                                  end: Offset.zero,
                                ).animate(animation),
                                child: child,
                              );
                            },
                          ),
                        );
                      },
                      child: Container(
                        height: 50,
                        child: Column(
                          children: [
                            Icon(
                              Icons.update,
                              size: 20,
                              color: Color.fromARGB(255, 100, 100, 100),
                            ),
                            Text(
                              'Notes',
                              style: TextStyle(color: Color.fromARGB(255, 100, 100, 100), fontSize: 12),
                            )
                          ],
                        ),
                      )),
                ],
              )),
        ],
      ),
    );
  }
}
