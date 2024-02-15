import 'package:buildahome/NotesAndComments.dart';
import 'package:flutter/material.dart';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:percent_indicator/linear_percent_indicator.dart';
import 'main.dart';
import 'NavMenu.dart';
import 'UserHome.dart';
import 'Gallery.dart';
import 'AnimationHelper.dart';

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
        backgroundColor: Color.fromARGB(255, 233, 233, 233),
        drawer: NavMenuWidget(),
        appBar: AppBar(
          automaticallyImplyLeading: false,
          title: Text(
            appTitle,
            style: TextStyle(color: Color.fromARGB(255, 224, 224, 224), fontSize: 16),
          ),
          leading: new IconButton(
              icon: new Icon(Icons.menu),
              onPressed: () async {
                SharedPreferences prefs = await SharedPreferences.getInstance();
                var username = prefs.getString('username');
                _scaffoldKey.currentState!.openDrawer();
              }),
          backgroundColor: Color.fromARGB(255, 6, 10, 43),
        ),
        body: TaskScreenClass(),
      ),
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

    var url = 'https://office.buildahome.in/API/get_all_tasks?project_id=$id&nt_toggle=0';
    var response = await http.get(Uri.parse(url));
    setState(() {
      body = jsonDecode(response.body);
    });
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      height: MediaQuery.of(context).size.height,
      width: MediaQuery.of(context).size.width,
      child: Stack(
        alignment: Alignment.bottomCenter,
        children: [
          ListView(children: <Widget>[
            Container(
                padding: EdgeInsets.only(top: 20, left: 15, bottom: 20), decoration: BoxDecoration(), child: Text("Home construction Schedule", style: TextStyle(fontSize: 18, color: const Color.fromARGB(255, 0, 0, 0)))),
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
                  return AnimatedWidgetSlide(
                      direction: index % 2 == 0 ? SlideDirection.leftToRight : SlideDirection.rightToLeft, // Specify the slide direction
                      duration: Duration(milliseconds: 500), // Adjust the duration as needed

                      child: Container(
                        child: TaskItem(body[index]['task_name'].toString(), body[index]['start_date'].toString(), body[index]['end_date'].toString(), body[index]['sub_tasks'].toString(),
                            body[index]['progress'].toString(), body[index]['s_note'].toString()),
                      ));
                }),
          ]),
          Container(
              decoration: BoxDecoration(color: const Color.fromARGB(255, 223, 223, 223)),
              padding: EdgeInsets.only(top: 15, bottom: 1),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: [
                  InkWell(
                    onTap: () {
                      Navigator.push(
                          context,
                          PageRouteBuilder(
                            pageBuilder: (context, animation, secondaryAnimation) => Home(),
                            transitionsBuilder: (context, animation, secondaryAnimation, child) {
                              return SlideTransition(
                                position: Tween<Offset>(
                                  begin: const Offset(-1.0, 0.0),
                                  end: Offset.zero,
                                ).animate(animation),
                                child: child,
                              );
                            },
                          ),
                        );
                    },
                    child: Container(
                      height: 50,
                      child: Column(
                        children: [
                          Icon(
                            Icons.home_rounded,
                            size: 20,
                            color: Color.fromARGB(255, 100, 100, 100),
                          ),
                          Text(
                            'Home',
                            style: TextStyle(color: Color.fromARGB(255, 100, 100, 100), fontSize: 12),
                          )
                        ],
                      ),
                    ),
                  ),
                  Container(
                        height: 50,
                        child: Column(
                          children: [
                            Icon(
                              Icons.alarm,
                              size: 25,
                              color: const Color.fromARGB(255, 46, 46, 46),
                            ),
                            Text('Schedule', style: TextStyle(color: const Color.fromARGB(255, 46, 46, 46), fontSize: 12))
                          ],
                        ),
                      ),
                  InkWell(
                      onTap: () {
                        Navigator.push(
                          context,
                          PageRouteBuilder(
                            pageBuilder: (context, animation, secondaryAnimation) => Gallery(),
                            transitionsBuilder: (context, animation, secondaryAnimation, child) {
                              return SlideTransition(
                                position: Tween<Offset>(
                                  begin: const Offset(2.0, 0.0),
                                  end: Offset.zero,
                                ).animate(animation),
                                child: child,
                              );
                            },
                          ),
                        );
                      },
                      child: Container(
                        height: 50,
                        child: Column(
                          children: [
                            Icon(
                              Icons.photo_library,
                              size: 20,
                              color: Color.fromARGB(255, 100, 100, 100),
                            ),
                            Text(
                              'Gallery',
                              style: TextStyle(color: Color.fromARGB(255, 100, 100, 100), fontSize: 12),
                            )
                          ],
                        ),
                      )),
                  InkWell(
                      onTap: () {
                        Navigator.push(
                          context,
                          PageRouteBuilder(
                            pageBuilder: (context, animation, secondaryAnimation) => NotesAndComments(),
                            transitionsBuilder: (context, animation, secondaryAnimation, child) {
                              return SlideTransition(
                                position: Tween<Offset>(
                                  begin: const Offset(2.0, 0.0),
                                  end: Offset.zero,
                                ).animate(animation),
                                child: child,
                              );
                            },
                          ),
                        );
                      },
                      child: Container(
                        height: 50,
                        child: Column(
                          children: [
                            Icon(
                              Icons.update,
                              size: 20,
                              color: Color.fromARGB(255, 100, 100, 100),
                            ),
                            Text(
                              'Notes',
                              style: TextStyle(color: Color.fromARGB(255, 100, 100, 100), fontSize: 12),
                            )
                          ],
                        ),
                      )),
                ],
              )),
        ],
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
  final _color = Color.fromARGB(255, 255, 255, 255);
  final _subTasks;
  final _progressStr;
  final note;

  TaskItem(this._taskName, this._startDate, this._endDate, this._subTasks, this._progressStr, this.note);

  @override
  TaskItemWidget createState() {
    return TaskItemWidget(this._taskName, this._icon, this._startDate, this._endDate, this._progressStr, this._color, this._height, this._subTasks, this.note);
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

  TaskItemWidget(this._taskName, this._icon, this._startDate, this._endDate, this._progressStr, this._color, this._height, this._subTasks, this.note);

  @override
  Widget build(BuildContext context) {
    return Column(
      children: <Widget>[
        Container(
            child: AnimatedContainer(
          duration: Duration(milliseconds: 500),
          decoration: BoxDecoration(
            color: const Color.fromARGB(255, 233, 233, 233),
            borderRadius: BorderRadius.circular(5),
          ),
          child: Container(
            margin: EdgeInsets.only(left: 15, right: 15),
            decoration: BoxDecoration(color: this._color, border: Border(bottom: BorderSide(color: Color.fromARGB(255, 233, 233, 233), width: 2))),
            padding: EdgeInsets.symmetric(horizontal: 5, vertical: 5),
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
                          this._textColor == Colors.green[600]
                              ? Container(
                                  margin: EdgeInsets.all(10),
                                  padding: EdgeInsets.all(5),
                                  decoration: BoxDecoration(color: Color.fromARGB(255, 0, 153, 10), borderRadius: BorderRadius.circular(40)),
                                  child: Icon(
                                    Icons.check,
                                    size: 20,
                                    weight: 2.0,
                                    color: Colors.white!,
                                  ),
                                )
                              : Container(
                                  margin: EdgeInsets.all(10),
                                  padding: EdgeInsets.all(5),
                                  decoration: BoxDecoration(color: Colors.yellow[800], borderRadius: BorderRadius.circular(40)),
                                  child: Icon(
                                    Icons.schedule,
                                    size: 20,
                                    weight: 2.0,
                                    color: Colors.white!,
                                  ),
                                ),
                          Container(
                            width: MediaQuery.of(context).size.width * .7 - 20.0,
                            child: Text(
                              this._textColor == Colors.green[600] ? this._taskName + " (Completed)" : this._taskName,
                              textAlign: TextAlign.left,
                              style: TextStyle(fontSize: 14, fontWeight: FontWeight.normal, color: Color.fromARGB(255, 44, 44, 44)),
                            ),
                          ),
                          new Icon(view, color: const Color.fromARGB(255, 44, 44, 44)),
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
                    padding: EdgeInsets.only(left: 20, right: 20, bottom: 20),
                    child: Column(
                      children: <Widget>[
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: <Widget>[
                            Container(
                                padding: EdgeInsets.only(top: 10),
                                child: Text(
                                  this._startDate.trim() != "" ? DateFormat("dd MMM yy").format(DateTime.parse(this._startDate)).toString() : "",
                                  style: TextStyle(fontSize: 12, color: Color.fromARGB(255, 44, 44, 44)),
                                )),
                            Container(
                                padding: EdgeInsets.only(top: 10),
                                child: Text(
                                  this._endDate.trim() != '' ? DateFormat("dd MMM yy").format(DateTime.parse(this._endDate)).toString() : "",
                                  style: TextStyle(fontSize: 12, color: Color.fromARGB(255, 44, 44, 44)),
                                ))
                          ],
                        ),
                        Container(
                          padding: EdgeInsets.only(top: 5, bottom: 10),
                          child: LinearPercentIndicator(
                            lineHeight: 8.0,
                            percent: _progress(),
                            animationDuration: 500,
                            animation: true,
                            backgroundColor: Colors.grey[300],
                            progressColor: Color.fromARGB(255, 12, 148, 21),
                            clipLinearGradient: true,
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
                                              Icon(
                                                Icons.arrow_right_rounded,
                                                color: Color.fromARGB(255, 44, 44, 44),
                                              ),
                                              SizedBox(
                                                width: 5.0,
                                              ),
                                              Expanded(
                                                  child: Text(
                                                DateFormat("dd MMM yy").format(DateTime.parse(eachTask[1].toString())).toString() +
                                                    " to " +
                                                    DateFormat("dd MMM yy").format(DateTime.parse(eachTask[2].toString())).toString() +
                                                    " : " +
                                                    eachTask[0].toString(),
                                                style: TextStyle(color: Color.fromARGB(255, 44, 44, 44), fontSize: 14),
                                              )),
                                            ],
                                          ),
                                          if (notes.length > index && notes[index].trim() != "")
                                            Container(
                                                alignment: Alignment.centerLeft,
                                                padding: EdgeInsets.only(top: 3, left: 28),
                                                child: Text(
                                                  'buildAhome: ' + notes[index].trim(),
                                                  style: TextStyle(
                                                    fontSize: 12,
                                                    color: Color.fromARGB(255, 87, 87, 87),
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

enum SlideDirection { leftToRight, rightToLeft, topToBottom, bottomToTop }

class AnimatedWidgetSlide extends StatefulWidget {
  final Widget child;
  final SlideDirection direction;
  final Duration duration;

  AnimatedWidgetSlide({
    required this.child,
    required this.direction,
    required this.duration,
  });

  @override
  _AnimatedWidgetSlideState createState() => _AnimatedWidgetSlideState();
}

class _AnimatedWidgetSlideState extends State<AnimatedWidgetSlide> with SingleTickerProviderStateMixin {
  late AnimationController _animationController;
  late Animation<Offset> _slideAnimation;

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      vsync: this,
      duration: widget.duration,
    );

    switch (widget.direction) {
      case SlideDirection.leftToRight:
        _slideAnimation = Tween<Offset>(
          begin: const Offset(-1.0, 0.0),
          end: const Offset(0.0, 0.0),
        ).animate(CurvedAnimation(
          parent: _animationController,
          curve: Curves.easeIn,
        ));
        break;
      case SlideDirection.rightToLeft:
        _slideAnimation = Tween<Offset>(
          begin: const Offset(1.0, 0.0),
          end: const Offset(0.0, 0.0),
        ).animate(CurvedAnimation(
          parent: _animationController,
          curve: Curves.easeIn,
        ));
        break;
      case SlideDirection.topToBottom:
        _slideAnimation = Tween<Offset>(
          begin: const Offset(0.0, -1.0),
          end: const Offset(0.0, 0.0),
        ).animate(CurvedAnimation(
          parent: _animationController,
          curve: Curves.easeInOut,
        ));
        break;
      case SlideDirection.bottomToTop:
        _slideAnimation = Tween<Offset>(
          begin: const Offset(0.0, 1.0),
          end: const Offset(0.0, 0.0),
        ).animate(CurvedAnimation(
          parent: _animationController,
          curve: Curves.easeInOut,
        ));
        break;
    }

    _animationController.forward();
  }

  @override
  Widget build(BuildContext context) {
    return SlideTransition(
      position: _slideAnimation,
      child: widget.child,
    );
  }

  @override
  void dispose() {
    _animationController.dispose();
    super.dispose();
  }
}
