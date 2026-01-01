import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'services/data_provider.dart';
import 'Skin2/loginPage.dart';
import 'app_theme.dart';

class NavMenuItem extends StatelessWidget {
  final String _route;
  final IconData _icon;
  final Widget _routename;

  const NavMenuItem(this._route, this._icon, this._routename, {Key? key}) : super(key: key);

  _logout() {
    // Clear data immediately (synchronous)
    DataProvider().clearData();
    
    // Clear SharedPreferences in background (don't wait for it)
    SharedPreferences.getInstance().then((preferences) {
      preferences.clear();
    }).catchError((e) {
      print('Error clearing SharedPreferences: $e');
    });
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      decoration: BoxDecoration(
        color: isDark ? AppTheme.getBackgroundSecondary(context) : Colors.white,
        shape: BoxShape.rectangle,
        border: Border(
          bottom: BorderSide(width: 1.0, color: isDark ? Colors.white12 : Colors.black12),
        ),
      ),
      width: 400,
      padding: EdgeInsets.only(left: 20, top: 15, bottom: 15),
      child: InkWell(
        onTap: () {
          if (this._route == "Log out") {
            _logout();
            Navigator.pop(context);
            Navigator.pushAndRemoveUntil(
              context,
              MaterialPageRoute(builder: (context) => this._routename),
              (route) => false,
            );
          } else {
            Navigator.pop(context);
            Navigator.pushReplacement(
              context,
              PageRouteBuilder(
                pageBuilder: (context, animation, secondaryAnimation) => this._routename,
                transitionsBuilder: (context, animation, secondaryAnimation, child) {
                  return FadeTransition(
                    opacity: animation,
                    child: SlideTransition(
                      position: Tween<Offset>(
                        begin: const Offset(0.3, 0.0),
                        end: Offset.zero,
                      ).animate(CurvedAnimation(
                        parent: animation,
                        curve: Curves.easeOutCubic,
                      )),
                      child: child,
                    ),
                  );
                },
                transitionDuration: Duration(milliseconds: 300),
              ),
            );
          }
        },
        child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: <Widget>[
              Row(
                children: [
                  Icon(this._icon, color: Theme.of(context).iconTheme.color),
                  Container(
                    padding: EdgeInsets.only(left: 5),
                    child: Text(
                      this._route,
                      textAlign: TextAlign.left,
                      style: TextStyle(
                        fontSize: 18,
                        color: Theme.of(context).textTheme.bodyLarge?.color ?? Colors.black,
                      ),
                    ),
                  ),
                ],
              ),
              Container(
                  margin: EdgeInsets.only(right: 15),
                  child:
                      Icon(Icons.chevron_right, size: 20, color: Colors.grey))
            ]),
      ),
    );
  }
}

class NavMenuWidget extends StatefulWidget {
  @override
  NavMenuWidgetState createState() {
    return NavMenuWidgetState();
  }
}

class NavMenuWidgetState extends State<NavMenuWidget> {
  void initState() {
    super.initState();
    call();
  }

  var username;
  var role;
  var location;

  call() async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    setState(() {
      username = prefs.getString('username');
      role = prefs.getString('role');
      location = prefs.getString('location');
    });
  }

  @override
  Widget build(BuildContext context) {
    return Drawer(
      child: ListView(
          dragStartBehavior: DragStartBehavior.start,
          children: <Widget>[
            Container(
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: Color.fromARGB(255, 0, 0, 24),
                shape: BoxShape.rectangle,
              ),
              padding: EdgeInsets.only(top: 40, left: 20, bottom: 40),
              child: InkWell(
                child: Column(
                  children: <Widget>[
                    Row(children: <Widget>[
                      Container(
                        padding: EdgeInsets.all(2),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.all(Radius.circular(50)),
                        ),
                        child: Icon(
                          Icons.account_circle_sharp,
                          size: 60,
                          color: Color(0xFFDEEDF0),
                        ),
                      ),
                      Container(
                          padding: EdgeInsets.only(left: 15),
                          alignment: Alignment.centerLeft,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: <Widget>[
                              Container(
                                child: Text(
                                  username.toString(),
                                  textAlign: TextAlign.left,
                                  style: TextStyle(
                                      fontSize: 22,
                                      color: Colors.white,
                                      fontWeight: FontWeight.bold),
                                ),
                              ),
                              Container(
                                  padding: EdgeInsets.only(top: 5),
                                  child: Text(
                                    role.toString(),
                                    style: TextStyle(
                                        color: Colors.white, fontSize: 16),
                                  ))
                            ],
                          )),
                    ]),
                    if (role == "Client")
                      Container(
                          margin: EdgeInsets.only(top: 30),
                          alignment: Alignment.topLeft,
                          child: Text(
                            "Building a home at",
                            style: TextStyle(color: Colors.white, fontSize: 16),
                          )),
                    if (role == "Client")
                      Container(
                          margin: EdgeInsets.only(top: 10, left: 0),
                          alignment: Alignment.topLeft,
                          child: Text(
                            location.toString(),
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 14,
                            ),
                          ))
                  ],
                ),
              ),
            ),
            Container(
              child: NavMenuItem("Log out", Icons.logout, LoginScreenNew()),
            ),
          ]),
    );
  }
}
