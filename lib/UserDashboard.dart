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
  var expanded = false;

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

    this.expanded = true;
    setState(() {});

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
    if (response.body.trim() != "No updates") {
      updateResponseBody = jsonDecode(response.body);
    }
    var projectCompletionPercentage;
    if (prefs.containsKey("completed")) {
      print('projectCompletionPercentage');
      projectCompletionPercentage = prefs.getString('completed');
      print(projectCompletionPercentage);
      setState(() {});
      var url = 'https://office.buildahome.in/API/get_project_percentage?id=${id}';
      var percResponse = await http.get(Uri.parse(url));
      prefs.setString('completed', percResponse.body);
    } else {
      var url = 'https://office.buildahome.in/API/get_project_percentage?id=${id}';
      var percResponse = await http.get(Uri.parse(url));
      projectCompletionPercentage = percResponse.body;
      prefs.setString('completed', percResponse.body);
    }

    setState(() {
      if (prefs.getString('project_value') != null) value = prefs.getString('project_value')!;
      completed = projectCompletionPercentage;

      if (response.body.trim() == "No updates") {
        dailyUpdateList = [];
        dailyUpdateList.add('Stay tuned for updates about your home');
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
          // gradient: LinearGradient(
          //   begin: Alignment.bottomCenter,
          //   end: Alignment.topCenter,
          //   colors: [
          //     const Color.fromARGB(221, 0, 0, 0),
          //     const Color.fromARGB(255, 29, 28, 28)!,
          //     Colors.black,
          //   ],
          // ),
          color: Color.fromARGB(255, 233, 233, 233),
        ),
        child: ListView(
          children: <Widget>[
            AnimatedWidgetSlide(
                direction: SlideDirection.topToBottom, // Specify the slide direction
                duration: Duration(milliseconds: 300), // Adjust the duration as needed
                child: Column(
                  children: [
                    Container(
                      margin: EdgeInsets.symmetric(horizontal: 17),
                      child: Container(
                        padding: EdgeInsets.only(top: 20, left: 3, bottom: 10),
                        child: Text("${username.split('-')[0].trim()}'s Home", style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600, color: Color.fromARGB(255, 0, 0, 0))),
                      ),
                    ),
                    Visibility(
                        visible: location.isNotEmpty,
                        child: InkWell(
                          child: Container(
                            padding: EdgeInsets.only(left: 15, bottom: 15, top: 10),
                            child: Row(
                              children: [
                                Icon(Icons.location_on, color: Color.fromARGB(255, 255, 41, 25)),
                                SizedBox(
                                  width: 2,
                                ),
                                Container(
                                  margin: EdgeInsets.only(top: 5),
                                  child: Text(
                                    'Open Home in map',
                                    style: TextStyle(color: Color.fromARGB(255, 0, 0, 0), fontSize: 14),
                                  ),
                                )
                              ],
                            ),
                          ),
                          onTap: () async {
                            await launchUrl(Uri.parse(location), mode: LaunchMode.externalApplication);
                          },
                        )),
                    AnimatedContainer(
                      duration: Duration(milliseconds: 400),
                      width: expanded ? MediaQuery.of(context).size.width - 40 : 30,
                      child: Container(
                        margin: EdgeInsets.only(bottom: 20),
                        child: Stack(
                          alignment: Alignment.bottomRight,
                          children: [
                            Opacity(
                              opacity: blocked ? 0.5 : 1,
                              child: Container(
                                width: MediaQuery.of(context).size.width - 40,
                                decoration: BoxDecoration(
                                    color: Color.fromARGB(255, 214, 214, 214),
                                    border: Border.all(width: 1, color: Colors.grey[200]!),
                                    borderRadius: BorderRadius.circular(10),
                                    gradient: LinearGradient(colors: [Color.fromARGB(255, 214, 214, 214), Color.fromARGB(255, 233, 233, 233)], begin: Alignment.topLeft, end: Alignment.bottomRight)),
                                child: Image.network("https://office.buildahome.in/static/files/mobile_banner.png", fit: BoxFit.contain),
                                // child: Image.network("https://media.istockphoto.com/id/471493324/photo/modern-australian-home.webp?b=1&s=170667a&w=0&k=20&c=p0om_AWyA0_hJP-yKTlYKBt9DRBa4SpFWPXYhXq8JGk="),
                              ),
                            ),
                            Opacity(opacity: 1, child: Container(height: 27, width: 90, color: Colors.black)),
                            expanded ? Container(padding: EdgeInsets.all(5), child: Text("buildAhome", style: TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w500))) : Container(),
                          ],
                        ),
                      ),
                    ),
                  ],
                )),
            Container(
              padding: EdgeInsets.symmetric(horizontal: 20),
              child: Column(
                children: <Widget>[
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
                  Container(
                    padding: EdgeInsets.all(10),
                    decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(5), color: Color.fromARGB(255, 240, 237, 202), gradient: LinearGradient(colors: [Color.fromARGB(255, 245, 241, 194), Color.fromARGB(255, 250, 248, 228)])),
                    child: Column(children: [
                      Container(
                          padding: EdgeInsets.only(top: 15),
                          alignment: Alignment.centerLeft,
                          child: Text("Your Home is ${completed.toString()}% complete", style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Color.fromARGB(255, 34, 34, 34)))),
                      Container(
                        padding: EdgeInsets.only(top: 10, bottom: 10, left: 0, right: 0),
                        child: Center(
                          child: LinearPercentIndicator(
                            barRadius: Radius.circular(5),
                            padding: EdgeInsets.all(0),
                            lineHeight: 5.0,
                            percent: (int.parse(completed.toString()) / 100),
                            center: Column(
                              children: <Widget>[
                                Container(
                                  padding: EdgeInsets.only(top: 5),
                                  // child: Text(
                                  //   completed.toString() + " % Completed",
                                  //   style: TextStyle(
                                  //     fontSize: 14,
                                  //     color: Colors.white,
                                  //     fontWeight: FontWeight.normal,
                                  //   ),
                                  // ),
                                ),
                              ],
                            ),
                            animation: true,
                            animationDuration: 300,
                            backgroundColor: Color.fromARGB(255, 201, 201, 201),
                            progressColor: Color.fromARGB(255, 0, 0, 0),
                            clipLinearGradient: true,
                          ),
                        ),
                      ),
                    ]),
                  ),
                  AnimatedWidgetSlide(
                      direction: SlideDirection.bottomToTop, // Specify the slide direction
                      duration: Duration(milliseconds: 300), // Adjust the duration as needed
                      child: Column(
                        children: [
                          Container(
                            margin: EdgeInsets.only(bottom: 10, top: 20),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                InkWell(
                                  child: Column(
                                    mainAxisAlignment: MainAxisAlignment.start,
                                    children: [
                                      Container(
                                          alignment: Alignment.center,
                                          width: (MediaQuery.of(context).size.width / 3) - 25,
                                          height: (MediaQuery.of(context).size.width - 120) / 3,
                                          margin: EdgeInsets.all(5),
                                          padding: EdgeInsets.all(20),
                                          decoration: BoxDecoration(
                                              color: Color.fromARGB(255, 219, 219, 219),
                                              borderRadius: BorderRadius.circular(10),
                                              gradient: LinearGradient(colors: [
                                                Color.fromARGB(255, 219, 219, 219),
                                                Color.fromARGB(255, 190, 190, 190),
                                              ], begin: Alignment.topCenter, end: Alignment.bottomCenter)),
                                          child: Column(
                                            mainAxisAlignment: MainAxisAlignment.center,
                                            children: [
                                              Container(
                                                child: Image(
                                                  height: 50, // Set your height according to aspect ratio or fixed height
                                                  width: 50,
                                                  image: AssetImage('assets/images/Payments.png'),
                                                ),
                                              )
                                              // Icon(Icons.percent, size: 40, color: Color.fromARGB(255, 33, 0, 87)),
                                            ],
                                          )),
                                      Container(
                                        margin: EdgeInsets.only(top: 10),
                                        child: Text(
                                          'Payments',
                                          style: TextStyle(color: Color.fromARGB(255, 41, 41, 41)),
                                        ),
                                      )
                                    ],
                                  ),
                                  onTap: () {
                                    Navigator.push(
                                      context,
                                      MaterialPageRoute(builder: (context) => PaymentTaskWidget()),
                                    );
                                  },
                                ),
                                InkWell(
                                  child: Column(
                                    mainAxisAlignment: MainAxisAlignment.start,
                                    children: [
                                      Container(
                                          alignment: Alignment.center,
                                          width: (MediaQuery.of(context).size.width / 3) - 25,
                                          height: (MediaQuery.of(context).size.width - 120) / 3,
                                          margin: EdgeInsets.all(5),
                                          padding: EdgeInsets.all(20),
                                          decoration: BoxDecoration(
                                              color: Color.fromARGB(255, 219, 219, 219),
                                              borderRadius: BorderRadius.circular(10),
                                              gradient: LinearGradient(colors: [
                                                Color.fromARGB(255, 219, 219, 219),
                                                Color.fromARGB(255, 190, 190, 190),
                                              ], begin: Alignment.topCenter)),
                                          child: Column(
                                            mainAxisAlignment: MainAxisAlignment.center,
                                            children: [
                                              Container(
                                                child: Image(
                                                  height: 50, // Set your height according to aspect ratio or fixed height
                                                  width: 50,
                                                  image: AssetImage('assets/images/Non tender.png'),
                                                ),
                                              )
                                              // Icon(Icons.currency_rupee, size: 40, color: Color.fromARGB(255, 50, 151, 29)),
                                            ],
                                          )),
                                      Container(
                                        width: (MediaQuery.of(context).size.width - 60) / 4,
                                        margin: EdgeInsets.only(top: 10),
                                        child: Text(
                                          'Non Tender Payments',
                                          textAlign: TextAlign.center,
                                          style: TextStyle(color: Color.fromARGB(255, 41, 41, 41)),
                                        ),
                                      )
                                    ],
                                  ),
                                  onTap: () {
                                    Navigator.push(
                                      context,
                                      MaterialPageRoute(builder: (context) => NonTenderTaskWidget()),
                                    );
                                  },
                                ),
                                InkWell(
                                  child: Column(
                                    mainAxisAlignment: MainAxisAlignment.start,
                                    children: [
                                      Container(
                                          alignment: Alignment.center,
                                          width: (MediaQuery.of(context).size.width / 3) - 25,
                                          height: (MediaQuery.of(context).size.width - 120) / 3,
                                          margin: EdgeInsets.all(5),
                                          padding: EdgeInsets.all(20),
                                          decoration: BoxDecoration(
                                              color: Color.fromARGB(255, 219, 219, 219),
                                              borderRadius: BorderRadius.circular(10),
                                              gradient: LinearGradient(colors: [
                                                Color.fromARGB(255, 219, 219, 219),
                                                Color.fromARGB(255, 190, 190, 190),
                                              ], begin: Alignment.topCenter, end: Alignment.bottomCenter)),
                                          child: Column(
                                            mainAxisAlignment: MainAxisAlignment.center,
                                            children: [
                                              Container(
                                                child: Image(
                                                  height: 50, // Set your height according to aspect ratio or fixed height
                                                  width: 50,
                                                  image: AssetImage('assets/images/Documents.png'),
                                                ),
                                              )

                                              // Icon(Icons.note, size: 40, color: Color.fromARGB(255, 77, 43, 170)),
                                            ],
                                          )),
                                      Container(
                                        width: (MediaQuery.of(context).size.width - 60) / 4,
                                        margin: EdgeInsets.only(top: 10),
                                        child: Text(
                                          'Documents',
                                          textAlign: TextAlign.center,
                                          style: TextStyle(color: Color.fromARGB(255, 41, 41, 41)),
                                        ),
                                      )
                                    ],
                                  ),
                                  onTap: () {
                                    Navigator.push(
                                      context,
                                      MaterialPageRoute(builder: (context) => Documents()),
                                    );
                                  },
                                ),
                              ],
                            ),
                          ),
                        ],
                      )),
                  Container(
                      padding: EdgeInsets.all(10),
                      margin: EdgeInsets.only(top: 15, bottom: 80),
                      decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(5), color: Color.fromARGB(255, 241, 229, 255), gradient: LinearGradient(colors: [Color.fromARGB(255, 241, 229, 255), Color.fromARGB(255, 229, 213, 248)])),
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text("Latest updates about your construction", style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Color.fromARGB(255, 34, 34, 34))),
                        Container(
                          alignment: Alignment.topLeft,
                          // padding: EdgeInsets.all(15),
                          margin: EdgeInsets.only(top: 5, bottom: 20),
                          decoration: BoxDecoration(
                            // color: Color.fromARGB(255, 209, 209, 209),
                            // border: Border.all(color: Colors.black, width: 0.3),
                            borderRadius: BorderRadius.circular(5),
                          ),
                          child: Column(
                            children: <Widget>[
                              Row(
                                children: <Widget>[
                                  Row(
                                    children: <Widget>[
                                      Container(
                                        padding: EdgeInsets.only(bottom: 10),
                                        child: Text(updatePostedOnDate, style: TextStyle(fontSize: 12, color: Color.fromARGB(255, 78, 78, 78))),
                                      )
                                    ],
                                  ),
                                ],
                              ),
                              if (updateResponseBody != null && updateResponseBody.length > 0 && updateResponseBody[0]['tradesmenMap'].toString().length > 0)
                                Container(
                                  alignment: Alignment.topLeft,
                                  padding: EdgeInsets.only(top: 10),
                                  child: Text(updateResponseBody[0]['tradesmenMap'].toString().trim() == 'null' ? '' : updateResponseBody[0]['tradesmenMap'].toString().trim(),
                                      style: TextStyle(
                                        fontSize: 14,
                                        color: Color.fromARGB(255, 37, 37, 37),
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
                                          child: Text(dailyUpdateList[Index].toString(), style: TextStyle(fontSize: 14, color: const Color.fromARGB(255, 0, 0, 0))),
                                        )
                                      ],
                                    );
                                  }),
                            ],
                          ),
                        ),
                      ])),
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
