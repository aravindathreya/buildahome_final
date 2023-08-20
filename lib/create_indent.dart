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

class CreateIndentLayout extends StatelessWidget {
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
              onPressed: () => _scaffoldKey.currentState?.openDrawer()),
          backgroundColor: Color(0xFF000055),
        ),
        drawer: NavMenuWidget(),
        body: CreateIndent(),
      ),
    );
  }
}

class CreateIndent extends StatefulWidget {
  @override
  CreateIndentState createState() {
    return CreateIndentState();
  }
}

class CreateIndentState extends State<CreateIndent> {
  var user_id;
  var projectName = 'Select project';
  var projectId;
  var material = 'Select material';
  var unit = 'Unit';
  var quantityTextController = new TextEditingController();
  var purposeTextController = new TextEditingController();
  var diffCostTextController = new TextEditingController(text: '0');
  var approvalTaken = false;
  var attachedFileName = '';
  var attachedFile;

  @override
  void initState() {
    super.initState();
    call();
  }

  call() async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    user_id = prefs.getString('user_id');
  }

  void getFile() async {
    var res = await FilePicker.platform.pickFiles(allowMultiple: false);
    var file = res?.files.first;
    if (file != null) {
      setState(() {
        var fileSplit = file.path?.split('/');
        attachedFile = file;
        attachedFileName = 'Attached file: ' +
            (fileSplit![fileSplit.length - 1]);
      });
    } else {
      setState(() {
        attachedFileName = '';
      });
    }
  }

  bool _isNumeric(String str) {
    return double.tryParse(str) != null;
  }

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: EdgeInsets.symmetric(horizontal: 15),
      children: [
        Container(
            margin: EdgeInsets.symmetric(horizontal: 10, vertical: 20),
            child: Text('Create indent', style: get_header_text_style())),
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
              if (projectDetails != null) {
                projectName = projectDetails.split("|")[0];
                projectId = projectDetails.split("|")[1];
              } else {
                projectName = 'Select project';
                projectId = null;
              }
            });
          },
        ),
        InkWell(
          child: Container(
            padding: EdgeInsets.all(10),
            margin: EdgeInsets.all(10),
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
              if (materialDetails != null)
                material = materialDetails;
              else
                material = 'Select material';
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
                width: (MediaQuery.of(context).size.width * .3) - 40,
                padding: EdgeInsets.all(10),
                margin: EdgeInsets.all(10),
                alignment: Alignment.center,
                decoration: BoxDecoration(
                    color: Colors.grey[300],
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
                  if (unitDetails != null) {
                    unit = unitDetails;
                  } else {
                    unit = 'Unit';
                  }
                });
              },
            ),
          ],
        )),
        Container(
            margin: EdgeInsets.only(left: 10, right: 10),
            width: (MediaQuery.of(context).size.width * .7) - 50,
            child: TextFormField(
              controller: diffCostTextController,
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
                  borderSide: BorderSide(color: Colors.grey[600]!, width: 1.0),
                ),
                focusedBorder: OutlineInputBorder(
                  borderSide: BorderSide(color: Colors.grey[600]!, width: 1.0),
                ),
                enabledBorder: OutlineInputBorder(
                  borderSide: BorderSide(color: Colors.grey[300]!, width: 1.0),
                ),
                hintText: "Difference cost",
                alignLabelWithHint: true,
                labelText: "Difference cost",
              ),
            )),
        Container(
          margin: EdgeInsets.only(top: 10),
          child: Row(
            children: [
              Checkbox(
                activeColor: Colors.indigo[900],
                value: approvalTaken,
                onChanged: (value) {
                  setState(() {
                    approvalTaken = value!;
                  });
                },
              ),
              Container(
                child: Text(
                  'Approval taken',
                  style: TextStyle(fontSize: 16),
                ),
              )
            ],
          ),
        ),
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
        Container(
            child: InkWell(
          onTap: () async => getFile(),
          child: Container(
              margin: EdgeInsets.only(left: 10, right: 10),
              decoration: BoxDecoration(
                color: Colors.white,
                border: Border.all(width: 1.0, color: Colors.grey[300]!),
                borderRadius: BorderRadius.all(Radius.circular(5)),
              ),
              padding: EdgeInsets.all(15),
              child: Row(
                children: <Widget>[
                  Container(
                    decoration: BoxDecoration(
                        borderRadius: BorderRadius.all(Radius.circular(50)),
                        color: Colors.white),
                    child: Icon(Icons.file_upload,
                        size: 25, color: Colors.indigo[900]),
                  ),
                  Container(
                      padding: EdgeInsets.only(left: 10),
                      child: Text('Add attachment (Optional)',
                          style: TextStyle(fontSize: 16)))
                ],
              )),
        )),
        Container(
          margin: EdgeInsets.only(left: 15, bottom: 10, top: 10),
          child: Text(
            attachedFileName,
            style: TextStyle(fontWeight: FontWeight.w600),
          ),
        ),
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
                  Colors.indigo[900]!,
                ],
              ),
              border: Border.all(color: Colors.black, width: 1),
              borderRadius: BorderRadius.all(Radius.circular(5)),
            ),
            child: Text(
              "Submit",
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

            if (projectName == 'Select project') {
              Navigator.of(context, rootNavigator: true).pop();
              showDialog(
                  context: context,
                  builder: (BuildContext context) {
                    return AlertDialog(
                      content: Text(
                        "Please select a project",
                      ),
                    );
                  });
              return;
            }

            if (material == 'Select material') {
              Navigator.of(context, rootNavigator: true).pop();
              showDialog(
                  context: context,
                  builder: (BuildContext context) {
                    return AlertDialog(
                      content: Text(
                        "Please select a material",
                      ),
                    );
                  });
              return;
            }

            if (quantityTextController.text.trim() == '') {
              Navigator.of(context, rootNavigator: true).pop();
              showDialog(
                  context: context,
                  builder: (BuildContext context) {
                    return AlertDialog(
                      content: Text(
                        "Please enter quantity",
                      ),
                    );
                  });
              return;
            }

            if (!_isNumeric(quantityTextController.text.trim())) {
              Navigator.of(context, rootNavigator: true).pop();
              showDialog(
                  context: context,
                  builder: (BuildContext context) {
                    return AlertDialog(
                      content: Text(
                        "Please enter valid data for quantity",
                      ),
                    );
                  });
              return;
            }

            if (unit == 'Unit') {
              Navigator.of(context, rootNavigator: true).pop();
              showDialog(
                  context: context,
                  builder: (BuildContext context) {
                    return AlertDialog(
                      content: Text(
                        "Please select a unit",
                      ),
                    );
                  });
              return;
            }

            if (!_isNumeric(diffCostTextController.text.trim())) {
              Navigator.of(context, rootNavigator: true).pop();
              showDialog(
                  context: context,
                  builder: (BuildContext context) {
                    return AlertDialog(
                      content: Text(
                        "Please enter valid data for difference cost",
                      ),
                    );
                  });
              return;
            }

            if (purposeTextController.text.trim() == '') {
              Navigator.of(context, rootNavigator: true).pop();
              showDialog(
                  context: context,
                  builder: (BuildContext context) {
                    return AlertDialog(
                      content: Text(
                        "Please enter purpose for indent",
                      ),
                    );
                  });
              return;
            }

            DateTime now = DateTime.now();
            String formattedDate = DateFormat('EEEE d MMMM H:m').format(now);
            var url = 'https://app.buildahome.in/erp/API/create_indent';
            var response = await http.post(Uri.parse(url), body: {
              'project_id': projectId,
              'material': material,
              'quantity': quantityTextController.text.trim(),
              'unit': unit,
              'differenceCost': diffCostTextController.text.trim(),
              'purpose': purposeTextController.text.trim(),
              'approvalTaken': approvalTaken ? '1' : '0',
              'user_id': user_id,
              'timestamp': formattedDate,
            });
            print(response.body);
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
            var indentId = responseBody['indent_id'];
            if (attachedFileName != '') {
              var uri = Uri.parse(
                  "https://app.buildahome.in/erp/API/indent_file_uplpoad");
              var request = new http.MultipartRequest("POST", uri);

              var pic =
                  await http.MultipartFile.fromPath("file", attachedFile.path);

              request.files.add(pic);
              request.fields['indent_id'] = indentId.toString();
              var fileResponse = await request.send();
              var responseData = await fileResponse.stream.toBytes();
              var responseString = String.fromCharCodes(responseData);
              print(responseString);
            }
            Navigator.of(context, rootNavigator: true).pop();
            showDialog(
                context: context,
                builder: (BuildContext context) {
                  return ShowAlert("Indent added successfully", false);
                });

            setState(() {
              projectName = 'Select project';
              projectId = null;
              material = 'Select material';
              unit = 'Unit';
              quantityTextController.text = '';
              purposeTextController.text = '';
              diffCostTextController.text = '0';
              approvalTaken = false;
              attachedFileName = '';
            });

            //set_response_text(response.body);
          },
        )
      ],
    );
  }
}
