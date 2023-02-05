import 'dart:convert';
import 'package:http/http.dart' as http;

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import "NavMenu.dart";

image_func(image_bytes) {
    if (image_bytes != null) {
      print("Here $image_bytes");
      return new Image.memory(image_bytes);
    }
}

class Update extends StatelessWidget {
  var update='';
  var image;
  var date;
  Update(this.image, this.date, this.update);


  @override
  Widget build(BuildContext context) {
    print("Here $this.update");
    final appTitle = 'BuildAhome';
    final GlobalKey<ScaffoldState> _scaffoldKey =
    new GlobalKey<ScaffoldState>();
    return MaterialApp(
      title: appTitle,
      theme: ThemeData(fontFamily: 'Raleway'),
      home: Scaffold(
        key: _scaffoldKey, // ADD THIS LINE
        appBar: AppBar(
          automaticallyImplyLeading: false,
          title: Text(appTitle),
          leading: new IconButton(
              icon: new Icon(Icons.menu),
              onPressed: () => _scaffoldKey.currentState.openDrawer()),
          backgroundColor: Colors.indigo[900],
        ),

        drawer: NavMenuWidget(),

        body: UpdateBox(this.date, this.update),
      ),
    );
  }
}

class UpdateBox extends StatelessWidget{
  var update='';
  var image;
  var date;
  var data;
  UpdateBox(this.date, this.update);


  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.all(5),
      child: Column(
        children: <Widget>[
          Container(
            height: MediaQuery.of(context).size.height * .60,
            color: Colors.blue,
            child: FutureBuilder(
                future: http.post(Uri.parse("http://192.168.0.105:80/bah/api/get_image.php"),

                    body: {
                      'pr_name': "hi".toString(),
                      'update': update.toString(),
                      'date': date.toString()
                    }),
                builder: (context, snapshot) {
                  switch (snapshot.connectionState) {
                    case ConnectionState.none:
                      return Text(
                          'Press button to start.');
                    case ConnectionState.active:
                    case ConnectionState.waiting:
                      return Text('Awaiting result...');
                    case ConnectionState.done:
                      if (snapshot.hasError)
                        return Text('Error: ${snapshot.error}');
                      var a = snapshot.data.body;
                      print(a);
                      final stripped = a.toString().replaceFirst(RegExp(r'data:image/jpeg;base64,'), '');
                      var data = base64.decode(stripped);
                      return image_func(data);

                  }
                }

            )

          )
        ],
      )
    );
  }
}
