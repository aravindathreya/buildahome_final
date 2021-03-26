import 'package:flutter/material.dart';
import 'package:flutter/widgets.dart';
import 'dart:convert';
import 'package:http/http.dart' as http;
import '../NavMenu.dart';
import 'package:photo_view/photo_view.dart';
import 'dart:typed_data';
import 'package:shared_preferences/shared_preferences.dart';
import '../main.dart';
import 'package:cached_network_image/cached_network_image.dart';
import "Dpr.dart";
import "Scheduler.dart";
import "Payments.dart";
import "Drawings.dart";
import 'newRoute.dart';

var images = {};
class FullScreenImage extends StatefulWidget {
  var id;

  FullScreenImage(this.id);

  @override
  State<FullScreenImage> createState() => FullScreenImage1(this.id);
}

class FullScreenImage1 extends State<FullScreenImage> {
  var image;

  FullScreenImage1(this.image);

  

  @override
  Widget build(BuildContext context) {
      return Container(
          decoration: BoxDecoration(border: Border.all(color: Colors.black)),
          child: PhotoView(
            imageProvider:  CachedNetworkImageProvider(
                                       this.image,
                                  ),)
          );
    }
}

class Gallery extends StatelessWidget{
  
  var id;
  Gallery(this.id);

  @override
  Widget build(BuildContext context) {
      return MaterialApp(
      title: "buildAhome",
      theme: ThemeData(fontFamily: MyApp().fontName),
      home: Scaffold(
        
        drawer: NavMenuWidget(),
        appBar: AppBar(
          automaticallyImplyLeading: false,
          title: Text("buildAhome"),
          leading: new IconButton(
              icon: new Icon(Icons.arrow_back_ios),
              onPressed: () => {
                    Navigator.pop(context),
                  }),
          backgroundColor: Color(0xFF000055),
        ),
        body: GalleryForm(this.id, context),
        bottomNavigationBar: BottomNavigationBar(
          currentIndex: 2,
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
              title: Text(
                'Home',
                style: TextStyle(fontSize: 12),
              ),
            ),
            BottomNavigationBarItem(
              icon: Icon(
                Icons.picture_as_pdf,
              ),
              title: Text(
                'Drawings',
                style: TextStyle(fontSize: 12),
              ),
            ),
            BottomNavigationBarItem(
              icon: Icon(
                Icons.photo_album,
              ),
              title: Text(
                "Gallery",
                style: TextStyle(fontSize: 12),
              ),
            ),          
          ],
        ),
        
      ),
    );
  
  }
  
}


class GalleryForm extends StatefulWidget {
  var id;
  var con;

  GalleryForm(this.id, this.con);

  @override
  GalleryState createState() {
    return GalleryState(this.id, this.con);
  }
}

class GalleryState extends State<GalleryForm> {
  var id;
  var con;

  GalleryState(this.id, this.con);

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
  var dates = {};

  call() async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    pr_id = prefs.getString('project_id');

    var url = 'https://www.buildahome.in/api/get_gallery_data.php?id=$pr_id';

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
      if (update_id != "From list") images[update_id] = _image_string;
      Uint8List bytes = base64Decode(stripped);
      return InkWell(
          child: actual_image,
          onTap: ()  {
            BuildContext context2;
            Navigator.push(
              context2,
              MaterialPageRoute(
                  builder: (context2) => FullScreenImage(
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
        itemCount: subset == null ? 0 : subset.length,
        itemBuilder: (BuildContext ctxt, int Index) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Container(
                padding: EdgeInsets.only(bottom: 5, top: 10),
                child: Text(subset[Index],
                    style: TextStyle(fontWeight: FontWeight.bold)),
              ),
              Wrap(
                children: <Widget>[
                  for (int i = 0; i < entries.length; i++)
                    if (entries[i]['date'] == subset[Index])
                      if (images.containsKey(entries[i]['image_id']))
                        Container(
                            width: (MediaQuery.of(context).size.width - 20) / 3,
                            height:
                                (MediaQuery.of(context).size.width - 20) / 3,
                            decoration: BoxDecoration(
                              border: Border.all(),
                            ),
                            child: _image_func(
                                images[entries[i]['image_id']], "From list"))
                      else
                        Container(
                          width: (MediaQuery.of(context).size.width - 20) / 3,
                          height: (MediaQuery.of(context).size.width - 20) / 3,
                          decoration: BoxDecoration(
                            border: Border.all(),
                          ),
                          child: InkWell(
                              onLongPress: () {
                                showDialog(
                                    context: context,
                                    child: AlertDialog(
                                        content: Container(
                                            height: 120,
                                            child: Column(
                                              children: <Widget>[
                                                Container(
                                                  child: Text(
                                                      "Are you sure you want to delete this image?",
                                                      style: TextStyle(
                                                          fontSize: 18)),
                                                ),
                                                Container(
                                                    alignment:
                                                        Alignment.bottomRight,
                                                    margin: EdgeInsets.only(
                                                        top: 15),
                                                    child: Row(
                                                      mainAxisAlignment:
                                                          MainAxisAlignment.end,
                                                      children: <Widget>[
                                                        InkWell(
                                                          onTap: () {
                                                            Navigator.of(context, rootNavigator: true).pop('dialog');
                                                          },
                                                            child: Container(
                                                                padding:
                                                                    EdgeInsets
                                                                        .all(
                                                                            10),
                                                                margin: EdgeInsets
                                                                    .only(
                                                                        left:
                                                                            15),
                                                                decoration: BoxDecoration(
                                                                    color: Colors
                                                                        .white24,
                                                                    borderRadius:
                                                                        BorderRadius
                                                                            .circular(
                                                                                5),
                                                                    border: Border
                                                                        .all()),
                                                                child: Text(
                                                                  "Cancel",
                                                                  style:
                                                                      TextStyle(),
                                                                ))),
                                                        InkWell(
                                                            onTap: () async {
                                                              var id = entries[
                                                                      i]
                                                                  ['image_id'];
                                                              var url =
                                                                  'https://www.buildahome.in/api/delete_image.php?id=${id}';
                                                              var response =
                                                                  await http
                                                                      .get(url);

                                                              setState(() {
                                                                Navigator.of(context, rootNavigator: true).pop('dialog');
                                                                Navigator
                                                                    .pushReplacement(
                                                                  context,
                                                                  MaterialPageRoute(
                                                                      builder: (context) =>
                                                                          Gallery(
                                                                              this.id)),
                                                                );
                                                              });
                                                            },
                                                            child: Container(
                                                                margin: EdgeInsets
                                                                    .only(
                                                                        left:
                                                                            15),
                                                                padding:
                                                                    EdgeInsets
                                                                        .all(
                                                                            10),
                                                                decoration:
                                                                    BoxDecoration(
                                                                  color: Colors
                                                                          .indigo[
                                                                      900],
                                                                  borderRadius:
                                                                      BorderRadius
                                                                          .circular(
                                                                              5),
                                                                ),
                                                                child: Text(
                                                                  "Yes, Delete",
                                                                  style: TextStyle(
                                                                      color: Colors
                                                                          .white),
                                                                ))),
                                                      ],
                                                    ))
                                              ],
                                            ))));
                              },
                              onTap: ()  {
                                Navigator.push(
                                  this.con,
                                  MaterialPageRoute(
                                        builder: (context) => FullScreenImage(
                                            "https://buildahome.in/api/images/${entries[i]['image']}"
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
                                        "https://buildahome.in/api/images/${entries[i]['image']}",
                                  ),)
                        )
                ],
              )
            ],
          );
        });
  }
}
