import 'package:buildahome/Admin/Dpr.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import "Scheduler.dart";
import "Payments.dart";
import "Gallery.dart";
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'NavMenu.dart';
import 'package:percent_indicator/linear_percent_indicator.dart';
import 'package:intl/intl.dart';
import 'main.dart';
import 'UserDashboard.dart';
import 'Drawings.dart';
import 'NonTenderTasks.dart';
import 'NotesAndComments.dart';
import 'po_bills.dart';
import 'Dpr.dart';
import 'checklist_categories.dart';

class Home extends StatelessWidget {
  final GlobalKey<ScaffoldState> _scaffoldKey = new GlobalKey<ScaffoldState>();

  @override
  Widget build(BuildContext context) {
    final appTitle = 'buildAhome';
    return MaterialApp(
      title: appTitle,
      theme: ThemeData(fontFamily: App().fontName),
      home: Scaffold(
        key: _scaffoldKey,
        backgroundColor: Colors.black,

        drawer: NavMenuWidget(),
        appBar: AppBar(
          automaticallyImplyLeading: false,
          title: Text(
            appTitle,
          ),
          leading: new IconButton(
              icon: new Icon(Icons.menu),
              onPressed: () async {
                SharedPreferences prefs = await SharedPreferences.getInstance();
                var username = prefs.getString('username');
                _scaffoldKey.currentState!.openDrawer();
              }),
          backgroundColor: Colors.transparent,
        ),
        body: UserHomeScreen(),
      ),
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
  var tabsList = [
    'My Home',
    "Scheduler",
    "Payments",
    "Non tender payments",
    "Gallery",
    "Documents"
  ];
  @override
  void initState() {
    super.initState();
  }

  var activeDecoration = BoxDecoration(
    color: Color(0xFF000055),
  );

  var inactiveDecoration = BoxDecoration(
      color: const Color.fromARGB(255, 0, 0, 0), borderRadius: BorderRadius.circular(2));

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
              UserHomeScreenState().pageController.animateToPage(i,
                  duration: Duration(milliseconds: 100), curve: Curves.elasticInOut);
            },
            child: Container(
                padding: EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                margin: EdgeInsets.symmetric(horizontal: 5, vertical: 5),
                decoration: tabsList[i] == activeTab
                    ? activeDecoration
                    : inactiveDecoration,
                child: Text(
                  tabsList[i],
                  style: TextStyle(
                    color:
                        tabsList[i] == activeTab ? Colors.white : Colors.black,
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
    "Notes and comments",
    "Payments",
    "Non tender payments",
  ];
  var widgetList = [
    UserDashboardScreen(),
    TaskScreenClass(),
    Gallery(),
    Documents(),
    NotesAndComments(),
    PaymentTasksClass(),
    NTPaymentTasksClass()
  ];


  var blocked = false;
  var block_reason = '';

  var activeDecoration = BoxDecoration(
      color: Color(0xFF000055), borderRadius: BorderRadius.circular(5));

  var inactiveDecoration = BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(5),
      border: Border.all(color: Colors.grey[300]!));

  void setUserRole() async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    role = prefs.getString('role')!;
    if (role == 'Architect' || role == 'Senior Architect') {
      setState(() {
        activeTab = 'Documents';
        tabsList = [
          "Documents",
          "Notes and comments",
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
    SharedPreferences prefs = await SharedPreferences.getInstance();
    var id = prefs.getString('project_id');
    var statusUrl =
        'https://office.buildahome.in/API/get_project_block_status?project_id=$id';
    var statusResponse = await http.get(Uri.parse(statusUrl));
    var statusResponseBody = jsonDecode(statusResponse.body);
    if (statusResponseBody['status'] == 'blocked') {
      setState(() {
        blocked = true;
        block_reason = statusResponseBody['reason'];
        if (role == 'Client') {
          tabsList = [
            'Home',
            "Payments",
            "Non tender payments",
          ];
          widgetList = [
            UserDashboardScreen(),
            PaymentTasksClass(),
            NTPaymentTasksClass()
          ];
        }
      });
    }
  }

  @override
  void initState() {
    super.initState();
    setUserRole();
    set_project_status();
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
            decoration: BoxDecoration(
              border: Border(top: BorderSide(color: const Color.fromARGB(255, 49, 49, 49))),
              color: Colors.black
            ),
            padding: EdgeInsets.only(top: 15, bottom: 15),
            child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              Container(
                  height: 50,
                  child: Column(children: [
                  Icon(Icons.home_rounded, size: 30, color: Colors.white,),
                  Text('Home', style: TextStyle(color: Colors.white),)
                ],),
                ),
              InkWell(
               onTap: () {
                  Navigator.push(context, MaterialPageRoute(builder: (context) => TaskWidget()));
                },
                child: Container(
                  height: 50,
                  child: Column(children: [
                  Icon(Icons.alarm, color: Colors.grey,),
                  Text('Schedule', style: TextStyle(color: Colors.grey),)
                ],),
                )
              ),
              InkWell(
                onTap: () {
                  Navigator.push(context, MaterialPageRoute(builder: (context) => Gallery()));
                },
                child: Container(
                  height: 50,
                  child: Column(children: [
                  Icon(Icons.photo_library, color: Colors.grey,),
                  Text('Gallery', style: TextStyle(color: Colors.grey),)
                ],),
                )
              ),
            ],
          )
        
          ),
          ],
      ),
    );

    
  }
}
