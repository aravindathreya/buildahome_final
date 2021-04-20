import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'NavMenu.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'main.dart';

class Chatbox extends StatefulWidget{
  @override
  ChatboxState createState() {
    return ChatboxState();
  }
}
class ChatboxState extends State<Chatbox> {

  var list_of_messages = [];
  var who = [];
  var added_messages = [];
  var times = [];

  getmessages() async{
    SharedPreferences prefs = await SharedPreferences.getInstance();
    Timer.periodic(new Duration(seconds: 1), (timer) {
      if(timer.tick.toInt()%10==0){
        //getmessages();
      }
    });
    var username = prefs.getString('username');
    var url = 'https://app.buildahome.in/api/get_messages.php?username=${username}';
    var response = await http.get(url);
    var a = jsonDecode(response.body);

    setState(() {
      for(var i=0; i<a.length;i++){
            added_messages.add(a[i]['msg_id']);
            list_of_messages.add(a[i]['msg'].toString());

            var time = DateTime.parse(a[i]['sent_at'].toString());
            var formatted = new DateFormat('hh:mm').format(time);
            times.add(formatted);
            if(a[i]['sent_from_role']!=prefs.getString('role')){
              who.add(Alignment.topLeft);
            }
            else{
              who.add(Alignment.topRight);
            }
      }

    });

  }

  @override
  void initState() {
    super.initState();
    getmessages();
  }
  final GlobalKey<ScaffoldState> _scaffoldKey = new GlobalKey<ScaffoldState>();
  final message = TextEditingController();


  void send_message() async{
    if(message.text!=''){
      SharedPreferences prefs = await SharedPreferences.getInstance();


      var url = 'https://app.buildahome.in/api/chatbox.php';
      var response = await http.post(url, body: {
        "msg": message.text,
        "sent_from_role": prefs.getString('role'),
        "sent_from":  prefs.getString('username'),
        "project_id": prefs.getString('project_id')

      });
      setState(() {
        list_of_messages.add(message.text);
        who.add(Alignment.topRight);
        message.text ="";
        times.add(new DateFormat('hh:mm').format(DateTime.now()));

      });

    }

  }
  @override
  Widget build(BuildContext context) {
    final appTitle = 'buildAhome';



    return MaterialApp(
      title: appTitle,
      theme: ThemeData(fontFamily: MyApp().fontName),
      home: Scaffold(
        key: _scaffoldKey,
        // ADD THIS LINE
        drawer: NavMenuWidget(),
        appBar: AppBar(
          automaticallyImplyLeading: false,
          title: Text(appTitle, ),
          leading: new IconButton(
              icon: new Icon(Icons.menu),
              onPressed: () => _scaffoldKey.currentState.openDrawer()),
          backgroundColor: Color(0xFF000055),
        ),
        body: ListView(
          reverse: true,
          physics: BouncingScrollPhysics(),
          children: <Widget>[
            Column(
              mainAxisAlignment: MainAxisAlignment.end,
              children: <Widget>[
                Container(
                    padding: EdgeInsets.all(15),
                    decoration: BoxDecoration(),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: <Widget>[
                        ListView.builder(
                            physics: BouncingScrollPhysics(),
                            shrinkWrap: true,
                            itemCount: list_of_messages.length,
                            itemBuilder: (BuildContext ctxt, int Index) {
                              return Column(
                                children: <Widget>[
                                  Container(
                                    padding: EdgeInsets.only(bottom: 15),
                                    alignment: who[Index],
                                    child: Container(
                                      alignment: Alignment.topLeft,
                                      padding: EdgeInsets.all(15),
                                      width: MediaQuery.of(context).size.width * .80,
                                      decoration: BoxDecoration(
                                        borderRadius:
                                        BorderRadius.all(Radius.elliptical(10, 10)),
                                        gradient: LinearGradient(
                                          // Where the linear gradient begins and ends
                                          begin: Alignment.topLeft,
                                          end: Alignment.bottomRight,

                                          // Add one stop for each color. Stops should increase from 0 to 1
                                          stops: [0.1, 0.3, 0.7, 0.9],
                                          colors: [
                                            // Colors are easy thanks to Flutter's Colors class.

                                            //Colors.blue,
                                            Colors.indigo[900],
                                            Colors.indigo[800],
                                            //Colors.indigo[700],
                                            Colors.indigo[700],
                                            Colors.indigo[900],
                                          ],
                                        ),

                                      ),
                                      child: Wrap(

                                        children: <Widget>[
                                          Text(list_of_messages[Index].toString(),
                                              style: TextStyle(fontSize: 16, color: Colors.white)),
                                          Container(
                                            alignment: Alignment.bottomRight,
                                            child:Text(times[Index].toString(),
                                                style: TextStyle(fontSize: 12, color: Colors.white)),

                                          ),
                                        ],
//                                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                      ),

                                    ),
                                  ),
                                ],
                              );
                            }),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: <Widget>[
                            Container(
                              width: MediaQuery.of(context).size.width * .78,
                              child: TextFormField(
                                controller: message,
                                textCapitalization: TextCapitalization.sentences,
                                decoration: InputDecoration(
//                              suffixIcon: Container(
//                                  color: Colors.indigo[900],
//                                  child: InkWell(
//                                    child: Icon(
//                                      Icons.send,
//                                      color: Colors.white,
//                                    ),
//                                    onTap: () => send_message(),
//                                  )),

                                  border: OutlineInputBorder(
                                    borderSide:
                                    BorderSide(color: Colors.black, width: 10.0),
                                  ),
                                  contentPadding: EdgeInsets.all(12),
                                  labelStyle: TextStyle(
                                    fontSize: 24,

                                  ),
                                ),
                                style: TextStyle(fontSize: 16),


                              ),
                            ),
                            InkWell(
                              onTap: () => send_message(),
                              child: Container(
                                  color: Colors.indigo[900],
                                  padding: EdgeInsets.all(10),
                                  child: Icon(Icons.send, color: Colors.white,)
                              ),
                            ),
                          ],
                        ),

                      ],
                    )),
              ],
            )
          ],
        )
      ),
    );
  }
}
