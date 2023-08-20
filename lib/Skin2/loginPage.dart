// Built in packages
import 'package:flutter/material.dart';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_spinkit/flutter_spinkit.dart';

// Custom dart files
import '../UserHome.dart';
import "../AdminDashboard.dart";

class LoginScreenNew extends StatefulWidget {
  @override
  LoginScreenNewState createState() {
    return LoginScreenNewState();
  }
}

class LoginScreenNewState extends State<LoginScreenNew> {
  var imageContainerShrinked = false;
  var userNamefocusNode = FocusNode();
  var passwordfocusNode = FocusNode();
  var showUsernameField = false;
  var showUsernameError = false;
  var usernameTextController = new TextEditingController();
  var passwordTextController = new TextEditingController();
  var showPasswordError = false;
  var showPasswordField = false;
  var formBeingSubmitted = false;
  var showIncorrectCredentials = false;
  var showLoginForm = false;

  void initState() {
    super.initState();
    checkIfAlreadyLoggedIn();
  }

  checkIfAlreadyLoggedIn() async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    var username = prefs.getString('username');
    var role = prefs.getString('role');

    setState(() {
      if (username != null) {
        this.showLoginForm = false;
        if (role == "Client") {
          Navigator.pushReplacement(
            context,
            MaterialPageRoute(builder: (context) => Home()),
          );
        } else {
          Navigator.pushReplacement(
            context,
            MaterialPageRoute(builder: (context) => AdminDashboard()),
          );
        }
      } else {
        this.showLoginForm = true;
      }
    });
  }

  String getCTAButtonText() {
    if (showUsernameField)
      return 'NEXT';
    else if (showPasswordField)
      return 'SUBMIT';
    else
      return 'LOGIN';
  }

  setSharedPrefs(username, role, projectId, projectValue, completed, userId, location, apiToken) async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    prefs.setString("username", username.toString());
    prefs.setString("role", role.toString());
    prefs.setString("userId", userId.toString());
    prefs.setString("user_id", userId.toString());
    prefs.setString("api_token", apiToken.toString());

    if (role.toString() == 'Client') {
      prefs.setString("project_id", projectId.toString());
      prefs.setString("project_value", projectValue.toString());
      prefs.setString("completed", completed.toString());
      prefs.setString("location", location.toString());
    }
  }

  loginUser() async {
    var url = Uri.parse('https://app.buildahome.in/erp/API/login');
    var response =
        await http.post(url, body: {'username': usernameTextController.text, 'password': passwordTextController.text});
    print(response.body);
    Map<String, dynamic> jsonDecodedResponse;
    try {
      jsonDecodedResponse = jsonDecode(response.body);
      if (jsonDecodedResponse['message'].toString() != "success") {
        setState(() {
          this.showIncorrectCredentials = true;
          this.showUsernameField = true;
          this.formBeingSubmitted = false;
        });
      } else {
        if (jsonDecodedResponse['role'] == 'Client') {
          setSharedPrefs(
              usernameTextController.text,
              jsonDecodedResponse['role'],
              jsonDecodedResponse['project_id'],
              jsonDecodedResponse['project_value'],
              jsonDecodedResponse['completed_percentage'],
              jsonDecodedResponse['user_id'],
              jsonDecodedResponse['location'],
              jsonDecodedResponse['api_token']);

          Navigator.pushReplacement(
            context,
            MaterialPageRoute(builder: (context) => Home()),
          );
        } else {
          setSharedPrefs(usernameTextController.text, jsonDecodedResponse['role'], '', '', '',
              jsonDecodedResponse["user_id"], '', jsonDecodedResponse['api_token']);

          Navigator.pushReplacement(
            context,
            MaterialPageRoute(builder: (context) => AdminDashboard()),
          );
        }
      }
    } catch (e) {
      print('Error: $e');
      setState(() {
        this.showIncorrectCredentials = true;
        this.showUsernameField = true;
        this.formBeingSubmitted = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Colors.white,
      height: MediaQuery.of(context).size.height,
      width: MediaQuery.of(context).size.width,
      child: this.showLoginForm
          ? Column(children: [
              AnimatedContainer(
                  height: this.imageContainerShrinked
                      ? MediaQuery.of(context).size.height * .3
                      : MediaQuery.of(context).size.height * .6,
                  decoration: BoxDecoration(color: Colors.grey[200]),
                  duration: Duration(milliseconds: 300),
                  child: Container(
                    color: Colors.white,
                    padding: this.imageContainerShrinked ? EdgeInsets.only(top: 50) : EdgeInsets.all(30),
                    child: Image(
                      image: AssetImage('assets/images/login_illustration.png'),
                      fit: BoxFit.cover,
                    ),
                  )),
              Visibility(
                visible: this.showUsernameField,
                child: Container(
                    margin: EdgeInsets.symmetric(vertical: 20, horizontal: 15),
                    width: MediaQuery.of(context).size.width - 30,
                    child: TextField(
                      controller: usernameTextController,
                      focusNode: userNamefocusNode,
                      decoration: InputDecoration(
                        hintText: 'Username',
                        contentPadding: EdgeInsets.only(bottom: 10),
                        isDense: true,
                        enabledBorder: UnderlineInputBorder(
                          borderSide: BorderSide(color: Color.fromARGB(255, 13, 17, 65)),
                        ),
                        focusedBorder: UnderlineInputBorder(
                          borderSide: BorderSide(color: Color.fromARGB(255, 13, 17, 65), width: 2),
                        ),
                      ),
                    )),
              ),
              Visibility(
                  visible: this.showUsernameError,
                  child: Container(
                    margin: EdgeInsets.symmetric(horizontal: 15),
                    alignment: Alignment.centerLeft,
                    child: Text(
                      'Username cannot be empty',
                      style: TextStyle(color: Colors.red[600]),
                    ),
                  )),
              Visibility(
                  visible: this.showIncorrectCredentials,
                  child: Container(
                    margin: EdgeInsets.symmetric(horizontal: 15),
                    alignment: Alignment.centerLeft,
                    child: Text(
                      'Incorrect username or password',
                      style: TextStyle(color: Colors.red[600]),
                    ),
                  )),
              Visibility(
                  visible: this.showPasswordField,
                  child: InkWell(
                    child: Container(
                        margin: EdgeInsets.symmetric(horizontal: 8),
                        alignment: Alignment.centerLeft,
                        child: Row(
                          children: [
                            Icon(
                              Icons.chevron_left,
                              size: 30,
                            ),
                            Text('Back')
                          ],
                        )),
                    onTap: () {
                      setState(() {
                        this.showPasswordError = false;
                        this.showPasswordField = false;
                        this.showUsernameField = true;
                      });
                    },
                  )),
              Visibility(
                visible: this.showPasswordField,
                child: Container(
                    margin: EdgeInsets.symmetric(vertical: 20, horizontal: 15),
                    width: MediaQuery.of(context).size.width - 30,
                    child: TextField(
                      controller: passwordTextController,
                      obscureText: true,
                      focusNode: passwordfocusNode,
                      decoration: InputDecoration(
                        hintText: 'Password',
                        contentPadding: EdgeInsets.only(bottom: 10),
                        isDense: true,
                        enabledBorder: UnderlineInputBorder(
                          borderSide: BorderSide(color: Color.fromARGB(255, 13, 17, 65)),
                        ),
                        focusedBorder: UnderlineInputBorder(
                          borderSide: BorderSide(color: Color.fromARGB(255, 13, 17, 65), width: 2),
                        ),
                      ),
                    )),
              ),
              Visibility(
                  visible: this.showPasswordError,
                  child: Container(
                    margin: EdgeInsets.symmetric(horizontal: 15),
                    alignment: Alignment.centerLeft,
                    child: Text(
                      'Password cannot be empty',
                      style: TextStyle(color: Colors.red[600]),
                    ),
                  )),
              Visibility(
                visible: this.formBeingSubmitted,
                child: Container(
                    margin: EdgeInsets.symmetric(vertical: 20, horizontal: 15),
                    width: MediaQuery.of(context).size.width - 30,
                    child: Text('Verifying information..')),
              ),
              InkWell(
                child: Opacity(
                  opacity: this.formBeingSubmitted ? 0.5 : 1,
                  child: AnimatedContainer(
                    duration: Duration(milliseconds: 200),
                    margin: EdgeInsets.symmetric(vertical: 20, horizontal: 15),
                    padding: EdgeInsets.symmetric(vertical: 10, horizontal: 10),
                    width: this.formBeingSubmitted ? 100 : MediaQuery.of(context).size.width - 20,
                    alignment: Alignment.center,
                    decoration:
                        BoxDecoration(color: Color.fromARGB(255, 13, 17, 65), borderRadius: BorderRadius.circular(5)),
                    child: this.formBeingSubmitted
                        ? SpinKitRing(
                            color: Colors.white,
                            size: 15,
                            lineWidth: 2,
                          )
                        : Text(
                            getCTAButtonText(),
                            style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 16),
                          ),
                  ),
                ),
                onTap: () {
                  setState(() {
                    if (!this.imageContainerShrinked) {
                      this.imageContainerShrinked = true;
                      this.showUsernameField = true;
                      userNamefocusNode.requestFocus();
                    } else if (this.showUsernameField == true) {
                      if (this.usernameTextController.text.trim() == '') {
                        this.showUsernameError = true;
                        userNamefocusNode.requestFocus();
                        return;
                      }
                      this.showIncorrectCredentials = false;
                      this.showUsernameError = false;
                      this.showUsernameField = false;
                      this.showPasswordField = true;
                    } else {
                      if (this.passwordTextController.text == '') {
                        this.showPasswordError = true;
                        passwordfocusNode.requestFocus();
                        return;
                      }
                      this.showPasswordError = false;
                      this.showPasswordField = false;
                      this.formBeingSubmitted = true;
                      loginUser();
                    }
                  });
                },
              ),
            ])
          : Container(
              alignment: Alignment.center,
              child: SpinKitRing(
                lineWidth: 2,
                color: Color.fromARGB(255, 13, 17, 65),
              ),
            ),
    );
  }
}
