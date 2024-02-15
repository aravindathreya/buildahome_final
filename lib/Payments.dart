import 'package:flutter/material.dart';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'NavMenu.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'main.dart';
import "UserHome.dart";
import "Scheduler.dart";
import "Gallery.dart";
import 'AnimationHelper.dart';

class PaymentTaskWidget extends StatelessWidget {
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
          automaticallyImplyLeading: true,
          title: Text(
            appTitle,
            style: TextStyle(color: Color.fromARGB(255, 224, 224, 224), fontSize: 16),
          ),
          leading: new IconButton(
              icon: new Icon(Icons.chevron_left),
              onPressed: () async {
                Navigator.pop(context);
              }),
          backgroundColor: Color.fromARGB(255, 6, 10, 43),
        ),
        body: PaymentTasksClass(),
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
  final _paymentPercentage;
  final status;
  final note;
  final projectValue;

  TaskItem(this._taskName, this._startDate, this._endDate, this._paymentPercentage, this.status, this.note, this.projectValue);

  @override
  TaskItemWidget createState() {
    return TaskItemWidget(this._taskName, this._icon, this._startDate, this._endDate, this._color, this._height, this._paymentPercentage, this.status, this.note, this.projectValue);
  }
}

class TaskItemWidget extends State<TaskItem> with SingleTickerProviderStateMixin {
  String _taskName;
  var _icon = Icons.home;
  var _startDate;
  var _endDate;
  var _color;
  var vis = false;
  var _paymentPercentage;
  var _textColor = Colors.black;
  var _height = 50.0;
  var sprRadius = 1.0;
  var pad = 10.0;
  var valueStr;
  var value = 0;
  var status;
  var amt;
  var note;
  var gradient;
  var projectValue;

  @override
  void initState() {
    super.initState();
    _setValue();
    _progress();
  }

  _setValue() async {
    if(this._paymentPercentage.toString().trim() == '') {
      this._paymentPercentage = '0';
    }
    setState(() {
      amt = ((int.parse(this._paymentPercentage)) / 100) * int.parse(this.projectValue);
    });
  }

  _progress() {
    if (this.status == 'not due') {
      this._color = Colors.white;
      this._textColor = Colors.black;
      this.gradient = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        stops: [0.1, 0.9],
        colors: [
          Colors.white,
          Colors.white,
        ],
      );
    } else if (this.status == 'paid') {
      this._color = Colors.green;
      this._textColor = Colors.white;
      this.gradient = LinearGradient(
        // Where the linear gradient begins and ends
        begin: Alignment.centerLeft,
        end: Alignment.centerRight,

        // Add one stop for each color. Stops should increase from 0 to 1
        stops: [0.3, 0.7],
        colors: [
          // Colors are easy thanks to Flutter's Colors class.

          Color(0xff009900),
          Color(0xff33cc00),
        ],
      );
    } else {
      this._color = Colors.deepOrange;
      this._textColor = Colors.white;
      this.gradient = LinearGradient(
        // Where the linear gradient begins and ends
        begin: Alignment.centerLeft,
        end: Alignment.centerRight,

        // Add one stop for each color. Stops should increase from 0 to 1
        stops: [0.3, 0.7],
        colors: [
          // Colors are easy thanks to Flutter's Colors class.

          Color(0xFF7b0909),
          Color(0xFFd51010),
        ],
      );
    }
  }

  var view = Icons.expand_more;

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

  TaskItemWidget(this._taskName, this._icon, this._startDate, this._endDate, this._color, this._height, this._paymentPercentage, this.status, this.note, this.projectValue);

  @override
  Widget build(BuildContext context) {
    return Column(
      children: <Widget>[
        Container(
            margin: EdgeInsets.only(left: 20, top: 15, right: 20),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(5),
              color: Colors.white,
            ),
            child: AnimatedContainer(
              duration: Duration(milliseconds: 500),
              decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(5), color: Color.fromARGB(255, 199, 199, 199), gradient: LinearGradient(colors: [Color.fromARGB(255, 167, 166, 166), Color.fromARGB(255, 221, 221, 221)])),
              padding: EdgeInsets.all(this.pad),
              child: Container(
                child: Column(children: <Widget>[
                  AnimatedContainer(
                    duration: Duration(milliseconds: 900),
                    padding: EdgeInsets.only(left: 7),
                    child: Row(
                      children: <Widget>[
                        if (this._color == Colors.green)
                          Container(
                            height: 45,
                            width: 45,
                            alignment: Alignment.center,
                            decoration: BoxDecoration(color: Colors.green[900], borderRadius: BorderRadius.circular(50)),
                            child: Text(
                              'PAID',
                              style: TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold),
                            ),
                          ),
                        if (this._color == Colors.white)
                          Container(
                            height: 45,
                            width: 45,
                            alignment: Alignment.center,
                            decoration: BoxDecoration(color: Colors.yellow[700], borderRadius: BorderRadius.circular(50)),
                            child: Text(
                              'WIP',
                              style: TextStyle(color: const Color.fromARGB(255, 0, 0, 0), fontSize: 10, fontWeight: FontWeight.bold),
                            ),
                          ),
                        if (this._color == Colors.deepOrange)
                          Container(
                            height: 45,
                            width: 45,
                            alignment: Alignment.center,
                            decoration: BoxDecoration(color: Colors.red[700], borderRadius: BorderRadius.circular(50)),
                            child: Text(
                              'DUE',
                              style: TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold),
                            ),
                          ),
                        SizedBox(
                          width: 15,
                        ),
                        InkWell(
                          onTap: _expandCollapse,
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: <Widget>[
                              Container(
                                width: MediaQuery.of(context).size.width * .6 - 7,
                                child: Text(
                                  this._taskName,
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
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          Container(
                              padding: EdgeInsets.all(10),
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: <Widget>[
                                  Text(
                                    this._paymentPercentage + "%     ₹ " + ((amt != null) ? amt.toStringAsFixed(2) : ''),
                                    style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Color.fromARGB(255, 44, 44, 44)),
                                  )
                                ],
                              )),
                          if (this.note.trim() != '')
                            Container(
                                padding: EdgeInsets.all(10),
                                child: Text(
                                  this.note.trim(),
                                  style: TextStyle(color: Color.fromARGB(255, 44, 44, 44)),
                                ))
                        ],
                      )),
                ]),
              ),
            )),
      ],
    );
  }
}

class PaymentTasksClass extends StatefulWidget {
  @override
  PaymentTasks createState() {
    return PaymentTasks();
  }
}

class PaymentTasks extends State<PaymentTasksClass> {
  var body;
  var tasks = [];
  var projectValue = "";
  var outstanding = "";
  var totalPaid = "";

  @override
  void initState() {
    super.initState();
    call();
    print('call');
  }

  call() async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    var id = prefs.getString('project_id');
    var url = 'https://office.buildahome.in/API/get_all_tasks?project_id=$id&nt_toggle=1 ';
    var response = await http.get(Uri.parse(url));
    body = jsonDecode(response.body);

    var url1 = 'https://office.buildahome.in/API/get_payment?project_id=$id';
    var response1 = await http.get(Uri.parse(url1));
    var details = jsonDecode(response1.body);
    outstanding = details[0]['outstanding'];
    totalPaid = double.parse(details[0]['total_paid'].toString().trim()).toString();
    projectValue = details[0]['value'];

    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        Opacity(
          opacity: 0.3,
          child: Container(
            width: MediaQuery.of(context).size.width,
            height: MediaQuery.of(context).size.height,
            decoration: BoxDecoration(
                color: Color.fromARGB(255, 214, 214, 214),
                border: Border.all(width: 1, color: Colors.grey[200]!),
                borderRadius: BorderRadius.circular(10),
                ),
            
            child: Image.network("https://images.unsplash.com/photo-1502005097973-6a7082348e28?w=500&auto=format&fit=crop&q=60&ixlib=rb-4.0.3&ixid=M3wxMjA3fDB8MHxzZWFyY2h8MzV8fEhvdXNlfGVufDB8fDB8fHww", fit: BoxFit.fill),
          ),
        ),
        Padding(
          padding: EdgeInsets.only(bottom: 1),
          child: ListView(children: <Widget>[
            Container(margin: EdgeInsets.only(top: 20, left: 20, bottom: 10), child: Text("Project Payments", style: TextStyle(fontSize: 16, color: const Color.fromARGB(255, 37, 37, 37)))),
            AnimatedWidgetSlide(
                direction: SlideDirection.leftToRight, // Specify the slide direction
                duration: Duration(milliseconds: 300),
                child: Container(
                  height: 2,
                  color: const Color.fromARGB(255, 34, 34, 34),
                  width: 100,
                  margin: EdgeInsets.only(left: 20, right: 250),
                )),
            Container(
              margin: EdgeInsets.symmetric(vertical: 20, horizontal: 10),
              padding: EdgeInsets.all(10),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(5),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Container(
                    width: 150,
                    margin: EdgeInsets.symmetric(vertical: 5),
                    padding: EdgeInsets.all(10),
                    decoration: BoxDecoration(color: Color.fromARGB(255, 240, 255, 242), borderRadius: BorderRadius.circular(6)),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(child: Text("Project Value", style: TextStyle(fontSize: 10))),
                        Container(margin: EdgeInsets.only(top: 5), child: Text("₹ " + projectValue, style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold))),
                      ],
                    ),
                  ),
                  Container(
                    width: 150,
                    margin: EdgeInsets.symmetric(vertical: 5),
                    padding: EdgeInsets.all(10),
                    decoration: BoxDecoration(color: Color.fromARGB(255, 255, 237, 237), borderRadius: BorderRadius.circular(6)),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(
                            child: Text("Paid till date",
                                style: TextStyle(
                                  fontSize: 10,
                                ))),
                        Container(margin: EdgeInsets.only(top: 5), child: Text("₹ " + totalPaid, style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.green[700]))),
                      ],
                    ),
                  ),
                  Container(
                    width: 150,
                    margin: EdgeInsets.symmetric(vertical: 5),
                    padding: EdgeInsets.all(10),
                    decoration: BoxDecoration(color: Color.fromARGB(255, 246, 248, 225), borderRadius: BorderRadius.circular(6)),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(
                            child: Text("Current Outstanding",
                                style: TextStyle(
                                  fontSize: 10,
                                ))),
                        Container(margin: EdgeInsets.only(top: 5), child: Text("₹ " + outstanding, style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.red[500]))),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            new ListView.builder(
                shrinkWrap: true,
                physics: BouncingScrollPhysics(),
                itemCount: body == null ? 0 : body.length,
                itemBuilder: (BuildContext ctxt, int index) {
                  return AnimatedWidgetSlide(
                      direction: index % 2 == 0 ? SlideDirection.leftToRight : SlideDirection.rightToLeft, // Specify the slide direction
                      duration: Duration(milliseconds: 300),
                      child: Container(
                        child: TaskItem(body[index]['task_name'].toString(), body[index]['start_date'].toString(), body[index]['end_date'].toString(), body[index]['payment'].toString(), body[index]['paid'].toString(),
                            body[index]['p_note'].toString(), projectValue),
                      ));
                }),
          ]),
        )
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
          curve: Curves.easeInSine,
        ));
        break;
      case SlideDirection.rightToLeft:
        _slideAnimation = Tween<Offset>(
          begin: const Offset(1.0, 0.0),
          end: const Offset(0.0, 0.0),
        ).animate(CurvedAnimation(
          parent: _animationController,
          curve: Curves.easeInOut,
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
