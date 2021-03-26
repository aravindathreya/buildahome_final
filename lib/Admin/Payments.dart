import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'dart:convert';
import 'package:http/http.dart' as http;
import '../NavMenu.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../main.dart';

import "Dpr.dart";
import "Scheduler.dart";
import "Gallery.dart";
import "Drawings.dart";

class PaymentTaskWidget extends StatelessWidget {

  var id;
  PaymentTaskWidget(this.id);

  @override
  Widget build(BuildContext context) {
    final appTitle = 'buildAhome';
    final GlobalKey<ScaffoldState> _scaffoldKey =
        new GlobalKey<ScaffoldState>();
    return MaterialApp(
      title: appTitle,
      theme: ThemeData(fontFamily: MyApp().fontName),
      home: Scaffold(
        key: _scaffoldKey, // ADD THIS LINE
        drawer: NavMenuWidget(),
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
        body: PaymentTasksClass(this.id),
        bottomNavigationBar: BottomNavigationBar(
          currentIndex: 4,
          selectedItemColor: Colors.indigo[900],
          onTap: (int index) {
            if (index == 0) {
              Navigator.pushReplacement(
                context,
                MaterialPageRoute(builder: (context) => Dpr(this.id)),
              );
            } else if (index == 1) {
              Navigator.pushReplacement(
                context,
                MaterialPageRoute(builder: (context) => Documents(this.id)),
              );
            } else if (index == 2) {
              Navigator.pushReplacement(
                context,
                MaterialPageRoute(builder: (context) => Gallery(this.id)),
              );
            } else if (index == 3) {
                Navigator.pushReplacement(
                  context,
                  MaterialPageRoute(builder: (context) => TaskWidget(this.id)),
                );
            } else if (index == 4) {
              Navigator.pushReplacement(
                context,
                MaterialPageRoute(builder: (context) => PaymentTaskWidget(this.id)),
              );
            }
          },
          unselectedItemColor: Colors.grey[400],
          type: BottomNavigationBarType.fixed,
          items: [
            BottomNavigationBarItem(
              icon: Icon(
                Icons.home,
              ),
              title: Text(
                'Home',
                style: TextStyle(fontSize: 12),
              ),
            ),
            BottomNavigationBarItem(
              icon: Icon(
                Icons.picture_as_pdf,
              ),
              title: Text(
                'Drawings',
                style: TextStyle(fontSize: 12),
              ),
            ),
            BottomNavigationBarItem(
              icon: Icon(
                Icons.photo_album,
              ),
              title: Text(
                "Gallery",
                style: TextStyle(fontSize: 12),
              ),
            ),
              BottomNavigationBarItem(
                icon: Icon(
                  Icons.access_time,
                ),
                title: Text(
                  'Scheduler',
                  style: TextStyle(fontSize: 12),
                ),
              ),
            BottomNavigationBarItem(
                icon: Icon(
                  Icons.payment,
                ),
                title: Text(
                  'Payment',
                  style: TextStyle(fontSize: 12),
                ),
              ),
              
          ],
        ),
        
      ),
    );
  }
}
class TaskItem extends StatefulWidget {
  String _Task_name;
  var _icon = Icons.home;
  var _start_date;
  var _end_date;
  var _height;
  var _color = Colors.white;
  var _payment_percentage;
  var status;
  var note;

  TaskItem(this._Task_name, this._start_date, this._end_date,
      this._payment_percentage, this.status, this.note);

  @override
  TaskItemWidget createState() {
    return TaskItemWidget(this._Task_name, this._icon, this._start_date,
        this._end_date, this._color, this._height, this._payment_percentage, this.status, this.note);
  }
}

class TaskItemWidget extends State<TaskItem> with SingleTickerProviderStateMixin {
  String _Task_name;
  var _icon = Icons.home;
  var _start_date;
  var _end_date;
  var _color;
  var vis = false;
  var _payment_percentage;
  var _text_color = Colors.black;
  var _height = 50.0;
  var spr_radius = 1.0;
  var pad = 10.0;
  var value_str;
  var value =0;
  var status;
  var amt;
  var note;
  var gradient;

  @override
  void initState() {
    super.initState();
    _set_value();
    _progress();

  }

  _set_value() async{
    SharedPreferences prefs = await SharedPreferences.getInstance();
    value_str = prefs.getString("pr_value");
    value = int.parse(value_str);
    setState(() {
      amt = ((int.parse(this._payment_percentage))/100 ) * value;

    });
  }
  _progress() {

    if (this.status=='not due')
    {
      this._color = Colors.white;
      this._text_color = Colors.black;
      this.gradient = LinearGradient(
        // Where the linear gradient begins and ends
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,

        // Add one stop for each color. Stops should increase from 0 to 1
        stops: [0.1, 0.9],
        colors: [
          // Colors are easy thanks to Flutter's Colors class.

          Colors.white,
          Colors.white,
        ],
      );
    }
    else if (this.status=='paid'){
      this._color = Colors.green;
      this._text_color = Colors.white;
      this.gradient = LinearGradient(
        // Where the linear gradient begins and ends
        begin: Alignment.centerLeft,
        end: Alignment.centerRight,

        // Add one stop for each color. Stops should increase from 0 to 1
        stops: [0.3, 0.5, 0.9],
        colors: [
          // Colors are easy thanks to Flutter's Colors class.

          Colors.green[700],
          Colors.green[500],
          Colors.green[700],
        ],
      );
    }
    else{
      this._color = Colors.deepOrange;
      this._text_color = Colors.white;
      this.gradient = LinearGradient(
        // Where the linear gradient begins and ends
        begin: Alignment.centerLeft,
        end: Alignment.centerRight,

        // Add one stop for each color. Stops should increase from 0 to 1
        stops: [0.2, 0.5, 0.9],
        colors: [
          // Colors are easy thanks to Flutter's Colors class.

          Color(0xFFff3300),
          Color(0xFFff471a),
          Color(0xFFff3300),
        ],
      );
    }
  }

  var view = Icons.expand_more;

  _expand_collapse() {
    setState(() {
      if (vis == false) {
        vis = true;
        view = Icons.expand_less;
        spr_radius = 1.0;
      } else if (vis == true) {
        vis = false;
        view = Icons.expand_more;
        spr_radius = 1.0;
      }
    });
  }

  TaskItemWidget(this._Task_name, this._icon, this._start_date, this._end_date,
      this._color, this._height, this._payment_percentage, this.status, this.note);

  @override
  Widget build(BuildContext context) {
    return Column(
      children: <Widget>[
        Container(
            child: AnimatedContainer(
              duration: Duration(milliseconds: 500),
              decoration: BoxDecoration(
                  color: this._color,
                  gradient: this.gradient,
                  boxShadow: [
                    new BoxShadow(
                        color: Colors.grey[400],
                        blurRadius: 10,
                        spreadRadius: this.spr_radius,
                        offset: Offset(0.0, 10.0))
                  ],
                  border: Border.all(color: Colors.black, width: 2.0)),
              padding: EdgeInsets.all(this.pad),
              child: Container(

                child: Column(children: <Widget>[
                  AnimatedContainer(
                    duration: Duration(milliseconds: 900),
                    padding: EdgeInsets.only(left: 7),
                    child: Row(
                      children: <Widget>[
                        InkWell(
                          onTap: _expand_collapse,
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: <Widget>[
                              Container(
                                width: MediaQuery.of(context).size.width * .8,
                                child: Text(
                                  this._Task_name,
                                  textAlign: TextAlign.left,
                                  style: TextStyle(
                                    fontSize: 14,
                                    color: this._text_color,
                                  ),
                                ),
                              ),
                              new Icon(view, color: this._text_color),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  Visibility(
                      visible: this.vis,
                      child: Column(
                        children: <Widget>[
                          Container(
                              padding: EdgeInsets.all(10),
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: <Widget>[
                                  Text(
                                    this._payment_percentage + "%     ₹ "+amt.toString(),
                                    style: TextStyle(
                                        fontSize: 18,
                                        fontWeight: FontWeight.bold,
                                        color: this._text_color),
                                  )
                                ],
                              )
                          ),
                          Container(
                              alignment: Alignment.centerLeft,
                              child: Text(this.note, style: TextStyle(color: this._text_color, fontWeight: FontWeight.bold),)
                          )

                        ],
                      )


                  ),

                ]),
              ),
            )),
      ],
    );
  }
}

class PaymentTasksClass extends StatefulWidget {
  var id;

  PaymentTasksClass(this.id);
  @override
  PaymentTasks createState() {
    return PaymentTasks(this.id);
  }
}

class PaymentTasks extends State<PaymentTasksClass> {
  var body;
  var tasks = [];
  var id;
  var outstanding = "";
  var total_paid = "";
  var project_value="";

  PaymentTasks(this.id);
  ScrollController _controller = new ScrollController();

  @override
  void initState() {
    super.initState();
    call();
  }


  call() async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    id = prefs.getString('project_id');
    var url = 'https://www.buildahome.in/api/get_all_tasks.php?project_id=$id&nt_toggle=1  ';
    var response = await http.get(url);
    var url1 = 'https://www.buildahome.in/api/get_payment.php?project_id=$id ';
    var response1 = await http.get(url1);
    var details = jsonDecode(response1.body);
    prefs.setString("pr_value",details[0]['value']);
    setState(() {
    outstanding = details[0]['outstanding'];
    total_paid = details[0]['total_paid'];
        project_value = details[0]['value'];
        body = jsonDecode(response.body);
    });

  }


  @override
  Widget build(BuildContext context) {
    return ListView(children: <Widget>[
      Container(
          padding: EdgeInsets.only(top: 20, left: 10, bottom: 10),
          decoration: BoxDecoration(
              border: Border(
            bottom: BorderSide(width: 6.0, color: Colors.indigo[900]),
          )),
          child: Text("Payments",
              style: TextStyle(
                fontSize: 20,
              ))),
      Container(
        padding: EdgeInsets.all(10),
        child: Container(
        padding: EdgeInsets.all(10),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: <Widget>[
            Container(
              padding: EdgeInsets.only(top: 15),
              child: Row(
                children: <Widget>[
                  Container(
                      padding: EdgeInsets.only(right: 10),
                      height: 10,
                      width: 10,
                      decoration: BoxDecoration(
                        color: Colors.deepOrange,
                        border: Border.all(color: Colors.grey[300]),
                        borderRadius: BorderRadius.circular(3)
                      ),
                      ),
                  Container(
                      padding: EdgeInsets.only(left: 5),
                      child: Text("Due")),
                ],
              ),
            ),
            Container(
              padding: EdgeInsets.only(top: 15),
              child: Row(
                children: <Widget>[
                  Container(
                      padding: EdgeInsets.only(right: 10),
                      height: 10,
                      width: 10,
                      decoration: BoxDecoration(
                          border: Border.all(color: Colors.grey[300]),
                          borderRadius: BorderRadius.circular(3),
                          color: Colors.green
                      ),
                    ),
                  Container(
                      padding: EdgeInsets.only(left: 5),
                      child: Text("Paid")
                  ),
                ],
              ),
            ),
            Container(
              padding: EdgeInsets.only(top: 15),
              child: Row(
                children: <Widget>[
                  Container(
                      padding: EdgeInsets.only(right: 10),
                      height: 10,
                      width: 10,
                      decoration: BoxDecoration(
                          color: Colors.white70,
                          border: Border.all(color: Colors.grey[300]),
                          borderRadius: BorderRadius.circular(3)
                      ),
                    ),
                  Container(
                      padding: EdgeInsets.only(left: 5),
                      child: Text("Ongoing tasks"))
                ],
              ),
            ),
          ],
        ),
      ),),
      
      Container(
        margin: EdgeInsets.symmetric(vertical: 20, horizontal: 10),
        padding: EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: Colors.grey[200],
          borderRadius: BorderRadius.circular(5),
        ),
        child: Column(
          children: <Widget>[
            Container(
              padding: EdgeInsets.symmetric(vertical: 5),
              child: Row(
                children: <Widget>[
                Container(
                  width: 150,
                  child: Text("Project Value :", style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold))
                ),
                Container(
                  child: Text("₹ "+project_value, style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold))
                )
              ],)
            ),
            // Container(
            //   padding: EdgeInsets.symmetric(vertical: 5),
            //   child: Row(
            //     children: <Widget>[
            //     Container(
            //       width: 150,
            //       child: Text("Amount paid :", style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.green))
            //     ),
            //     Container(
            //       child: Text("₹ 3,00,000", style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.green))
            //     )
            //   ],)
            // ),
            Container(
              padding: EdgeInsets.symmetric(vertical: 5),
              child: Row(
                children: <Widget>[
                Container(
                  width: 150,
                  child: Text("Paid till date :", style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.green[500]))
                ),
                Container(
                  child: Text("₹ "+total_paid, style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.green[500]))
                )
              ],)
            ),
            Container(
              padding: EdgeInsets.symmetric(vertical: 5),
              child: Row(
                children: <Widget>[
                Container(
                  width: 150,
                  child: Text("Current Outstanding :", style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.red[500]))
                ),
                Container(
                  child: Text("₹ "+outstanding, style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.red[500]))
                )
              ],)
            )
          ],
        ),
      ),
      
      new ListView.builder(
          shrinkWrap: true,
          physics: BouncingScrollPhysics(),
          itemCount: body == null ? 0 : body.length,
          itemBuilder: (BuildContext ctxt, int Index) {
            return Container(
              child: TaskItem(

                  body[Index]['task_name'].toString(),
                  body[Index]['start_date'].toString(),
                  body[Index]['end_date'].toString(),
                  body[Index]['payment'].toString(),
                  body[Index]['paid'].toString(),
                  body[Index]['p_note'].toString(),
              ),


            );
          }),
    ]);
  }
}
