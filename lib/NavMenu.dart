import 'package:buildahome/AdminDashboard.dart';
import 'package:buildahome/Scheduler.dart' as prefix0;
import 'package:buildahome/Drawings.dart';
import 'package:buildahome/ViewDrawings.dart';
import 'package:buildahome/main.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'Addproject.dart';
import 'ViewProjects.dart';
import 'Gallery.dart';
import 'Scheduler.dart';
import 'UserHome.dart';
import "AdminChatBox.dart";
import 'AddDailyUpdate.dart';
import 'ChatBox.dart';
import 'AddNewUser.dart';
import "NonTenderTasks.dart";

import 'package:shared_preferences/shared_preferences.dart';
import 'Payments.dart';

class NavMenuItem extends StatelessWidget {
  String _route;
  final _icon;
  final _routename;
  NavMenuItem(this._route, this._icon, this._routename);

  _logout() async{
    SharedPreferences preferences = await SharedPreferences.getInstance();
    preferences.clear();
  }
  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        shape: BoxShape.rectangle,
        border: Border(
            bottom: BorderSide(width:1.0, color: Colors.black12),
        ),
        boxShadow: [
          new BoxShadow(
            color: Colors.black12,
            blurRadius: 15,
            spreadRadius: 2,

          )
        ],

      ),
      width: 400,
      padding: EdgeInsets.only(left:20, top: 20, bottom: 10),
      child: InkWell(
        onTap: () {
          if(this._route=="Log out"){
            _logout();
          }
          Navigator.pop(context);
          Navigator.push(
            context,
            MaterialPageRoute(builder: (context) => this._routename),
          );

        },
        child: Row(
            children: <Widget>[
              Icon(this._icon),
              Container(
                padding: EdgeInsets.only(left:5),
                child: Text(this._route , textAlign: TextAlign.left, style: TextStyle(fontSize:18, color: Colors.black,),),
              ),
            ]),
      ),
    );
  }
}



class NavMenuWidget extends StatefulWidget {
  @override
  NavMenuWidgetState createState() {
    return NavMenuWidgetState();
  }
}

class NavMenuWidgetState extends State<NavMenuWidget> {
  void initState() {
    super.initState();
    call();
  }
  var username;
  var role;
  var location;

  call() async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    setState(() {
      username = prefs.getString('username');
      role = prefs.getString('role');
      location = prefs.getString('location');

    });
  }

  @override
  Widget build(BuildContext context) {
    final appTitle = 'buildAhome';
    return Drawer(

          child: ListView(
            dragStartBehavior: DragStartBehavior.start,
              children: <Widget>[
                Container(
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: Color(0xFF000969),
                    shape: BoxShape.rectangle,
                  ),
                  padding: EdgeInsets.only(top: 80, left: 20, bottom: 40),
                  child: InkWell(
                    child: Column(
                      children: <Widget>[
                        Row(

                            children: <Widget>[
                              Container(
                                decoration: BoxDecoration(
                                  color: Color(0xFF000969),

                                ),
                                child: Container(

                                  padding: EdgeInsets.all(10),
                                  decoration: BoxDecoration(
                                    color: Color(0xFF000979),
                                    border: Border.all(color: Colors.white, width: 4.0),
                                    borderRadius: BorderRadius.all(Radius.circular(50)),

                                  ),
                                  child: Icon(Icons.person ,size: 40, color: Colors.white),
                                ),
                              ),


                              Container(
                                  padding: EdgeInsets.only(left: 15),
                                  alignment: Alignment.centerLeft,
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,

                                    children: <Widget>[

                                      Container(

                                        child: Text(username.toString(), textAlign: TextAlign.left, style: TextStyle(fontSize:22, color: Colors.white, fontWeight: FontWeight.bold),),
                                      ),
                                      Container(
                                          padding: EdgeInsets.only(top: 5),
                                          child: Text(role.toString(), style: TextStyle(color: Colors.white, fontSize: 16),)
                                      )
                                    ],)

                              ),

                            ]),
                          if(role=="Client")
                          Container(
                            margin: EdgeInsets.only(top: 30),
                            alignment: Alignment.topLeft,
                            child: Text("Building a home at", style: TextStyle(color: Colors.white, fontSize: 16),)
                          ),
                           if(role=="Client")
                          Row(
                            mainAxisAlignment: MainAxisAlignment.start,
                            children: <Widget>[
                              Container(
                                margin: EdgeInsets.only(top: 10, right: 10),
                                alignment: Alignment.topLeft,
                                child: Icon(Icons.location_on, color: Colors.white),
                              ),


                              Container(
                                  margin: EdgeInsets.only(top: 10),
                                  alignment: Alignment.topLeft,
                                  width: 200,
                                  child: Text(location.toString(), style: TextStyle(color: Colors.white, fontSize: 22,),)
                              )
                            ],

                          ),
                      ],
                    ),

                  ),
                ),
                if(role=='Client')
                  Container(
                    child: NavMenuItem("Dashboard", Icons.dashboard, Home()),
                  ),
                if(role=='Client')
                  Container(
                    child: NavMenuItem("Scheduler", Icons.access_time, TaskWidget()),
                  ),
                if(role=='Client')
                  Container(
                    child: NavMenuItem("Non Tender Payments", Icons.not_interested, NonTenderTaskWidget()),
                  ),
                if(role=='Client')
                  Container(
                    child: NavMenuItem("Payments", Icons.payment, PaymentTaskWidget()),
                  ),
                if(role=='Client')
                  Container(
                  child: NavMenuItem("Gallery", Icons.photo_album, Gallery()),
                ),
//                if(role=='Client')
//                  Container(
//                    child: NavMenuItem("Drawings", Icons.image, VIewDrawing()),
//                  ),
                if(role=='Client')
                  Container(
                  child: NavMenuItem("Drawings & Documents", Icons.insert_drive_file, Documents()),
                ),
                if(role=='Admin'||role=='Project Coordinator'||role=='Site Engineer')
                  Container(
                    child: NavMenuItem("Dashboard", Icons.dashboard, AdminDashboard()),
                  ),
                if(role=='Admin'||role=='Project Coordinator'||role=='Site Engineer')
                  Container(
                    child: NavMenuItem("Add Daily Update", Icons.update, AddDailyUpdate()),
                  ),
                
//                if(role=='Admin'||role=='Office Manager'||role=='Site Engineer')
//                  Container(
//                    child: NavMenuItem("Add Drawing", Icons.image, AddDrawing()),
//                  ),
                if(role=='Client')
                  Container(
                  child: NavMenuItem("Message Box", Icons.chat_bubble_outline, Chatbox()),
                ),
//                if(role=="Admin")
//                  Container(
//                    child: NavMenuItem("Queries", Icons.question_answer, AdminChatbox()),
//                  ),
                Container(
                  child: NavMenuItem("Log out", Icons.backspace, MyApp()),
                ),
              ]
          ),

    );
  }
}
