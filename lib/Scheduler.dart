import 'package:flutter/material.dart';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:percent_indicator/linear_percent_indicator.dart';
import 'main.dart';

class TaskWidget extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final appTitle = 'buildAhome';
    final GlobalKey<ScaffoldState> _scaffoldKey = new GlobalKey<ScaffoldState>();
    return MaterialApp(
      title: appTitle,
      theme: ThemeData(fontFamily: App().fontName),
      home: Scaffold(
        key: _scaffoldKey,
        body: TaskScreenClass(),
      ),
    );
  }
}

class TaskItem extends StatefulWidget {
  final String _taskName;
  final _icon = Icons.home;
  final _startDate;
  final _endDate;
  final _height = 0.0;
  final _color = Colors.white;
  final _subTasks;
  final _progressStr;
  final note;

  TaskItem(this._taskName, this._startDate, this._endDate, this._subTasks, this._progressStr, this.note);

  @override
  TaskItemWidget createState() {
    return TaskItemWidget(this._taskName, this._icon, this._startDate, this._endDate, this._progressStr, this._color,
        this._height, this._subTasks, this.note);
  }
}

class TaskItemWidget extends State<TaskItem> with SingleTickerProviderStateMixin {
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
    var total = this._subTasks.split("^");
    var done = (this._progressStr.split("|"));
    notes = this.note.split("|");
    if (((done.length - 1) / (total.length - 1)) > 0.9) {
      setState(() {
        this._textColor = Colors.green[600]!;
      });
    }
  }

  _progress() {
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

  TaskItemWidget(this._taskName, this._icon, this._startDate, this._endDate, this._progressStr, this._color,
      this._height, this._subTasks, this.note);

  @override
  Widget build(BuildContext context) {
    return Column(
      children: <Widget>[
        Container(
            child: AnimatedContainer(
              duration: Duration(milliseconds: 500),
              decoration: BoxDecoration(
                color: Colors.grey[200],
                borderRadius: BorderRadius.circular(5),
              ),
              child: Container(
                margin: EdgeInsets.only(top: 15, left: 15, right: 15),
                decoration: BoxDecoration(
                  color: this._color,
                  borderRadius: BorderRadius.circular(5),
                ),
                padding: EdgeInsets.symmetric(horizontal: 5, vertical: 20),
                child: Column(children: <Widget>[
                  AnimatedContainer(
                    duration: Duration(milliseconds: 900),
                    child: Row(
                      children: <Widget>[
                        InkWell(
                          onTap: _expandCollapse,
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: <Widget>[
                              this._textColor == Colors.green[600] ? Container(
                                margin: EdgeInsets.all(10),
                                padding: EdgeInsets.all(6),
                                decoration: BoxDecoration(
                                    color: Colors.green[900],
                                    borderRadius: BorderRadius.circular(40)
                                ),
                                child: Icon(Icons.check, size: 22, weight: 2.0, color: Colors.white!,),

                              ) : Container(
                                margin: EdgeInsets.all(10),
                                padding: EdgeInsets.all(6),
                                decoration: BoxDecoration(
                                    color: Colors.yellow[800],
                                    borderRadius: BorderRadius.circular(40)
                                ),
                                child: Icon(Icons.schedule, size: 22, weight: 2.0, color: Colors.white!,),

                              ),
                              Container(
                                width: MediaQuery.of(context).size.width * .7 - 30.0,
                                child: Text(
                                  this._textColor == Colors.green[600]
                                      ? this._taskName + " (Completed)"
                                      : this._taskName,
                                  textAlign: TextAlign.left,
                                  style: TextStyle( fontSize:  14, fontWeight: this.vis ? FontWeight.bold : FontWeight.normal),
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
                        padding: EdgeInsets.symmetric(horizontal: 20),
                        child: Column(
                          children: <Widget>[
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: <Widget>[
                                Container(
                                    padding: EdgeInsets.only(top: 10),
                                    child: Text(
                                      this._startDate.trim() != ""
                                          ? DateFormat("dd MMM yy").format(DateTime.parse(this._startDate)).toString()
                                          : "",
                                      style: TextStyle(
                                        fontSize: 12,
                                        color: Colors.black,
                                      ),
                                    )),
                                Container(
                                    padding: EdgeInsets.only(top: 10),
                                    child: Text(
                                      this._endDate.trim() != ''
                                          ? DateFormat("dd MMM yy").format(DateTime.parse(this._endDate)).toString()
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
                                animationDuration: 200,
                                backgroundColor: Colors.grey[300],
                                progressColor: Colors.indigo[800],
                              ),
                            ),
                            Container(
                              padding: EdgeInsets.only(top: 5),
                              child: ListView.builder(
                                  shrinkWrap: true,
                                  physics: NeverScrollableScrollPhysics(),
                                  itemCount: this._subTasks.split("^").length - 1,
                                  itemBuilder: (BuildContext ctxt, int index) {
                                    var subTasks = _subTasks.split("^");
                                    var eachTask = subTasks[index].split("|");
                                    if (eachTask[0] != "")
                                      return Container(
                                          margin: EdgeInsets.only(top: 15),
                                          child: Column(
                                            crossAxisAlignment: CrossAxisAlignment.start,
                                            children: <Widget>[
                                              Row(
                                                children: <Widget>[
                                                  Icon(Icons.arrow_right_rounded),
                                                  SizedBox(width: 5.0,),
                                                  Expanded(
                                                      child: Text(
                                                        DateFormat("dd MMM yy")
                                                            .format(DateTime.parse(eachTask[1].toString()))
                                                            .toString() +
                                                            " to " +
                                                            DateFormat("dd MMM yy")
                                                                .format(DateTime.parse(eachTask[2].toString()))
                                                                .toString() +
                                                            " : " +
                                                            eachTask[0].toString(),
                                                        style: TextStyle(color: Colors.black54, fontSize: 14),
                                                      )),
                                                ],
                                              ),
                                              if (notes.length > index && notes[index].trim() != "")
                                                Container(
                                                    alignment: Alignment.centerLeft,
                                                    padding: EdgeInsets.only(top: 3, left: 28),
                                                    child: Text(
                                                      notes[index].trim(),
                                                      style: TextStyle(
                                                        fontSize: 10,
                                                        color: Colors.grey[500],
                                                      ),
                                                    ))
                                            ],
                                          ));
                                    return null;
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

  call() async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    var id = prefs.getString('project_id');

    var url = 'https://app.buildahome.in/api/get_all_tasks.php?project_id=$id&nt_toggle=1 ';
    var response = await http.get(Uri.parse(url));
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
            bottom: BorderSide(width: 3.0, color: Colors.indigo[900]!),
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
            itemBuilder: (BuildContext ctxt, int index) {
              return Row(
                mainAxisAlignment: MainAxisAlignment.start,
                children: [
                  Container(
                    width: MediaQuery.of(context).size.width,
                    alignment: Alignment.centerLeft,
                    padding: EdgeInsets.symmetric(horizontal: 15, vertical: 25),
                    decoration: BoxDecoration(
                        color: Colors.grey[200], border: Border(bottom: BorderSide(color: Colors.grey[300]!))),
                  )
                ],
              );
            }),
      new ListView.builder(
         padding: EdgeInsets.only(bottom: 100),
          shrinkWrap: true,
          physics: BouncingScrollPhysics(),
          itemCount: body == null ? 0 : body.length,
          itemBuilder: (BuildContext ctxt, int index) {
            return Container(
              child: TaskItem(
                  body[index]['task_name'].toString(),
                  body[index]['start_date'].toString(),
                  body[index]['end_date'].toString(),
                  body[index]['sub_tasks'].toString(),
                  body[index]['progress'].toString(),
                  body[index]['s_note'].toString()),
            );
          }),
    ]);
  }
}
