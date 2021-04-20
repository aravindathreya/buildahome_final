import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'NavMenu.dart';
import "ShowAlert.dart";
import 'clients.dart';
import 'package:intl/intl.dart';

class AddProject extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final appTitle = 'BuildAhome';
    final GlobalKey<ScaffoldState> _scaffoldKey =
    new GlobalKey<ScaffoldState>();
    return MaterialApp(
      title: appTitle,
      theme: ThemeData(fontFamily: 'Varela'),
      home: Scaffold(
        key: _scaffoldKey, // ADD THIS LINE
        appBar: AppBar(
          automaticallyImplyLeading: false,
          title: Text(appTitle),
          leading: new IconButton(
              icon: new Icon(Icons.menu),
              onPressed: () => _scaffoldKey.currentState.openDrawer()),
          backgroundColor: Colors.indigo[900],
        ),

        drawer: NavMenuWidget(),
        body: AddProjectForm(),
      ),
    );
  }
}

class AddProjectForm extends StatefulWidget {
  @override
  AddProjectState createState() {
    return AddProjectState();
  }
}

class TaskBlock extends StatefulWidget {
  var task_name = new TextEditingController();
  var task_start_date;
  var task_finish_date;
  //TaskBlock(this.task_name, this.task_start_date, this.task_finish_date);

  @override
  TaskBlockState createState() {
    return TaskBlockState(this.task_name, this.task_start_date, this.task_finish_date);
  }
}
var tasks=[];
var starts=[];
var ends=[];

class TaskBlockState extends State<TaskBlock> with SingleTickerProviderStateMixin{

  AnimationController _controller;
  Animation animation;


  @override
  void initState(){
    super.initState();
    this.task_finish_date = 'Finish date';
    this.task_start_date = 'Start date';
    tasks.clear();
    starts.clear();
    ends.clear();

    _controller = new AnimationController(
      duration: const Duration(milliseconds: 100),
      vsync: this,


    );
    _controller.addListener((){
      setState((){
      });
    });

    _controller.forward();

    Tween _tween = new Tween(
        begin: 0.0,
        end: 1.0,
    );

    animation = _tween.animate(_controller);
  }

  var task_name;
  var task_start_date;
  var task_finish_date;

  var actual_start = new TextEditingController();
  var actual_end = new TextEditingController();

  TaskBlockState(this.task_name, this.task_start_date, this.task_finish_date);
  @override

  Future _select_start_date() async {
    DateTime picked = await showDatePicker(
        context: context,
        initialDate: new DateTime.now(),
        firstDate: new DateTime(2016),
        lastDate: new DateTime(2030));
    setState(() {
      if (picked != null) {
        this.task_start_date = new DateFormat('dd/MM/y')
            .format(picked)
            .toString();
        this.actual_start.text = new DateFormat('EE MM dd')
            .format(picked)
            .toString();
      }
    });
  }

  Future _select_finish_date() async {
    DateTime picked = await showDatePicker(
        context: context,
        initialDate: new DateTime.now(),
        firstDate: new DateTime(2016),
        lastDate: new DateTime(2030));
    setState(() {
      if (picked != null) {
        this.task_finish_date =new DateFormat('dd/MM/y')
            .format(picked)
            .toString();
        this.actual_end.text = new DateFormat('EEEE MMMM dd')
            .format(picked)
            .toString();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    if(tasks.contains(this.task_name)==false){
      tasks.add(this.task_name);
      starts.add(this.actual_start);
      ends.add(this.actual_end);
    }

    return Container
      (
      padding: EdgeInsets.only(top: 20),
      child: AnimatedContainer(
          duration: Duration(milliseconds: 100 ),
          height: animation.value * 140,
          padding: EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: Colors.white,
            border: Border.all(width: 1.0, color: Colors.black),
            borderRadius: BorderRadius.all(Radius.circular(5)),
              boxShadow: [
                new BoxShadow(
                  color: Colors.grey[500],
                  blurRadius: 15,
                  spreadRadius: 2,

                )
              ],
          ),
          child: Opacity(
            opacity: animation.value,
            child: Column(
              children: <Widget>[

                Container(
                    padding: const EdgeInsets.all(10),
                    child: TextFormField(
                      controller: task_name,
                      decoration: InputDecoration(
                        border: OutlineInputBorder(
                          borderSide: BorderSide(
                              color: Colors.greenAccent, width: 15.0),
                        ),
                        labelText: "Task name",
                        labelStyle: TextStyle(
                          fontSize: 18,
                        ),
                        contentPadding: EdgeInsets.all(12),

                      ),
                      validator: (value) {
                        if (value.isEmpty) {
                          return 'This field cannot be empty';
                        }
                        return null;
                      },
                    )),
                Row(
                  children: <Widget>[
                    Visibility(
                      child: Row(
                          mainAxisAlignment: MainAxisAlignment.start,
                          children: <Widget>[
                            FlatButton(
                              padding: const EdgeInsets.all(10),
                              child: Container(


                                child: Row(
                                  children: <Widget>[
                                    Icon(Icons.calendar_today, size: 20, color: Colors.indigo[900]),
                                    Container(
                                      decoration: BoxDecoration(
                                          border: Border(
                                            bottom: BorderSide(width: 0.8, color: Colors.black),
                                          )),
//                                width: MediaQuery
//                                    .of(context)
//                                    .size
//                                    .width * .68,
                                      padding: EdgeInsets.only(left: 5  ),
                                      child: Text(this.task_start_date,
                                          style: TextStyle(
                                              fontSize: 16,
                                              fontWeight: FontWeight.normal,
                                              color: Colors.black54)),
                                    ),
                                  ],
                                ),
                              ),
                              onPressed: _select_start_date,
                            ),
                          ]),
                    ),
                    Visibility(
                      child: Row(

                          mainAxisAlignment: MainAxisAlignment.start,
                          children: <Widget>[
                            FlatButton(
                              padding: const EdgeInsets.only(left:20, top:10, bottom: 10,),

                              child: Container(
                                child: Row(
                                  children: <Widget>[
                                    Icon(Icons.calendar_today, size: 20, color: Colors.indigo[900]),
                                    Container(
                                      decoration: BoxDecoration(
                                          border: Border(
                                            bottom: BorderSide(width: 0.8, color: Colors.black),
                                          )),
//                                width: MediaQuery
//                                    .of(context)
//                                    .size
//                                    .width * .68,
                                      padding: EdgeInsets.only(left: 5  ),
                                      child: Text(this.task_finish_date,
                                          style: TextStyle(
                                              fontSize: 16,
                                              fontWeight: FontWeight.normal,
                                              color: Colors.black54)),
                                    ),
                                  ],
                                ),
                              ),
                              onPressed: _select_finish_date,
                            ),
                          ]),
                    ),
                  ],
                ),

              ],
            )
          )



      )
    );

  }
}

class AddProjectState extends State<AddProjectForm> {
  final _formKey = GlobalKey<FormState>();
  final projectname = TextEditingController();
  final projectlocation = TextEditingController();
  final clientname = TextEditingController();
  final clientphone = TextEditingController();
  final projectincharge = TextEditingController();
  final projectinchargephone = TextEditingController();
  int task_count = 1;
  var client_name = "Choose client";
  var projects =[];
  call() async {
    var url = 'https://app.buildahome.in/api/view_all_projects.php';
    var response = await http.get(url);
    print(response.body);
    setState(() {
      projects = jsonDecode(response.body);
    });
  }

  void initState(){
    super.initState();
    call();
  }
  String _date = "Select Project start date";
  String _responsetext = "";
  bool _vis = false;

  Future _selectDate() async {
    DateTime picked = await showDatePicker(
        context: context,
        initialDate: new DateTime.now(),
        firstDate: new DateTime(2016),
        lastDate: new DateTime(2030));
    setState(() {
      if (picked != null) {
        _date = picked.toString().substring(0, 10);
      }
    });
  }

  void set_response_text(String response) async {
    setState(() {
      _vis = true;
      _responsetext = response;
    });
  }


  void submit_form() async{

    if (_formKey.currentState.validate()) {
      showDialog(
          context: context,
          builder: (BuildContext context) {
            return ShowAlert(
                "Hang in there. Uploading details for this project", true);
          });

      var tasks_list = [];
        for(var i=0;i<tasks.length;i++){
          var  task = tasks[i].text.toString() + "|" +starts[i].text.toString()+ "|" +ends[i].text.toString();
          if(tasks_list.contains(task)==false)
            tasks_list.add(task);
        }
        print(tasks_list);
        print(clientphone.text);
        print(clientname.text);

        var url = 'https://app.buildahome.in/api/add_new_project.php';
        var response = await http.post(url, body: {
          'tasks' : jsonEncode(tasks_list),
          'project_name': projectname.text,
          'project_location': projectlocation.text,
          'client_name': client_name,
          'client_phone': clientphone.text,
          'project_incharge': projectincharge.text,
//          'pr_incharge_phone': projectinchargephone.text,
//          'project_start_date': _date,
        });
        print('Response status: ${response.statusCode}');
        print('Response body: ${response.body}');
      Navigator.of(context, rootNavigator: true)
          .pop('dialog');
      showDialog(
          context: context,
          builder: (BuildContext context) {
            return ShowAlert(
                "Project created", false);
          });
//        set_response_text(response.body.toString());
      }
  }

  AnimationController task_controller;
  Animation<Offset> offset;


  @override
  Widget build(BuildContext context) {
    return PageView(
      children: <Widget>[
        ListView(

          scrollDirection: Axis.vertical,
          padding: EdgeInsets.all(10),
          children: <Widget>[
            Container(
                padding: EdgeInsets.only(top: 20, bottom: 10, left: 5, right: 5),
                decoration: BoxDecoration(
                    border: Border(
                      bottom: BorderSide(width:2.0, color: Colors.indigo[900]),
                    )
                ),
                child: Text("All projects", style: TextStyle(fontSize: 20,))

            ),
            ListView.builder(
              shrinkWrap: true,
              physics: new BouncingScrollPhysics(),
              scrollDirection: Axis.vertical,
              itemCount: projects.length,
              itemBuilder: (BuildContext ctxt, int Index) {
                return Container(
                    padding: EdgeInsets.only(top: 20, left: 5, right: 5),

                    child: Container(
                        decoration: BoxDecoration(
                          color: Colors.white,
                          border: Border.all(width: 1.0, color: Colors.black),
                          borderRadius: BorderRadius.all(Radius.circular(5)),
                          boxShadow: [
                            new BoxShadow(
                              color: Colors.grey[500],
                              blurRadius: 15,
                              spreadRadius: 2,

                            )
                          ],
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: <Widget>[
                            Container(
                                padding: EdgeInsets.all(10),
                                child: Text(projects[Index]['name'], style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold))
                            ),
                            Container(
                                padding: EdgeInsets.only(top: 5, left: 10),
                                child: Text("Client: "+ projects[Index]['client'], style: TextStyle(fontSize: 14))
                            ),
                            Container(
                                padding: EdgeInsets.only(top: 5, left: 10),
                                child: Text("Client contact: "+projects[Index]['client_phone'], style: TextStyle(fontSize: 14))
                            ),
                            Container(
                                padding: EdgeInsets.all(10),
                                child: Text("Project in-charge: "+projects[Index]['incharge'], style: TextStyle(fontSize: 14))
                            ),

                          ],
                        )
                    )
                );
              },)
          ],
        ),
        Form(
          key: _formKey,
          child: ListView(
            children: <Widget>[
              Container(
                padding: const EdgeInsets.only(top: 30, left:20, right:20, bottom: 10),
                child: Text(
                  'Add a new project',
                  style: TextStyle(fontSize: 20, color: Colors.black),
                ),
              ),
              Container(
                  padding: EdgeInsets.only(left: 20, right: 20),
                  child: Container(
                    decoration: BoxDecoration(
                        border: Border.all(color: Colors.black)
                    ),
                  )
              ),
              Container(
                  padding: const EdgeInsets.only(top: 20, left: 20, right: 20),
                  child: TextFormField(
                    style: TextStyle(fontSize: 18),
                    controller: projectname,
                    decoration: InputDecoration(
                      border: OutlineInputBorder(
                        borderSide:
                        BorderSide(color: Colors.greenAccent, width: 5.0),
                      ),
                      labelText: "Project Name",
                      hintText: "Project Name",
                      hasFloatingPlaceholder: false,
                      contentPadding: EdgeInsets.all(12),
                      labelStyle: TextStyle(
                        fontSize: 16,
                      ),
                    ),
                    validator: (value) {
                      if (value.isEmpty) {
                        return 'This field cannot be empty';
                      }
                      return null;
                    },
                  )),
              Container(
                  padding: const EdgeInsets.only(top: 20, left: 20, right: 20),
                  child: TextFormField(
                    style: TextStyle(fontSize: 18),
                    controller: projectlocation,
                    decoration: InputDecoration(
                      border: OutlineInputBorder(
                        borderSide:
                        BorderSide(color: Colors.greenAccent, width: 5.0),
                      ),
                      contentPadding: EdgeInsets.all(12),
                      labelText: "Project Location",
                      hintText: "Project Location",
                      hasFloatingPlaceholder: false,
                      labelStyle: TextStyle(
                        fontSize: 16,
                      ),
                    ),
                    validator: (value) {
                      if (value.isEmpty) {
                        return 'This field cannot be empty';
                      }
                      return null;
                    },
                  )),
              Container(
                  padding: const EdgeInsets.only(top: 20, left: 20, right: 20),
                  child: TextFormField(
                    style: TextStyle(fontSize: 18),
                    controller: projectincharge,
                    decoration: InputDecoration(
                      border: OutlineInputBorder(
                        borderSide:
                        BorderSide(color: Colors.greenAccent, width: 5.0),
                      ),
                      contentPadding: EdgeInsets.all(12),
                      labelText: "Project Incharge",
                      hintText: "Project Incharge",
                      hasFloatingPlaceholder: false,
                      labelStyle: TextStyle(
                        fontSize: 16,
                      ),
                    ),
                    validator: (value) {
                      if (value.isEmpty) {
                        return 'This field cannot be empty';
                      }
                      return null;
                    },
                  )),
              Visibility(
                child: Row(
                    mainAxisAlignment: MainAxisAlignment.start,
                    children: <Widget>[
                      FlatButton(
                        padding:
                        const EdgeInsets.only(top: 20, left: 20, right: 20),
                        child: Container(
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            border: Border.all(),
                          ),
                          child: Row(
                            children: <Widget>[
                              Icon(Icons.calendar_today, color: Colors.indigo[900]),
                              Container(
//                            width: MediaQuery
//                                .of(context)
//                                .size
//                                .width * .79,
                                padding: EdgeInsets.only(left: 20),
                                child: Text(_date,
                                    style: TextStyle(
                                        fontSize: 16,
                                        fontWeight: FontWeight.normal,
                                        color: Colors.black54)),
                              ),
                            ],
                          ),
                        ),
                        onPressed: _selectDate,
                      ),
                    ]),
              ),
              Container(
                padding: const EdgeInsets.only(top: 30, left:20, right:20, bottom: 10),
                child: Text(
                  'Client Information',
                  style: TextStyle(fontSize: 20, color: Colors.black),
                ),
              ),
              Container(
                  padding: EdgeInsets.only(left: 20, right: 20),
                  child: Container(
                    decoration: BoxDecoration(
                        border: Border.all(color: Colors.black)
                    ),
                  )
              ),
              Container(
                padding: EdgeInsets.only(left: 20, right: 20, top: 20),
                child: InkWell(
                  onTap: () async {

                    var a = await showDialog(
                        context: context,
                        builder: (BuildContext context) {
                          return clientsModal();
                        });
                    if(a!=null) {
                      setState(() {
                        client_name = a;
                      });
                      print(a);
                    }
                  },
                  child:Container(
                      decoration: BoxDecoration(
                        color: Colors.white,
                        border: Border.all(width: 1.0, color: Colors.black),
                        borderRadius: BorderRadius.all(Radius.circular(5)),

                      ),  padding: EdgeInsets.all(10),
                      child: Row(
                        children: <Widget>[
                          Container(
                            decoration: BoxDecoration(
                                borderRadius: BorderRadius.all(Radius.circular(50)),
                                color: Colors.white
                            ),
                            child: Icon(Icons.view_list, size: 25, color: Colors.indigo[900]),
                          ),
                          Container(
                              padding: EdgeInsets.only(left: 10),
                              child: Text(client_name,
                                  style: TextStyle(fontSize: 18)))
                        ],
                      )),
                ),
              ),

//          Container(
//              padding: const EdgeInsets.only(top: 20, left: 20, right: 20),
//              child: TextFormField(
//                controller: projectincharge,
//                decoration: InputDecoration(
//                  border: OutlineInputBorder(
//                    borderSide:
//                    BorderSide(color: Colors.greenAccent, width: 5.0),
//                  ),
//                  labelText: "Project incharge ",
//                  labelStyle: TextStyle(
//                    fontSize: 20,
//                  ),
//                ),
//                validator: (value) {
//                  if (value.isEmpty) {
//                    return 'This field cannot be empty';
//                  }
//                  return null;
//                },
//              )),
//          Container(
//              padding: const EdgeInsets.only(
//                  top: 20, left: 20, right: 20, bottom: 20),
//              child: TextFormField(
//                controller: projectinchargephone,
//                decoration: InputDecoration(
//                  border: OutlineInputBorder(
//                    borderSide:
//                    BorderSide(color: Colors.greenAccent, width: 5.0),
//                  ),
//                  labelText: "Project incharge Phone ",
//                  labelStyle: TextStyle(
//                    fontSize: 20,
//                  ),
//                ),
//                keyboardType: TextInputType.number,
//                validator: (value) {
//                  if (value.isEmpty) {
//                    return 'This field cannot be empty';
//                  }
//                  return null;
//                },
//              )),
              Visibility(
                  visible: _vis,
                  child: Container(
                      padding: const EdgeInsets.only(
                          top: 20, left: 20, right: 20, bottom: 20),
                      child: (Text(
                        _responsetext,
                        style: TextStyle(color: Colors.green[700], fontSize: 20),
                      )))),
              Container(
                padding: const EdgeInsets.only(top: 30, left:20, right:20, bottom: 10),
                child: Text(
                  'Project Tasks',
                  style: TextStyle(fontSize: 20, color: Colors.black),
                ),
              ),
              Container(
                  padding: EdgeInsets.only(left: 20, right: 20),
                  child: Container(
                    decoration: BoxDecoration(
                        border: Border.all(color: Colors.black)
                    ),
                  )
              ),
              Container(
                  padding: EdgeInsets.only(left: 20, right: 20, top: 20),
                  child: ListView.builder(

                      physics: NeverScrollableScrollPhysics(),
                      shrinkWrap: true,
                      itemCount: task_count,
                      itemBuilder: (BuildContext ctxt, int Index) {
                        var obj = new TaskBlock();
                        return obj;

                      })),
              Container(
                padding: EdgeInsets.all(20),
                alignment: Alignment.bottomLeft,
                child: InkWell(
                    onTap: () => {
                      setState(() {
                        task_count++;

                        for(var i=0;i<tasks.length;i++){
                          var task = tasks[i];
                          print(task.text);
                          print(starts[i].text);
                          print(ends[i].text);
                        }
                      })
                    },
                    child: Container(


                        child: Row(
                          children: <Widget>[
                            Container(
                              padding: EdgeInsets.all(5),
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.all(Radius.circular(50)),
                                color: Colors.indigo[900],
                              ),
                              child: Icon(Icons.add, size: 15, color: Colors.white),
                            ),

                            Container(
                                padding: EdgeInsets.only(left:10),
                                child: Text("Add new task", style: TextStyle(fontSize: 20))
                            )
                          ],
                        )

                    )
                ),
              ),
              Container(
                alignment: Alignment.center,
                padding: EdgeInsets.all(30),
                //height: 100,
                child: InkWell(
                    onTap: ()  => submit_form(),
                    splashColor: Colors.indigo[900],
                    child: Container(
                        padding: EdgeInsets.all(7),
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            // Where the linear gradient begins and ends
                            begin: Alignment.centerLeft,
                            end: Alignment.centerRight,

                            // Add one stop for each color. Stops should increase from 0 to 1
                            stops: [0.2, 0.4, 0.6, 0.8],
                            colors: [
                              // Colors are easy thanks to Flutter's Colors class.

                              //Colors.blue,
                              Colors.indigo[900],
                              Colors.indigo[700],
                              Colors.indigo[700],
                              Colors.indigo[900],
                            ],
                          ),
                          borderRadius: BorderRadius.all(Radius.circular(5)),
                        ),
                        child: Row(

                          mainAxisAlignment: MainAxisAlignment.center,
                          children: <Widget>[
                            Container(
                                child: Text("Submit",
                                    style: TextStyle(
                                        fontSize: 18, color: Colors.white, fontWeight: FontWeight.bold)))
                          ],
                        ))),
              ),

//          Container(
//            padding:
//            const EdgeInsets.only(top: 20, left: 40, right: 40, bottom: 20),
//            child: RaisedButton(
//              color: Colors.indigo[900],
//              onPressed: () async {
//                // Validate returns true if the form is valid, or false
//                // otherwise.
//                if (_formKey.currentState.validate()) {
//                  var url = 'http://192.168.0.104:80/bah/api/add_project.php';
//                  var response = await http.post(url, body: {
//                    ''
//                        'pr_name': projectname.text,
//                    'pr_location': projectlocation.text,
//                    'client_name': clientname.text,
//                    'client_phone': clientphone.text,
//                    'pr_incharge': projectincharge.text,
//                    'pr_incharge_phone': projectinchargephone.text,
//                    'pr_start_date': _date,
//                  });
//                  print('Response status: ${response.statusCode}');
//                  print('Response body: ${response.body}');
//                  set_response_text(response.body.toString());
//                }
//              },
//              child: Center(
//                child: Text(
//                  'Submit',
//                  style: TextStyle(fontSize: 20, color: Colors.white),
//                ),
//              ),
//            ),
//          ),
            ],
          ),
        ),

      ],
    );

  }
}
