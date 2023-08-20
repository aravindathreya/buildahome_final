import 'package:buildahome/widgets/material_units.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:http/http.dart' as http;
import 'view_open_indents.dart';
import 'package:shared_preferences/shared_preferences.dart';
import "ShowAlert.dart";
import 'projects.dart';
import 'main.dart';
import 'utilities/styles.dart';
import 'widgets/material.dart';
import 'widgets/material_units.dart';
import 'package:intl/intl.dart';
import 'dart:async';
import 'dart:convert';

class EditIndentLayout extends StatelessWidget {
  final indent;
  EditIndentLayout(this.indent);

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
          automaticallyImplyLeading: true,
          title: Text(appTitle),
          leading: new IconButton(
              icon: new Icon(Icons.chevron_left),
              onPressed: () => {Navigator.pop(context)}),
          backgroundColor: Color(0xFF000055),
        ),

        body: EditIndent(this.indent),
      ),
    );
  }
}

class EditIndent extends StatefulWidget {
  var indent;
  EditIndent(this.indent);

  @override
  EditIndentState createState() {
    return EditIndentState(this.indent);
  }
}

class EditIndentState extends State<EditIndent> {
  var indent;
  EditIndentState(this.indent);

  var user_id;
  var current_user_name;
  var projectName = 'Select project';
  var projectId;
  var material = 'Select material';
  var unit = 'Unit';
  var quantityTextController = new TextEditingController();
  var purposeTextController = new TextEditingController();

  @override
  void initState() {
    super.initState();
    call();
  }

  call() async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    user_id = prefs.getString('user_id');
    current_user_name = prefs.get('username');
    setState(() {
      projectId = this.indent['project_id'];
      projectName = this.indent['project_name'];
      material = this.indent['material'];
      quantityTextController.text = this.indent['quantity'];
      purposeTextController.text = this.indent['purpose'];
      unit = this.indent['unit'];
    });
  }

  @override
  Widget build(BuildContext context) {
    return ListView(
      children: [
        Container(
            margin: EdgeInsets.symmetric(horizontal: 10, vertical: 20),
            child: Text('Edit indent', style: get_header_text_style())),
        InkWell(
          child: Container(
            width: MediaQuery.of(context).size.width,
            padding: EdgeInsets.all(10),
            margin: EdgeInsets.all(10),
            decoration: get_button_decoration(),
            child: Text(projectName, style: get_button_text_style()),
          ),
          onTap: () async {
            //Get the project name to which the user wants to upload
            var projectDetails = await showDialog(
                context: context,
                builder: (BuildContext context) {
                  return ProjectsModal(user_id);
                });
            setState(() {
              projectName = projectDetails.split("|")[0];
              projectId = projectDetails.split("|")[1];
            });
          },
        ),
        InkWell(
          child: Container(
            padding: EdgeInsets.all(10),
            margin: EdgeInsets.only(top: 10, bottom: 10, left: 10),
            decoration: get_button_decoration(),
            child: Text(material, style: get_button_text_style()),
          ),
          onTap: () async {
            //Get the project name to which the user wants to upload
            var materialDetails = await showDialog(
                context: context,
                builder: (BuildContext context) {
                  return Materials();
                });
            setState(() {
              material = materialDetails;
            });
          },
        ),
        Container(
            child: Row(
          children: [
            Container(
                margin: EdgeInsets.only(left: 10),
                width: (MediaQuery.of(context).size.width * .7) - 20,
                child: TextFormField(
                  controller: quantityTextController,
                  keyboardType: TextInputType.numberWithOptions(),
                  decoration: InputDecoration(
                    contentPadding:
                        EdgeInsets.symmetric(vertical: 5, horizontal: 10),
                    border: OutlineInputBorder(),
                    floatingLabelBehavior: FloatingLabelBehavior.never,
                    fillColor: Colors.white,
                    focusColor: Colors.white,
                    filled: true,
                    errorBorder: OutlineInputBorder(
                      borderSide:
                          BorderSide(color: Colors.grey[600]!, width: 1.0),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderSide:
                          BorderSide(color: Colors.grey[600]!, width: 1.0),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderSide:
                          BorderSide(color: Colors.grey[300]!, width: 1.0),
                    ),
                    hintText: "Quantity",
                    alignLabelWithHint: true,
                    labelText: "Quantity",
                  ),
                )),
            InkWell(
              child: Container(
                width: (MediaQuery.of(context).size.width * .3) - 10,
                padding: EdgeInsets.all(10),
                margin: EdgeInsets.all(10),
                alignment: Alignment.center,
                decoration: BoxDecoration(
                    color: Colors.grey[300]!,
                    border: Border.all(color: Colors.grey[300]!, width: 1.5)),
                child: Text(unit, style: get_button_text_style()),
              ),
              onTap: () async {
                //Get the project name to which the user wants to upload
                var unitDetails = await showDialog(
                    context: context,
                    builder: (BuildContext context) {
                      return MaterialUnits();
                    });
                setState(() {
                  unit = unitDetails;
                });
              },
            ),
          ],
        )),
        Container(
            alignment: Alignment.topLeft,
            margin: EdgeInsets.all(10),
            child: TextFormField(
              autocorrect: true,
              controller: purposeTextController,
              keyboardType: TextInputType.multiline,
              textCapitalization: TextCapitalization.sentences,
              maxLines: 4,
              style: TextStyle(fontSize: 18),
              decoration: InputDecoration(
                  focusColor: Colors.black,
                  floatingLabelBehavior: FloatingLabelBehavior.never,
                  errorBorder: OutlineInputBorder(
                    borderSide: BorderSide(color: Colors.grey[600]!, width: 1.0),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderSide: BorderSide(color: Colors.grey[600]!, width: 1.0),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderSide: BorderSide(color: Colors.grey[300]!, width: 1.0),
                  ),
                  filled: true,
                  hintText: "Purpose for indent",
                  alignLabelWithHint: true,
                  labelText: "Purpose for indent",
                  labelStyle: TextStyle(
                    fontSize: 18,
                  ),
                  fillColor: Colors.white),
              validator: (value) {
                if (value!.isEmpty) {
                  return 'This field cannot be empty';
                }
                return null;
              },
            )),
        InkWell(
          child: Container(
            alignment: Alignment.center,
            padding: EdgeInsets.all(8),
            margin: EdgeInsets.all(10),
            decoration: BoxDecoration(
              boxShadow: [
                new BoxShadow(
                  color: Colors.grey[600]!,
                  blurRadius: 5,
                  spreadRadius: 1,
                )
              ],
              gradient: LinearGradient(
                // Where the linear gradient begins and ends
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,

                // Add one stop for each color. Stops should increase from 0 to 1
                stops: [0.2, 0.5, 0.8],
                colors: [
                  // Colors are easy thanks to Flutter's Colors class.

                  //Colors.blue,
                  Colors.indigo[900]!,
                  Colors.indigo[700]!,
                  //Colors.indigo[700]!,
                  Colors.indigo[900]!,
                ],
              ),
              border: Border.all(color: Colors.black, width: 1),
              borderRadius: BorderRadius.all(Radius.circular(5)),
            ),
            child: Text(
              "Approve",
              style: TextStyle(
                  fontSize: 18,
                  color: Colors.white,
                  fontWeight: FontWeight.bold),
            ),
          ),
          onTap: () async {
            showDialog(
                barrierDismissible: false,
                context: context,
                builder: (BuildContext context) {
                  return ShowAlert(
                      "Hang in there. We're adding this user to our records",
                      true);
                });

            DateTime now = DateTime.now();
            String formattedDate = DateFormat('EEEE d MMMM H:m').format(now);

            var url =
                'https://app.buildahome.in/erp/API/edit_and_approve_indent';
            var response = await http.post(Uri.parse(url), body: {
              'indent_id': this.indent['id'].toString(),
              'project_id': projectId.toString(),
              'material': material,
              'quantity': quantityTextController.text,
              'unit': unit,
              'purpose': purposeTextController.text,
              'user_id': user_id.toString(),
              'acted_by_user': user_id.toString(),
              'notification_body':
                  '${quantityTextController.text} ${unit} ${material} Indent for project ${projectName} has been edited and approved by ${current_user_name}',
              'timestamp': formattedDate,
            });
            var responseBody = jsonDecode(response.body);
            if (responseBody['message'] == 'failure') {
              Navigator.of(context, rootNavigator: true).pop();
              showDialog(
                  context: context,
                  builder: (BuildContext context) {
                    return ShowAlert(
                        "Indent failed. " + responseBody['reason'], false);
                  });
              return;
            }

            Navigator.of(context, rootNavigator: true).pop();
            showDialog(
                context: context,
                builder: (BuildContext context) {
                  return ShowAlert("Indent updated and approved!", false);
                });
            Navigator.pop(context);
            Navigator.push(
              context,
              MaterialPageRoute(builder: (context) => ViewIndentsLayout()),
            );
            setState(() {
              projectName = 'Select project';
              projectId = null;
              material = 'Select material';
              unit = 'Unit';
              quantityTextController.text = '';
              purposeTextController.text = '';
            });

            //set_response_text(response.body);
          },
        )
      ],
    );
  }
}
