import 'package:buildahome/AdminDashboard.dart';
import 'package:buildahome/main.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'UserHome.dart';
import 'AddDailyUpdate.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'create_indent.dart';
import 'view_open_indents.dart';
import 'notifcations.dart';
import 'RequestDrawing.dart';
import 'NotesAndComments.dart';
import 'my_indents.dart';
import 'stock_report.dart';
import 'checklist_categories.dart';

class NavMenuItem extends StatelessWidget {
  String _route;
  final _icon;
  final _routename;
  NavMenuItem(this._route, this._icon, this._routename);

  _logout() async {
    SharedPreferences preferences = await SharedPreferences.getInstance();
    preferences.clear();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        shape: BoxShape.rectangle,
        border: Border(
          bottom: BorderSide(width: 1.0, color: Colors.black12),
        ),
      ),
      width: 400,
      padding: EdgeInsets.only(left: 20, top: 15, bottom: 15),
      child: InkWell(
        onTap: () {
          if (this._route == "Log out") {
            _logout();
          }
          Navigator.pop(context);
          Navigator.push(
            context,
            MaterialPageRoute(builder: (context) => this._routename),
          );
        },
        child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: <Widget>[
              Row(
                children: [
                  Icon(this._icon),
                  Container(
                    padding: EdgeInsets.only(left: 5),
                    child: Text(
                      this._route,
                      textAlign: TextAlign.left,
                      style: TextStyle(
                        fontSize: 18,
                        color: Colors.black,
                      ),
                    ),
                  ),
                ],
              ),
              Container(
                  margin: EdgeInsets.only(right: 15),
                  child:
                      Icon(Icons.chevron_right, size: 20, color: Colors.grey))
            ]),
      ),
    );
  }
}

class NavMenuWidget extends StatefulWidget {
  @override
  NavMenuWidgetState createState() {
    return NavMenuWidgetState();
  }
}

class NavMenuWidgetState extends State<NavMenuWidget> {
  void initState() {
    super.initState();
    call();
  }

  var username;
  var role;
  var location;

  call() async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    setState(() {
      username = prefs.getString('username');
      role = prefs.getString('role');
      location = prefs.getString('location');
    });
  }

  @override
  Widget build(BuildContext context) {
    final appTitle = 'buildAhome';
    return Drawer(
      child: ListView(
          dragStartBehavior: DragStartBehavior.start,
          children: <Widget>[
            Container(
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: Color.fromARGB(255, 0, 0, 24),
                shape: BoxShape.rectangle,
              ),
              padding: EdgeInsets.only(top: 40, left: 20, bottom: 40),
              child: InkWell(
                child: Column(
                  children: <Widget>[
                    Row(children: <Widget>[
                      Container(
                        padding: EdgeInsets.all(2),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.all(Radius.circular(50)),
                        ),
                        child: Icon(
                          Icons.account_circle_sharp,
                          size: 60,
                          color: Color(0xFFDEEDF0),
                        ),
                      ),
                      Container(
                          padding: EdgeInsets.only(left: 15),
                          alignment: Alignment.centerLeft,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: <Widget>[
                              Container(
                                child: Text(
                                  username.toString(),
                                  textAlign: TextAlign.left,
                                  style: TextStyle(
                                      fontSize: 22,
                                      color: Colors.white,
                                      fontWeight: FontWeight.bold),
                                ),
                              ),
                              Container(
                                  padding: EdgeInsets.only(top: 5),
                                  child: Text(
                                    role.toString(),
                                    style: TextStyle(
                                        color: Colors.white, fontSize: 16),
                                  ))
                            ],
                          )),
                    ]),
                    if (role == "Client")
                      Container(
                          margin: EdgeInsets.only(top: 30),
                          alignment: Alignment.topLeft,
                          child: Text(
                            "Building a home at",
                            style: TextStyle(color: Colors.white, fontSize: 16),
                          )),
                    if (role == "Client")
                      Container(
                          margin: EdgeInsets.only(top: 10, left: 0),
                          alignment: Alignment.topLeft,
                          child: Text(
                            location.toString(),
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 14,
                            ),
                          ))
                  ],
                ),
              ),
            ),
            if (role == 'Client')
              Container(
                child: NavMenuItem("Dashboard", Icons.dashboard, Home()),
              ),
            if (role != 'Client')
              Container(
                child:
                    NavMenuItem("Dashboard", Icons.dashboard, AdminDashboard()),
              ),
            if (role == 'Admin' ||
                role == 'Project Coordinator' ||
                role == 'Project Manager' ||
                role == 'Site Engineer')
              Container(
                child: NavMenuItem(
                    "Add Daily Update", Icons.update, AddDailyUpdate()),
              ),
            if (role == 'Admin' ||
                role == 'Site Engineer' ||
                role == 'Project Coordinator' ||
                role == 'Project Manager')
              Container(
                child: NavMenuItem(
                    "Create Indent", Icons.request_quote, CreateIndentLayout()),
              ),
            if (role != 'Client')
              Container(
                child: NavMenuItem(
                    "Stock report", Icons.inventory, StockReportLayout()),
              ),
            if (role == 'Client')
              Container(
                child: NavMenuItem("Checklist", Icons.list, ChecklistCategoriesLayout()),
              ),
            if (role == 'Admin' ||
                role == 'Project Coordinator' ||
                role == 'Project Manager' ||
                role == 'Site Engineer')
              Container(
                child: NavMenuItem(
                    "My Indents", Icons.access_alarm_sharp, MyIndentsLayout()),
              ),
            if (role == 'Admin' ||
                role == 'Project Coordinator' ||
                role == 'Project Manager' ||
                role == 'Site Engineer')
              Container(
                child: NavMenuItem("View open Indents", Icons.pending_actions,
                    ViewIndentsLayout()),
              ),
            if (role == 'Admin' ||
                role == 'Project Coordinator' ||
                role == 'Project Manager' ||
                role == 'Site Engineer')
              Container(
                child: NavMenuItem("Request drawing",
                    Icons.playlist_add_outlined, RequestDrawingLayout()),
              ),
            Container(
              child: NavMenuItem(
                  "My Notifications", Icons.notifications_on, Notifications()),
            ),
            Container(
              child: NavMenuItem("Log out", Icons.backspace, App()),
            ),
          ]),
    );
  }
}
