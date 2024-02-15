import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'NavMenu.dart';
import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';
import 'main.dart';

class Documents extends StatefulWidget {
  @override
  DocumentsState createState() {
    return DocumentsState();
  }
}

class DocumentObject extends StatefulWidget {
  var parent;
  var children;
  var drawing_id;

  DocumentObject(this.parent, this.children, this.drawing_id);

  @override
  DocumentObjectState createState() {
    return DocumentObjectState(this.parent, this.children, this.drawing_id);
  }
}

class DocumentObjectState extends State<DocumentObject> {
  var parent;
  var children;
  var drawing_id;
  bool vis = false;
  Icon _icon = Icon(Icons.expand_more);

  DocumentObjectState(this.parent, this.children, this.drawing_id);

  _launchURL(url) async {
    await launch(url);
  }

  @override
  Widget build(BuildContext context) {
    return Container(
        decoration: BoxDecoration(
            color: Colors.grey[200], borderRadius: BorderRadius.circular(10)),
        margin: EdgeInsets.symmetric(vertical: 10, horizontal: 5),
        child: Column(
          children: <Widget>[
            InkWell(
              onTap: () {
                setState(() {
                  !vis
                      ? _icon = Icon(Icons.expand_less)
                      : _icon = Icon(Icons.expand_more);
                  vis = !vis;
                });
              },
              child: Container(
                padding: EdgeInsets.all(15),
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
                                    builder: (BuildContext context) {
                                      return AlertDialog(
                                          content: Text("Loading..."));
                                    }),
                                Navigator.of(context, rootNavigator: true)
                                    .pop(),
                                _launchURL(
                                    "https://app.buildahome.in/team/Drawings/" +
                                        children[x].toString())
                              },
                          child: Container(
                            padding:
                                EdgeInsets.only(left: 15, right: 15, bottom: 5),
                            alignment: Alignment.centerLeft,
                            margin: EdgeInsets.only(top: 20),
                            child: Text(
                              children[x].toString(),
                              style: TextStyle(
                                  color: Colors.indigo[900],
                                  fontWeight: FontWeight.bold),
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
  var subfolders = {};
  var drawing_ids = {};
  var work_orders = [];
  var purchase_orders = [];
  var role;

  call() async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    var id = prefs.getString('project_id');
    var url = Uri.parse('https://office.buildahome.in/API/view_all_documents?id=$id');
    var response = await http.get(url);
    var _role = prefs.getString('role');
    var pos = [];
    var wos = [];

    setState(() {
      role = _role;
      folders = [];
      subfolders = {};
      drawing_ids = {};
      if (response.body != '') {
        entries = jsonDecode(response.body);
        for (int i = 0; i < entries.length; i++) {
          if (folders.contains(entries[i]['folder']) == false &&
              entries[i]['folder'].trim() != "") {
            folders.add(entries[i]['folder']);
          }
        }
        for (int i = 0; i < folders.length; i++) {
          for (int x = 0; x < entries.length; x++) {
            if (entries[x]["folder"] == folders[i]) {
              if (subfolders.containsKey(folders[i])) {
                subfolders[folders[i]].add(entries[x]["name"]);
                drawing_ids[folders[i]].add(entries[x]["doc_id"]);
              } else {
                subfolders[folders[i]] = [];
                drawing_ids[folders[i]] = [];
                subfolders[folders[i]].add(entries[x]["name"]);
                drawing_ids[folders[i]].add(entries[x]["doc_id"]);
              }
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
    final GlobalKey<ScaffoldState> _scaffoldKey =
        new GlobalKey<ScaffoldState>();
    return Scaffold(
        key: _scaffoldKey,
        backgroundColor: Color.fromARGB(255, 233, 233, 233),

        appBar: AppBar(
          automaticallyImplyLeading: true,
          title: Text(
            appTitle,
            style: TextStyle(color: Color.fromARGB(255, 224, 224, 224), fontSize: 16),
          ),
          leading: new IconButton(
              icon: new Icon(Icons.chevron_left),
              onPressed: () async {
                Navigator.pop(context);
              }),
          backgroundColor: Color.fromARGB(255, 6, 10, 43),

        ),
        body: Stack(children: [
          Opacity(
          opacity: 0.4,
          child: Container(
            width: MediaQuery.of(context).size.width,
            height: MediaQuery.of(context).size.height,
            decoration: BoxDecoration(
                color: Color.fromARGB(255, 214, 214, 214),
                border: Border.all(width: 1, color: Colors.grey[200]!),
                borderRadius: BorderRadius.circular(10),
                ),
            
            child: Image.network("https://plus.unsplash.com/premium_photo-1677402408071-232d1c3c3787?w=500&auto=format&fit=crop&q=60&ixlib=rb-4.0.3&ixid=M3wxMjA3fDB8MHxzZWFyY2h8Mjl8fGZpbGVzfGVufDB8fDB8fHww", fit: BoxFit.fill),
          ),
        ),
          ListView(
          children: [
            Container(margin: EdgeInsets.only(top: 20, left: 15, bottom: 10), child: Text("Project Documents", style: TextStyle(fontSize: 16, color: const Color.fromARGB(255, 37, 37, 37)))),

            ListView.builder(
              shrinkWrap: true,
              physics: NeverScrollableScrollPhysics(),
              padding: EdgeInsets.all(15),
              itemCount: folders == null ? 0 : folders.length,
              itemBuilder: (BuildContext ctxt, int Index) {
                return Container(
                  child: DocumentObject(folders[Index].toString(),
                      subfolders[folders[Index]], drawing_ids[folders[Index]]),
                );
              },
            ),
            Container(
              margin: EdgeInsets.only(bottom: 100),
            )
          ],
        )
        ],)
        );
  }
}
