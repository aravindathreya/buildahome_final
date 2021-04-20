

import 'package:flutter/material.dart';
import 'package:flutter/widgets.dart';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'NavMenu.dart';
import 'dart:typed_data';
import 'package:shared_preferences/shared_preferences.dart';
import 'main.dart';
import "FullScreenImage.dart";
import "UserHome.dart";
import "Scheduler.dart";
import 'package:cached_network_image/cached_network_image.dart';
import "Payments.dart";

BuildContext context;
var images = {};


class Gallery extends StatelessWidget {
  @override
  Widget build(context) {
    final appTitle = 'buildAhome';
    final GlobalKey<ScaffoldState> _scaffoldKey =
        new GlobalKey<ScaffoldState>();
    return MaterialApp(
      title: appTitle,
      theme: ThemeData(fontFamily: MyApp().fontName),
      home: Scaffold(
        key: _scaffoldKey, // ADD THIS LINE
        drawer: NavMenuWidget(),
        appBar: AppBar(
          automaticallyImplyLeading: false,
          title: Text(appTitle, style: TextStyle(fontFamily: "PatuaOne"),),
          leading: new IconButton(
              icon: new Icon(Icons.menu),
              onPressed: () => _scaffoldKey.currentState.openDrawer()),
          backgroundColor: Color(0xFF000055),
        ),
        body: GalleryForm(context),
        bottomNavigationBar: BottomNavigationBar(
          currentIndex: 3 ,
          selectedItemColor: Colors.indigo[900],

          onTap: (int index) {
            if(index==0){
              Navigator.push(
                context,
                MaterialPageRoute(builder: (context) => Home()),
              );
            }
            else if(index==1){
              Navigator.push(
                context,
                MaterialPageRoute(builder: (context) => TaskWidget()),
              );
            }
            else if(index==2){
              Navigator.push(
                context,
                MaterialPageRoute(builder: (context) => PaymentTaskWidget()),
              );
            }
            else if(index==3){
              Navigator.push(
                context,
                MaterialPageRoute(builder: (context) => Gallery()),
              );
            }
          },
          unselectedItemColor: Colors.grey[400],

          type: BottomNavigationBarType.fixed,
          items: [
            BottomNavigationBarItem(

              icon: Icon(Icons.home, ),
              title: Text('Home', style: TextStyle(fontSize: 12),),
            ),
            BottomNavigationBarItem(
              icon: Icon(Icons.access_time, ),
              title: Text('Scheduler', style: TextStyle(fontSize: 12),),
            ),
            BottomNavigationBarItem(
              icon: Icon(Icons.payment,),
              title: Text('Payment', style: TextStyle( fontSize: 12),),
            ),
            BottomNavigationBarItem(
              icon: Icon(Icons.photo_album, ),
              title: Text("Gallery", style: TextStyle(fontSize: 12),),
            ),
          ],
        ),
      ),
    );
  }
}

class GalleryForm extends StatefulWidget {
  var con;
  GalleryForm(this.con);

  @override
  GalleryState createState() {
    return GalleryState(this.con);
  }
}

class GalleryState extends State<GalleryForm> {
  var con;
  GalleryState(this.con);

  @override
  void initState() {
    super.initState();
    call();
  }

  var entries_count = 0;
  var data = [];
  var entries;
  var a;
  var bytes;
  var updates = [];
  var subset = [];
  var pr_id;
  var dates={};

  call() async {

    SharedPreferences prefs = await SharedPreferences.getInstance();
    pr_id = prefs.getString('project_id');

    var url = 'https://app.buildahome.in/api/get_gallery_data.php?id=$pr_id';

    var response = await http.get(url);
    entries = jsonDecode(response.body);
    entries_count = entries.length;
    for (int i = 0; i < entries_count; i++) {
      if (subset.contains(entries[i]['date']) == false) {
        setState(() {
          subset.add(entries[i]['date']);
        });
      }
    }
  }


  _image_func(_image_string, update_id) {
    var stripped = _image_string
        .toString()
        .replaceFirst(RegExp(r'data:image/jpeg;base64,'), '');
    var imageAsBytes = base64.decode(stripped);

    if (imageAsBytes != null) {
      var actual_image = new Image.memory(imageAsBytes);
      if (update_id != "From list")
        images[update_id] = _image_string;
      Uint8List bytes = base64Decode(stripped);
      return InkWell(
          child: actual_image,
          onTap: () async {
            Navigator.push(
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
  Widget build(context) {
    return new ListView.builder(
        padding: EdgeInsets.all(10),
        shrinkWrap: true,
        itemCount: subset==null? 0: subset.length,
        itemBuilder: (context, int Index) {

          return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Container(
                  padding: EdgeInsets.only(bottom: 5, top:10),
                  child: Text(subset[Index], style: TextStyle(fontWeight: FontWeight.bold)),
                ),

                Wrap(
                  children: <Widget>[
                    for(int i = 0; i < entries.length; i++)
                      if(entries[i]['date'] == subset[Index])
                        if(images.containsKey(entries[i]['image_id']))
                          Container(

                              width: (MediaQuery.of(context).size.width-20)/3,
                              height: (MediaQuery.of(context).size.width-20)/3,
                              decoration: BoxDecoration(
                                border: Border.all(),
                              ),
                              child: _image_func(
                                  images[entries[i]['image_id']], "From list")
                          )
                        else
                          Container(
                            width: (MediaQuery.of(context).size.width - 20) / 3,
                            height: (MediaQuery.of(context).size.width - 20) / 3,
                            decoration: BoxDecoration(
                              border: Border.all(),
                            ),
                            child: InkWell(
                                onTap: ()  {
                                  Navigator.push(
                                    
                                    this.con,
                                    MaterialPageRoute(
                                        builder: (context) => FullScreenImage(
                                            "https://app.buildahome.in/api/images/${entries[i]['image']}"
                                        )),
                                  );
                                },
                                child: CachedNetworkImage(
                                    progressIndicatorBuilder: (context, url, progress) =>
                                        Container(
                                          height: 20, 
                                          width: 20,
                                          child: CircularProgressIndicator(
                                            value: progress.progress,
                                          ),
                                        ),
                                        
                                    imageUrl:
                                        "https://app.buildahome.in/api/images/${entries[i]['image']}",
                                  ),)
                          )
                  ],
                )
              ],
            );



        });

  }
}
