import 'package:flutter/material.dart';
import 'package:flutter/widgets.dart';
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'NavMenu.dart';


class ProjectCard extends StatelessWidget{
  String pr_name = "";
  String client_name = "";
  String pr_location = "";
  String pr_start_date = "";

  ProjectCard(this.pr_name, this.pr_location, this.pr_start_date, this.client_name);

  @override
  Widget build(BuildContext context) {

  return Card(
    child: Container(
        width: 400,
        padding: EdgeInsets.all(30),
        decoration: BoxDecoration(

          gradient: LinearGradient(
            // Where the linear gradient begins and ends
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,

            // Add one stop for each color. Stops should increase from 0 to 1
            stops: [0.3, 0.7],
            colors: [
              // Colors are easy thanks to Flutter's Colors class.
              Colors.grey[300],
              Colors.grey[100],
            ],
          ),
          border: Border.all(),
          borderRadius: BorderRadius.all(Radius.elliptical(15, 15)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.start,
          children: <Widget>[
            Container(
              child: Text("Project name ${pr_name}", style: TextStyle(fontSize: 24,fontWeight: FontWeight.bold),),
            ),
            Container(
              padding: EdgeInsets.only(top:20),
              child: Text("Location ${pr_location}", style: TextStyle(fontSize: 20,),),
            ),
            Container(
              padding: EdgeInsets.only(top:20),
              child: Text("Start Date ${pr_start_date}", style: TextStyle(fontSize: 20,),),
            ),Container(
              padding: EdgeInsets.only(top:20),
              child: Text("Client name ${client_name}", style: TextStyle(fontSize: 20,),),
            ),

          ],
        )
      ),
    );
  }
}

class ViewProject extends StatelessWidget {


  final GlobalKey<ScaffoldState> _scaffoldKey = new GlobalKey<ScaffoldState>();
  @override
  Widget build(BuildContext context) {
    final appTitle = 'BuildAhome';

    return MaterialApp(
      title: appTitle,
      home: Scaffold(
        key: _scaffoldKey, // ADD THIS LINE
        drawer: NavMenuWidget(),

        appBar: AppBar(
          automaticallyImplyLeading: false,
          title:  Text(appTitle),
          leading: new IconButton(icon: new Icon(Icons.menu),
              onPressed: () => _scaffoldKey.currentState.openDrawer()),
          backgroundColor: Colors.indigo[900],

        ),
        body: ViewProjectForm(),
      ),
    );
  }
}


class ViewProjectForm extends StatefulWidget {
  @override
  ViewProjectState createState() {
    return ViewProjectState();
  }
}

class ViewProjectState extends State<ViewProjectForm> {
  @override
  void initState() {
    super.initState();
    call();
  }
  var a;
  call() async{
    print("check");
    var url = 'http://10.0.2.2:80/bah/api/view_projects.php';
    var response = await http.get(Uri.parse(url));
    print(response.body);
    setState(() {
      a = jsonDecode(response.body);
    });
  }

  Widget build(BuildContext context) {
      return Container(
          padding: EdgeInsets.all(20),
          child:new ListView.builder(
            itemCount: a == null? 0 : a.length ,
            itemBuilder: (BuildContext ctxt, int Index) {
              return new Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[

                  ProjectCard(a[Index]['pr_name'].toString(),a[Index]['pr_location'].toString(),a[Index]['pr_start_date'].toString(),a[Index]['pr_client'].toString(),)
                ],
              );
            },

          )

      );


  }
}

