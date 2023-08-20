import 'package:flutter/material.dart';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:percent_indicator/linear_percent_indicator.dart';
import 'package:intl/intl.dart';

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
  var completed = "0";
  var updateResponseBody;
  var blocked = false;
  var bolckReason = '';

  @override
  void initState() {
    super.initState();
    set_project_status();

    call();
  }

  set_project_status() async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    var id = prefs.getString('project_id');
    var statusUrl = 'https://app.buildahome.in/erp/API/get_project_block_status?project_id=${id}';
    var statusResponse = await http.get(Uri.parse(statusUrl));
    var statusResponseBody = jsonDecode(statusResponse.body);
    if (statusResponseBody['status'] == 'blocked') {
      setState(() {
        blocked = true;
        bolckReason = statusResponseBody['reason'];
      });
    }
  }

  call() async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    var id = prefs.getString('project_id');
    var role = prefs.getString('role');
    if (prefs.containsKey("client_name")) {
      username = prefs.getString('client_name')!;
    } else {
      username = prefs.getString('username')!;
    }

    if (role == 'Client') {
      // final FirebaseMessaging _messaging = FirebaseMessaging();
      // _messaging.subscribeToTopic(username);
    }

    var url = 'https://app.buildahome.in/api/latest_update.php?id=${id}';
    var response = await http.get(Uri.parse(url));
    if (response.body.trim() != "No updates") {
      updateResponseBody = jsonDecode(response.body);
    }
    var projectCompletionPercentage;
    if (prefs.containsKey("completed")) {
      projectCompletionPercentage = prefs.getString('completed');
      var url = 'https://app.buildahome.in/api/get_project_percentage.php?id=${id}';
      var percResponse = await http.get(Uri.parse(url));
      prefs.setString('completed', percResponse.body);
    } else {
      var url = 'https://app.buildahome.in/api/get_project_percentage.php?id=${id}';
      var percResponse = await http.get(Uri.parse(url));
      projectCompletionPercentage = percResponse.body;
    }

    setState(() {
      if(prefs.getString('project_value') != null)
        value = prefs.getString('project_value')!;
      completed = projectCompletionPercentage;

      if (response.body.trim() == "No updates") {
        dailyUpdateList = [];
        dailyUpdateList.add('No updates for today yet');
        updatePostedOnDate = DateFormat("EEEE dd MMMM").format(DateTime.now()).toString();
      } else {
        dailyUpdateList = [];
        for (int x = 0; x < updateResponseBody.length; x++) {
          if (dailyUpdateList.contains(updateResponseBody[x]['update_title']) == false) {
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
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w500, color: Colors.black)),
          ),
        ),
        Container(
          margin: EdgeInsets.symmetric(horizontal: 17),
          child: Container(
            padding: EdgeInsets.only(bottom: 20),
            child: Text("Your home construction is in safe hands!",
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500, color: Colors.grey[500])),
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
                    Opacity(
                      opacity: blocked ? 0.5 : 1,
                      child: Container(
                        width: MediaQuery.of(context).size.width - 40,
                        height: MediaQuery.of(context).size.width - 40,
                        decoration: BoxDecoration(
                            color: Colors.grey[200],
                            border: Border.all(width: 1, color: Colors.grey[200]!),
                            borderRadius: BorderRadius.circular(5)),
                        child: Image.network("https://app.buildahome.in/erp/static/files/mobile_banner.png"),
                      ),
                    ),
                    Opacity(opacity: 0.7, child: Container(height: 27, width: 90, color: Colors.black)),
                    Container(
                        padding: EdgeInsets.all(5),
                        child: Text("buildAhome",
                            style: TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w500))),
                  ],
                ),
              ),
              if (blocked == true)
                Column(
                  children: [
                    Container(
                        alignment: Alignment.centerLeft,
                        child: Text("Project blocked",
                            style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.red))),
                    Container(
                        alignment: Alignment.centerLeft,
                        margin: EdgeInsets.only(bottom: 15),
                        child: Text("Reason : " + bolckReason.toString(),
                            style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.red))),
                  ],
                ),
              Container(
                  alignment: Alignment.centerLeft,
                  child: Text("Here is how much is done",
                      style: TextStyle(
                        fontSize: 16,
                      ))),
              Container(
                padding: EdgeInsets.only(top: 10, bottom: 10, left: 0, right: 0),
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
                                    style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
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
                          updateResponseBody[0]['tradesmenMap'].toString().length > 0)
                        Container(
                          alignment: Alignment.topLeft,
                          padding: EdgeInsets.only(top: 10),
                          child: Text(
                              updateResponseBody[0]['tradesmenMap'].toString().trim() == 'null'
                                  ? ''
                                  : updateResponseBody[0]['tradesmenMap'].toString().trim(),
                              style: TextStyle(
                                fontSize: 14,
                                color: Colors.grey[700],
                              )),
                        ),
                      ListView.builder(
                          physics: NeverScrollableScrollPhysics(),
                          shrinkWrap: true,
                          itemCount: dailyUpdateList == null ? 0 : dailyUpdateList.length,
                          itemBuilder: (BuildContext ctxt, int Index) {
                            return Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: <Widget>[
                                Container(
                                  alignment: Alignment.topLeft,
                                  padding: EdgeInsets.only(top: 10),
                                  width: MediaQuery.of(context).size.width - 120,
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
