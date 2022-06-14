import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'NavMenu.dart';
import 'package:percent_indicator/linear_percent_indicator.dart';
import 'package:intl/intl.dart';
import 'package:firebase_messaging/firebase_messaging.dart';

class UserDashboardScreen extends StatefulWidget {
  @override
  UserDashboardScreenState createState() {
    return UserDashboardScreenState();
  }
}

class UserDashboardScreenState extends State<UserDashboardScreen> {
  List dailyUpdateList;
  var username = ' ';
  var updatePostedOnDate = " ";
  var value = " ";
  var completed = "0";
  var updateResponseBody;

  @override
  void initState() {
    super.initState();
    call();
  }

  call() async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    var id = prefs.getString('project_id');
    var role = prefs.getString('role');
    if (prefs.containsKey("client_name")) {
      username = prefs.getString('client_name');
    } else {
      username = prefs.getString('username');
    }

    if (role == 'Client') {
      final FirebaseMessaging _messaging = FirebaseMessaging();

      _messaging.subscribeToTopic(username);
    }

    var url = 'https://app.buildahome.in/api/latest_update.php?id=${id}';
    var response = await http.get(url);
    if (response.body.trim() != "No updates") {
      updateResponseBody = jsonDecode(response.body);
    }
    var project_completion_percentage;
    if (prefs.containsKey("completed")) {
      project_completion_percentage = prefs.getString('completed');
      var url =
          'https://app.buildahome.in/api/get_project_percentage.php?id=${id}';
      var percResponse = await http.get(url);
      prefs.setString('completed', percResponse.body);
    } else {
      var url =
          'https://app.buildahome.in/api/get_project_percentage.php?id=${id}';
      var percResponse = await http.get(url);
      project_completion_percentage = percResponse.body;
    }

    setState(() {
      value = prefs.getString('project_value');
      completed = project_completion_percentage;

      print(response.body);
      if (response.body.trim() == "No updates") {
        dailyUpdateList = [];
        dailyUpdateList.add('No updates for today yet');
        updatePostedOnDate =
            DateFormat("EEEE dd MMMM").format(DateTime.now()).toString();
      } else {
        dailyUpdateList = [];
        for (int x = 0; x < updateResponseBody.length; x++) {
          if (dailyUpdateList.contains(updateResponseBody[x]['update_title']) ==
              false) {
            dailyUpdateList.add(updateResponseBody[x]['update_title']);
          }
        }
        updatePostedOnDate = updateResponseBody[0]['date'];
      }
    });
  }

  Widget build(BuildContext context) {
    return Container(
        child: ListView(
      children: <Widget>[
        Container(
          margin: EdgeInsets.symmetric(horizontal: 17),
          child: Container(
            padding: EdgeInsets.only(top: 20),
            child: Text("Welcome $username!",
                style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w500,
                    color: Colors.black)),
          ),
        ),
        Container(
          margin: EdgeInsets.symmetric(horizontal: 17),
          child: Container(
            padding: EdgeInsets.only(bottom: 20),
            child: Text("Your home construction is in safe hands!",
                style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                    color: Colors.grey[500])),
          ),
        ),
        Container(
          padding: EdgeInsets.symmetric(horizontal: 20),
          child: Column(
            children: <Widget>[
              Container(
                margin: EdgeInsets.only(bottom: 20),
                child: Stack(
                  alignment: Alignment.bottomRight,
                  children: [
                    Container(
                      width: MediaQuery.of(context).size.width - 40,
                      height: MediaQuery.of(context).size.width - 40,
                      decoration: BoxDecoration(
                          color: Colors.grey[200],
                          border: Border.all(width: 1, color: Colors.grey[200]),
                          borderRadius: BorderRadius.circular(5)),
                      child: Image.network(
                          "https://app.buildahome.in/erp/static/files/mobile_banner.png"),
                    ),
                    Opacity(
                        opacity: 0.7,
                        child: Container(
                            height: 27, width: 90, color: Colors.black)),
                    Container(
                        padding: EdgeInsets.all(5),
                        child: Text("buildAhome",
                            style: TextStyle(
                                color: Colors.white,
                                fontSize: 14,
                                fontWeight: FontWeight.w500))),
                  ],
                ),
              ),
              Container(
                  alignment: Alignment.centerLeft,
                  child: Text("Here is how much is done",
                      style: TextStyle(
                        fontSize: 16,
                      ))),
              Container(
                padding:
                    EdgeInsets.only(top: 10, bottom: 10, left: 0, right: 0),
                child: Center(
                  child: LinearPercentIndicator(
                    padding: EdgeInsets.all(0),
                    lineHeight: 28.0,
                    percent: (int.parse(completed.toString()) / 100),
                    center: Column(
                      children: <Widget>[
                        Container(
                          padding: EdgeInsets.only(top: 5),
                          child: Text(
                            completed.toString() + " % Completed",
                            style: TextStyle(
                              fontSize: 14,
                              color: Colors.white,
                              fontWeight: FontWeight.normal,
                            ),
                          ),
                        ),
                      ],
                    ),
                    animation: true,
                    animationDuration: 1500,
                    backgroundColor: Colors.grey[400],
                    progressColor: Color(0xFFFFA41B),
                    linearStrokeCap: LinearStrokeCap.butt,
                  ),
                ),
              ),
              Container(
                  alignment: Alignment.topLeft,
                  padding: EdgeInsets.all(15),
                  margin: EdgeInsets.only(top: 30, bottom: 100),
                  decoration: BoxDecoration(
                    color: Color(0xFFe6f3ff),
                    border: Border.all(color: Colors.black, width: 0.3),
                    borderRadius: BorderRadius.circular(5),
                  ),
                  child: Column(
                    children: <Widget>[
                      Row(
                        children: <Widget>[
                          Row(
                            children: <Widget>[
                              Icon(Icons.event_note),
                              Container(
                                padding: EdgeInsets.only(left: 10),
                                child: Text(updatePostedOnDate + " (Today)",
                                    style: TextStyle(
                                        fontSize: 14,
                                        fontWeight: FontWeight.w600)),
                              )
                            ],
                          ),
                        ],
                      ),
                      Container(
                          alignment: Alignment.centerLeft,
                          padding: EdgeInsets.only(top: 10),
                          child: Container(
                            height: 1,
                            color: Colors.black,
                          )),
                      if (updateResponseBody != null &&
                          updateResponseBody.length > 0 &&
                          updateResponseBody[0]['tradesmenMap']
                                  .toString()
                                  .length >
                              0)
                        Container(
                          alignment: Alignment.topLeft,
                          padding: EdgeInsets.only(top: 10),
                          child: Text(
                              updateResponseBody[0]['tradesmenMap']
                                          .toString()
                                          .trim() ==
                                      'null'
                                  ? ''
                                  : updateResponseBody[0]['tradesmenMap']
                                      .toString()
                                      .trim(),
                              style: TextStyle(
                                fontSize: 14,
                                color: Colors.grey[700],
                              )),
                        ),
                      ListView.builder(
                          physics: NeverScrollableScrollPhysics(),
                          shrinkWrap: true,
                          itemCount: dailyUpdateList == null
                              ? 0
                              : dailyUpdateList.length,
                          itemBuilder: (BuildContext ctxt, int Index) {
                            return Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: <Widget>[
                                Container(
                                  alignment: Alignment.topLeft,
                                  padding: EdgeInsets.only(top: 10),
                                  width:
                                      MediaQuery.of(context).size.width - 120,
                                  child: Text(dailyUpdateList[Index].toString(),
                                      style: TextStyle(
                                        fontSize: 14,
                                        color: Colors.grey[700],
                                      )),
                                )
                              ],
                            );
                          }),
                    ],
                  ))
            ],
          ),
        )
      ],
    ));
  }
}
