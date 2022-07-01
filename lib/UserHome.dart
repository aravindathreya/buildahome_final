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
import 'package:firebase_messaging/firebase_messaging.dart';
import 'UserDashboard.dart';
import 'Drawings.dart';
import 'NonTenderTasks.dart';
import 'NotesAndComments.dart';
import 'po_bills.dart';

class Home extends StatelessWidget {
  final GlobalKey<ScaffoldState> _scaffoldKey = new GlobalKey<ScaffoldState>();

  @override
  Widget build(BuildContext context) {
    final appTitle = 'buildAhome';
    return MaterialApp(
      title: appTitle,
      theme: ThemeData(fontFamily: MyApp().fontName),
      home: Scaffold(
        key: _scaffoldKey,
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
                _scaffoldKey.currentState.openDrawer();
              }),
          backgroundColor: Color(0xFF000055),
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
      color: Colors.grey[200], borderRadius: BorderRadius.circular(2));

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
                  duration: Duration(milliseconds: 300), curve: Curves.easeIn);
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
    'My Home',
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
      color: Color(0xFF000055), borderRadius: BorderRadius.circular(20));

  var inactiveDecoration = BoxDecoration(
      borderRadius: BorderRadius.circular(20),
      border: Border.all(color: Colors.grey[600]));

  void setUserRole() async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    role = prefs.getString('role');
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
      });
    }
  }

  set_project_status() async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    var id = prefs.getString('project_id');
    var status_url =
        'https://app.buildahome.in/erp/API/get_project_block_status?project_id=${id}';
    var status_response = await http.get(status_url);
    var status_response_body = jsonDecode(status_response.body);
    if (status_response_body['status'] == 'blocked') {
      setState(() {
        blocked = true;
        block_reason = status_response_body['reason'];
        if (role == 'Client') {
          tabsList = [
            'My Home',
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
        child: ListView(
      physics: new NeverScrollableScrollPhysics(),
      children: <Widget>[
        Container(
            padding: EdgeInsets.all(10),
            height: 70,
            decoration: BoxDecoration(color: Colors.white, boxShadow: [
              new BoxShadow(
                  color: Colors.grey[400],
                  blurRadius: 10,
                  spreadRadius: 1,
                  offset: new Offset(0.0, 2.0))
            ]),
            child: ListView(
              shrinkWrap: true,
              scrollDirection: Axis.horizontal,
              children: [
                for (var i = 0; i < tabsList.length; i++)
                  InkWell(
                    onTap: () {
                      setState(() {
                        activeTab = tabsList[i];
                      });
                      this.pageController.animateToPage(i,
                          duration: Duration(milliseconds: 300),
                          curve: Curves.easeIn);
                    },
                    child: Container(
                        alignment: Alignment.center,
                        padding:
                            EdgeInsets.symmetric(horizontal: 25, vertical: 2),
                        margin:
                            EdgeInsets.symmetric(horizontal: 5, vertical: 5),
                        decoration: tabsList[i] == activeTab
                            ? activeDecoration
                            : inactiveDecoration,
                        child: Text(
                          tabsList[i],
                          style: TextStyle(
                            color: tabsList[i] == activeTab
                                ? Colors.white
                                : Colors.black,
                            fontSize: 14,
                          ),
                        )),
                  )
              ],
            )),
        Container(
            height: MediaQuery.of(context).size.height - 90,
            child: PageView(
              controller: pageController,
              allowImplicitScrolling: false,
              physics: new NeverScrollableScrollPhysics(),
              children: [
                for (var i = 0; i < widgetList.length; i++) widgetList[i]
              ],
            )),
      ],
    ));
  }
}
