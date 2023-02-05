import 'package:flutter/material.dart';
import 'package:flutter/widgets.dart';
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'NavMenu.dart';
import 'AddNewUser.dart';

class UserCard extends StatelessWidget {
  String name = "";
  String email = "";
  String role = "";

  UserCard(this.name, this.email, this.role);

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Container(
          width: 400,
          padding: EdgeInsets.all(20),
          decoration: BoxDecoration(
            border: Border.all(),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: <Widget>[
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.start,
                children: <Widget>[
                  Container(
                      child: Row(
                        children: <Widget>[
                          Icon(Icons.person),
                          Text(name,
                              style:
                              TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                        ],
                      )),
                  Container(
                      padding: EdgeInsets.only(top: 5),
                      child: Row(
                        children: <Widget>[
                          Text(email,
                              style:
                              TextStyle(fontSize: 14)),
                        ],
                      )),

                ],
              ),
              Text(role,
                  style:
                  TextStyle(fontSize: 14)),

            ],

          )
          ),

    );
  }
}

class ViewUsers extends StatelessWidget {
  final GlobalKey<ScaffoldState> _scaffoldKey = new GlobalKey<ScaffoldState>();

  @override
  Widget build(BuildContext context) {
    final appTitle = 'BuildAhome';
    void _onItemTapped(int index) {
      print(index);
      if (index == 0) {
        Navigator.pop(context);

        Navigator.push(
          context,
          MaterialPageRoute(builder: (context) => Users()),
        );
      }
    }

    return MaterialApp(
      title: appTitle,
      home: Scaffold(
        key: _scaffoldKey,
        // ADD THIS LINE
        drawer: NavMenuWidget(),

        appBar: AppBar(
          automaticallyImplyLeading: false,
          title: Text(appTitle),
          leading: new IconButton(
              icon: new Icon(Icons.menu),
              onPressed: () => _scaffoldKey.currentState.openDrawer()),
          backgroundColor: Colors.indigo[900],
        ),
        bottomNavigationBar: BottomNavigationBar(
          items: const <BottomNavigationBarItem>[

            BottomNavigationBarItem(
              icon: Icon(Icons.person_add),
              label: 'Add new user',
            ),
            BottomNavigationBarItem(
              icon: Icon(Icons.view_list),
              label: 'View all users',
            ),
          ],
          currentIndex: 1,
          onTap: _onItemTapped,
        ),

        body: ViewUsersForm(),
      ),
    );
  }
}

class ViewUsersForm extends StatefulWidget {
  @override
  ViewUsersState createState() {
    return ViewUsersState();
  }
}

class ViewUsersState extends State<ViewUsersForm> {


  var a;

  call() async {
    var url = 'http://192.168.0.105:80/bah/api/view_all_users.php';
    var response = await http.get(Uri.parse(url));
    print(response.body);
    setState(() {
      a = jsonDecode(response.body);
    });
  }

  Widget build(BuildContext context) {
    return Container(
        child: new ListView.builder(
      itemCount: a == null ? 0 : a.length,
      itemBuilder: (BuildContext ctxt, int Index) {
        return new Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            UserCard(
              a[Index]['name'].toString(),
              a[Index]['email'].toString(),
              a[Index]['role'].toString(),
            )
          ],
        );
      },
    ));
  }
}
