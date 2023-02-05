import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_spinkit/flutter_spinkit.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';

class UpdateTemplates extends StatelessWidget{
  String mesaage;
  bool is_Loading=false;



  Widget build(BuildContext context){

    return AlertDialog(
        contentPadding: EdgeInsets.all(0),

        content:
        FutureBuilder(
            future: http.get(Uri.parse("https://app.buildahome.in/api/update_templates.php"),),
            builder: (context, snapshot) {
              switch (snapshot.connectionState) {
                case ConnectionState.none:
                  return Text('Press button to start.');
                case ConnectionState.active:

                case ConnectionState.waiting:
                  return Container(
                    padding: EdgeInsets.only(top: 20),
                    child: SpinKitThreeBounce(
                      color: Colors.indigo[900],
                      size: 30.0,
                    ),
                  );

                case ConnectionState.done:
                  if (snapshot.hasError)
                    return Text('Error: ${snapshot.error}');
                  var projects = jsonDecode(snapshot.data.body);
                  return ListView(
                      scrollDirection: Axis.vertical,
                      children: <Widget>[
                        Container(
                            padding: EdgeInsets.all(15),
                            child: Text("Tap on update to select", )
                        ),
                        ListView.builder(
                            shrinkWrap: true,
                            physics: new BouncingScrollPhysics(),
                            scrollDirection: Axis.vertical,
                            itemCount: projects.length,
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
                                        Navigator.pop(context, projects[Index]['text']);
                                      },
                                      child: Text(projects[Index]['text'], style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold))
                                  )

                              );
                            }
                        )
                      ]
                  );
              }
            }
        )

    );

  }
}

