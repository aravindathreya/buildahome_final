import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'NavMenu.dart';
import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

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

    var url = 'https://app.buildahome.in/api/view_all_dpr.php?id=${id}';
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
    final GlobalKey<ScaffoldState> _scaffoldKey =
        new GlobalKey<ScaffoldState>();
    return Container(
      padding: EdgeInsets.only(bottom: 100),
      child: ListView.builder(
        itemCount: listOfDates.length,
        itemBuilder: (BuildContext ctxt, int index) {
          return Container(
              child: Container(
                  padding: EdgeInsets.all(15),
                  margin: EdgeInsets.only(left: 20, top: 30, right: 20),
                  decoration:
                  BoxDecoration(),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Row(
                        children: <Widget>[

                          Container(
                              padding: EdgeInsets.only(bottom: 10),
                              child: Text(listOfDates[index], style: TextStyle(fontSize: 12),),)
                        ],
                      ),
                      for (int x = 0; x < updateIds.length; x++)
                        if (updateDates[x] == listOfDates[index])
                          Container(
                            padding: EdgeInsets.all(8),
                            margin: EdgeInsets.only(top: 10, bottom: 15),
                            decoration: BoxDecoration(
                                color: Colors.white30),
                            child: Row(
                              mainAxisAlignment:
                              MainAxisAlignment.spaceBetween,
                              children: <Widget>[
                                Expanded(child: Text(listOfUpdates[x])),
                                SizedBox(width: 10,),
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
                                                var url =
                                                    'https://app.buildahome.in/api/delete_update.php?id=${updateIds[x]}';
                                                var response = await http.get(Uri.parse(url));
                                                print('${updateIds[x]} ${response.statusCode}');

                                                setState(() {
                                                  listOfUpdates = [];
                                                  updateIds = [];
                                                  call();
                                                });// Submit feedback
                                              },
                                              child: const Text('Yes, delete'),
                                            ),
                                          ],
                                        ),
                                      );

                                    },
                                    child: Text('Delete', style: TextStyle(color: Colors.red[700], fontSize: 12),)
                                )
                              ],
                            ),
                          ),
                    ],
                  )));
        },
      ),
    );
  }
}
