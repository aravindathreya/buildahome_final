import 'package:buildahome/ViewAllUsers.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'NavMenu.dart';
import "ShowAlert.dart";
import "ViewAllUsers.dart";
import 'package:grouped_buttons/grouped_buttons.dart';
import 'dart:convert';
import 'dart:async';

class Users extends StatefulWidget {
  @override
  UsersState createState() {
    return UsersState();
  }
}


class UsersState extends State<Users> {
  var name = TextEditingController();
  var email = TextEditingController();
  var password = TextEditingController();
  var role = TextEditingController();

  var projects =[];
  call() async {
    var url = 'https://app.buildahome.in/api/view_all_users.php';
    var response = await http.get(url);
    print(response.body);
    setState(() {
      projects = jsonDecode(response.body);
    });
  }

  @override
  void initState() {
    super.initState();
    call();
  }
  @override
  Widget build(BuildContext context) {
    void _onItemTapped(int index) {
      print(index);
      if (index == 1) {
        Navigator.pop(context);

        Navigator.push(
          context,
          MaterialPageRoute(builder: (context) => ViewUsers()),
        );
      }
    }

    final appTitle = 'BuildAhome';
    final _formKey = GlobalKey<FormState>();
    final GlobalKey<ScaffoldState> _scaffoldKey =
        new GlobalKey<ScaffoldState>();
    return MaterialApp(
      title: appTitle,
      theme: ThemeData(fontFamily: 'Varela'),
      home: Scaffold(
        key: _scaffoldKey,
        // ADD THIS LINE
        appBar: AppBar(
          automaticallyImplyLeading: false,
          title: Text(appTitle),
          leading: new IconButton(
              icon: new Icon(Icons.menu),
              onPressed: () => _scaffoldKey.currentState.openDrawer()),
          backgroundColor: Colors.indigo[900],
        ),
        drawer: NavMenuWidget(),

        body: PageView(
          children: <Widget>[
            ListView(
              padding: EdgeInsets.all(15),
              children: <Widget>[
                Container(
                  padding: const EdgeInsets.only(
                      top: 15, left: 5, right: 5, bottom: 10),
                  child: Text(
                    'All Users',
                    style: TextStyle(fontSize: 20, color: Colors.black),
                  ),
                ),
                Container(
                    padding: EdgeInsets.only(left: 5, right: 5),
                    child: Container(
                      decoration:
                      BoxDecoration(border: Border.all(color: Colors.black)),
                    )),
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
                                    child: Text("Email: "+ projects[Index]['email'], style: TextStyle(fontSize: 14))
                                ),

                                Container(
                                    padding: EdgeInsets.all(10),
                                    child: Text("Role: "+projects[Index]['role'], style: TextStyle(fontSize: 14))
                                ),

                              ],
                            )
                        )
                    );
                  },),
              ],
            ),


            Form(
              key: _formKey,
              child: ListView(
                children: <Widget>[
                  Container(
                    padding: const EdgeInsets.only(
                        top: 30, left: 20, right: 20, bottom: 10),
                    child: Text(
                      'User Information',
                      style: TextStyle(fontSize: 20, color: Colors.black),
                    ),
                  ),
                  Container(
                      padding: EdgeInsets.only(left: 20, right: 20),
                      child: Container(
                        decoration:
                        BoxDecoration(border: Border.all(color: Colors.black)),
                      )),
                  Container(
                      padding: const EdgeInsets.only(top: 20, left: 20, right: 20),
                      child: TextFormField(
                        controller: name,
                        decoration: InputDecoration(
                          border: OutlineInputBorder(
                            borderSide:
                            BorderSide(color: Colors.greenAccent, width: 5.0),
                          ),
                          contentPadding: EdgeInsets.all(12),
                          labelText: "Name",
                          hintText: "Name",
                          hasFloatingPlaceholder: false,
                          labelStyle: TextStyle(
                            fontSize: 16,
                          ),
                        ),
                        style: TextStyle(fontSize: 16),
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
                        controller: email,
                        decoration: InputDecoration(
                          border: OutlineInputBorder(
                            borderSide:
                            BorderSide(color: Colors.greenAccent, width: 5.0),
                          ),
                          contentPadding: EdgeInsets.all(12),
                          labelText: "Email",
                          hintText: "Email",
                          hasFloatingPlaceholder: false,
                          labelStyle: TextStyle(
                            fontSize: 16,
                          ),
                        ),
                        style: TextStyle(fontSize: 16),
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
                        controller: password,
                        decoration: InputDecoration(
                          border: OutlineInputBorder(
                            borderSide:
                            BorderSide(color: Colors.greenAccent, width: 5.0),
                          ),
                          contentPadding: EdgeInsets.all(12),
                          labelText: "Password",
                          hintText: "Password",
                          hasFloatingPlaceholder: false,
                          labelStyle: TextStyle(
                            fontSize: 16,
                          ),
                        ),
                        style: TextStyle(fontSize: 16),
                        validator: (value) {
                          if (value.isEmpty) {
                            return 'This field cannot be empty';
                          }
                          return null;
                        },
                        obscureText: true,
                      )),
                  Container(
                    padding: const EdgeInsets.only(top: 20, left: 20, right: 20),
                    alignment: Alignment.bottomLeft,
                    child: Container(
                        decoration: BoxDecoration(
                            borderRadius: BorderRadius.all(Radius.elliptical(5, 5)),
                            border: Border.all(color: Colors.black54)),
                        child: Column(
                          children: <Widget>[
                            Container(
                              alignment: Alignment.topLeft,
                              padding: EdgeInsets.all(10),
                              child: Text(
                                "Select role",
                                style:
                                TextStyle(fontSize: 16, color: Colors.black54),
                              ),
                            ),
                            Container(
                              child: RadioButtonGroup(
                                labels: <String>[
                                  "Site engineer",
                                  "Office manager",
                                  "Super Admin",
                                  "Client"
                                ],
                                activeColor: Colors.indigo[900],
                                onSelected: (String label) => role.text = label,
                                labelStyle:
                                TextStyle(fontSize: 16, color: Colors.black87),
                              ),
                            ),
                          ],
                        )),
                  ),
                  Container(
                    padding: EdgeInsets.all(20),
                    child: InkWell(
                        child: Container(
                          alignment: Alignment.center,
                          padding: EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            boxShadow: [
                              new BoxShadow(
                                color: Colors.grey[600],
                                blurRadius: 5,
                                spreadRadius: 1,
                              )
                            ],
                            gradient: LinearGradient(
                              // Where the linear gradient begins and ends
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,

                              // Add one stop for each color. Stops should increase from 0 to 1
                              stops: [0.2, 0.5, 0.8],
                              colors: [
                                // Colors are easy thanks to Flutter's Colors class.

                                //Colors.blue,
                                Colors.indigo[900],
                                Colors.indigo[700],
                                //Colors.indigo[700],
                                Colors.indigo[900],
                              ],
                            ),
                            border: Border.all(color: Colors.black, width: 1),
                            borderRadius: BorderRadius.all(Radius.circular(5)),
                          ),
                          child: Text(
                            "Submit",
                            style: TextStyle(
                                fontSize: 18,
                                color: Colors.white,
                                fontWeight: FontWeight.bold),
                          ),
                        ),
                        onTap: () async {
                          if (_formKey.currentState.validate()) {
                            showDialog(
                                context: context,
                                builder: (BuildContext context) {
                                  return ShowAlert(
                                      "Hang in there. We're adding this user to our records",
                                      true);
                                });
                            var url =
                                'https://app.buildahome.in/api/add_new_user.php';
                            var response = await http.post(url, body: {
                              "email": email.text,
                              "name": name.text,
                              "password": password.text,
                              "role": role.text
                            });
                            print(response.body);
                            Navigator.of(context, rootNavigator: true).pop();
                            showDialog(
                                context: context,
                                builder: (BuildContext context) {
                                  return ShowAlert("User added sucessfully", false);
                                });

                            print('Response body: ${response.body}');
                            //set_response_text(response.body);

                          }
                        }),
                  )


                ],
              ),
            ),
          ],
        )


      ),
    );
  }
}
