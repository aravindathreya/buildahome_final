import 'package:buildahome/AddDailyUpdate.dart';
import 'package:buildahome/view_open_indents.dart';
import 'package:flutter/material.dart';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_spinkit/flutter_spinkit.dart';

import 'NavMenu.dart';
import 'main.dart';
import 'package:buildahome/UserHome.dart';
import 'package:intl/intl.dart';

class AdminDashboard extends StatelessWidget {
  final GlobalKey<ScaffoldState> _scaffoldKey = new GlobalKey<ScaffoldState>();

  @override
  Widget build(BuildContext context) {
    final appTitle = 'buildAhome';

    return MaterialApp(
      title: appTitle,
      theme: ThemeData(
        fontFamily: App().fontName,
        colorScheme: ThemeData().colorScheme.copyWith(
              primary: Color.fromARGB(255, 13, 17, 65),
            ),
      ),
      home: Scaffold(
        key: _scaffoldKey, // ADD THIS LINE
        drawer: NavMenuWidget(),

        appBar: AppBar(
          automaticallyImplyLeading: false,
          title: Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [],
          ),
          shadowColor: Colors.grey[100],
          leading: new IconButton(
              icon: new Icon(Icons.menu, color: Colors.black),
              onPressed: () async {
                _scaffoldKey.currentState?.openDrawer();
              }),
          backgroundColor: Colors.white,
        ),
        body: AdminHome(),
      ),
    );
  }
}

class AdminHome extends StatefulWidget {
  @override
  AdminHomeState createState() {
    return AdminHomeState();
  }
}

class AdminHomeState extends State<AdminHome> {
  var currentWidgetContext;
  var currentDate;
  var showTopSection = true;
  var showProjects = false;
  var searchProjectfocusNode = FocusNode();
  var searchProjectTextController = new TextEditingController();
  var currentUserRole = '';
  var projects = [];
  var projectsToShow = [];
  bool readOnly = true;

  setDate() {
    var now = new DateTime.now();
    var formatter = new DateFormat('d, MMMM');
    currentDate = formatter.format(now);
  }

  setRole() async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    setState(() {
      currentUserRole = prefs.getString('role')!;
    });
  }

  loadProjects() async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    var role = prefs.getString('role');
    var userId = prefs.getString('userId') == null ? prefs.getString('userId') : prefs.getString('user_id');
    String? apiToken = prefs.getString('api_token');

    print('$role $apiToken $userId');
    var response = await http.post(Uri.parse("https://app.buildahome.in/erp/API/get_projects_for_user"), body: {"user_id": userId, "role": role, "api_token": apiToken});
    print(response.statusCode);
    setState(() {
      try {
        projects = jsonDecode(response.body);
        projectsToShow = projects;
      } catch (e) {
        print('Error $e');
      }
    });
  }

  @override
  void initState() {
    super.initState();
    setDate();
    setRole();
    loadProjects();
  }

  Widget build(BuildContext context) {
    currentWidgetContext = context;
    return Container(
        color: Colors.white,
        height: MediaQuery.of(context).size.height,
        width: MediaQuery.of(context).size.width,
        child: ListView(
          children: [
            Visibility(
                visible: showTopSection,
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Container(
                      margin: EdgeInsets.only(left: 15, right: 15),
                      child: Text('Welcome back!', style: TextStyle(fontWeight: FontWeight.w500, fontSize: 18)),
                    ),
                    Container(
                      alignment: Alignment.centerRight,
                      child: Image(
                        height: 120, // Set your height according to aspect ratio or fixed height
                        width: 120,
                        image: AssetImage('assets/images/logo-big.png'),
                        fit: BoxFit.contain,
                      ),
                    )
                  ],
                )),
            Visibility(
              visible: showTopSection,
              child: Container(
                  margin: EdgeInsets.only(left: 15, right: 15, top: 20),
                  padding: EdgeInsets.all(10),
                  decoration: BoxDecoration(color: Color.fromARGB(255, 216, 213, 252), borderRadius: BorderRadius.circular(10)),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Container(
                            margin: EdgeInsets.only(top: 120),
                            child: Text(
                              'Role: $currentUserRole',
                              style: TextStyle(fontSize: 14),
                            ),
                          ),
                          Container(
                            margin: EdgeInsets.only(top: 10),
                            child: Text(
                              currentDate,
                              style: TextStyle(fontSize: 24),
                            ),
                          ),
                        ],
                      ),
                      Icon(Icons.calendar_month_outlined, size: 50)
                    ],
                  )),
            ),
            Container(
                margin: EdgeInsets.only(bottom: 10, top: 10, left: 15, right: 15),
                color: Colors.white,
                child: TextField(
                  onTap: () {
                    setState(() {
                      this.showTopSection = false;
                      this.readOnly = true;
                      Future.delayed(
                        Duration(milliseconds: 100),
                        () {
                          setState(() {
                            this.showProjects = true;
                            this.readOnly = false;
                          });
                        },
                      );
                    });
                  },
                  onChanged: (text) {
                    setState(() {});
                  },
                  readOnly: this.readOnly,
                  controller: searchProjectTextController,
                  focusNode: searchProjectfocusNode,
                  cursorColor: Color.fromARGB(255, 13, 17, 65),
                  decoration: InputDecoration(
                    hoverColor: Color.fromARGB(255, 13, 17, 65),
                    hintText: 'Search project',
                    contentPadding: EdgeInsets.only(left: 10, top: 14),
                    suffixIcon: InkWell(
                        child: Icon(
                      Icons.search,
                    )),
                    prefixIconConstraints: BoxConstraints(maxWidth: 30),
                    prefixIcon: Visibility(
                      visible: !showTopSection,
                      child: InkWell(
                        child: Container(
                          padding: EdgeInsets.zero,
                          child: Icon(Icons.chevron_left, size: 30),
                        ),
                        onTap: () {
                          setState(() {
                            searchProjectTextController.text = '';
                            searchProjectfocusNode.unfocus();
                          });
                          this.showProjects = false;
                          Future.delayed(
                            Duration(milliseconds: 500),
                            () {
                              setState(() {
                                this.showTopSection = true;
                              });
                            },
                          );
                        },
                      ),
                    ),
                    focusColor: Color.fromARGB(255, 13, 17, 65),
                    enabledBorder: UnderlineInputBorder(
                      borderSide: BorderSide(color: Color.fromARGB(255, 13, 17, 65)),
                    ),
                    focusedBorder: UnderlineInputBorder(
                      borderSide: BorderSide(color: Color.fromARGB(255, 13, 17, 65), width: 2),
                    ),
                  ),
                )),
            Visibility(
                visible: showProjects,
                child: ListView.builder(
                    shrinkWrap: true,
                    physics: new BouncingScrollPhysics(),
                    scrollDirection: Axis.vertical,
                    itemCount: projectsToShow.length,
                    itemBuilder: (BuildContext ctxt, int index) {
                      return Visibility(
                          visible: searchProjectTextController.text.trim() == '' || projectsToShow[index]['name'].toLowerCase().contains(searchProjectTextController.text.trim().toLowerCase()),
                          child: InkWell(
                              onTap: () async {
                                SharedPreferences prefs = await SharedPreferences.getInstance();
                                await prefs.setString("project_id", projectsToShow[index]['id'].toString());
                                await prefs.setString("client_name", projectsToShow[index]['name'].toString());

                                Navigator.push(
                                  context,
                                  MaterialPageRoute(builder: (context) => Home()),
                                );
                              },
                              child: Container(
                                  padding: EdgeInsets.symmetric(horizontal: 25, vertical: 20),
                                  decoration: BoxDecoration(
                                    color: Colors.white,
                                    shape: BoxShape.rectangle,
                                    border: Border(
                                      bottom: BorderSide(width: 1.0, color: Colors.grey[300]!),
                                    ),
                                  ),
                                  child: Row(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: <Widget>[
                                      Container(
                                          width: MediaQuery.of(context).size.width * 0.65,
                                          child: Text(projectsToShow[index]['name'].trim(), overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 18, fontWeight: FontWeight.w500)))
                                    ],
                                  ))));
                    })),
            Visibility(
              visible: showTopSection,
              child: Container(
                margin: EdgeInsets.only(top: 20, left: 10, right: 10, bottom: 20),
                child: Wrap(
                  children: [
                    InkWell(
                      child: Container(
                          width: (MediaQuery.of(context).size.width - 40) / 2,
                          margin: EdgeInsets.all(5),
                          padding: EdgeInsets.all(20),
                          decoration: BoxDecoration(
                            color: Colors.grey[200],
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Column(
                            children: [
                              Icon(Icons.update, size: 30),
                              Container(
                                margin: EdgeInsets.only(top: 10),
                                child: Text('Add daily update'),
                              )
                            ],
                          )),
                      onTap: () {
                        Navigator.pushReplacement(
                          currentWidgetContext,
                          MaterialPageRoute(builder: (currentWidgetContext) => AddDailyUpdate()),
                        );
                      },
                    ),
                    InkWell(
                      child: Container(
                          width: (MediaQuery.of(context).size.width - 40) / 2,
                          margin: EdgeInsets.all(5),
                          padding: EdgeInsets.all(20),
                          decoration: BoxDecoration(
                            color: Colors.grey[200],
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Column(
                            children: [
                              Icon(Icons.dock, size: 30),
                              Container(
                                margin: EdgeInsets.only(top: 10),
                                child: Text('Open indents'),
                              )
                            ],
                          )),
                      onTap: () {
                        Navigator.push(context,

                        MaterialPageRoute(builder: (context) => ViewIndentsLayout()));
                      },
                    ),


                  ],
                ),
              ),
            )
          ],
        ));
  }
}

class Dashboard extends StatefulWidget {
  @override
  DashboardState createState() {
    return DashboardState();
  }
}

class DashboardState extends State<Dashboard> {
  var update = "";
  var username = "";
  var date = "";
  var role = "";

  var userId;
  var data;
  var searchData;

  @override
  void initState() {
    super.initState();
    call();
  }

  call() async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    role = prefs.getString('role')!;
    userId = prefs.getString('userId');
    String apiToken = prefs.getString('api_token')!;
    var response = await http.post(Uri.parse("https://app.buildahome.in/erp/API/get_projects_for_user"), body: {"user_id": userId, "role": role, "api_token": apiToken});

    setState(() {
      print(data);
      data = jsonDecode(response.body);
      searchData = data;

      username = prefs.getString('username')!;
    });
  }

  Widget build(BuildContext context) {
    return Container(
        child: ListView(
      padding: EdgeInsets.all(25),
      children: <Widget>[
        Container(
          padding: EdgeInsets.only(bottom: 10),
          margin: EdgeInsets.only(bottom: 10, right: 100),
          child: Text("Projects handled by you", style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
          decoration: BoxDecoration(border: Border(bottom: BorderSide(width: 3))),
        ),
        Container(
            margin: EdgeInsets.only(bottom: 10, top: 10),
            color: Colors.white,
            child: TextFormField(
              onChanged: (text) {
                setState(() {
                  searchData = [];
                  for (int i = 0; i < data.length; i++) {
                    if (text.toLowerCase().trim() == "") {
                      searchData.add(data[i]);
                    } else if (data[i]['name'].toLowerCase().contains(text)) {
                      searchData.add(data[i]);
                    }
                  }
                });
              },
              decoration: InputDecoration(
                hintText: 'Search project',
                contentPadding: EdgeInsets.all(10),
                suffixIcon: InkWell(child: Icon(Icons.search)),
              ),
            )),
        if (searchData == null)
          ListView.builder(
              shrinkWrap: true,
              physics: new BouncingScrollPhysics(),
              scrollDirection: Axis.vertical,
              itemCount: 10,
              itemBuilder: (BuildContext ctxt, int index) {
                return Container(
                    padding: EdgeInsets.all(15),
                    margin: EdgeInsets.only(bottom: 10),
                    decoration: BoxDecoration(
                      color: Colors.grey[200],
                      shape: BoxShape.rectangle,
                      border: Border(
                        bottom: BorderSide(width: 1.0, color: Colors.grey[300]!),
                      ),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        SpinKitRing(
                          color: Color(0xFF03045E),
                          size: 20,
                          lineWidth: 2,
                        ),
                        Container(width: 60, child: Text('', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold))),
                        Container(child: Text('', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)))
                      ],
                    ));
              }),
        ListView.builder(
            shrinkWrap: true,
            physics: new BouncingScrollPhysics(),
            scrollDirection: Axis.vertical,
            itemCount: searchData == null ? 0 : searchData.length,
            itemBuilder: (BuildContext ctxt, int index) {
              return searchData[index]['name'].trim().length > 0
                  ? InkWell(
                      onTap: () async {
                        SharedPreferences prefs = await SharedPreferences.getInstance();
                        await prefs.setString("project_id", searchData[index]['id'].toString());
                        await prefs.setString("client_name", searchData[index]['name'].toString());

                        Navigator.push(
                          context,
                          MaterialPageRoute(builder: (context) => Home()),
                        );
                      },
                      child: Container(
                          padding: EdgeInsets.symmetric(horizontal: 15, vertical: 20),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            shape: BoxShape.rectangle,
                            border: Border(
                              bottom: BorderSide(width: 1.0, color: Colors.grey[300]!),
                            ),
                          ),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: <Widget>[
                              Container(width: 40, child: Text((index + 1).toString() + ".", style: TextStyle(fontSize: 18, fontWeight: FontWeight.w500))),
                              Container(
                                  width: MediaQuery.of(context).size.width * 0.65,
                                  child: Text(searchData[index]['name'].trim(), overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 18, fontWeight: FontWeight.w500)))
                            ],
                          )))
                  : Container();
            })
      ],
    ));
  }
}

class HomeWidget extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container();
  }
}
