import 'package:buildahome/UserHome.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'NavMenu.dart';
import 'package:flutter_spinkit/flutter_spinkit.dart';
import 'main.dart';

class AdminDashboard extends StatelessWidget {
  final GlobalKey<ScaffoldState> _scaffoldKey = new GlobalKey<ScaffoldState>();

  @override
  Widget build(BuildContext context) {
    final appTitle = 'buildAhome';

    return MaterialApp(
      title: appTitle,
      theme: ThemeData(fontFamily: MyApp().fontName),
      home: Scaffold(
        key: _scaffoldKey, // ADD THIS LINE
        drawer: NavMenuWidget(),

        appBar: AppBar(
          automaticallyImplyLeading: false,
          title: Text(
            appTitle,
          ),
          leading: new IconButton(
              icon: new Icon(Icons.menu),
              onPressed: () async {
                SharedPreferences prefs = await SharedPreferences.getInstance();
                var username = prefs.getString('username');
                _scaffoldKey.currentState.openDrawer();
              }),
          backgroundColor: Color(0xFF000055),
        ),
        body: Dashboard(),
      ),
    );
  }
}

class Dashboard extends StatefulWidget {
  @override
  DashboardState createState() {
    return DashboardState();
  }
}

class DashboardState extends State<Dashboard> {
  var update = " ";
  var username = ' ';
  var date = " ";
  var role = "";
  var value = " ";
  var completed = "0";
  var user_id;
  var data;
  var search_data;

  @override
  void initState() {
    super.initState();
    call();
  }

  call() async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    username = prefs.getString('username');
    role = prefs.getString('role');
    var id = prefs.getString('project_id');
    user_id = prefs.getString('user_id');
    var response = await http
        .get("https://app.buildahome.in/api/projects_access.php?id=${user_id}");

    setState(() {
      print(data);
      data = jsonDecode(response.body);
      search_data = data;
      value = prefs.getString('project_value');
      completed = prefs.getString('completed');
      username = prefs.getString('username');
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
          child: Text("Details",
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
          decoration:
              BoxDecoration(border: Border(bottom: BorderSide(width: 3))),
        ),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: <Widget>[
            Container(
                alignment: Alignment.centerLeft,
                width: (MediaQuery.of(context).size.width - 60) / 2,
                margin: EdgeInsets.only(bottom: 10),
                child: Text("Name",
                    style: TextStyle(color: Colors.grey[600], fontSize: 18))),
            Container(
                alignment: Alignment.centerLeft,
                width: (MediaQuery.of(context).size.width - 60) / 2,
                margin: EdgeInsets.only(bottom: 10),
                child: Text(username,
                    style: TextStyle(color: Colors.black, fontSize: 18))),
          ],
        ),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: <Widget>[
            Container(
                alignment: Alignment.centerLeft,
                width: (MediaQuery.of(context).size.width - 60) / 2,
                margin: EdgeInsets.only(bottom: 30),
                child: Text("Role",
                    style: TextStyle(color: Colors.grey[600], fontSize: 18))),
            Container(
                alignment: Alignment.centerLeft,
                width: (MediaQuery.of(context).size.width - 60) / 2,
                margin: EdgeInsets.only(bottom: 30),
                child: Text(role,
                    style: TextStyle(color: Colors.black, fontSize: 18))),
          ],
        ),
        Container(
          padding: EdgeInsets.only(bottom: 10),
          margin: EdgeInsets.only(bottom: 10, right: 100),
          child: Text("Projects handled by you",
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
          decoration:
              BoxDecoration(border: Border(bottom: BorderSide(width: 3))),
        ),
        Container(
            margin: EdgeInsets.only(bottom: 10, top: 10),
            color: Colors.white,
            child: TextFormField(
              onChanged: (text) {
                setState(() {
                  search_data = [];
                  for (int i = 0; i < data.length; i++) {
                    if (text.toLowerCase().trim() == "") {
                      search_data.add(data[i]);
                    } else if (data[i]['name'].toLowerCase().contains(text)) {
                      search_data.add(data[i]);
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
        if (search_data == null)
          ListView.builder(
              shrinkWrap: true,
              physics: new BouncingScrollPhysics(),
              scrollDirection: Axis.vertical,
              itemCount: 10,
              itemBuilder: (BuildContext ctxt, int Index) {
                return Container(
                    padding: EdgeInsets.all(15),
                    margin: EdgeInsets.only(bottom: 10),
                    decoration: BoxDecoration(
                      color: Colors.grey[200],
                      shape: BoxShape.rectangle,
                      border: Border(
                        bottom: BorderSide(width: 1.0, color: Colors.grey[300]),
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
                        Container(
                            width: 60,
                            child: Text('',
                                style: TextStyle(
                                    fontSize: 18,
                                    fontWeight: FontWeight.bold))),
                        Container(
                            child: Text('',
                                style: TextStyle(
                                    fontSize: 18, fontWeight: FontWeight.bold)))
                      ],
                    ));
              }),
        ListView.builder(
            shrinkWrap: true,
            physics: new BouncingScrollPhysics(),
            scrollDirection: Axis.vertical,
            itemCount: search_data == null ? 0 : search_data.length,
            itemBuilder: (BuildContext ctxt, int Index) {
              return search_data[Index]['name'].trim().length > 0
                  ? InkWell(
                      onTap: () async {
                        SharedPreferences prefs =
                            await SharedPreferences.getInstance();
                        await prefs.setString(
                            "project_id", search_data[Index]['id'].toString());
                        await prefs.setString("client_name",
                            search_data[Index]['name'].toString());

                        Navigator.push(
                          context,
                          MaterialPageRoute(builder: (context) => Home()),
                        );
                      },
                      child: Container(
                          padding: EdgeInsets.symmetric(
                              horizontal: 15, vertical: 20),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            shape: BoxShape.rectangle,
                            border: Border(
                              bottom: BorderSide(
                                  width: 1.0, color: Colors.grey[300]),
                            ),
                          ),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: <Widget>[
                              Container(
                                  width: 40,
                                  child: Text((Index + 1).toString() + ".",
                                      style: TextStyle(
                                          fontSize: 18,
                                          fontWeight: FontWeight.w500))),
                              Container(
                                  width:
                                      MediaQuery.of(context).size.width * 0.65,
                                  child: Text(search_data[Index]['name'].trim(),
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                          fontSize: 18,
                                          fontWeight: FontWeight.w500)))
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
