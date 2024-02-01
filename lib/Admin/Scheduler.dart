import 'package:flutter/material.dart';
import 'dart:convert';
import 'package:http/http.dart' as http;
import '../NavMenu.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:percent_indicator/linear_percent_indicator.dart';
import '../main.dart';

import "Dpr.dart";
import "Payments.dart";
import "Gallery.dart";
import 'Drawings.dart';

class TaskWidget extends StatefulWidget {
  final id;
  TaskWidget(this.id);

  @override
  State<TaskWidget> createState() => TaskWidget1(this.id);
}

class TaskWidget1 extends State<TaskWidget> {
  var id;
  var role = "";
  TaskWidget1(this.id);

  call() async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    setState(() {
      role = prefs.getString("role")!;
    });
  }

  @override
  void initState() {
    // TODO: implement initState
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
      theme: ThemeData(fontFamily: App().fontName),
      home: Scaffold(
        key: _scaffoldKey,
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
        body: TaskScreenClass(this.id),
        bottomNavigationBar: BottomNavigationBar(
          currentIndex: 3,
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
                MaterialPageRoute(
                    builder: (context) => PaymentTaskWidget(this.id)),
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
                label: 'Home'
            ),
            BottomNavigationBarItem(
                icon: Icon(
                  Icons.picture_as_pdf,
                ),
                label: 'Drawings'
            ),
            BottomNavigationBarItem(
                icon: Icon(
                  Icons.photo_album,
                ),
                label: "Gallery"
            ),
            if (role == 'Site Engineer' ||
                role == "Admin" ||
                role == 'Project Coordinator')
              BottomNavigationBarItem(
                  icon: Icon(
                    Icons.access_time,
                  ),
                  label: 'Scheduler'
              ),
            if (role == 'Project Coordinator' || role == "Admin")
              BottomNavigationBarItem(
                  icon: Icon(
                    Icons.payment,
                  ),
                  label: 'Payment'
              ),
          ],
        ),
      ),
    );
  }
}

class TaskItem extends StatefulWidget {
  final _taskName;
  final _icon = Icons.home;
  final _startDate;
  final _endDate;
  final _height = 0.0;
  final _color = Colors.white;
  final _subTasks;
  final _progressStr;
  final note;

  TaskItem(this._taskName, this._startDate, this._endDate, this._subTasks,
      this._progressStr, this.note);

  @override
  TaskItemWidget createState() {
    return TaskItemWidget(
        this._taskName,
        this._icon,
        this._startDate,
        this._endDate,
        this._progressStr,
        this._color,
        this._height,
        this._subTasks,
        this.note);
  }
}

class TaskItemWidget extends State<TaskItem>
    with SingleTickerProviderStateMixin {
  String _taskName;
  var _icon = Icons.home;
  var _startDate;
  var _endDate;
  var _color;
  var vis = false;
  var _subTasks;
  var _textColor = Colors.black;
  var _height = 50.0;
  var sprRadius = 1.0;
  var pad = 10.0;
  var _progressStr;
  var note;
  var view = Icons.expand_more;
  var notes;

  @override
  void initState() {
    super.initState();
    call();
  }

  call() {
    var total = this._subTasks.split("^");
    var done = (this._progressStr.split("|"));
    notes = (this.note.split("|"));
    print(notes);
    if (((done.length - 1) / (total.length - 1)) > 0.9) {
      setState(() {
        this._textColor = Colors.green[600]!;
      });
    }
  }

  _progress() {
    print('${this._subTasks} Subtasks, $_progressStr');
    var total = this._subTasks.split("^");
    var done = (this._progressStr.split("|"));
    var percent = (done.length - 1) / (total.length - 1);
    if (percent > 1) return 1.0;
    return percent;
  }

  _expandCollapse() {
    setState(() {
      if (vis == false) {
        vis = true;
        view = Icons.expand_less;
        sprRadius = 1.0;
      } else if (vis == true) {
        vis = false;
        view = Icons.expand_more;
        sprRadius = 1.0;
      }
    });
  }

  TaskItemWidget(this._taskName, this._icon, this._startDate, this._endDate,
      this._progressStr, this._color, this._height, this._subTasks, this.note);

  @override
  Widget build(BuildContext context) {
    return Column(
      children: <Widget>[
        Container(
            color: this._color,
            child: AnimatedContainer(
              duration: Duration(milliseconds: 500),
              decoration: BoxDecoration(
                  color: Colors.white,
                  boxShadow: [
                    new BoxShadow(
                        color: Colors.grey[400]!,
                        blurRadius: 10,
                        spreadRadius: this.sprRadius,
                        offset: Offset(0.0, 10.0))
                  ],
                  border: Border.all(color: Colors.black, width: 2.0)),
              child: Container(
                decoration: BoxDecoration(
                  color: this._color,
                ),
                padding: EdgeInsets.all(this.pad),
                child: Column(children: <Widget>[
                  AnimatedContainer(
                    duration: Duration(milliseconds: 900),
                    padding: EdgeInsets.only(left: 7),
                    child: Row(
                      children: <Widget>[
                        InkWell(
                          onTap: _expandCollapse,
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: <Widget>[
                              Container(
                                width: MediaQuery.of(context).size.width * .8,
                                child: Text(
                                  this._taskName,
                                  textAlign: TextAlign.left,
                                  style: TextStyle(
                                      fontSize: 14,
                                      color: _textColor,
                                      fontWeight: FontWeight.bold),
                                ),
                              ),
                              new Icon(view, color: Colors.indigo[600]),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  Visibility(
                    visible: this.vis,
                    child: Container(
                        width: MediaQuery.of(context).size.width,
                        child: Column(
                          children: <Widget>[
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: <Widget>[
                                Container(
                                    padding: EdgeInsets.only(left: 7, top: 10),
                                    child: Text(
                                      DateFormat("dd MMM")
                                          .format(
                                              DateTime.parse(this._startDate))
                                          .toString(),
                                      style: TextStyle(
                                        fontSize: 12,
                                        color: Colors.black,
                                      ),
                                    )),
                                Container(
                                    padding: EdgeInsets.only(right: 7, top: 10),
                                    child: Text(
                                      DateFormat("dd MMM")
                                          .format(
                                              DateTime.parse(this._endDate))
                                          .toString(),
                                      style: TextStyle(
                                        fontSize: 12,
                                        color: Colors.black,
                                      ),
                                    ))
                              ],
                            ),
                            Container(
                              padding: EdgeInsets.only(top: 0, bottom: 10),
                              child: LinearPercentIndicator(
                                lineHeight: 8.0,
                                percent: _progress(),
                                animation: true,
                                animationDuration: 200,
                                backgroundColor: Colors.grey[300],
                                progressColor: Colors.indigo[500],
                              ),
                            ),
                            Container(
                              padding: EdgeInsets.only(top: 15),
                              child: ListView.builder(
                                  shrinkWrap: true,
                                  physics: NeverScrollableScrollPhysics(),
                                  itemCount:
                                      this._subTasks.split("^").length - 1,
                                  itemBuilder: (BuildContext ctxt, int index) {
                                    var subTasks = _subTasks.split("^");

                                    var task = subTasks[index].split("|");
                                    if (task[0] != "")
                                      return Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: <Widget>[
                                          Wrap(
                                            children: <Widget>[
                                              Icon(Icons.arrow_right),
                                              Container(
                                                  width: MediaQuery.of(context)
                                                          .size
                                                          .width *
                                                      .75,
                                                  child: Text(
                                                    DateFormat("dd MMM")
                                                            .format(DateTime
                                                                .parse(task[
                                                                        1]
                                                                    .toString()))
                                                            .toString() +
                                                        " to " +
                                                        DateFormat("dd MMM")
                                                            .format(DateTime
                                                                .parse(task[
                                                                        2]
                                                                    .toString()))
                                                            .toString() +
                                                        " : " +
                                                        task[0].toString(),
                                                    style: TextStyle(
                                                        color: Colors.black),
                                                  )),
                                            ],
                                          ),
                                          if (notes.length > index &&
                                              notes[index].trim() != "")
                                            Container(
                                                alignment: Alignment.centerLeft,
                                                padding: EdgeInsets.all(5),
                                                child: Text(
                                                  notes[index],
                                                  style: TextStyle(
                                                      color: Colors.black,
                                                      fontWeight:
                                                          FontWeight.bold),
                                                ))
                                        ],
                                      );
                                  }),
                            ),
                          ],
                        )),
                  ),
                ]),
              ),
            )),
      ],
    );
  }
}

class TaskScreenClass extends StatefulWidget {
  final id;

  TaskScreenClass(this.id);

  @override
  TaskScreen createState() {
    return TaskScreen(this.id);
  }
}

class TaskScreen extends State<TaskScreenClass> {
  var id;

  TaskScreen(this.id);

  @override
  void initState() {
    super.initState();
    call();
  }

  var body;
  var tasks = [];

  call() async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    var prId = prefs.getString('project_id');

    if (prId != null) {
          var url = 'https://office.buildahome.in/API/get_all_tasks?project_id=$id&nt_toggle=0';

      print(url);
      var response = await http.get(Uri.parse(url));
      setState(() {
        body = jsonDecode(response.body);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListView(children: <Widget>[
      Container(
          padding: EdgeInsets.only(top: 20, left: 10, bottom: 10),
          decoration: BoxDecoration(
              border: Border(
            bottom: BorderSide(width: 6.0, color: Colors.indigo[900]!),
          )),
          child: Text("What's done and what's not?",
              style: TextStyle(
                fontSize: 20,
              ))),
      new ListView.builder(
          shrinkWrap: true,
          physics: BouncingScrollPhysics(),
          itemCount: body == null ? 0 : body.length,
          itemBuilder: (BuildContext ctxt, int index) {
            return Container(
              padding: EdgeInsets.only(bottom: 12, left: 5, right: 5, top: 5),
              child: TaskItem(
                  body[index]['task_name'].toString(),
                  body[index]['start_date'].toString(),
                  body[index]['end_date'].toString(),
                  body[index]['subTasks'].toString(),
                  body[index]['progress'].toString(),
                  body[index]['s_note'].toString()),
            );
          }),
    ]);
  }
}
