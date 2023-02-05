import 'package:buildahome/edit_indent.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'NavMenu.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'main.dart';
import 'utilities/styles.dart';
import 'widgets/confirmation.dart';
import 'providers/apis.dart';
import "ShowAlert.dart";
import 'edit_indent.dart';

class ViewIndentsLayout extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final appTitle = 'buildAhome';
    final GlobalKey<ScaffoldState> _scaffoldKey =
        new GlobalKey<ScaffoldState>();
    return MaterialApp(
      title: appTitle,
      theme: ThemeData(fontFamily: App().fontName),
      home: Scaffold(
        key: _scaffoldKey, // ADD THIS LINE
        appBar: AppBar(
          automaticallyImplyLeading: false,
          title: Text(appTitle),
          leading: new IconButton(
              icon: new Icon(Icons.menu),
              onPressed: () => _scaffoldKey.currentState.openDrawer()),
          backgroundColor: Color(0xFF000055),
        ),
        drawer: NavMenuWidget(),
        body: ViewIndents(),
      ),
    );
  }
}

class ViewIndents extends StatefulWidget {
  @override
  ViewIndentsState createState() {
    return ViewIndentsState();
  }
}

class ViewIndentsState extends State<ViewIndents> {
  var user_id;
  var indents = [];
  var current_user_name;
  var role;

  @override
  void initState() {
    super.initState();
    call();
  }

  call() async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    user_id = prefs.getString('user_id');
    current_user_name = prefs.get('username');

    var url =
        'https://app.buildahome.in/erp/API/get_unapproved_indents?user_id=${user_id}';
    var response = await http.get(Uri.parse(url));
    print(response.body);
    setState(() {
      indents = jsonDecode(response.body);
      role = prefs.get('role');
    });
  }

  @override
  Widget build(BuildContext context) {
    return Container(
        height: MediaQuery.of(context).size.height,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
                margin: EdgeInsets.symmetric(horizontal: 10, vertical: 20),
                child: Text('Open indents (${indents.length})',
                    style: get_header_text_style())),
            Container(
              height: MediaQuery.of(context).size.height - 180,
              child: ListView.builder(
                  shrinkWrap: true,
                  padding: EdgeInsets.all(15),
                  itemCount: indents.length,
                  itemBuilder: (BuildContext ctxt, int Index) {
                    return Container(
                        margin: EdgeInsets.only(bottom: 30),
                        padding: EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          border: Border.all(color: Colors.grey[500]),
                          borderRadius: BorderRadius.circular(8),
                          color: Colors.grey[100],
                          boxShadow: [
                            new BoxShadow(
                              color: Colors.grey[400],
                              blurRadius: 15,
                              spreadRadius: 3,
                            )
                          ],
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Container(
                                  width: 100,
                                  margin: EdgeInsets.only(bottom: 15),
                                  child: Text(
                                    'Project',
                                    style: TextStyle(fontSize: 15),
                                  ),
                                ),
                                Container(
                                  width:
                                      (MediaQuery.of(context).size.width - 40) /
                                          2,
                                  margin: EdgeInsets.only(bottom: 15),
                                  child: Text(
                                    '${indents[Index]['project_name']}',
                                    style: TextStyle(
                                        fontSize: 15,
                                        fontWeight: FontWeight.w600),
                                  ),
                                ),
                              ],
                            ),
                            Row(
                              children: [
                                Container(
                                  width: 100,
                                  margin: EdgeInsets.only(bottom: 15),
                                  child: Text(
                                    'Material',
                                    style: TextStyle(fontSize: 15),
                                  ),
                                ),
                                Container(
                                  width:
                                      (MediaQuery.of(context).size.width - 40) /
                                          2,
                                  margin: EdgeInsets.only(bottom: 15),
                                  child: Text(
                                    '${indents[Index]['material']}',
                                    style: TextStyle(
                                        fontSize: 15,
                                        fontWeight: FontWeight.w600),
                                  ),
                                ),
                              ],
                            ),
                            Row(
                              children: [
                                Container(
                                  width: 100,
                                  margin: EdgeInsets.only(bottom: 15),
                                  child: Text(
                                    'Quantity',
                                    style: TextStyle(fontSize: 15),
                                  ),
                                ),
                                Container(
                                  width:
                                      (MediaQuery.of(context).size.width - 40) /
                                          2,
                                  margin: EdgeInsets.only(bottom: 15),
                                  child: Text(
                                    '${indents[Index]['quantity']} ${indents[Index]['unit']}',
                                    style: TextStyle(
                                        fontSize: 15,
                                        fontWeight: FontWeight.w600),
                                  ),
                                ),
                              ],
                            ),
                            Row(
                              children: [
                                Container(
                                  width: 100,
                                  margin: EdgeInsets.only(bottom: 15),
                                  child: Text(
                                    'Purpose',
                                    style: TextStyle(fontSize: 15),
                                  ),
                                ),
                                Container(
                                  width:
                                      (MediaQuery.of(context).size.width - 40) /
                                          2,
                                  margin: EdgeInsets.only(bottom: 15),
                                  child: Text(
                                    '${indents[Index]['purpose']}',
                                    style: TextStyle(
                                        fontSize: 15,
                                        fontWeight: FontWeight.w600),
                                  ),
                                ),
                              ],
                            ),
                            Container(
                              margin: EdgeInsets.only(bottom: 30),
                              child: Text(
                                  'Indent created by ${indents[Index]['created_by_user']} on ${indents[Index]['timestamp']}'),
                            ),
                            if (role != 'Site Engineer')
                              Row(
                                mainAxisAlignment:
                                    MainAxisAlignment.spaceBetween,
                                children: [
                                  InkWell(
                                    child: Container(
                                        padding: EdgeInsets.all(10),
                                        width:
                                            (MediaQuery.of(context).size.width -
                                                    80) /
                                                3,
                                        alignment: Alignment.center,
                                        decoration: BoxDecoration(
                                            borderRadius:
                                                BorderRadius.circular(5),
                                            color: Colors.indigo[900]),
                                        child: Text("Edit",
                                            style: TextStyle(
                                                color: Colors.white))),
                                    onTap: () {
                                      Navigator.push(
                                        context,
                                        MaterialPageRoute(
                                            builder: (context) =>
                                                EditIndentLayout(
                                                    indents[Index])),
                                      );
                                    },
                                  ),
                                  InkWell(
                                    child: Container(
                                        padding: EdgeInsets.all(10),
                                        width:
                                            (MediaQuery.of(context).size.width -
                                                    80) /
                                                3,
                                        alignment: Alignment.center,
                                        decoration: BoxDecoration(
                                            borderRadius:
                                                BorderRadius.circular(5),
                                            color: Colors.red[500]),
                                        child: Text("Reject",
                                            style: TextStyle(
                                                color: Colors.white))),
                                    onTap: () async {
                                      var response_for_confirmation =
                                          await showDialog(
                                              barrierDismissible: false,
                                              context: context,
                                              builder: (BuildContext context) {
                                                return Confirmation(
                                                    'Are you sure you want to reject this indent?');
                                              });
                                      if (response_for_confirmation ==
                                          'Confirm') {
                                        showDialog(
                                            barrierDismissible: false,
                                            context: context,
                                            builder: (BuildContext context) {
                                              return ShowAlert(
                                                  "Hang in there. We're adding this user to our records",
                                                  true);
                                            });
                                        await update_indent_status(
                                            'rejected',
                                            indents[Index]['id'].toString(),
                                            indents[Index]
                                                ['created_by_user_id'],
                                            user_id,
                                            '${indents[Index]['quantity']} ${indents[Index]['unit']} ${indents[Index]['material']} Indent for project ${indents[Index]['project_name']} has been rejected by ${current_user_name}');
                                        setState(() {
                                          indents.removeAt(Index);
                                        });
                                        Navigator.of(context,
                                                rootNavigator: true)
                                            .pop();
                                      }
                                    },
                                  ),
                                  InkWell(
                                    child: Container(
                                        padding: EdgeInsets.all(10),
                                        width:
                                            (MediaQuery.of(context).size.width -
                                                    80) /
                                                3,
                                        alignment: Alignment.center,
                                        decoration: BoxDecoration(
                                            borderRadius:
                                                BorderRadius.circular(5),
                                            color: Colors.green[500]),
                                        child: Text("Approve",
                                            style: TextStyle(
                                                color: Colors.white))),
                                    onTap: () async {
                                      var response_for_confirmation =
                                          await showDialog(
                                              barrierDismissible: false,
                                              context: context,
                                              builder: (BuildContext context) {
                                                return Confirmation(
                                                    'Are you sure you want to approve this indent?');
                                              });
                                      if (response_for_confirmation ==
                                          'Confirm') {
                                        showDialog(
                                            barrierDismissible: false,
                                            context: context,
                                            builder: (BuildContext context) {
                                              return ShowAlert(
                                                  "Hang in there. We're adding this user to our records",
                                                  true);
                                            });
                                        await update_indent_status(
                                            'approved',
                                            indents[Index]['id'].toString(),
                                            indents[Index]
                                                ['created_by_user_id'],
                                            user_id,
                                            '${indents[Index]['quantity']} ${indents[Index]['unit']} ${indents[Index]['material']} Indent for project ${indents[Index]['project_name']} has been approved by ${current_user_name}');
                                        setState(() {
                                          indents.removeAt(Index);
                                        });
                                        Navigator.of(context,
                                                rootNavigator: true)
                                            .pop();
                                      }
                                    },
                                  ),
                                ],
                              )
                          ],
                        ));
                  }),
            ),
          ],
        ));
  }
}
