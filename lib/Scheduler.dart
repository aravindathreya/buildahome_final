import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'NavMenu.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:percent_indicator/linear_percent_indicator.dart';
import 'main.dart';
import 'package:flutter_spinkit/flutter_spinkit.dart';
import "UserHome.dart";
import "Payments.dart";
import "Gallery.dart";

class TaskWidget extends StatelessWidget {
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
        body: TaskScreenClass(),
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
  var _sub_tasks;
  var _progressStr;
  var note;

  TaskItem(this._Task_name, this._start_date, this._end_date, this._sub_tasks,
      this._progressStr, this.note);

  @override
  TaskItemWidget createState() {
    return TaskItemWidget(
        this._Task_name,
        this._icon,
        this._start_date,
        this._end_date,
        this._progressStr,
        this._color,
        this._height,
        this._sub_tasks,
        this.note);
  }
}

class TaskItemWidget extends State<TaskItem>
    with SingleTickerProviderStateMixin {
  String _Task_name;
  var _icon = Icons.home;
  var _start_date;
  var _end_date;
  var _color;
  var vis = false;
  var _sub_tasks;
  var _text_color = Colors.black;
  var _height = 50.0;
  var spr_radius = 1.0;
  var pad = 15.0;
  var _progressStr;
  var note;
  var notes;
  var view = Icons.expand_more;

  @override
  void initState() {
    super.initState();
    call();
  }

  call() {
    var total = this._sub_tasks.split("^");
    var done = (this._progressStr.split("|"));
    notes = this.note.split("|");
    if (((done.length - 1) / (total.length - 1)) > 0.9) {
      setState(() {
        this._text_color = Colors.green[600];
      });
    }
  }

  _progress() {
    print('${this._sub_tasks} Subtasks, ${_progressStr}');
    var total = this._sub_tasks.split("^");
    var done = (this._progressStr.split("|"));
    print((done.length - 1) / (total.length - 1));
    return ((done.length - 1) / (total.length - 1));
  }

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
      this._progressStr, this._color, this._height, this._sub_tasks, this.note);

  @override
  Widget build(BuildContext context) {
    return Column(
      children: <Widget>[
        Container(
            color: this._color,
            child: AnimatedContainer(
              duration: Duration(milliseconds: 500),
              decoration: BoxDecoration(
                color: Colors.grey[200],
                borderRadius: BorderRadius.circular(5),
              ),
              child: Container(
                decoration: BoxDecoration(
                  color: this._color,
                  border: Border(
                      bottom: BorderSide(width: 1, color: Colors.grey[300])),
                ),
                padding: EdgeInsets.symmetric(horizontal: 15, vertical: 20),
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
                                  this._text_color == Colors.green[600]
                                      ? this._Task_name + " (Completed)"
                                      : this._Task_name,
                                  textAlign: TextAlign.left,
                                  style: TextStyle(
                                      fontSize: 15,
                                      color: _text_color,
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
                                      this._start_date.trim() != ""
                                          ? DateFormat("dd MMM")
                                              .format(DateTime.parse(
                                                  this._start_date))
                                              .toString()
                                          : "",
                                      style: TextStyle(
                                        fontSize: 12,
                                        color: Colors.black,
                                      ),
                                    )),
                                Container(
                                    padding: EdgeInsets.only(right: 7, top: 10),
                                    child: Text(
                                      this._end_date.trim() != ''
                                          ? DateFormat("dd MMM")
                                              .format(DateTime.parse(
                                                  this._end_date))
                                              .toString()
                                          : "",
                                      style: TextStyle(
                                        fontSize: 12,
                                        color: Colors.black,
                                      ),
                                    ))
                              ],
                            ),
                            Container(
                              padding: EdgeInsets.only(top: 5, bottom: 10),
                              child: LinearPercentIndicator(
                                lineHeight: 8.0,
                                percent: _progress(),
                                animation: true,
                                animationDuration: 200,
                                backgroundColor: Colors.grey[300],
                                progressColor: Colors.indigo[800],
                                linearStrokeCap: LinearStrokeCap.butt,
                              ),
                            ),
                            Container(
                              padding: EdgeInsets.only(top: 5),
                              child: ListView.builder(
                                  shrinkWrap: true,
                                  physics: NeverScrollableScrollPhysics(),
                                  itemCount:
                                      this._sub_tasks.split("^").length - 1,
                                  itemBuilder: (BuildContext ctxt, int Index) {
                                    var sub_tasks = _sub_tasks.split("^");
                                    var each_task = sub_tasks[Index].split("|");
                                    if (each_task[0] != "")
                                      return Container(
                                          margin: EdgeInsets.only(top: 12),
                                          child: Column(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            children: <Widget>[
                                              Wrap(
                                                children: <Widget>[
                                                  Container(
                                                      padding: EdgeInsets.only(
                                                          left: 5),
                                                      width:
                                                          MediaQuery.of(context)
                                                                  .size
                                                                  .width *
                                                              .75,
                                                      child: Text(
                                                        DateFormat("dd MMM")
                                                                .format(DateTime
                                                                    .parse(each_task[
                                                                            1]
                                                                        .toString()))
                                                                .toString() +
                                                            " to " +
                                                            DateFormat("dd MMM")
                                                                .format(DateTime
                                                                    .parse(each_task[
                                                                            2]
                                                                        .toString()))
                                                                .toString() +
                                                            " : " +
                                                            each_task[0]
                                                                .toString(),
                                                        style: TextStyle(
                                                            color:
                                                                Colors.black),
                                                      )),
                                                ],
                                              ),
                                              if (notes.length > Index &&
                                                  notes[Index].trim() != "")
                                                Container(
                                                    alignment:
                                                        Alignment.centerLeft,
                                                    padding: EdgeInsets.all(5),
                                                    child: Text(
                                                      notes[Index],
                                                      style: TextStyle(
                                                        fontSize: 10,
                                                        color: Colors.grey[500],
                                                      ),
                                                    ))
                                            ],
                                          ));
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
  @override
  TaskScreen createState() {
    return TaskScreen();
  }
}

class TaskScreen extends State<TaskScreenClass> {
  @override
  void initState() {
    super.initState();
    call();
  }

  var body;
  var tasks = [];
  ScrollController _controller = new ScrollController();

  call() async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    var id = prefs.getString('project_id');

    var url =
        'https://app.buildahome.in/api/get_all_tasks.php?project_id=$id&nt_toggle=1 ';
    var response = await http.get(url);
    setState(() {
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
            bottom: BorderSide(width: 3.0, color: Colors.indigo[900]),
          )),
          child: Text("What's done and what's not?",
              style: TextStyle(
                fontSize: 20,
              ))),
      if (body == null)
        new ListView.builder(
            shrinkWrap: true,
            physics: BouncingScrollPhysics(),
            itemCount: 10,
            itemBuilder: (BuildContext ctxt, int Index) {
              return Row(
                mainAxisAlignment: MainAxisAlignment.start,
                children: [
                  Container(
                    width: MediaQuery.of(context).size.width,
                    alignment: Alignment.centerLeft,
                    padding: EdgeInsets.symmetric(horizontal: 15, vertical: 25),
                    decoration: BoxDecoration(
                        color: Colors.grey[200],
                        border: Border(
                            bottom: BorderSide(color: Colors.grey[300]))),
                  )
                ],
              );
            }),
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
                  body[Index]['sub_tasks'].toString(),
                  body[Index]['progress'].toString(),
                  body[Index]['s_note'].toString()),
            );
          }),
    ]);
  }
}
