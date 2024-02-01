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

class StockReportLayout extends StatelessWidget {
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
          automaticallyImplyLeading: false,
          title: Text(appTitle),
          leading: new IconButton(icon: new Icon(Icons.menu), onPressed: () => _scaffoldKey.currentState?.openDrawer()),
          backgroundColor: Color(0xFF000055),
        ),
        drawer: NavMenuWidget(),
        body: StockReport(),
      ),
    );
  }
}

class StockReport extends StatefulWidget {
  @override
  StockReportState createState() {
    return StockReportState();
  }
}

class StockReportState extends State<StockReport> {
  var user_id;
  var userName;
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
  var materialsTextController = [new TextEditingController()];
  var quantitiesTextController = [new TextEditingController()];
  var unitsTextController = [new TextEditingController()];

  @override
  void initState() {
    super.initState();
    call();
  }

  call() async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    user_id = prefs.getString('user_id');
    userName = prefs.getString('username')!;
  }

  void getFile() async {
    var res = await FilePicker.platform.pickFiles(allowMultiple: false);
    var file = res?.files.first;
    if (file != null) {
      setState(() {
        var fileSplit = file.path?.split('/');
        attachedFile = file;
        attachedFileName = 'Attached file: ' + (fileSplit![fileSplit.length - 1]);
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
            child: Text('Stock report', style: get_header_text_style())),
        Container(
          margin: EdgeInsets.symmetric(horizontal: 10, vertical: 20),
          child: Text(
            DateFormat("dd MMMM yyyy").format(DateTime.now()),
          ),
        ),
        InkWell(
          child: Container(
            width: MediaQuery.of(context).size.width,
            padding: EdgeInsets.all(10),
            margin: EdgeInsets.only(left: 10, bottom: 20),
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
        for (var i = 0; i < materialsTextController.length; i++)
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              InkWell(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      margin: EdgeInsets.only(left: 10, top: 15),
                      child: Text(
                        'Material',
                        style: TextStyle(fontSize: 12),
                      ),
                    ),
                    Container(
                        padding: EdgeInsets.all(15),
                        margin: EdgeInsets.all(10),
                        decoration: BoxDecoration(color: Colors.white, border: Border.all(color: Colors.grey[300]!)),
                        child: Container(
                          width: (MediaQuery.of(context).size.width - 60) * .55,
                          child: Text(materialsTextController[i].text, style: TextStyle(fontSize: 12)),
                        )),
                  ],
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
                      materialsTextController[i].text = materialDetails;

                  });
                },
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    margin: EdgeInsets.only(left: 10, top: 15),
                    child: Text(
                      'Quantity',
                      style: TextStyle(fontSize: 12),
                    ),
                  ),
                  Container(
                      margin: EdgeInsets.only(left: 10, top: 10, right: 10),
                      width: (MediaQuery.of(context).size.width - 60) * .3,
                      child: TextFormField(
                        controller: quantitiesTextController[i],
                        keyboardType: TextInputType.numberWithOptions(),
                        decoration: InputDecoration(
                          contentPadding: EdgeInsets.symmetric(vertical: 5, horizontal: 10),
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
                          alignLabelWithHint: true,
                        ),
                      )),
                ],
              ),
            ],
          ),
        InkWell(
            child: Container(
          alignment: Alignment.centerLeft,
          padding: EdgeInsets.all(8),
          margin: EdgeInsets.all(10),
              child: Text('Add new entry'),
        ),

          onTap: () {
              setState(() {
                materialsTextController.add(TextEditingController());
                quantitiesTextController.add(TextEditingController());
              });
          },
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
              style: TextStyle(fontSize: 18, color: Colors.white, fontWeight: FontWeight.bold),
            ),
          ),
          onTap: () async {
            showDialog(
                barrierDismissible: false,
                context: context,
                builder: (BuildContext context) {
                  return ShowAlert("Hang in there. We're adding this user to our records", true);
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

            if (materialsTextController.isEmpty) {
              Navigator.of(context, rootNavigator: true).pop();
              showDialog(
                  context: context,
                  builder: (BuildContext context) {
                    return AlertDialog(
                      content: Text(
                        "Please add atleast one entry",
                      ),
                    );
                  });
              return;
            }


            var stockReportEntries = [];
            for(var i=0; i< materialsTextController.length; i++) {
              if(materialsTextController[i].text == '') {
                Navigator.of(context, rootNavigator: true).pop();
                showDialog(
                    context: context,
                    builder: (BuildContext context) {
                      return AlertDialog(
                        content: Text(
                          "Material cannot be empty",
                        ),
                      );
                    });
                return;
              }
              if(quantitiesTextController[i].text == '') {
                Navigator.of(context, rootNavigator: true).pop();
                showDialog(
                    context: context,
                    builder: (BuildContext context) {
                      return AlertDialog(
                        content: Text(
                          "Quantity cannot be empty",
                        ),
                      );
                    });
                return;
              }
              stockReportEntries.add('${materialsTextController[i].text}|${quantitiesTextController[i].text}');
            }


            DateTime now = DateTime.now();
            String formattedDate = DateFormat('EEEE d MMMM yyyy H:m').format(now);
            var url = 'https://office.buildahome.in/API/update_stock_report';
            var response = await http.post(Uri.parse(url), body: {
              'project_id': projectId,
              'timestamp': formattedDate,
              'stock_report_entries': stockReportEntries.join('^'),
              'user_id': user_id,
              'user_name': userName
            });
            print(response.body);
            if (response.statusCode != 200) {
              Navigator.of(context, rootNavigator: true).pop();
              showDialog(
                  context: context,
                  builder: (BuildContext context) {
                    return ShowAlert("Something went wrong", false);
                  });
              return;
            }

            Navigator.of(context, rootNavigator: true).pop();
            showDialog(
                context: context,
                builder: (BuildContext context) {
                  return ShowAlert("Stock report submitted successfully", false);
                });

            setState(() {
              projectName = 'Select project';
              projectId = null;
              materialsTextController.clear();
              quantitiesTextController.clear();
            });

            //set_response_text(response.body);
          },
        )
      ],
    );
  }
}
