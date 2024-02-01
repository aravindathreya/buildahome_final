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
import 'checklist_items.dart';

class ChecklistCategoriesLayout extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final appTitle = 'buildAhome';
    final GlobalKey<ScaffoldState> _scaffoldKey = new GlobalKey<ScaffoldState>();
    return MaterialApp(
      title: appTitle,
      theme: ThemeData(fontFamily: App().fontName),
      home: Scaffold(
        backgroundColor: Colors.black,
        key: _scaffoldKey, // ADD THIS LINE
        appBar: AppBar(
          automaticallyImplyLeading: true,
          title: Text(appTitle),
          leading: new IconButton(
              icon: new Icon(
                Icons.chevron_left,
                size: 30,
              ),
              onPressed: () => Navigator.pop(context)),
          backgroundColor: Color.fromARGB(255, 0, 0, 0),
        ),

        body: ChecklistCategories()
      ),
    );
  }
}

class ChecklistCategories extends StatefulWidget {
  @override
  ChecklistCategoriesState createState() {
    return ChecklistCategoriesState();
  }
}

class ChecklistCategoriesState extends State<ChecklistCategories> {
  var categories = [];

  @override
  void initState() {
    super.initState();
    call();
  }

  call() async {
    var url = 'https://office.buildahome.in/API/get_checklist_categories';
    var response = await http.get(Uri.parse(url));
    setState(() {
      categories = jsonDecode(response.body)['categories'];
    });
  }




  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: EdgeInsets.symmetric(horizontal: 15, vertical: 20),
      children: [
        Container(
            margin: EdgeInsets.symmetric(horizontal: 10, vertical: 20),
            child: Text('Select category to view checklist', style: TextStyle(color: Color.fromARGB(255, 202, 202, 202)),))
        ,
        for(var i=0; i< categories.length; i++)
          InkWell(
            child: Container(
              padding: EdgeInsets.all(16),
              decoration: BoxDecoration(
                border: Border(
                  bottom: BorderSide(color: Color.fromARGB(255, 65, 65, 65)!)
                )
              ),
              child: Row(
                children: [
                  Icon(Icons.arrow_right_rounded,color: Colors.white),
                  SizedBox(width: 5,),
                  Expanded(child: Text(categories[i], style: TextStyle(fontSize: 16, color: Colors.white),),)
                ],
              )
            ),
            onTap: () {
              Navigator.push(context, MaterialPageRoute(builder: (context) => ChecklistItemsLayout(categories[i])));
            },
          )
      ],
    );
  }
}
