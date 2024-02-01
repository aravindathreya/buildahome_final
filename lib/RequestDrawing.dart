import 'package:buildahome/widgets/material_units.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:http/http.dart' as http;
import 'NavMenu.dart';
import 'package:shared_preferences/shared_preferences.dart';
import "ShowAlert.dart";
import 'projects.dart';
import 'main.dart';
import 'utilities/styles.dart';
import 'widgets/material.dart';
import 'widgets/material_units.dart';
import 'package:intl/intl.dart';

class RequestDrawingLayout extends StatelessWidget {
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
        body: RequestDrawing(),
      ),
    );
  }
}

class RequestDrawing extends StatefulWidget {
  @override
  RequestDrawingState createState() {
    return RequestDrawingState();
  }
}

class RequestDrawingState extends State<RequestDrawing> {
  var user_id;
  var projectName = 'Select project';
  var projectId;
  var category = 'Select category';
  var drawingsSet = {
    'Artchitectural': [
      'Working Drawings',
      'Misc Details',
      'Filter slab layout',
      'Sections',
      '2d elevation',
      'Door window details, Window grill details',
      'Flooring layout details',
      'Toilet kitchen dadoing details',
      'Compound wall details',
      'Fabrication details',
      'Sky light details',
      'External and internal paint shades',
      'Isometric views',
      '3d drawings'
    ],
    'Structural': [
      'Column marking',
      'Footing layout',
      'UG sump details',
      'Plinth beam layout',
      'Staircase details',
      'Floor form work beam and slab reinforcement details',
      'OHT slab details',
      'Lintel details'
    ],
    'Electrical': ['Electrical drawing', 'Conduit drawing'],
    'Plumbing': ['Water line drawing', 'Drinage line drawing', 'RWH details']
  };
  var drawing = 'Select drawing';
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
  }

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: EdgeInsets.all(16),
      children: [
        Container(
            margin: EdgeInsets.symmetric(horizontal: 10, vertical: 20),
            child: Text('Request drawing', style: get_header_text_style())),
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
            margin: EdgeInsets.only(top: 10, bottom: 10, left: 10, right: 10),
            decoration: get_button_decoration(),
            child: Text(category, style: get_button_text_style()),
          ),
          onTap: () async {
            //Get the project name to which the user wants to upload
            var drawingDetails = await showDialog(
                context: context,
                builder: (BuildContext context) {
                  return AlertDialog(
                      contentPadding: EdgeInsets.all(0),
                      content: Column(children: [
                        Container(
                            alignment: Alignment.centerLeft,
                            padding: EdgeInsets.all(10),
                            child: Text("Select category")),
                        Container(
                            height: MediaQuery.of(context).size.height - 130,
                            width: MediaQuery.of(context).size.width - 20,
                            child: ListView.builder(
                                shrinkWrap: true,
                                physics: new BouncingScrollPhysics(),
                                scrollDirection: Axis.vertical,
                                itemCount: drawingsSet.keys.length,
                                itemBuilder: (BuildContext ctxt, int Index) {
                                  return Container(
                                      padding: EdgeInsets.all(20),
                                      decoration: BoxDecoration(
                                        color: Colors.white,
                                        shape: BoxShape.rectangle,
                                        border: Border(
                                          bottom: BorderSide(
                                              width: 1.0,
                                              color: Colors.grey[300]!),
                                        ),
                                      ),
                                      child: InkWell(
                                          onTap: () {
                                            Navigator.pop(
                                                context,
                                                drawingsSet.keys
                                                    .toList()[Index]);
                                          },
                                          child: Text(
                                              drawingsSet.keys.toList()[Index],
                                              style: TextStyle(
                                                  fontSize: 18,
                                                  fontWeight:
                                                      FontWeight.bold))));
                                }))
                      ]));
                });
            setState(() {
              if (drawingDetails != null) {
                category = drawingDetails;
              } else {
                category = 'Select category';
                drawing = "Select drawing";
              }
            });
          },
        ),
        if (category != 'Select category')
          InkWell(
            child: Container(
              padding: EdgeInsets.all(10),
              margin: EdgeInsets.only(top: 10, bottom: 10, left: 10),
              decoration: get_button_decoration(),
              child: Text(drawing, style: get_button_text_style()),
            ),
            onTap: () async {
              //Get the project name to which the user wants to upload
              var selectedDrawing = await showDialog(
                  context: context,
                  builder: (BuildContext context) {
                    return AlertDialog(
                        contentPadding: EdgeInsets.all(0),
                        content: Column(children: [
                          Container(
                              alignment: Alignment.centerLeft,
                              padding: EdgeInsets.all(10),
                              child: Text("Select drawing")),
                          Container(
                              height: MediaQuery.of(context).size.height - 130,
                              width: MediaQuery.of(context).size.width - 20,
                              child: ListView.builder(
                                  shrinkWrap: true,
                                  physics: new BouncingScrollPhysics(),
                                  scrollDirection: Axis.vertical,
                                  itemCount: drawingsSet[category]?.length,
                                  itemBuilder: (BuildContext ctxt, int Index) {
                                    return Container(
                                        padding: EdgeInsets.all(20),
                                        decoration: BoxDecoration(
                                          color: Colors.white,
                                          shape: BoxShape.rectangle,
                                          border: Border(
                                            bottom: BorderSide(
                                                width: 1.0,
                                                color: Colors.grey[300]!),
                                          ),
                                        ),
                                        child: InkWell(
                                            onTap: () {
                                              Navigator.pop(context,
                                                  drawingsSet[category]?[Index]);
                                            },
                                            child: Text(
                                                drawingsSet[category]![Index],
                                                style: TextStyle(
                                                    fontSize: 18,
                                                    fontWeight:
                                                        FontWeight.bold))));
                                  }))
                        ]));
                  });
              setState(() {
                if (selectedDrawing != null) {
                  drawing = selectedDrawing;
                } else {
                  drawing = "Select drawing";
                }
              });
            },
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
                  hintText: "Comments",
                  alignLabelWithHint: true,
                  labelText: "Comments",
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

            if (category == 'Select category') {
              Navigator.of(context, rootNavigator: true).pop();
              showDialog(
                  context: context,
                  builder: (BuildContext context) {
                    return AlertDialog(
                      content: Text(
                        "Please select a category",
                      ),
                    );
                  });
              return;
            }

            if (drawing == 'Select drawing') {
              Navigator.of(context, rootNavigator: true).pop();
              showDialog(
                  context: context,
                  builder: (BuildContext context) {
                    return AlertDialog(
                      content: Text(
                        "Please select a drawing",
                      ),
                    );
                  });
              return;
            }

            DateTime now = DateTime.now();
            String formattedDate = DateFormat('EEEE d MMMM H:m').format(now);
            var url =
                'https://office.buildahome.in/API/create_drawing_request';
            var response = await http.post(Uri.parse(url), body: {
              'project_id': projectId,
              'category': category,
              'drawing': drawing,
              'purpose': purposeTextController.text,
              'user_id': user_id,
              'timestamp': formattedDate,
            });
            print(response.body);
            Navigator.of(context, rootNavigator: true).pop();
            showDialog(
                context: context,
                builder: (BuildContext context) {
                  return ShowAlert("Request created successfully", false);
                });

            setState(() {
              projectName = 'Select project';
              category = 'Select category';
              projectId = null;
              drawing = 'Select drawing';
              purposeTextController.text = '';
            });
          },
        )
      ],
    );
  }
}
