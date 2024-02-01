import 'package:flutter/material.dart';
import 'package:flutter/widgets.dart';
import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:http/http.dart';
import 'NavMenu.dart';
import 'package:photo_view/photo_view.dart';
import 'Update.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:typed_data';

var drawings = {};

class FullScreenImage extends StatelessWidget {
  var image;

  FullScreenImage(this.image);


  Widget build(BuildContext context) {
    return Container(

            decoration: BoxDecoration(border: Border.all(color: Colors.black)),
            child: PhotoView(

              imageProvider: this.image
            )


        );
  }
}


class VIewDrawing extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final appTitle = 'buildAhome';
    final GlobalKey<ScaffoldState> _scaffoldKey =
        new GlobalKey<ScaffoldState>();
    return MaterialApp(
      title: appTitle,
      theme: ThemeData(fontFamily: 'Varela'),
      home: Scaffold(
        key: _scaffoldKey, // ADD THIS LINE
        appBar: AppBar(
          automaticallyImplyLeading: false,
          title: Text(appTitle, style: TextStyle(fontFamily: "PatuaOne"),),
          leading: new IconButton(
              icon: new Icon(Icons.menu),
              onPressed: () => _scaffoldKey.currentState!.openDrawer()),
          backgroundColor: Color(0xFF000055),
        ),
        drawer: NavMenuWidget(),
        body: VIewDrawingForm(),
      ),
    );
  }
}

class VIewDrawingForm extends StatefulWidget {
  @override
  VIewDrawingState createState() {
    return VIewDrawingState();
  }
}

class VIewDrawingState extends State<VIewDrawingForm> {
  @override
  void initState() {
    super.initState();
    call();
  }

  var entries = [];
  var pr_id;

  call() async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    pr_id = prefs.getString('project_id');

    var url = 'https://office.buildahome.in/API/get_drawing?id=$pr_id';
    print(url);
    var response = await http.get(Uri.parse(url));
    setState(() {
      entries = jsonDecode(response.body);
    });
  }

  _image_func(_image_string, update_id) {
    var stripped = _image_string
        .toString()
        .replaceFirst(RegExp(r'data:image/jpeg;base64,'), '');
    var imageAsBytes = base64.decode(stripped);

    if (imageAsBytes != null) {
      var actual_image = new Image.memory(imageAsBytes);
      if (update_id != "From list") drawings[update_id] = _image_string;
      Uint8List bytes = base64Decode(stripped);
      return InkWell(
          child: actual_image,
          onTap: () async {
            var img = await Navigator.push(
              context,
              MaterialPageRoute(
                  builder: (context) => FullScreenImage(
                        MemoryImage(bytes),
                      )),
            );
          });
    } else {
      return Container(
          padding: EdgeInsets.all(30),
          width: 100,
          height: 100,
          color: Colors.grey[100],
          child: CircularProgressIndicator());
    }
  }

  @override
  Widget build(BuildContext context) {
    return new ListView.builder(
        shrinkWrap: true,
        padding: EdgeInsets.all(20),
        itemCount: entries.length,
        itemBuilder: (BuildContext ctxt, int Index) {
          var id = entries[Index]['id'];

          if (drawings.containsKey(id))
            return Container(
              padding: EdgeInsets.only(bottom: 10),
              child:  Container(
                  padding: EdgeInsets.all(5),
                  decoration: BoxDecoration(
                      border: Border.all(color: Colors.black26)
                  ),
                  child: Column(
                    children: <Widget>[
                      Container(
                          alignment: Alignment.centerLeft,
                          padding: EdgeInsets.only(left: 10, bottom: 5),
                          child: Text(entries[Index]['date'])),
                      Container(
                        width: MediaQuery.of(context).size.width * .80,
                        height: MediaQuery.of(context).size.width * .80,
                        color: Colors.grey[100],
                        child: _image_func(drawings[id], "From list"),
                      ),
                      Container(
                          alignment: Alignment.center,
                          padding: EdgeInsets.only(top: 10, bottom: 10),
                          child: Text(
                            entries[Index]['dr_name'],
                            style:
                            TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                          )),
                    ],
                  )
              )
            );





          else
            return Container(
              padding: EdgeInsets.only(bottom: 10),
              child: Container(
                  padding: EdgeInsets.all(5),
                  decoration: BoxDecoration(
                      border: Border.all(color: Colors.black26)
                  ),
                  child: Column(
                    children: <Widget>[
                      Container(
                          alignment: Alignment.centerLeft,
                          padding: EdgeInsets.only(left: 15, bottom: 5),
                          child: Text(entries[Index]['date'])),
                  FutureBuilder<Response>(
                    future: http.post(
                      Uri.parse("https://office.buildahome.in/API/get_dr_image"),
                      body: {'drawing_id': id},
                    ),
                    builder: (context, snapshot) {
                      switch (snapshot.connectionState) {
                        case ConnectionState.none:
                        case ConnectionState.active:
                          return Container(
                            padding: EdgeInsets.all(30),
                            height: 100,
                            width: 100,
                            child: CircularProgressIndicator(),
                          );
                        case ConnectionState.waiting:
                          return Container(
                            padding: EdgeInsets.all(100),
                            width: MediaQuery.of(context).size.width * .80,
                            height: MediaQuery.of(context).size.width * .80,
                            color: Colors.grey[100],
                            child: CircularProgressIndicator(),
                          );
                        case ConnectionState.done:
                          if (snapshot.hasError) {
                            return Container(
                              width: MediaQuery.of(context).size.width * .80,
                              height: MediaQuery.of(context).size.width * .80,
                              color: Colors.grey[100],
                            );
                          }

                          // Check if snapshot.data.body is not null and not an empty string
                          if (snapshot.data != null && snapshot.data?.body.isNotEmpty == true) {
                            return _image_func(snapshot.data?.body, entries[Index]["id"]);
                          } else {
                            return Container(width: 1, height: 1, color: Colors.grey);
                          }
                      }
                    },
                  ),

                  Container(
                          alignment: Alignment.center,
                          padding: EdgeInsets.only(top: 10, bottom: 10),
                          child: Text(
                            entries[Index]['dr_name'],
                            style:
                            TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                          )),
                    ],
                  )
              ),
            );



        });
  }
}
