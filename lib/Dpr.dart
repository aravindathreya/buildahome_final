import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'NavMenu.dart';
import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'AnimationHelper.dart';
import 'main.dart';

class DprScreen extends StatefulWidget {
  @override
  DprState createState() {
    return DprState();
  }
}

class DprState extends State<DprScreen> {
  var entries;
  var listOfDates = [];
  var listOfUpdates = [];
  var updateDates = [];
  var updateIds = [];

  call() async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    var id = prefs.getString('project_id');

    var url = 'https://office.buildahome.in/API/view_all_dpr?id=${id}';
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
    return Container(
      padding: EdgeInsets.only(bottom: 100),
      child: ListView.builder(
        itemCount: listOfDates.length,
        itemBuilder: (BuildContext ctxt, int index) {
          return Container(
              child: Container(
                  padding: EdgeInsets.all(15),
                  margin: EdgeInsets.only(left: 20, top: 30, right: 20),
                  decoration: BoxDecoration(),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Row(
                        children: <Widget>[
                          listOfDates[index].trim() != '' ? Container(
                            padding: EdgeInsets.only(bottom: 10),
                            child: Row(children: [
                              Icon(Icons.date_range, color: Colors.white,),
                              const SizedBox(width: 10,),
                               Text(
                              listOfDates[index],
                              style: TextStyle(fontSize: 18, color: Colors.white),
                            ),
                            ],)
                          ) : Container(height: 20,)
                        ],
                      ),
                      for (int x = 0; x < updateIds.length; x++)
                        if (updateDates[x] == listOfDates[index])
                          AnimatedWidgetSlide(
                            direction: x % 2 == 0 ? SlideDirection.leftToRight : SlideDirection.rightToLeft, // Specify the slide direction
                            duration: Duration(milliseconds: 100), // Adjust the duration as needed
                            child: Container(
                              margin: EdgeInsets.only(bottom: 10),
                              decoration: BoxDecoration(color: Color.fromARGB(95, 70, 70, 70),  borderRadius: BorderRadius.circular(10),
                                
                                border: Border.all(color: Color.fromARGB(255, 51, 51, 51))
                              ),
                              child: Column(children: [
                                Container(
                                  height: 40,
                                  decoration: BoxDecoration(color: Color(0xFF000055), borderRadius: BorderRadius.only(
                                    topLeft: Radius.circular(10),
                                    topRight: Radius.circular(10),
                                  )),
                                ),
                                Container(
                                  padding: EdgeInsets.all(15),
                                  child: Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: <Widget>[
                                  Expanded(child: Text(listOfUpdates[x], style: TextStyle(color: Colors.white, fontSize: 16),)),
                                  SizedBox(
                                    width: 10,
                                  ),
                                  InkWell(
                                      onTap: () async {
                                        showDialog(
                                          context: context,
                                          builder: (BuildContext context) => AlertDialog(
                                            title: const Text('Confirmation'),
                                            content: const Text('Are you sure you want to submit your feedback?'),
                                            actions: <Widget>[
                                              TextButton(
                                                onPressed: () {
                                                  Navigator.of(context).pop(); // Close the confirmation dialog
                                                },
                                                child: const Text('Cancel'),
                                              ),
                                              TextButton(
                                                onPressed: () async {
                                                  Navigator.of(context).pop(); // Close the confirmation dialog
                                                  var url = 'https://office.buildahome.in/API/delete_update?id=${updateIds[x]}';
                                                  var response = await http.get(Uri.parse(url));
                                                  print('${updateIds[x]} ${response.statusCode}');

                                                  setState(() {
                                                    listOfUpdates = [];
                                                    updateIds = [];
                                                    call();
                                                  }); // Submit feedback
                                                },
                                                child: const Text('Yes, delete'),
                                              ),
                                            ],
                                          ),
                                        );
                                      },
                                      child: Text(
                                        'Delete',
                                        style: TextStyle(color: Colors.red[700], fontSize: 12),
                                      ))
                                ],
                              ),
                                )
                                
                              ],)
                            ),
                          )
                    ],
                  )));
        },
      ),
    );
  }
}
