import 'package:buildahome/AdminDashboard.dart';
import 'package:flutter/material.dart';
import 'package:flutter/material.dart' as prefix0;
import 'package:flutter/rendering.dart';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'NavMenu.dart';
import 'package:file_picker/file_picker.dart';
import 'package:image_picker/image_picker.dart';
import 'package:image/image.dart' as Image;
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import "ShowAlert.dart";
import 'projects.dart';
import "UpdateTemplates.dart";
import 'package:photo_view/photo_view.dart';
import 'main.dart';

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
class AddDailyUpdate extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final appTitle = 'buildAhome';
    final GlobalKey<ScaffoldState> _scaffoldKey = new GlobalKey<
        ScaffoldState>();
    return MaterialApp(
      title: appTitle,
      theme: ThemeData(fontFamily: MyApp().fontName),
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
        body: AddDailyUpdateForm(),
      ),
    );
  }
}

class AddDailyUpdateForm extends StatefulWidget {
  @override
  AddDailyUpdateState createState() {
    return AddDailyUpdateState();
  }
}

class AddDailyUpdateState extends State<AddDailyUpdateForm> {

  var _updateText;
  var addPictureBtnText = "Add picture from phone";
  var _visibility = false;
  String filename = "";
  String _responsetext = "";
  var _imgpath;
  var _b64_image;
  var bytes;
  var actual_filename;
  var compressed = false;
  var project_name = "Choose project";
  var project_id;
  String dropdownValue = 'One'; 
  var update_pictures = [];
  var update_pictures_b64 = [];
  int last_compressed = -1;
  var update_pictures_names = [];
  var user_id;
  var pictures_path = [];
  var success_response = 0;

  @override
  void initState() {
    super.initState();
    _updateText = TextEditingController();
    call();
  }


  call() async{
    SharedPreferences prefs = await SharedPreferences.getInstance();
    user_id = prefs.getString('user_id');

  }

  void getFile() async {
    var image = await ImagePicker.pickImage(source: ImageSource.gallery, imageQuality: 50);
    pictures_path.add(image);
    setState(() {
      _imgpath = image.path;

      actual_filename = _imgpath.split('/')[_imgpath
          .split('/')
          .length - 1].toString();
      update_pictures_b64.add(image.readAsBytesSync().toList());

      update_pictures.add(MemoryImage(image.readAsBytesSync()));
      update_pictures_names.add(actual_filename);
      addPictureBtnText = "Add another picture";
    });


//    Timer.periodic(new Duration(seconds: 1), (timer) {
//      if (timer.tick == 2) {
//        compressimage();
//      }
//    });
  }

  postImage(image) async{

    var uri = Uri.parse("https://app.buildahome.in/api/upload_image.php");
    var request = new http.MultipartRequest("POST", uri);

    var pic = await http.MultipartFile.fromPath("image", image.path);
    //contentType: new MediaType('image', 'png'));

    request.files.add(pic);
    var response = await request.send();
    var responseData = await response.stream.toBytes();
    var responseString = String.fromCharCodes(responseData);
    print(responseData);
    print(responseString);
    print(responseString.trim().toString()=="success");
    if(responseString.trim().toString()=="success"){
      success_response += 1;
      print(success_response);
      if(success_response==pictures_path.length){
        Navigator.of(context, rootNavigator: true)
          .pop('dialog');
        showDialog(
            context: context,  
            builder: (BuildContext context) {
              return ShowAlert(
                  "Thanks for the update", false);
            });
        Navigator.push(
          context,
          MaterialPageRoute(builder: (context) =>
              AdminDashboard()),
        );
      }
    }
    
  }

  void compressimage() async {
    int pic_quality = 1400;
    var image = Image.decodeImage(bytes);
    var resized = Image.copyResizeCropSquare(image, pic_quality);
    var compressed_image = Image.encodePng(resized);
    _b64_image = base64Encode(compressed_image);
    for (int i = 100; _b64_image.length > 300000; i = i + 100) {
      pic_quality = pic_quality - i;
      var resized = Image.copyResizeCropSquare(image, pic_quality);
      var compressed_image = Image.encodePng(resized);
      _b64_image = base64Encode(compressed_image);

    }
    setState(() {
      filename = actual_filename;
      compressed = true;
    });
  }

  @override
  Widget build(BuildContext context) {
    return ListView(
      children: <Widget>[
        Column(
          children: <Widget>[
            Column(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: <Widget>[
                //Add picture from phone button
                Container(
                    padding: EdgeInsets.only(top: 20, left: 30, right: 30),

                    child: InkWell(
                      onTap: () async => getFile(),
                      child: Container(
                          decoration: BoxDecoration(
                            color: Colors.white,
                            border: Border.all(width: 1.0, color: Colors.black),
                            borderRadius: BorderRadius.all(Radius.circular(5)),
                            boxShadow: [
                              new BoxShadow(
                                  color: Colors.grey[500],
                                  blurRadius: 10,
                                  spreadRadius: 1,
                                  offset: new Offset(5.0, 5.0)
                              )
                            ],
                          ), padding: EdgeInsets.all(15),
                          child: Row(
                            children: <Widget>[
                              Container(
                                decoration: BoxDecoration(
                                    borderRadius: BorderRadius.all(
                                        Radius.circular(50)),
                                    color: Colors.white
                                ),
                                child: Icon(Icons.add_a_photo, size: 25,
                                    color: Colors.indigo[900]),
                              ),
                              Container(
                                  padding: EdgeInsets.only(left: 10),
                                  child: Text(addPictureBtnText,
                                      style: TextStyle(fontSize: 18)))
                            ],
                          )),
                    )


                ),



                //List of images stacked horizontally
                if(update_pictures.length != 0)
                  Container(
                      margin:
                      EdgeInsets.symmetric(horizontal: 25, vertical: 20),
                      child: Container(
                          alignment: Alignment.topLeft,
                          height: 150,
                          child: ListView.builder(
                              shrinkWrap: true,

                              scrollDirection: Axis.horizontal,
                              itemCount: update_pictures.length,
                              itemBuilder: (BuildContext ctxt, int Index) {
                                return InkWell(
                                onTap: () async {
                                  Navigator.push(
                                    context, MaterialPageRoute(
                                        builder: (context) => FullScreenImage(
                                        update_pictures[Index],
                                    )),
                                  );
                                },
                                child: Container(
                                      margin: EdgeInsets.only(right: 10),
                                      height: (MediaQuery.of(context).size.width - 30) / 2,
                                      width: (MediaQuery.of(context).size.width - 30) / 2,
                                      decoration: BoxDecoration(
                                        image: DecorationImage(
                                          image: update_pictures[Index],
                                          fit: BoxFit.cover,
                                        ),
                                        border: Border.all(color: Colors.grey),
                                        borderRadius: BorderRadius.circular(13),
                                      ),
                                      alignment: Alignment.topRight,
                                      child: InkWell(
                                        child: Container(
                                            height: 30,
                                            width: 30,
                                            decoration: BoxDecoration(
                                              color: Colors.white,
                                              border: Border.all(),
                                              borderRadius: prefix0.BorderRadius.circular(30),
                                            ),
                                            padding: EdgeInsets.all(2),
                                            margin: EdgeInsets.all(5),
                                            child: Icon(Icons.close, size: 15,  color: Colors.black)
                                        ),
                                        onTap: (){
                                          setState(() {
                                            update_pictures.removeAt(Index);
                                            update_pictures_names.removeAt(Index);
                                            if(update_pictures.length==0){
                                              addPictureBtnText = "Add picture from phone";
                                            }
                                          });
                                        },

                                      )
                                  )
                                );
                              }))),

                // Default update templates
                Container(
                    padding: EdgeInsets.only(top: 20, ),
                    width: MediaQuery.of(context).size.width-60,
                    child: InkWell(
                      onTap: () async {

                        var a = await showDialog(
                            context: context,
                            builder: (BuildContext context) {
                              return UpdateTemplates();
                            });
                        setState(() {
                          _updateText.text = a;
                        });

                      },
                      child: Container(
                          decoration: BoxDecoration(
                            color: Colors.white,
                            border: Border.all(width: 1.0, color: Colors.black),
                            borderRadius: BorderRadius.all(Radius.circular(5)),
                            boxShadow: [
                              new BoxShadow(
                                  color: Colors.grey[500],
                                  blurRadius: 10,
                                  spreadRadius: 1,
                                  offset: new Offset(5.0, 5.0)
                              )
                            ],
                          ), padding: EdgeInsets.all(15),
                          child: Container(
                              padding: EdgeInsets.only(left: 10),
                              child: Text("Choose exisiting update",
                                  style: TextStyle(fontSize: 18)))),
                    )


                ),
              ],
            ),
            Container(
              child: ListView(
                shrinkWrap: true,
                physics: prefix0.NeverScrollableScrollPhysics(),
                padding: EdgeInsets.only(top: 15, right: 30, left: 30),
                children: <Widget>[

                  // Text field card with date header
                  Container(
                      padding: EdgeInsets.all(10),
                      decoration: BoxDecoration(
                          gradient: LinearGradient(
                            // Where the linear gradient begins and ends
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,

                            // Add one stop for each color. Stops should increase from 0 to 1
                            stops: [0.2, 0.4, 0.6, 0.9],
                            colors: [
                              // Colors are easy thanks to Flutter's Colors class.

                              //Colors.blue,
                              Colors.indigo[900],
                              Colors.indigo[600],
                              Colors.indigo[600],
                              //Colors.indigo[700],
                              Colors.indigo[900],
                            ],
                          ),
                          border: Border(
                            left: BorderSide(width: 2.0, color: Colors.black54),
                            right: BorderSide(
                                width: 2.0, color: Colors.black54),
                            top: BorderSide(width: 2.0, color: Colors.black54),
                          )
//                        borderRadius: BorderRadius.all(Radius.circular(5)),
                      ),
                      child: Row(
                        children: <Widget>[
                          Icon(Icons.event_note, size: 25, color: Colors.white),
                          Container(
                              padding: prefix0.EdgeInsets.only(left: 10),
                              child: Text(DateFormat("dd MMMM").format(DateTime
                                  .now()), style: TextStyle(fontSize: 18,
                                  color: Colors.white),)
                          ),


                        ],
                      )

                  ),
                  Container(
                      alignment: Alignment.topLeft,

                      child: TextFormField(
                        autocorrect: true,
                        controller: _updateText,
                        keyboardType: TextInputType.multiline,
                        textCapitalization: prefix0.TextCapitalization.sentences,
                        maxLines: 8,
                        style: prefix0.TextStyle(fontSize: 18),

                        decoration: InputDecoration(
                            focusColor: Colors.black,

                            hasFloatingPlaceholder: false,
                            errorBorder: OutlineInputBorder(
                              borderSide: BorderSide(color: Colors.indigo[900],
                                  width: 1.0),
                            ),
                            focusedBorder: OutlineInputBorder(
                              borderSide: BorderSide(color: Colors.indigo[900],
                                  width: 1.0),
                            ),
                            enabledBorder: OutlineInputBorder(
                              borderSide: BorderSide(color: Colors.black,
                                  width: 1.0),
                            ),
                            filled: true,
                            hintText: "What's done today?",
                            alignLabelWithHint: true,
                            labelText: "Type in update",
                            labelStyle: TextStyle(
                              fontSize: 18,
                            ),
                            fillColor: Colors.white
                        ),
                        validator: (value) {
                          if (value.isEmpty) {
                            return 'This field cannot be empty';
                          }
                          return null;
                        },
                      )),


                  // Add update button
                  Container(
                      padding: const EdgeInsets.only(
                        top: 20,
                      ),
                      child: InkWell(
                        child: Container(
                          alignment: Alignment.center,
                          padding: EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            boxShadow: [
                              new BoxShadow(
                                color: Colors.grey[600],
                                blurRadius: 5,
                                spreadRadius: 1,

                              )
                            ],
                            gradient: LinearGradient(
                              // Where the linear gradient begins and ends
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,

                              // Add one stop for each color. Stops should increase from 0 to 1
                              stops: [0.2, 0.5, 0.8],
                              colors: [
                                // Colors are easy thanks to Flutter's Colors class.

                                //Colors.blue,
                                Colors.indigo[900],
                                Colors.indigo[700],
                                //Colors.indigo[700],
                                Colors.indigo[900],
                              ],
                            ),
                            border: Border.all(color: Colors.black, width: 1),
                            borderRadius: BorderRadius.all(Radius.circular(5)),
                          ),
                          child: Text(
                            "Add update",
                            style: TextStyle(fontSize: 18,
                                color: Colors.white,
                                fontWeight: FontWeight.bold),
                          ),
                        ),
                        onTap: () async {
                          if (true) {
                            var projectName = await showDialog(
                                context: context,
                                builder: (BuildContext context) {

                                  return ProjectsModal(user_id);
                                });
                            projectName = projectName.split("|");
                            setState(() {
                              project_name = projectName[0];
                              project_id = projectName[1];
                            });

                            showDialog(
                                context: context,
                                builder: (BuildContext context) {
                                  return ShowAlert(
                                      "Hang in there. Submitting update", true);
                                });

                            var url =
                                'https://app.buildahome.in/api/add_daily_update.php';
                            for(int x=0;x<update_pictures.length;x++) {
                              var response = await http.post(url, body: {
                                'pr_id': project_id.toString(),
                                'date': new DateFormat('EEEE MMMM dd')
                                    .format(DateTime.now())
                                    .toString(),
                                'desc': _updateText.text,
                                'image': update_pictures_names[x].toString()
                              });
                              postImage(pictures_path[x]);
                            }


                            
                          }
                        },
                      )),
                ],
              ),
            )
          ],
        )
      ],
    );
  }

}
