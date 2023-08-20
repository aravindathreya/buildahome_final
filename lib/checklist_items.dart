import 'package:buildahome/widgets/material_units.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'NavMenu.dart';
import 'package:shared_preferences/shared_preferences.dart';
import "ShowAlert.dart";
import 'projects.dart';
import 'main.dart';
import 'utilities/styles.dart';
import 'widgets/material.dart';
import 'package:intl/intl.dart';
import 'package:file_picker/file_picker.dart';
import 'dart:convert';

class ChecklistItemsLayout extends StatelessWidget {
  late final String category;

  ChecklistItemsLayout(this.category);

  @override
  Widget build(BuildContext context) {
    final appTitle = 'buildAhome';
    final GlobalKey<ScaffoldState> _scaffoldKey = new GlobalKey<ScaffoldState>();
    return MaterialApp(
      title: appTitle,
      theme: ThemeData(fontFamily: App().fontName),
      home: Scaffold(
        key: _scaffoldKey, // ADD THIS LINE
        appBar: AppBar(
          automaticallyImplyLeading: true,
          title: Text(appTitle),
          leading: new IconButton(
              icon: new Icon(Icons.chevron_left, size: 30,), onPressed: () => Navigator.pop(context)),
          backgroundColor: Color(0xFF000055),
        ),

        body: ChecklistItems(category),
      ),
    );
  }
}

class ChecklistItems extends StatefulWidget {
  final String category;

  ChecklistItems(this.category);

  @override
  ChecklistItemsState createState() {
    return ChecklistItemsState(this.category);
  }
}

class ChecklistItemsState extends State<ChecklistItems> {
  final String category;

  ChecklistItemsState(this.category);

  var data;
  var loaded = false;
  var projectId;

  @override
  void initState() {
    super.initState();
    call();
  }

  call() async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    projectId = prefs.getString('project_id');
    var url = 'https://app.buildahome.in/erp/API/get_checklist_items_for_category';
    var response = await http.post(Uri.parse(url),
        body: {
          'project_id': projectId,
          'category': category
        }
    );
    print(response.statusCode);
    print(response.body);

    setState(() {
      loaded = true;
      data = jsonDecode(response.body)['data'];
    });
  }


  @override
  Widget build(BuildContext context) {
    return ListView(
      shrinkWrap: true,
      padding: EdgeInsets.symmetric(horizontal: 15),
      children: [
        Container(
            margin: EdgeInsets.symmetric(horizontal: 10, vertical: 20),
            child: Text('Checklist for ${category}'))
        ,
        if(loaded != false)
          for(var i = 0; i < data.length; i++)
            Container(
                padding: EdgeInsets.all(16),
                decoration: BoxDecoration(
                    border: Border(
                        bottom: BorderSide(color: Colors.grey[300]!)
                    )
                ),
                child: Wrap(
                  children: [
                    Expanded(child: Text(data[i][1], style: TextStyle(fontSize: 14),),),
                    Visibility(
                        visible: data[i][2] != null && data[i][2] != 0,
                        child: Container(
                            margin: EdgeInsets.only(top: 10),
                            child: Row(
                              children: [
                                Icon(Icons.check),
                                SizedBox(width: 5),
                                Expanded(child: Text('Checked by buildahome on ${data[i][4]}', style: TextStyle(
                                    color: Colors.indigo[900], fontSize: 12),),)
                              ],
                            )
                        )),
                    Visibility(
                        visible: data[i][3] != null && data[i][3] != 0,
                        child: Container(
                            alignment: Alignment.bottomRight,
                            margin: EdgeInsets.only(top: 10),
                            child: Row(
                              children: [
                                Icon(Icons.check),
                                SizedBox(width: 5),
                                Expanded(child: Text('Marked as checked by you on ${data[i][5]}', style: TextStyle(
                                    color: Colors.green[900], fontSize: 12),),)
                              ],
                            )
                        )),
                    Visibility(
                        visible: data[i][2] != null && data[i][2] != 0 && (data[i][3] == null || data[i][3] == 0),
                        child: Container(
                            alignment: Alignment.bottomRight,
                            margin: EdgeInsets.only(top: 10),
                            child: InkWell(
                              child: Container(
                                padding: EdgeInsets.all(10),
                                margin: EdgeInsets.only(top: 15),
                                decoration: BoxDecoration(
                                    color: Colors.green[900],
                                    borderRadius: BorderRadius.circular(5)
                                ),
                                child: Text('Mark as checked', style: TextStyle(color: Colors.white, fontSize: 12),),
                              ),
                              onTap: () {
                                showDialog(
                                  context: context,
                                  builder: (BuildContext context) =>
                                      AlertDialog(
                                        title: const Text('Confirmation'),
                                        content: const Text('Are you sure you want to mark this item as checked?'),
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
                                                  'https://app.buildahome.in/erp/API/update_checklist_item_by_client';
                                              var response = await http.post(Uri.parse(url),
                                                  body: {
                                                    'project_id': projectId,
                                                    'checklist_item_id': data[i][0].toString()
                                                  }
                                              );
                                              print(response.statusCode);
                                              print(response.body);
                                              call();
                                              if (response.statusCode != 200) {
                                                Navigator.of(context, rootNavigator: true).pop();
                                                showDialog(
                                                    context: context,
                                                    builder: (BuildContext context) {
                                                      return ShowAlert("Something went wrong", false);
                                                    });
                                                return;
                                              }
                                            },
                                            child: const Text('Yes, confirm'),
                                          ),
                                        ],
                                      ),
                                );
                              },
                            )
                        ))
                  ],
                )
            ),
      ],
    );
  }
}
