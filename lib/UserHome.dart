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
        body: LatestUpdate(),
        bottomNavigationBar: BottomNavigationBar(
          currentIndex: 0,
          selectedItemColor: Colors.indigo[900],
          onTap: (int index) {
            if (index == 0) {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (context) => Home()),
              );
            }
            else if (index == 1) {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (context) => TaskWidget()),
              );
            }
            else if (index == 2) {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (context) => PaymentTaskWidget()),
              );
            }
            else if (index == 3) {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (context) => Gallery()),
              );
            }
          },
          selectedIconTheme: IconThemeData(color: Colors.indigo[900]),
          unselectedItemColor: Colors.grey[400],
          type: BottomNavigationBarType.fixed,
          items: [
            BottomNavigationBarItem(
              icon: Icon(
                Icons.home,
              ),
              title: Text(
                'Home',
                style: TextStyle(fontSize: 12),
              ),
            ),
            BottomNavigationBarItem(
              icon: Icon(
                Icons.access_time,
              ),
              title: Text(
                'Scheduler',
                style: TextStyle(fontSize: 12),
              ),
            ),
            BottomNavigationBarItem(
              icon: Icon(
                Icons.payment,
              ),
              title: Text(
                'Payment',
                style: TextStyle(fontSize: 12),
              ),
            ),
            BottomNavigationBarItem(
              icon: Icon(
                Icons.photo_album,
              ),
              title: Text(
                "Gallery",
                style: TextStyle(fontSize: 12),
              ),
            ),
          ],
        ),

      ),
    );
  }
}

class LatestUpdate extends StatefulWidget {
  @override
  LatestUpdateState createState() {
    return LatestUpdateState();
  }
}

class LatestUpdateState extends State<LatestUpdate> {
  List update ;
  var username = ' ';
  var date = " ";
  var value = " ";
  var completed = "0";
  var body;

  @override
  void initState() {
    super.initState();
    call();
    
  }

  call() async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    var id = prefs.getString('project_id');
    username = prefs.getString('username');
    final FirebaseMessaging _messaging = FirebaseMessaging();
    
    _messaging.subscribeToTopic(username);
    
    var url = 'https://app.buildahome.in/api/latest_update.php?id=${id}';
    var response = await http.get(url);
    if (response.body.trim() != "No updates") {
      body = jsonDecode(response.body);
    }

    setState(() {
      value = prefs.getString('project_value');
      completed = prefs.getString('completed');
      print(response.body);
      if (response.body.trim() == "No updates") {

        update = [];
        update.add('No updates for today yet');
        date = DateFormat("EEEE dd MMMM").format(DateTime.now()).toString();
      }
      else {
        update = [];
            for(int x=0;x<body.length;x++){
            if(update.contains(body[x]['update_title'])==false){
              update.add(body[x]['update_title']);
            }
          }
          date = body[0]['date'];

      }
    });
  }

  Widget build(BuildContext context) {
    return Container(
        child: ListView(
          children: <Widget>[
              //Fixed image with welcome greeting text
              Container(
                padding: EdgeInsets.all(15),
                width: MediaQuery.of(context).size.width - 40,
                height: 250,
                decoration: BoxDecoration(
                    image: DecorationImage(
                      image: AssetImage("assets/images/app bg 3.webp"),
                      fit: BoxFit.cover,
                    ),
                    border: Border.all()),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Container(
                      padding: EdgeInsets.only(bottom: 5),
                      child: Text("Hi $username",
                          style: TextStyle(
                              letterSpacing: 1,
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                              color: Colors.black)),
                    ),
                    Text("We've got your home contruction covered!",
                        style: TextStyle(
                            letterSpacing: 1,
                            fontSize: 14,
                            fontWeight: FontWeight.bold,
                            color: Colors.black)),
                  ],
                ),
              ),
              //Progress report and DPR
              Container(
                padding: EdgeInsets.all(20),
                child: Column(
                  children: <Widget>[
                    Container(
                        padding: EdgeInsets.only(
                          top: 10,
                        ),
                        alignment: Alignment.centerLeft,
                        child: Text("Progress report",
                            style: TextStyle(
                                fontSize: 20,
                                fontWeight: FontWeight.bold,
                                color: Colors.indigo[900]))),
                    Container(
                      alignment: Alignment.centerLeft,
                      padding: EdgeInsets.only(top: 6),
                      child: Container(
                        height: 2,
                        width: 155,
                        color: Colors.indigo[900],
                      ),
                    ),
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
                                  completed.toString() + " % Complete",
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
                          backgroundColor: Colors.grey[300],
                          progressColor: Color(0xFF000055),
                          linearStrokeCap: LinearStrokeCap.butt,
                        ),
                      ),
                    ),
                    Container(
                        alignment: Alignment.topLeft,
                        padding: EdgeInsets.all(20),
                        decoration: BoxDecoration(
                            color: Colors.white30,
                            border: Border.all(color: Colors.black, width: 2)),
                        child: Column(
                          children: <Widget>[
                            Row(
                              children: <Widget>[
                                Row(
                                  children: <Widget>[
                                    Icon(Icons.event_note),
                                    Container(
                                      padding: EdgeInsets.only(left: 10),
                                      child: Text(date,
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
                            ListView.builder(
                                physics: NeverScrollableScrollPhysics(),
                                shrinkWrap: true,
                                itemCount: update==null?0: update.length,
                                itemBuilder: (BuildContext ctxt, int Index) {

                                    return Row(
                                    children: <Widget>[
                                      Container(
                                        padding: EdgeInsets.only(top: 10),
                                        child: Icon(Icons.check, color: Colors.green, size: 30)
                                      ),
                                      Container(
                                        alignment: Alignment.topLeft,
                                        padding: EdgeInsets.only(top: 10, left: 5),
                                        width: MediaQuery.of(context).size.width-120,
                                        child: Text(
                                            update[Index].toString(),
                                            style: TextStyle(
                                                fontSize: 16,
                                                color: Colors.black,
                                                letterSpacing: 1)),
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

class HomeWidget extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container();
  }
}
