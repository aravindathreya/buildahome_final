import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'NavMenu.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'main.dart';
import 'ShowAlert.dart';
import 'package:file_picker/file_picker.dart';
import 'package:url_launcher/url_launcher.dart';

class NotesAndComments extends StatefulWidget {
  @override
  NotesAndCommentsState createState() {
    return NotesAndCommentsState();
  }
}

class NotesAndCommentsState extends State<NotesAndComments> {
  var project_id;
  var notes;
  var showPostBtn = false;
  var user_id = '';
  var attached_file_name = '';
  var attached_file;

  getNotes() async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    Timer.periodic(new Duration(seconds: 1), (timer) {
      if (timer.tick.toInt() % 10 == 0) {
        //getNotes();
      }
    });
    var _project_id = prefs.getString('project_id');
    user_id = prefs.getString('user_id')!;

    var url =
        'https://office.buildahome.in/API/get_notes?project_id=${_project_id}';
    var response = await http.get(Uri.parse(url));
    print(response.body);
    var a = jsonDecode(response.body);

    setState(() {
      notes = a;
      project_id = _project_id;
    });
  }

  void getFile() async {
    var res = await FilePicker.platform.pickFiles(allowMultiple: false);
    var file = res?.files.first;

    if (file != null) {
      setState(() {
        setState(() {
          var fileSplit = file.path?.split('/');
          attached_file = file;
          attached_file_name = 'Attached file: ' +
              (fileSplit![fileSplit.length - 1]);
        });
      });
    } else {
      setState(() {
        attached_file_name = '';
      });
    }
  }

  _launchURL(url) async {
    if (await canLaunch(url)) {
      await launch(url);
    } else {
      throw 'Could not launch $url';
    }
  }

  @override
  void initState() {
    super.initState();
    getNotes();
  }

  final GlobalKey<ScaffoldState> _scaffoldKey = new GlobalKey<ScaffoldState>();
  final message = TextEditingController();

  @override
  Widget build(BuildContext context) {
    final appTitle = 'buildAhome';
     return MaterialApp(
      title: appTitle,
      theme: ThemeData(fontFamily: App().fontName),
      home: Scaffold(
        key: _scaffoldKey,
        backgroundColor: Colors.black,
        drawer: NavMenuWidget(),
        appBar: AppBar(
          automaticallyImplyLeading: true,
          title: Text(
            appTitle,
          ),
          leading: new IconButton(
              icon: new Icon(Icons.chevron_left),
              onPressed: () async {
                Navigator.pop(context);
              }),
          backgroundColor: Colors.transparent,
        ),
        body: ListView(
          padding: EdgeInsets.only(left: 15, right: 15),
      children: [
        Text('Notes and comments', style: TextStyle(fontSize: 20, color: Colors.white),),
        Container(
            margin: EdgeInsets.symmetric(horizontal: 15, vertical: 20),
            child: TextFormField(
              controller: message,
              autocorrect: true,
              keyboardType: TextInputType.multiline,
              textCapitalization: TextCapitalization.sentences,
              maxLines: 4,
              onChanged: (value) => {
                setState(() {
                  showPostBtn = value.length > 0;
                })
              },
              style: TextStyle(fontSize: 18),
              decoration: InputDecoration(
                  focusColor: Colors.black,
                  floatingLabelBehavior: FloatingLabelBehavior.never,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.zero,
                    borderSide: BorderSide(
                      color: Colors.grey[300]!,
                      width: 1.0,
                    ),
                  ),
                  filled: true,
                  hintText: "Add a note",
                  alignLabelWithHint: true,
                  labelStyle: TextStyle(
                    fontSize: 18,
                  ),
                  fillColor: Colors.white),
            )),
        Container(
            child: InkWell(
          onTap: () async => getFile(),
          child: Container(
              margin: EdgeInsets.only(left: 15, right: 15, top: 10),
              decoration: BoxDecoration(
                color: Colors.white,
                border: Border.all(width: 1.0, color: Colors.black),
                borderRadius: BorderRadius.all(Radius.circular(5)),
              ),
              padding: EdgeInsets.all(15),
              child: Row(
                children: <Widget>[
                  Container(
                    decoration: BoxDecoration(
                        borderRadius: BorderRadius.all(Radius.circular(50)),
                        color: Colors.white),
                    child: Icon(Icons.file_upload,
                        size: 25, color: Colors.indigo[900]),
                  ),
                  Container(
                      padding: EdgeInsets.only(left: 10),
                      child: Text('Add attachment',
                          style: TextStyle(fontSize: 18)))
                ],
              )),
        )),
        Container(
          margin: EdgeInsets.only(left: 15, bottom: 10, top: 10),
          child: Text(
            attached_file_name,
            style: TextStyle(fontWeight: FontWeight.w600),
          ),
        ),
        if (showPostBtn)
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              InkWell(
                child: Container(
                  padding: EdgeInsets.symmetric(horizontal: 30, vertical: 15),
                  margin: EdgeInsets.only(right: 15),
                  decoration: BoxDecoration(
                      color: Color(0xFF000055),
                      borderRadius: BorderRadius.circular(5)),
                  child: Text(
                    'Post',
                    style: TextStyle(color: Colors.white),
                  ),
                ),
                onTap: () async {
                  showDialog(
                      barrierDismissible: false,
                      context: context,
                      builder: (BuildContext context) {
                        return ShowAlert(
                            "Hang in there. Submitting update", true);
                      });
                  var url = Uri.parse(
                      "https://office.buildahome.in/API/post_comment");
                  var response = await http.post(url, body: {
                    'project_id': project_id.toString(),
                    'user_id': user_id,
                    'note': message.text
                  });
                  var responseBody = jsonDecode(response.body);
                  var note_id = responseBody['note_id'];
                  if (attached_file_name != '') {
                    var uri = Uri.parse(
                        "https://office.buildahome.in/API/notes_picture_uplpoad");
                    var request = new http.MultipartRequest("POST", uri);

                    var pic = await http.MultipartFile.fromPath(
                        "file", attached_file.path);

                    request.files.add(pic);
                    request.fields['note_id'] = note_id.toString();
                    var fileResponse = await request.send();
                    var responseData = await fileResponse.stream.toBytes();
                    var responseString = String.fromCharCodes(responseData);
                  }

                 Navigator.pop(context);
                  await showDialog(
                      context: context,
                      builder: (BuildContext context) {
                        return ShowAlert("Note added successfully", false);
                      });

                  getNotes();
                  setState(() {
                    message.text = '';
                    showPostBtn = false;
                    attached_file_name = '';
                    attached_file = null;
                  });
                },
              )
            ],
          ),
        Container(
            margin: EdgeInsets.only(bottom: 100),
            child: ListView.builder(
                physics: NeverScrollableScrollPhysics(),
                shrinkWrap: true,
                itemCount: notes == null ? 0 : notes.length,
                itemBuilder: (BuildContext ctxt, int Index) {
                  return Container(
                      alignment: Alignment.centerLeft,
                      padding: EdgeInsets.all(10),
                      decoration: BoxDecoration(
                          color: Colors.grey[200],
                          border: Border(
                              left: BorderSide(
                                  color: Color(0xFFFCD900), width: 5))),
                      margin: EdgeInsets.all(10),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Container(
                            padding: EdgeInsets.only(bottom: 5),
                            decoration: BoxDecoration(
                                border: Border(
                                    bottom: BorderSide(
                                        width: 0.5, color: Colors.grey))),
                            child: Row(
                              children: [
                                Icon(Icons.account_circle),
                                Container(
                                  margin: EdgeInsets.only(left: 5),
                                  child: Text(
                                    notes[Index][2].toString(),
                                    style: TextStyle(fontSize: 16),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          Container(
                            margin: EdgeInsets.only(top: 5, left: 2),
                            child: Expanded(
                              child: Text(
                                notes[Index][0].toString(),
                                style: TextStyle(
                                    fontSize: 15, color: Colors.indigo[900]),
                              ),
                            )
                          ),
                          if (notes[Index][4].toString() != '0')
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
                                          "https://app.buildahome.in/files/" +
                                              notes[Index][4].toString()),
                                    },
                                child: Container(
                                    margin: EdgeInsets.only(top: 15),
                                    padding: EdgeInsets.all(10),
                                    decoration: BoxDecoration(
                                        border:
                                            Border.all(color: Colors.grey[500]!),
                                        color: Colors.grey[100],
                                        borderRadius: BorderRadius.circular(5)),
                                    width: 150,
                                    child: Row(
                                      mainAxisAlignment:
                                          MainAxisAlignment.spaceBetween,
                                      children: [
                                        Container(
                                          child: Icon(
                                            Icons.attach_file,
                                            size: 15,
                                            color: Colors.indigo[900],
                                          ),
                                        ),
                                        Container(
                                          alignment: Alignment.centerLeft,
                                          child: Text(
                                            'View attachment',
                                            style: TextStyle(
                                                color: Colors.indigo[900],
                                                fontWeight: FontWeight.bold),
                                          ),
                                        )
                                      ],
                                    ))),
                          Container(
                            alignment: Alignment.bottomRight,
                            margin: EdgeInsets.only(top: 10),
                            child: Text(
                              notes[Index][1].toString(),
                              style: TextStyle(
                                  fontSize: 14, color: Colors.grey[600]),
                            ),
                          ),
                        ],
                      ));
                })),
      ],
    ),
      ),
    );

    
  }
}
