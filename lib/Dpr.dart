import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'NavMenu.dart';
import 'dart:convert';

import 'main.dart';

class Dpr extends StatefulWidget {
  var id;

  Dpr(this.id);

  @override
  DprState createState() {
    return DprState(this.id);
  }
}


class DprState extends State<Dpr> {

  var entries;
  var id;
  var list_of_dates = [];
  var list_of_updates = [];
  var update_dates = [];
  var update_ids = [];

  DprState(this.id);

  call() async {
    var url = 'https://www.buildahome.in/api/view_all_dpr.php?id=${this.id}';
    var response = await http.get(url);
    setState(() {
      list_of_dates = [];
      entries = jsonDecode(response.body);
      for(int i=0;i<entries.length;i++){
        if(list_of_dates.contains(entries[i]['date'])==false){
          list_of_dates.add(entries[i]['date']);
        }
        if(list_of_updates.contains(entries[i]['update_title'])==false){
          list_of_updates.add(entries[i]['update_title']);
          update_dates.add(entries[i]['date']);
          update_ids.add(entries[i]['id']);
        }
      }
    });
  }

  @override
  void initState() {
    super.initState();
    call();
  }


  @override
  Widget build(BuildContext context) {

    final appTitle = 'buildAhome';
    final GlobalKey<ScaffoldState> _scaffoldKey =
    new GlobalKey<ScaffoldState>();
    return MaterialApp(
      title: appTitle,
      theme: ThemeData(fontFamily: MyApp().fontName),
      home: Scaffold(
          key: _scaffoldKey,
          appBar: AppBar(
            automaticallyImplyLeading: false,
            title: Text(appTitle),
            leading: new IconButton(
                icon: new Icon(Icons.arrow_back_ios),
                onPressed: () => {
                  Navigator.pop(context),
                }),
            backgroundColor: Color(0xFF000055),
          ),
          drawer: NavMenuWidget(),
          body: ListView.builder(
            itemCount: list_of_dates == null? 0 : list_of_dates.length ,
            itemBuilder: (BuildContext ctxt, int Index) {
              return Container(
                  child: Container(
                      padding: EdgeInsets.all(15),
                      decoration: BoxDecoration(
                          border: Border(
                              bottom: BorderSide()
                          )
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          Row(
                            children: <Widget>[

                              Icon(Icons.calendar_today, color: Colors.black),
                              Container(
                                  padding: EdgeInsets.only(left: 5, bottom: 10),
                                  child: Text(list_of_dates[Index])
                              )
                            ],
                          ),
                          for(int x=0;x<update_ids.length;x++)
                            if(update_dates[x]==list_of_dates[Index])
                              Container(
                                padding: EdgeInsets.all(8),
                                margin: EdgeInsets.only(left: 25,top : 5),
                                decoration: BoxDecoration(
                                  border: Border.all(),
                                  color: Colors.white30
                                ),
                                child: Row(
                                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                  children: <Widget>[
                                    Container(
                                        child: Text(list_of_updates[x])
                                    ),
                                    InkWell(
                                        onTap: () async{
                                          print(update_ids[x]);
                                          var url = 'https://www.buildahome.in/api/delete_update.php?id=${update_ids[x]}';
                                          var response = await http.get(url);
                                          setState(() {
                                            list_of_updates.removeAt(x);
                                            update_ids.removeAt(x);
                                          });

                                        },
                                        child: Icon(Icons.close, color: Colors.red)
                                    )
                                  ],
                                ),
                              ),


                        ],
                      )
                  )
              );



            },
          )
      ),
    );
  }
}
