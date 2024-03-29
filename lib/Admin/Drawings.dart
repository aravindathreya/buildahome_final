import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'Scheduler.dart';
import 'Payments.dart';
import 'Gallery.dart';
import 'Dpr.dart';

class Documents extends StatefulWidget {
  final String id;

  Documents(this.id);

  @override
  DocumentsState createState() {
    return DocumentsState(this.id);
  }
}

class DocumentObject extends StatefulWidget {
  final parent;
  final children;
  final drawingId;

  DocumentObject(this.parent, this.children, this.drawingId);

  @override
  DocumentObjectState createState() {
    return DocumentObjectState(this.parent, this.children, this.drawingId);
  }
}

class DocumentObjectState extends State<DocumentObject> {
  var parent;
  var children;
  var drawingId;
  bool vis = false;
  Icon _icon = Icon(Icons.expand_more);

  DocumentObjectState(this.parent, this.children, this.drawingId);

  _launchURL(url) async {
    await _launchURL(Uri.parse(url));
  }

  @override
  Widget build(BuildContext context) {
    return Container(
        padding: EdgeInsets.all(15),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(5),
          color: Colors.grey[200],
        ),
        margin: EdgeInsets.symmetric(vertical: 10, horizontal: 5),
        child: Column(
          children: <Widget>[
            InkWell(
              onTap: () {
                setState(() {
                  vis ? _icon = Icon(Icons.expand_less) : _icon = Icon(Icons.expand_more);
                  vis ? vis = false : vis = true;
                });
              },
              child: Container(
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: <Widget>[
                    Text(
                      this.parent.toString(),
                      style: TextStyle(fontSize: 16),
                    ),
                    _icon,
                  ],
                ),
              ),
            ),
            Visibility(
                visible: vis,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    for (int x = 0; x < this.children.length; x++)
                      InkWell(
                          onTap: () => {
                                showDialog(
                                    context: context,
                                    builder: (BuildContext ctx) {
                                      return AlertDialog(content: Text("Loading..."));
                                    }),
                                _launchURL("https://app.buildahome.in/team.dart/Drawings/" + children[x].toString()),
                              },
                          child: Container(
                            alignment: Alignment.centerLeft,
                            margin: EdgeInsets.only(top: 20),
                            child: Text(
                              children[x].toString(),
                              style: TextStyle(color: Colors.indigo[900], fontWeight: FontWeight.bold),
                            ),
                          ))
                  ],
                ))
          ],
        ));
  }
}

class DocumentsState extends State<Documents> {
  var entries;
  var folders = [];
  var subFolders = {};
  var drawingIds = {};
  var id;
  var role = "";

  DocumentsState(this.id);

  setProjectId(projectId) async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    prefs.setString("projectId", projectId.toString());
    setState(() {
      role = prefs.getString("role")!;
      print(role);
    });
  }

  call() async {
    setProjectId(this.id);
    SharedPreferences prefs = await SharedPreferences.getInstance();
    var id = prefs.getString('projectId');
    var url = 'https://office.buildahome.in/API/view_all_documents?id=$id';
    var response = await http.get(Uri.parse(url));

    setState(() {
      folders = [];
      subFolders = {};
      drawingIds = {};
      entries = jsonDecode(response.body);
      for (int i = 0; i < entries.length; i++) {
        if (folders.contains(entries[i]['folder']) == false && entries[i]['folder'].trim() != "") {
          folders.add(entries[i]['folder']);
        }
      }
      for (int i = 0; i < folders.length; i++) {
        for (int x = 0; x < entries.length; x++) {
          if (entries[x]["folder"] == folders[i]) {
            if (subFolders.containsKey(folders[i])) {
              subFolders[folders[i]].add(entries[x]["name"]);
              drawingIds[folders[i]].add(entries[x]["doc_id"]);
            } else {
              subFolders[folders[i]] = [];
              drawingIds[folders[i]] = [];
              subFolders[folders[i]].add(entries[x]["name"]);
              drawingIds[folders[i]].add(entries[x]["doc_id"]);
            }
          }
        }
      }
    });
  }

  @override
  void initState() {
    super.initState();
    call();
  }

  @override
  Widget build(BuildContext context) {
    final appTitle = 'buildAhome';
    final GlobalKey<ScaffoldState> _scaffoldKey = new GlobalKey<ScaffoldState>();
    return MaterialApp(
      title: appTitle,
      home: Scaffold(
          key: _scaffoldKey,
          appBar: AppBar(
            automaticallyImplyLeading: false,
            title: Text(appTitle),
            leading: new IconButton(
                icon: new Icon(Icons.arrow_back_ios),
                onPressed: () => {
                      Navigator.pop(context),
                    }),
            backgroundColor: Color(0xFF000055),
          ),
          bottomNavigationBar: BottomNavigationBar(
            currentIndex: 1,
            selectedItemColor: Colors.indigo[900],
            onTap: (int index) {
              if (index == 0) {
                Navigator.pushReplacement(
                  context,
                  MaterialPageRoute(builder: (context) => Dpr(this.id)),
                );
              } else if (index == 1) {
                Navigator.pushReplacement(
                  context,
                  MaterialPageRoute(builder: (context) => Documents(this.id)),
                );
              } else if (index == 2) {
                Navigator.pushReplacement(
                  context,
                  MaterialPageRoute(builder: (context) => Gallery(this.id)),
                );
              } else if (index == 3) {
                Navigator.pushReplacement(
                  context,
                  MaterialPageRoute(builder: (context) => TaskWidget(this.id)),
                );
              } else if (index == 4) {
                Navigator.pushReplacement(
                  context,
                  MaterialPageRoute(builder: (context) => PaymentTaskWidget(this.id)),
                );
              }
            },
            unselectedItemColor: Colors.grey[400],
            type: BottomNavigationBarType.fixed,
            items: [
              BottomNavigationBarItem(
                  icon: Icon(
                    Icons.home,
                  ),
                  label: 'Home'),
              BottomNavigationBarItem(
                  icon: Icon(
                    Icons.picture_as_pdf,
                  ),
                  label: 'Drawings'),
              BottomNavigationBarItem(
                  icon: Icon(
                    Icons.photo_album,
                  ),
                  label: "Gallery"),
              if (role == 'Site Engineer' || role == "Admin" || role == 'Project Coordinator')
                BottomNavigationBarItem(
                    icon: Icon(
                      Icons.access_time,
                    ),
                    label: 'Scheduler'),
              if (role == 'Project Coordinator' || role == "Admin")
                BottomNavigationBarItem(
                    icon: Icon(
                      Icons.payment,
                    ),
                    label: 'Payment'),
            ],
          ),
          body: ListView.builder(
            itemCount: folders.length,
            itemBuilder: (BuildContext ctxt, int index) {
              return Container(
                child:
                    DocumentObject(folders[index].toString(), subFolders[folders[index]], drawingIds[folders[index]]),
              );
            },
          )),
    );
  }
}
