import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:percent_indicator/circular_percent_indicator.dart';
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'NavMenu.dart';
import 'package:intl/intl.dart';
import 'dart:async';
import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';


class AdminChatbox extends StatefulWidget{
  @override
  AdminChatboxState createState() {
    return AdminChatboxState();
  }
}


class AdminChatboxState extends State<AdminChatbox> {
  var projects;
  var records;
  getInfo() async{
    var response = await http.get(Uri.parse("https://app.buildahome.in/api/view_all_projects.php"));
      var prs = {};
      records = jsonDecode(response.body);
      for(int i=0; i<records.length; i++){
        var name = records[i]['name'];
        var url = "https://app.buildahome.in/api/get_latest_chat.php?username=$name";
        print(url);
        var lastmessage = await http.get(Uri.parse(url));
        print(lastmessage.body.toString());
        if(lastmessage.body==null){
          prs[name.toString()] = "-";
        }else{
          prs[name.toString()] = lastmessage.body;
        }


        print(prs);

      }
      setState(() {
        projects= prs;
      });

  }

  @override
  void initState() {
    super.initState();
    getInfo();
  }
  final GlobalKey<ScaffoldState> _scaffoldKey = new GlobalKey<ScaffoldState>();

  @override
  Widget build(BuildContext context) {
    final appTitle = 'BuildAhome';
    return MaterialApp(
      title: appTitle,
      theme: ThemeData(fontFamily: 'Varela'),
      home: Scaffold(
          key: _scaffoldKey,
          // ADD THIS LINE
          drawer: NavMenuWidget(),

          appBar: AppBar(
            automaticallyImplyLeading: false,
            title: Text(appTitle),
            leading: new IconButton(
                icon: new Icon(Icons.menu),
                onPressed: () => _scaffoldKey.currentState.openDrawer()),
            backgroundColor: Colors.indigo[900],
          ),
          body: ListView(
              scrollDirection: Axis.vertical,
              children: <Widget>[
                ListView.builder(
                    shrinkWrap: true,
                    physics: new BouncingScrollPhysics(),
                    scrollDirection: Axis.vertical,
                    itemCount: records==null ? 0 : records.length,
                    itemBuilder: (BuildContext ctxt, int Index) {
                      return Container(
                          padding: EdgeInsets.all(15),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            shape: BoxShape.rectangle,
                            border: Border(
                              bottom: BorderSide(width:1.0, color: Colors.black54),
                            ),
                            boxShadow: [
                              new BoxShadow(
                                color: Colors.black12,
                                blurRadius: 15,
                                spreadRadius: 2,
                              )
                            ],
                          ),
                          child: InkWell(
                              onTap: (){
                                Navigator.pop(context, records[Index]['name']+"|"+projects[Index]['id']);
                              },
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: <Widget>[
                                  Text(records[Index]['name'], style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                                  Container(
                                    padding: EdgeInsets.only(top: 5),
                                    child: Text(projects[records[Index]['name']], style: TextStyle(fontSize: 12
                                      ))
                                  ),

                                ],
                              )


                          )


                      );
                    }
                )
              ]
          )

      ),
    );
  }
}