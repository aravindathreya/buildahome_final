import 'package:flutter/material.dart';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'dart:typed_data';
import 'package:shared_preferences/shared_preferences.dart';
import "FullScreenImage.dart";
import 'package:cached_network_image/cached_network_image.dart';
import './AnimationHelper.dart';
import 'NavMenu.dart';
import 'main.dart';
import 'UserHome.dart';
import 'Scheduler.dart';
import 'NotesAndComments.dart';

var images = {};

class Gallery extends StatelessWidget {
  @override
  Widget build(context) {
    final appTitle = 'buildAhome';
    final GlobalKey<ScaffoldState> _scaffoldKey = new GlobalKey<ScaffoldState>();
    return MaterialApp(
      title: appTitle,
      theme: ThemeData(fontFamily: App().fontName),
      home: Scaffold(
        key: _scaffoldKey,
        backgroundColor: Color.fromARGB(255, 233, 233, 233),
        drawer: NavMenuWidget(),
        appBar: AppBar(
          automaticallyImplyLeading: false,
          title: Text(
            appTitle,
            style: TextStyle(color: Color.fromARGB(255, 224, 224, 224), fontSize: 16),
          ),
          leading: new IconButton(
              icon: new Icon(Icons.menu),
              onPressed: () async {
                SharedPreferences prefs = await SharedPreferences.getInstance();
                var username = prefs.getString('username');
                _scaffoldKey.currentState!.openDrawer();
              }),
          backgroundColor: Color.fromARGB(255, 6, 10, 43),
        ),
        body: GalleryForm(context),
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
  var dates = {};

  call() async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    pr_id = prefs.getString('project_id');

    var url = 'https://office.buildahome.in/API/get_gallery_data?id=$pr_id';

    var response = await http.get(Uri.parse(url));
    entries = jsonDecode(response.body);
    print(entries);
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
    var stripped = _image_string.toString().replaceFirst(RegExp(r'data:image/jpeg;base64,'), '');
    var imageAsBytes = base64.decode(stripped);

    if (imageAsBytes != null) {
      var actual_image = new Image.memory(imageAsBytes);
      if (update_id != "From list") images[update_id] = _image_string;
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
        color: Colors.grey[200],
      );
    }
  }

  @override
  Widget build(context) {
    return Container(
        height: MediaQuery.of(context).size.height,
        width: MediaQuery.of(context).size.width,
        child: Stack(alignment: Alignment.bottomCenter, children: [
          Container(
            padding: EdgeInsets.only(bottom: 100),
            child: new ListView.builder(
                padding: EdgeInsets.all(10),
                shrinkWrap: true,
                itemCount: subset == null ? 0 : subset.length,
                itemBuilder: (context, int Index) {
                  return AnimatedWidgetSlide(
                      direction: SlideDirection.bottomToTop, // Specify the slide direction
                      duration: Duration(milliseconds: 300),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          Container(
                              padding: EdgeInsets.only(bottom: 15, top: 25),
                              child: Row(
                                children: [
                                  Icon(Icons.date_range, color: Color.fromARGB(255, 44, 44, 44)),
                                  SizedBox(
                                    width: 10,
                                  ),
                                  Text(subset[Index], style: TextStyle(fontWeight: FontWeight.w600, fontSize: 12, color: Color.fromARGB(255, 44, 44, 44))),
                                ],
                              )),
                          Wrap(
                            children: <Widget>[
                              for (int i = 0; i < entries.length; i++)
                                if (entries[i]['date'] == subset[Index])
                                  if (images.containsKey(entries[i]['image_id']))
                                    Container(
                                        width: (MediaQuery.of(context).size.width - 20) / 3,
                                        height: (MediaQuery.of(context).size.width - 20) / 3,
                                        decoration: BoxDecoration(
                                          border: Border.all(),
                                        ),
                                        child: _image_func(images[entries[i]['image_id']], "From list"))
                                  else
                                    Container(
                                        width: (MediaQuery.of(context).size.width - 20) / 3,
                                        height: (MediaQuery.of(context).size.width - 20) / 3,
                                        decoration: BoxDecoration(
                                          border: Border.all(width: 0.5, color: Colors.grey[300]!),
                                        ),
                                        child: InkWell(
                                          onTap: () {
                                            Navigator.push(
                                              this.con,
                                              MaterialPageRoute(builder: (context) => FullScreenImage("https://app.buildahome.in/api/images/${entries[i]['image']}")),
                                            );
                                          },
                                          child: CachedNetworkImage(
                                            fit: BoxFit.cover,
                                            progressIndicatorBuilder: (context, url, progress) => Container(
                                              height: 20,
                                              width: 20,
                                            ),
                                            imageUrl: "https://app.buildahome.in/api/images/${entries[i]['image']}",
                                          ),
                                        ))
                            ],
                          )
                        ],
                      ));
                }),
          ),
         Container(
            decoration: BoxDecoration(
              color: const Color.fromARGB(255, 223, 223, 223)
            ),
            padding: EdgeInsets.only(top: 15, bottom: 1),
            child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
             InkWell(
                    onTap: () {
                      Navigator.push(
                          context,
                          PageRouteBuilder(
                            pageBuilder: (context, animation, secondaryAnimation) => Home(),
                            transitionsBuilder: (context, animation, secondaryAnimation, child) {
                              return SlideTransition(
                                position: Tween<Offset>(
                                  begin: const Offset(-1.0, 0.0),
                                  end: Offset.zero,
                                ).animate(animation),
                                child: child,
                              );
                            },
                          ),
                        );
                    },
                    child: Container(
                      height: 50,
                      child: Column(
                        children: [
                          Icon(
                            Icons.home_rounded,
                            size: 20,
                            color: Color.fromARGB(255, 100, 100, 100),
                          ),
                          Text(
                            'Home',
                            style: TextStyle(color: Color.fromARGB(255, 100, 100, 100), fontSize: 12),
                          )
                        ],
                      ),
                    ),
                  ),
              InkWell(
               onTap: () {
                  Navigator.push(
                          context,
                          PageRouteBuilder(
                            pageBuilder: (context, animation, secondaryAnimation) => TaskWidget(),
                            transitionsBuilder: (context, animation, secondaryAnimation, child) {
                              return SlideTransition(
                                position: Tween<Offset>(
                                  begin: const Offset(-1.0, 0.0),
                                  end: Offset.zero,
                                ).animate(animation),
                                child: child,
                              );
                            },
                          ),
                        );
                },
                child: Container(
                  height: 50,
                  child: Column(children: [
                  Icon(Icons.alarm, size: 20, color: const Color.fromARGB(255, 100, 100, 100),),
                  Text('Schedule', style: TextStyle(color:  Color.fromARGB(255, 100, 100, 100), fontSize: 12))
                ],),
                )
              ),
              Container(
                  height: 50,
                  child: Column(children: [
                  Icon(Icons.photo_library, size: 25, color:  const Color.fromARGB(255, 46, 46, 46),),
                  Text('Gallery', style: TextStyle(color:  const Color.fromARGB(255, 46, 46, 46), fontSize: 12),)
                ],),
                ),
              InkWell(
                onTap: () {
                   Navigator.push(
                          context,
                          PageRouteBuilder(
                            pageBuilder: (context, animation, secondaryAnimation) => NotesAndComments(),
                            transitionsBuilder: (context, animation, secondaryAnimation, child) {
                              return SlideTransition(
                                position: Tween<Offset>(
                                  begin: const Offset(1.0, 0.0),
                                  end: Offset.zero,
                                ).animate(animation),
                                child: child,
                              );
                            },
                          ),
                        );
                },
                child: Container(
                  height: 50,
                  child: Column(children: [
                  Icon(Icons.update, size: 20, color:  Color.fromARGB(255, 100, 100, 100),),
                  Text('Notes', style: TextStyle(color:  Color.fromARGB(255, 100, 100, 100), fontSize: 12),)
                ],),
                )
              ),
            ],
          )
        
          ),
        ]));
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

class _AnimatedWidgetSlideState extends State<AnimatedWidgetSlide>
with SingleTickerProviderStateMixin {
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