
import 'package:buildahome/NonTenderTasks.dart';
import 'package:flutter/material.dart';
import 'package:flutter_spinkit/flutter_spinkit.dart';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:percent_indicator/linear_percent_indicator.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';
import "Payments.dart";
import 'NonTenderTasks.dart';
import 'Drawings.dart';
import 'NotesAndComments.dart';

class UserDashboardScreen extends StatefulWidget {
  @override
  UserDashboardScreenState createState() {
    return UserDashboardScreenState();
  }
}

class UserDashboardScreenState extends State<UserDashboardScreen> {
  List dailyUpdateList = [];
  var username = ' ';
  var updatePostedOnDate = " ";
  var value = " ";
  var completed = "0";
  var updateResponseBody;
  var blocked = false;
  var bolckReason = '';
  var location = '';

  @override
  void initState() {
    super.initState();
    set_project_status();

    call();
  }

  // ignore: non_constant_identifier_names
  set_project_status() async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    var id = prefs.getString('project_id');
    var statusUrl = 'https://office.buildahome.in/API/get_project_block_status?project_id=${id}';
    var statusResponse = await http.get(Uri.parse(statusUrl));
    var statusResponseBody = jsonDecode(statusResponse.body);
    if (statusResponseBody['status'] == 'blocked') {
      setState(() {
        blocked = true;
        bolckReason = statusResponseBody['reason'];
      });
    }
  }

  call() async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    var id = prefs.getString('project_id');
    var role = prefs.getString('role');
    if (prefs.containsKey("client_name")) {
      username = prefs.getString('client_name')!;
    } else {
      username = prefs.getString('username')!;
    }
    setState(() {
      
    });

    if (role == 'Client') {
      // final FirebaseMessaging _messaging = FirebaseMessaging();
      // _messaging.subscribeToTopic(username);
    }

    var locationUrl = 'https://office.buildahome.in/API/get_project_location?id=${id}';
    var locResponse = await http.get(Uri.parse(locationUrl));
    if (locResponse.body.trim() != "" && locResponse.statusCode == 200) {
      setState(() {
        location = locResponse.body.trim();
      });
    }

    var url = 'https://office.buildahome.in/API/latest_update?id=${id}';
    var response = await http.get(Uri.parse(url));
    print(response.body);
    if (response.body.trim() != "No updates") {
      updateResponseBody = jsonDecode(response.body);
    }
    var projectCompletionPercentage;
    if (prefs.containsKey("completed")) {
      projectCompletionPercentage = prefs.getString('completed');
      var url = 'https://office.buildahome.in/API/get_project_percentage?id=${id}';
      var percResponse = await http.get(Uri.parse(url));
      prefs.setString('completed', percResponse.body);
    } else {
      var url = 'https://office.buildahome.in/API/get_project_percentage?id=${id}';
      var percResponse = await http.get(Uri.parse(url));
      projectCompletionPercentage = percResponse.body;
    }

    setState(() {
      if (prefs.getString('project_value') != null) value = prefs.getString('project_value')!;
      completed = projectCompletionPercentage;

      if (response.body.trim() == "No updates") {
        dailyUpdateList = [];
        dailyUpdateList.add('No updates for today yet');
        updatePostedOnDate = DateFormat("EEEE dd MMMM").format(DateTime.now()).toString();
      } else {
        dailyUpdateList = [];
        for (int x = 0; x < updateResponseBody.length; x++) {
          if (dailyUpdateList.contains(updateResponseBody[x]['update_title']) == false) {
            dailyUpdateList.add(updateResponseBody[x]['update_title']);
          }
        }
        updatePostedOnDate = updateResponseBody[0]['date'];
      }
    });
  }

  Widget build(BuildContext context) {
    return Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.bottomCenter,
            end: Alignment.topCenter,
            colors: [
              const Color.fromARGB(221, 0, 0, 0),
              const Color.fromARGB(255, 29, 28, 28)!,
              Colors.black,
            ],
          ),
        ),
        child: ListView(
          children: <Widget>[
            Container(
              margin: EdgeInsets.symmetric(horizontal: 17),
              child: Container(
                padding: EdgeInsets.only(top: 20),
                child: Text("Project for $username", style: TextStyle(fontSize: 18, fontWeight: FontWeight.w500, color: Color.fromARGB(255, 204, 204, 204))),
              ),
            ),
            Visibility(
                visible: location.isNotEmpty,
                child: InkWell(
                  child: Container(
                    padding: EdgeInsets.only(left: 15, bottom: 15),
                    child: Row(
                      children: [
                        Icon(Icons.location_on, color: Colors.red[500]),
                        SizedBox(
                          width: 2,
                        ),
                        Text('Open project location in map', style: TextStyle(color: const Color.fromARGB(255, 199, 199, 199)),)
                      ],
                    ),
                  ),
                  onTap: () async {
                    await launchUrl(Uri.parse(location), mode: LaunchMode.externalApplication);
                  },
                )),
            Container(
              padding: EdgeInsets.symmetric(horizontal: 20),
              child: Column(
                children: <Widget>[
                  // Container(
                  //   margin: EdgeInsets.only(bottom: 20),
                  //   child: Stack(
                  //     alignment: Alignment.bottomRight,
                  //     children: [
                  //       Opacity(
                  //         opacity: blocked ? 0.5 : 1,
                  //         child: Container(
                  //           width: MediaQuery.of(context).size.width - 40,
                  //           height: MediaQuery.of(context).size.width - 40,
                  //           decoration: BoxDecoration(
                  //               color: Colors.grey[200],
                  //               border: Border.all(width: 1, color: Colors.grey[200]!),
                  //               borderRadius: BorderRadius.circular(5)),
                  //           child: Image.network("https://office.buildahome.in/static/files/mobile_banner.png"),
                  //         ),
                  //       ),
                  //       Opacity(opacity: 0.7, child: Container(height: 27, width: 90, color: Colors.black)),
                  //       Container(
                  //           padding: EdgeInsets.all(5),
                  //           child: Text("buildAhome",
                  //               style: TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w500))),
                  //     ],
                  //   ),
                  // ),
                  if (blocked == true)
                    Column(
                      children: [
                        Container(alignment: Alignment.centerLeft, child: Text("Project blocked", style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.red))),
                        Container(
                            alignment: Alignment.centerLeft,
                            margin: EdgeInsets.only(bottom: 15),
                            child: Text("Reason : " + bolckReason.toString(), style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.red))),
                      ],
                    ),
                  Container(padding: EdgeInsets.only(top: 15), alignment: Alignment.centerLeft, child: Text("Completion percentage of project: ", style: TextStyle(fontSize: 16, color: const Color.fromARGB(255, 199, 199, 199)))),
                  Container(
                    padding: EdgeInsets.only(top: 10, bottom: 10, left: 0, right: 0),
                    child: Center(
                      child: LinearPercentIndicator(
                        padding: EdgeInsets.all(0),
                        lineHeight: 28.0,
                        percent: (int.parse(completed.toString()) / 100),
                        center: Column(
                          children: <Widget>[
                            Container(
                              padding: EdgeInsets.only(top: 5),
                              child: Text(
                                completed.toString() + " % Completed",
                                style: TextStyle(
                                  fontSize: 14,
                                  color: Colors.white,
                                  fontWeight: FontWeight.normal,
                                ),
                              ),
                            ),
                          ],
                        ),
                        animation: true,
                        animationDuration: 1500,
                        backgroundColor: Colors.grey[400],
                        progressColor: Color.fromARGB(255, 17, 0, 80),
                      ),
                    ),
                  ),
                  updatePostedOnDate == ' '
                      ? Container(
                          margin: EdgeInsets.only(top: 30, bottom: 100),
                          child: Container(
                            margin: EdgeInsets.only(top: 30),
                            child: SpinKitRing(
                              size: 80,
                              color: Colors.white,
                              lineWidth: 2,
                            ),
                          ))
                      : AnimatedWidgetSlide(
                          direction: SlideDirection.bottomToTop, // Specify the slide direction
                          duration: Duration(milliseconds: 500), // Adjust the duration as needed
                          child: Column(
                            children: [
                              Container(
                                alignment: Alignment.topLeft,
                                padding: EdgeInsets.all(15),
                                margin: EdgeInsets.only(top: 30, bottom: 20),
                                decoration: BoxDecoration(
                                  color: Color.fromARGB(255, 7, 0, 73),
                                  border: Border.all(color: Colors.black, width: 0.3),
                                  borderRadius: BorderRadius.circular(5),
                                ),
                                child: Column(
                                  children: <Widget>[
                                    Row(
                                      children: <Widget>[
                                        Row(
                                          children: <Widget>[
                                            Icon(
                                              Icons.event_note,
                                              color: Colors.white,
                                            ),
                                            Container(
                                              padding: EdgeInsets.only(left: 10),
                                              child: Text(updatePostedOnDate, style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: Colors.white)),
                                            )
                                          ],
                                        ),
                                      ],
                                    ),
                                    Container(
                                        alignment: Alignment.centerLeft,
                                        padding: EdgeInsets.only(top: 10),
                                        child: Container(
                                          height: 1,
                                          color: Colors.black,
                                        )),
                                    if (updateResponseBody != null && updateResponseBody.length > 0 && updateResponseBody[0]['tradesmenMap'].toString().length > 0)
                                      Container(
                                        alignment: Alignment.topLeft,
                                        padding: EdgeInsets.only(top: 10),
                                        child: Text(updateResponseBody[0]['tradesmenMap'].toString().trim() == 'null' ? '' : updateResponseBody[0]['tradesmenMap'].toString().trim(),
                                            style: TextStyle(
                                              fontSize: 14,
                                              color: const Color.fromARGB(255, 255, 255, 255),
                                            )),
                                      ),
                                    ListView.builder(
                                        physics: NeverScrollableScrollPhysics(),
                                        shrinkWrap: true,
                                        itemCount: dailyUpdateList == null ? 0 : dailyUpdateList.length,
                                        itemBuilder: (BuildContext ctxt, int Index) {
                                          return Row(
                                            crossAxisAlignment: CrossAxisAlignment.start,
                                            children: <Widget>[
                                              Container(
                                                alignment: Alignment.topLeft,
                                                padding: EdgeInsets.only(top: 10),
                                                width: MediaQuery.of(context).size.width - 120,
                                                child: Text(dailyUpdateList[Index].toString(), style: TextStyle(fontSize: 14, color: Colors.white)),
                                              )
                                            ],
                                          );
                                        }),
                                  ],
                                ),
                              ),
                              Container(
                                margin: EdgeInsets.only(bottom: 20),
                                child: Row(
                                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                  children: [
                                    InkWell(
                                      child: Container(
                                        alignment: Alignment.center,
                                          width: (MediaQuery.of(context).size.width - 70) / 2,
                                          height: (MediaQuery.of(context).size.width - 120) / 2,
                                          margin: EdgeInsets.all(5),
                                          padding: EdgeInsets.all(20),
                                          decoration: BoxDecoration(
                                            color: Color.fromARGB(255, 34, 34, 34),
                                            borderRadius: BorderRadius.circular(5),
                                          ),
                                          child: Column(
                                            mainAxisAlignment: MainAxisAlignment.center,
                                            children: [
                                              Icon(Icons.percent, size: 30, color: Colors.white),
                                              Container(
                                                margin: EdgeInsets.only(top: 10),
                                                child: Text('Payments', style: TextStyle(color: Colors.white),),
                                              )
                                            ],
                                          )),
                                      onTap: () {
                                        Navigator.push(
                                          context,
                                          MaterialPageRoute(builder: (context) => PaymentTaskWidget()),
                                        );
                                      },
                                    ),
                                    InkWell(
                                      child: Container(
                                          width: (MediaQuery.of(context).size.width - 70) / 2,
                                          height: (MediaQuery.of(context).size.width - 120) / 2,
                                          margin: EdgeInsets.all(5),
                                          padding: EdgeInsets.all(20),
                                          decoration: BoxDecoration(
                                            color: Color.fromARGB(255, 34, 34, 34),
                                            borderRadius: BorderRadius.circular(5),
                                          ),
                                          child: Column(
                                            mainAxisAlignment: MainAxisAlignment.center,
                                            children: [
                                              Icon(Icons.currency_rupee, size: 30, color: Colors.white),
                                              Container(
                                                margin: EdgeInsets.only(top: 10),
                                                child: Text('Non Tender Payments', textAlign: TextAlign.center, style: TextStyle(color: Colors.white),),
                                              )
                                            ],
                                          )),
                                      onTap: () {
                                        Navigator.push(
                                          context,
                                          MaterialPageRoute(builder: (context) => NonTenderTaskWidget()),
                                        );
                                      },
                                    ),
                                  ],
                                ),
                              ),
                              Container(
                                margin: EdgeInsets.only(bottom: 100),
                                child: Row(
                                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                  children: [
                                    InkWell(
                                      child: Container(
                                        alignment: Alignment.center,
                                          width: (MediaQuery.of(context).size.width - 70) / 2,
                                          height: (MediaQuery.of(context).size.width - 120) / 2,
                                          margin: EdgeInsets.all(5),
                                          padding: EdgeInsets.all(20),
                                          decoration: BoxDecoration(
                                            color: Color.fromARGB(255, 34, 34, 34),
                                            borderRadius: BorderRadius.circular(5),
                                          ),
                                          child: Column(
                                            mainAxisAlignment: MainAxisAlignment.center,
                                            children: [
                                              Icon(Icons.book, size: 30, color: Colors.white),
                                              Container(
                                                margin: EdgeInsets.only(top: 10),
                                                child: Text('Documents', style: TextStyle(color: Colors.white),),
                                              )
                                            ],
                                          )),
                                      onTap: () {
                                        Navigator.push(
                                          context,
                                          MaterialPageRoute(builder: (context) => Documents()),
                                        );
                                      },
                                    ),
                                    InkWell(
                                      child: Container(
                                          width: (MediaQuery.of(context).size.width - 70) / 2,
                                          height: (MediaQuery.of(context).size.width - 120) / 2,
                                          margin: EdgeInsets.all(5),
                                          padding: EdgeInsets.all(20),
                                          decoration: BoxDecoration(
                                            color: Color.fromARGB(255, 34, 34, 34),
                                            borderRadius: BorderRadius.circular(5),
                                          ),
                                          child: Column(
                                            mainAxisAlignment: MainAxisAlignment.center,
                                            children: [
                                              Icon(Icons.book, size: 30, color: Colors.white),
                                              Container(
                                                margin: EdgeInsets.only(top: 10),
                                                child: Text('Notes', textAlign: TextAlign.center, style: TextStyle(color: Colors.white),),
                                              )
                                            ],
                                          )),
                                      onTap: () {
                                        Navigator.push(
                                          context,
                                          MaterialPageRoute(builder: (context) => NotesAndComments()),
                                        );
                                      },
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          )),
                ],
              ),
            )
          ],
        ));
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
