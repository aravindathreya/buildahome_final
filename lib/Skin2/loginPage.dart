// Built in packages
import 'package:flutter/material.dart';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_spinkit/flutter_spinkit.dart';

// Custom dart files
import '../UserHome.dart';
import "../AdminDashboard.dart";
import '../services/data_provider.dart';

class LoginScreenNew extends StatefulWidget {
  @override
  LoginScreenNewState createState() {
    return LoginScreenNewState();
  }
}

class LoginScreenNewState extends State<LoginScreenNew> with SingleTickerProviderStateMixin {
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
  late AnimationController _scaleAnimationController;

  void initState() {
    super.initState();
    _scaleAnimationController = AnimationController(
      vsync: this,
      duration: Duration(milliseconds: 1500),
    )..repeat(reverse: true);
    checkIfAlreadyLoggedIn();
  }

  @override
  void dispose() {
    _scaleAnimationController.dispose();
    userNamefocusNode.dispose();
    passwordfocusNode.dispose();
    usernameTextController.dispose();
    passwordTextController.dispose();
    super.dispose();
  }

  checkIfAlreadyLoggedIn() async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    var username = prefs.getString('username');
    var role = prefs.getString('role');

    setState(() {
      if (username != null) {
        this.showLoginForm = false;
        // Initialize data provider on app load with force reload
        DataProvider().initializeData(force: true).then((_) {
          _scaleAnimationController.stop();
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
        });
      } else {
        _scaleAnimationController.stop();
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
    var url = Uri.parse('https://office.buildahome.in/API/login');
    var response =
        await http.post(url, body: {'username': usernameTextController.text, 'password': passwordTextController.text},);
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
          await setSharedPrefs(
              usernameTextController.text,
              jsonDecodedResponse['role'],
              jsonDecodedResponse['project_id'],
              jsonDecodedResponse['project_value'],
              jsonDecodedResponse['completed_percentage'],
              jsonDecodedResponse['user_id'],
              jsonDecodedResponse['location'],
              jsonDecodedResponse['api_token']);

          // Initialize data provider after login
          await DataProvider().initializeData();

          Navigator.pushReplacement(
            context,
            MaterialPageRoute(builder: (context) => Home()),
          );
        } else {
          await setSharedPrefs(usernameTextController.text, jsonDecodedResponse['role'], '', '', '',
              jsonDecodedResponse["user_id"], '', jsonDecodedResponse['api_token']);

          // Initialize data provider after login with force reload
          await DataProvider().initializeData(force: true);

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
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Stack(
        children: [
          // Background image - always visible, edge-to-edge without cropping with opacity 0.3
          Positioned.fill(
            child: Opacity(
              opacity: 0.3,
              child: Image.asset(
                'assets/images/Reveal Image.jpg',
                fit: BoxFit.cover,
                width: double.infinity,
                height: double.infinity,
                errorBuilder: (context, error, stackTrace) {
                  return Container(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [
                          Colors.white,
                          Color.fromARGB(255, 250, 250, 255),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
          // Semi-transparent overlay for better content readability
          Positioned.fill(
            child: Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Colors.transparent,
                    Colors.white.withOpacity(0.7),
                  ],
                ),
              ),
            ),
          ),
          // Content overlay
          this.showLoginForm
              ? SingleChildScrollView(
                  child: Container(
                    height: MediaQuery.of(context).size.height,
                    child: Column(
                      children: [
                        // Spacer for image area
                        AnimatedContainer(
                          height: this.imageContainerShrinked
                              ? MediaQuery.of(context).size.height * .25
                              : MediaQuery.of(context).size.height * .5,
                          duration: Duration(milliseconds: 400),
                          curve: Curves.easeInOutCubic,
                          child: Container(
                            padding: this.imageContainerShrinked ? EdgeInsets.only(top: 40) : EdgeInsets.all(40),
                          ),
                        ),

                AnimatedSwitcher(
                  duration: Duration(milliseconds: 300),
                  transitionBuilder: (Widget child, Animation<double> animation) {
                    return FadeTransition(
                      opacity: animation,
                      child: SlideTransition(
                        position: Tween<Offset>(
                          begin: Offset(0.0, 0.3),
                          end: Offset.zero,
                        ).animate(CurvedAnimation(
                          parent: animation,
                          curve: Curves.easeOutCubic,
                        )),
                        child: child,
                      ),
                    );
                  },
                  child: this.showUsernameField
                      ? Container(
                          key: ValueKey('username'),
                          margin: EdgeInsets.symmetric(vertical: 10, horizontal: 20),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              TextField(
                                controller: usernameTextController,
                                focusNode: userNamefocusNode,
                                style: TextStyle(fontSize: 16),
                                decoration: InputDecoration(
                                  hintText: 'Username',
                                  prefixIcon: Icon(Icons.person_outline, color: Color.fromARGB(255, 13, 17, 65)),
                                  filled: true,
                                  fillColor: Colors.white,
                                  border: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(16),
                                    borderSide: BorderSide.none,
                                  ),
                                  enabledBorder: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(16),
                                    borderSide: BorderSide(color: Colors.grey[300]!, width: 1),
                                  ),
                                  focusedBorder: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(16),
                                    borderSide: BorderSide(color: Color.fromARGB(255, 13, 17, 65), width: 2),
                                  ),
                                  contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 16),
                                ),
                              ),
                              if (this.showUsernameError)
                                Padding(
                                  padding: EdgeInsets.only(top: 8, left: 16),
                                  child: TweenAnimationBuilder<double>(
                                    tween: Tween(begin: 0.0, end: 1.0),
                                    duration: Duration(milliseconds: 200),
                                    builder: (context, value, child) {
                                      return Opacity(
                                        opacity: value,
                                        child: Row(
                                          children: [
                                            Icon(Icons.error_outline, size: 16, color: Colors.red[600]),
                                            SizedBox(width: 4),
                                            Text(
                                              'Username cannot be empty',
                                              style: TextStyle(color: Colors.red[600], fontSize: 12),
                                            ),
                                          ],
                                        ),
                                      );
                                    },
                                  ),
                                ),
                              if (this.showIncorrectCredentials)
                                Padding(
                                  padding: EdgeInsets.only(top: 8, left: 16),
                                  child: TweenAnimationBuilder<double>(
                                    tween: Tween(begin: 0.0, end: 1.0),
                                    duration: Duration(milliseconds: 200),
                                    builder: (context, value, child) {
                                      return Opacity(
                                        opacity: value,
                                        child: Row(
                                          children: [
                                            Icon(Icons.error_outline, size: 16, color: Colors.red[600]),
                                            SizedBox(width: 4),
                                            Text(
                                              'Incorrect username or password',
                                              style: TextStyle(color: Colors.red[600], fontSize: 12),
                                            ),
                                          ],
                                        ),
                                      );
                                    },
                                  ),
                                ),
                            ],
                          ),
                        )
                      : SizedBox.shrink(),
                ),
                AnimatedSwitcher(
                  duration: Duration(milliseconds: 300),
                  transitionBuilder: (Widget child, Animation<double> animation) {
                    return FadeTransition(
                      opacity: animation,
                      child: SlideTransition(
                        position: Tween<Offset>(
                          begin: Offset(0.0, 0.3),
                          end: Offset.zero,
                        ).animate(CurvedAnimation(
                          parent: animation,
                          curve: Curves.easeOutCubic,
                        )),
                        child: child,
                      ),
                    );
                  },
                  child: this.showPasswordField
                      ? Container(
                          key: ValueKey('password'),
                          margin: EdgeInsets.symmetric(vertical: 10, horizontal: 20),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              InkWell(
                                onTap: () {
                                  setState(() {
                                    this.showPasswordError = false;
                                    this.showPasswordField = false;
                                    this.showUsernameField = true;
                                  });
                                },
                                child: Container(
                                  margin: EdgeInsets.only(bottom: 8),
                                  padding: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                  child: Row(
                                    children: [
                                      Icon(Icons.arrow_back_ios, size: 16, color: Color.fromARGB(255, 13, 17, 65)),
                                      SizedBox(width: 4),
                                      Text(
                                        'Back',
                                        style: TextStyle(
                                          color: Color.fromARGB(255, 13, 17, 65),
                                          fontSize: 14,
                                          fontWeight: FontWeight.w500,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                              TextField(
                                controller: passwordTextController,
                                obscureText: true,
                                focusNode: passwordfocusNode,
                                style: TextStyle(fontSize: 16),
                                decoration: InputDecoration(
                                  hintText: 'Password',
                                  prefixIcon: Icon(Icons.lock_outline, color: Color.fromARGB(255, 13, 17, 65)),
                                  filled: true,
                                  fillColor: Colors.white,
                                  border: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(16),
                                    borderSide: BorderSide.none,
                                  ),
                                  enabledBorder: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(16),
                                    borderSide: BorderSide(color: Colors.grey[300]!, width: 1),
                                  ),
                                  focusedBorder: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(16),
                                    borderSide: BorderSide(color: Color.fromARGB(255, 13, 17, 65), width: 2),
                                  ),
                                  contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 16),
                                ),
                              ),
                              if (this.showPasswordError)
                                Padding(
                                  padding: EdgeInsets.only(top: 8, left: 16),
                                  child: TweenAnimationBuilder<double>(
                                    tween: Tween(begin: 0.0, end: 1.0),
                                    duration: Duration(milliseconds: 200),
                                    builder: (context, value, child) {
                                      return Opacity(
                                        opacity: value,
                                        child: Row(
                                          children: [
                                            Icon(Icons.error_outline, size: 16, color: Colors.red[600]),
                                            SizedBox(width: 4),
                                            Text(
                                              'Password cannot be empty',
                                              style: TextStyle(color: Colors.red[600], fontSize: 12),
                                            ),
                                          ],
                                        ),
                                      );
                                    },
                                  ),
                                ),
                            ],
                          ),
                        )
                      : SizedBox.shrink(),
                ),
                if (this.formBeingSubmitted)
                  Container(
                    margin: EdgeInsets.symmetric(vertical: 10, horizontal: 20),
                    child: TweenAnimationBuilder<double>(
                      tween: Tween(begin: 0.0, end: 1.0),
                      duration: Duration(milliseconds: 300),
                      builder: (context, value, child) {
                        return Opacity(
                          opacity: value,
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              SpinKitRing(
                                color: Color.fromARGB(255, 13, 17, 65),
                                size: 20,
                                lineWidth: 2,
                              ),
                              SizedBox(width: 12),
                              Text(
                                'Verifying information...',
                                style: TextStyle(
                                  color: Color.fromARGB(255, 13, 17, 65),
                                  fontSize: 14,
                                ),
                              ),
                            ],
                          ),
                        );
                      },
                    ),
                  ),
                Container(
                  margin: EdgeInsets.symmetric(vertical: 20, horizontal: 20),
                  child: TweenAnimationBuilder<double>(
                    tween: Tween(begin: 0.0, end: 1.0),
                    duration: Duration(milliseconds: 400),
                    curve: Curves.easeOut,
                    builder: (context, value, child) {
                      return Transform.scale(
                        scale: 0.8 + (0.2 * value),
                        child: Opacity(
                          opacity: value,
                          child: Material(
                            color: Colors.transparent,
                            child: InkWell(
                              onTap: this.formBeingSubmitted
                                  ? null
                                  : () {
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
                              borderRadius: BorderRadius.circular(16),
                              child: AnimatedContainer(
                                duration: Duration(milliseconds: 200),
                                curve: Curves.easeInOut,
                                padding: EdgeInsets.symmetric(vertical: 16, horizontal: 24),
                                width: double.infinity,
                                decoration: BoxDecoration(
                                  gradient: LinearGradient(
                                    colors: [
                                      Color.fromARGB(255, 13, 17, 65),
                                      Color.fromARGB(255, 20, 25, 80),
                                    ],
                                  ),
                                  borderRadius: BorderRadius.circular(16),
                                  boxShadow: [
                                    BoxShadow(
                                      color: Color.fromARGB(255, 13, 17, 65).withOpacity(0.3),
                                      blurRadius: 12,
                                      offset: Offset(0, 4),
                                    ),
                                  ],
                                ),
                                child: this.formBeingSubmitted
                                    ? Center(
                                        child: SpinKitRing(
                                          color: Colors.white,
                                          size: 20,
                                          lineWidth: 2,
                                        ),
                                      )
                                    : Center(
                                        child: Text(
                                          getCTAButtonText(),
                                          style: TextStyle(
                                            color: Colors.white,
                                            fontWeight: FontWeight.w600,
                                            fontSize: 16,
                                            letterSpacing: 0.5,
                                          ),
                                        ),
                                      ),
                              ),
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                        ),
                      ],
                    ),
                  ),
                )
              : Center(
                  child: AnimatedBuilder(
                    animation: _scaleAnimationController,
                    builder: (context, child) {
                      // Scale from 1.3 to 1.0 (scale out effect)
                      final scale = 1.3 - (0.3 * _scaleAnimationController.value);
                      return Transform.scale(
                        scale: scale,
                        child: Opacity(
                          opacity: 0.9 + (0.1 * _scaleAnimationController.value),
                          child: Container(
                            width: MediaQuery.of(context).size.width * 0.75,
                            height: MediaQuery.of(context).size.width * 0.6,
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                begin: Alignment.topLeft,
                                end: Alignment.bottomRight,
                                colors: [
                                  Colors.white,
                                  Color.fromARGB(255, 250, 250, 255),
                                ],
                              ),
                              borderRadius: BorderRadius.circular(20),
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                ),
        ],
      ),
    );
  }
}
