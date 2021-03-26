import 'package:flutter/material.dart';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'UserHome.dart';
import 'package:shared_preferences/shared_preferences.dart';
import "AdminDashboard.dart";
import "Loader.dart";
import 'package:firebase_messaging/firebase_messaging.dart';

void main() => runApp(MyApp());


class MyApp extends StatelessWidget {
  final fontName = 'SFPro';

  @override
  Widget build(BuildContext context) {
    final appTitle = 'buildAhome';

    return MaterialApp(
      title: appTitle,
      theme: ThemeData(fontFamily: fontName),
      home: Scaffold(
        body: LoginForm(),
      ),
    );
  }
}

// Create a Form widget.
class LoginForm extends StatefulWidget {
  @override
  LoginFormState createState() {
    return LoginFormState();
  }
}

class LoginFormState extends State<LoginForm> {
  

  String _response = "";
  var splash = false;
  void _login(String response){
    setState(() {
      _response = response;

    });
  }
  //
  final _formKey = GlobalKey<FormState>();

  set_persistence(username, role, project_id, project_value, completed, id, location) async{

    SharedPreferences prefs = await SharedPreferences.getInstance();
    prefs.setString("username", username.toString());
    prefs.setString("role", role.toString());
    prefs.setString("user_id", id.toString());
    if(role.toString()=='Client'){
      prefs.setString("project_id", project_id.toString());
      prefs.setString("project_value", project_value.toString());
      prefs.setString("completed", completed.toString());
      prefs.setString("location", location.toString());

    }
  }


  void initState() {
    super.initState();
    call();
    final FirebaseMessaging _messaging = FirebaseMessaging();
    _messaging.configure(
      onMessage: (Map<String, dynamic> message) async {
        print("onMessage: $message");
      },
      
      onLaunch: (Map<String, dynamic> message) async {
        print("onLaunch: $message");
      },
      onResume: (Map<String, dynamic> message) async {
        print("onResume: $message");
      },

    );
    _messaging.subscribeToTopic('All');
    _messaging.getToken().then((token){
      print(token);
         
    });
    
  }
  call() async{
    SharedPreferences prefs = await SharedPreferences.getInstance();
    var username = prefs.getString('username');
    var role = prefs.getString('role');

    setState(() {
      splash=false;
      if(username!=null){
        if(role=="Client") {
          Navigator.pushReplacement(
            context,
            MaterialPageRoute(builder: (context) => Home()),
          );
        }
        else{
          Navigator.pushReplacement(
            context,
            MaterialPageRoute(builder: (context) => AdminDashboard()),
          );
        }
      }
    });


  }

  @override
  Widget build(BuildContext context) {
    final username = TextEditingController();
    final password = TextEditingController();

    return Form(
      key: _formKey,
      child: Container(
        color: Colors.white,
        height: MediaQuery.of(context).size.height,
        alignment: Alignment.center,
        child: ListView(

          children: <Widget>[

            Container(
                padding: EdgeInsets.only(top: 40),
                width: MediaQuery.of(context).size.width*0.4,
                height: MediaQuery.of(context).size.height*0.4,
                alignment: Alignment.center,
                child: Image(image: AssetImage('assets/images/logo-big.png'))
            ),
            Padding(
              padding: const EdgeInsets.symmetric(vertical: .0, horizontal: 30),
              child: Text(
                _response, style: TextStyle( fontSize: 20, color: Colors.red[500]),
              ),
            ),
            Container(
              padding: EdgeInsets.only(left: 30, right: 30, bottom: 30, top: 15),
              alignment: Alignment.center,
              child: TextFormField(
                controller: username ,
                scrollPadding: EdgeInsets.all(1),
                style: TextStyle(fontSize: 16.0),

                decoration: InputDecoration(
                    labelText: 'Username',
                    contentPadding: EdgeInsets.only(bottom: 5),
                    labelStyle: TextStyle( fontSize: 16.0),
                ),validator: (value) {
                if (value.isEmpty) {
                  return 'This field cannot be empty';
                }
                return null;
                },
              ),
            ),

            Container(
              padding: EdgeInsets.only(left: 30, right: 30),
              alignment: Alignment.center,
              child: TextFormField(
                controller: password,
                keyboardType: TextInputType.phone,
                style: TextStyle(fontSize: 16.0),
                decoration: InputDecoration(
                  labelText: 'Phone',
                  contentPadding: EdgeInsets.only(bottom: 5),
                  errorStyle: TextStyle(color: Colors.indigo[800]),
                  labelStyle: TextStyle( fontSize: 16.0),
                ),validator: (value) {
                if (value.isEmpty) {
                  return 'This field cannot be empty';
                }
                return null;
                },
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(vertical: 40.0, horizontal: 30),
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
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: <Widget>[

                        Text(
                          "Step in ",
                          style: TextStyle(
                              fontSize: 18,
                              color: Colors.white,
                              fontWeight: FontWeight.bold),
                        ),
                        Icon(Icons.vpn_key, color: Colors.white),
                      ],
                    ),


                  ),
                  onTap: () async {
                    if (_formKey.currentState.validate()) {
                       var result = showDialog(
                          context: context,
                          builder: (BuildContext context) {
                            return Loader();
                          });

                      var url = 'https://www.buildahome.in/api/login.php';
                      var response = await http.post(url, body: {'username': username.text , 'password' :password.text });
                      Map<String, dynamic> user = jsonDecode(response.body);
                      print(response.body);
                       if(user['message'].toString()=="Access denied") {
                         Navigator.of(context, rootNavigator: true).pop('dialog');
                        _login(user['message']);
                      }
                      else{
                        Navigator.of(context, rootNavigator: true).pop('dialog');
                        if(user['role']=='Client') {
                          set_persistence(username.text, user['role'], user['project_id'], user['project_value'], user['completed_percentage'], user["id"], user['location']);

                          Navigator.pushReplacement(
                            context,
                            MaterialPageRoute(builder: (context) => Home()),
                          );
                        }
                        else{
                          set_persistence(username.text, user['role'], 'Hi', "Admin", "admin", user["id"], "Bengaluru");
                          Navigator.pushReplacement(
                            context,
                            MaterialPageRoute(builder: (context) => AdminDashboard()),
                          );
                        }
                      }
                    }

                  }),



            ),


          ],
        ),
      ),
    );

  }
}
