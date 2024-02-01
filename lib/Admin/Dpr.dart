import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import '../NavMenu.dart';
import 'dart:convert';
import '../main.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../ShowAlert.dart';
import 'Scheduler.dart';
import 'Payments.dart';
import 'Gallery.dart';
import 'Drawings.dart';

class Dpr extends StatefulWidget {
  final String id;

  Dpr(this.id);

  @override
  DprState createState() {
    return DprState(this.id);
  }
}

class DprState extends State<Dpr> {
  var entries;
  var id;
  var listOfDates = [];
  var listOfUpdates = [];
  var updateDates = [];
  var updateIds = [];
  var role = "";

  DprState(this.id);

  setProjectId(projectId) async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    prefs.setString("project_id", projectId.toString());
    setState(() {
      role = prefs.getString("role")!;
      print(role);
    });
  }

  call() async {
    setProjectId(this.id);
    var url = 'https://office.buildahome.in/API/view_all_dpr?id=${this.id}';
    var response = await http.get(Uri.parse(url));
    setState(() {
      listOfDates = [];
      entries = jsonDecode(response.body);
      for (int i = 0; i < entries.length; i++) {
        if (listOfDates.contains(entries[i]['date']) == false) {
          listOfDates.add(entries[i]['date']);
        }
        if (listOfUpdates.contains(entries[i]['update_title']) == false) {
          listOfUpdates.add(entries[i]['update_title']);
          updateDates.add(entries[i]['date']);
          updateIds.add(entries[i]['id']);
        }
      }
    });
  }

  @override
  void initState() {
    super.initState();
    call();
  }

  @override
  Widget build(BuildContext context) {
    final appTitle = 'buildAhome';
    final GlobalKey<ScaffoldState> _scaffoldKey = new GlobalKey<ScaffoldState>();
    return MaterialApp(
      title: appTitle,
      theme: ThemeData(fontFamily: App().fontName),
      home: Scaffold(
        key: _scaffoldKey,
        appBar: AppBar(
          automaticallyImplyLeading: false,
          title: Text(appTitle),
          leading: new IconButton(
              icon: new Icon(Icons.arrow_back_ios),
              onPressed: () => {
                    Navigator.pop(context),
                  }),
          backgroundColor: Color(0xFF000055),
        ),
        drawer: NavMenuWidget(),
        bottomNavigationBar: BottomNavigationBar(
          currentIndex: 0,
          selectedItemColor: Colors.indigo[900],
          onTap: (int index) {
            if (index == 0) {
              Navigator.pushReplacement(
                context,
                MaterialPageRoute(builder: (context) => Dpr(this.id)),
              );
            } else if (index == 1) {
              Navigator.pushReplacement(
                context,
                MaterialPageRoute(builder: (context) => Documents(this.id)),
              );
            } else if (index == 2) {
              Navigator.pushReplacement(
                context,
                MaterialPageRoute(builder: (context) => Gallery(this.id)),
              );
            } else if (index == 3) {
              Navigator.pushReplacement(
                context,
                MaterialPageRoute(builder: (context) => TaskWidget(this.id)),
              );
            } else if (index == 4) {
              Navigator.pushReplacement(
                context,
                MaterialPageRoute(builder: (context) => PaymentTaskWidget(this.id)),
              );
            }
          },
          unselectedItemColor: Colors.grey[400],
          type: BottomNavigationBarType.fixed,
          items: [
            BottomNavigationBarItem(
                icon: Icon(
                  Icons.home,
                ),
                label: 'Home'),
            BottomNavigationBarItem(
                icon: Icon(
                  Icons.picture_as_pdf,
                ),
                label: 'Drawings'),
            BottomNavigationBarItem(
                icon: Icon(
                  Icons.photo_album,
                ),
                label: "Gallery"),
            if (role == 'Site Engineer' || role == "Admin" || role == 'Project Coordinator')
              BottomNavigationBarItem(
                  icon: Icon(
                    Icons.access_time,
                  ),
                  label: 'Scheduler'),
            if (role == 'Project Coordinator' || role == "Admin")
              BottomNavigationBarItem(
                  icon: Icon(
                    Icons.payment,
                  ),
                  label: 'Payment'),
          ],
        ),
        body: ListView.builder(
          itemCount: listOfDates.length,
          itemBuilder: (BuildContext ctxt, int index) {
            return Container(
                child: Container(
                    padding: EdgeInsets.all(15),
                    margin: EdgeInsets.only(top: 10),
                    decoration: BoxDecoration(color: Colors.grey[200]),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Row(
                          children: <Widget>[
                            Icon(Icons.calendar_today, color: Colors.black),
                            Container(
                                padding: EdgeInsets.only(top: 10, left: 5, bottom: 10), child: Text(listOfDates[index]))
                          ],
                        ),
                        for (int x = 0; x < updateIds.length; x++)
                          if (updateDates[x] == listOfDates[index])
                            Container(
                              padding: EdgeInsets.all(8),
                              margin: EdgeInsets.only(left: 25, top: 5),
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: <Widget>[
                                  Container(
                                      width: MediaQuery.of(context).size.width - 100, child: Text(listOfUpdates[x])),
                                  InkWell(
                                      onTap: () async {
                                        print(updateIds[x]);
                                        var url = 'https://office.buildahome.in/API/delete_update?id=${updateIds[x]}';
                                        await http.get(Uri.parse(url));

                                        setState(() {
                                          showDialog(
                                              context: context,
                                              builder: (BuildContext context) {
                                                return ShowAlert("DPR deleted successfully", false);
                                              });
                                          Navigator.pushReplacement(
                                            context,
                                            MaterialPageRoute(builder: (context) => Dpr(this.id)),
                                          );
                                        });
                                      },
                                      child: Icon(Icons.delete, color: Colors.red))
                                ],
                              ),
                            ),
                      ],
                    )));
          },
        ),
      ),
    );
  }
}
