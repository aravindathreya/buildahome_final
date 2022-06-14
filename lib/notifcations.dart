import 'package:flutter/material.dart';
import 'package:flutter/widgets.dart';
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'NavMenu.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'AddNewUser.dart';
import 'utilities/styles.dart';
import 'main.dart';

class Notifications extends StatelessWidget {
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
          title: Text(appTitle),
          leading: new IconButton(
              icon: new Icon(Icons.menu),
              onPressed: () => _scaffoldKey.currentState.openDrawer()),
          backgroundColor: Color(0xFF000055),
        ),
        body: NotificationPageBody(),
      ),
    );
  }
}

class NotificationPageBody extends StatefulWidget {
  @override
  NotificationPageBodyState createState() {
    return NotificationPageBodyState();
  }
}

class NotificationPageBodyState extends State<NotificationPageBody> {
  var notifcations = [];

  void get_notifications_for_user() async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    var user_id = prefs.get('user_id');
    var url =
        'https://app.buildahome.in/erp/API/get_notifications?recipient=${user_id}';
    var response = await http.get(url);
    setState(() {
      notifcations = jsonDecode(response.body);
      print(notifcations);
      notifcations = notifcations.reversed.toList();
    });
  }

  void mark_all_notifications_as_read() async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    var user_id = prefs.get('user_id');
    var url =
        'https://app.buildahome.in/erp/API/mark_notifications_as_read?user_id=${user_id}';
    await http.get(url);
  }

  @override
  void initState() {
    super.initState();
    get_notifications_for_user();
    mark_all_notifications_as_read();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
        height: MediaQuery.of(context).size.height,
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Container(
              margin: EdgeInsets.symmetric(horizontal: 10, vertical: 20),
              child: Text('Notifications', style: get_header_text_style())),
          Container(
              height: MediaQuery.of(context).size.height - 180,
              child: ListView.builder(
                  shrinkWrap: true,
                  padding: EdgeInsets.all(15),
                  itemCount: notifcations.length,
                  itemBuilder: (BuildContext ctxt, int Index) {
                    return Container(
                      padding: EdgeInsets.all(10),
                      margin: EdgeInsets.only(bottom: 10),
                      decoration: BoxDecoration(
                        color: notifcations[Index]['unread'] == 1
                            ? Colors.green[100]
                            : Colors.white,
                        borderRadius: BorderRadius.circular(5),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Container(
                            margin: EdgeInsets.only(bottom: 5),
                            child: Text(
                              notifcations[Index]['title'],
                              style: TextStyle(
                                  fontSize: 16, fontWeight: FontWeight.w600),
                            ),
                          ),
                          Container(
                            child: Text(
                              notifcations[Index]['body'],
                              style: TextStyle(fontSize: 14),
                            ),
                          ),
                          Container(
                              alignment: Alignment.bottomRight,
                              margin: EdgeInsets.only(top: 15),
                              child: Text(
                                notifcations[Index]['timestamp'].toString() ==
                                        '0'
                                    ? ''
                                    : notifcations[Index]['timestamp']
                                        .toString(),
                                style: TextStyle(
                                    fontSize: 14, color: Colors.grey[500]),
                              ))
                        ],
                      ),
                    );
                  }))
        ]));
  }
}
