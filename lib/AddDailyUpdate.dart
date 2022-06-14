import 'package:buildahome/AdminDashboard.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'NavMenu.dart';
import 'package:file_picker/file_picker.dart';
import 'package:image_picker/image_picker.dart';
import 'package:multi_image_picker/multi_image_picker.dart';
import 'package:image/image.dart' as Image;
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import "ShowAlert.dart";
import 'projects.dart';
import "UpdateTemplates.dart";
import 'package:photo_view/photo_view.dart';
import 'main.dart';
import 'utilities/styles.dart';
import 'widgets/material.dart';
import 'widgets/material_units.dart';
import 'package:path_provider/path_provider.dart';
import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart' show rootBundle;

class FullScreenImage extends StatelessWidget {
  var image;
  FullScreenImage(this.image);
  Widget build(BuildContext context) {
    return Container(
        decoration: BoxDecoration(border: Border.all(color: Colors.black)),
        child: PhotoView(imageProvider: this.image));
  }
}

class AddDailyUpdate extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final appTitle = 'buildAhome';
    final GlobalKey<ScaffoldState> _scaffoldKey =
        new GlobalKey<ScaffoldState>();
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
          backgroundColor: Color(0xFF000055),
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
  var addPictureBtnText = "Add pictures from phone";
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
  var resource = 'Select tradesmen';
  var quantityTextController = new TextEditingController();
  var availableResources = [
    'Mason',
    'Helper',
    'Carpenter',
    'Barbender',
    'Painter',
    'Electrician',
    'Plumber',
    'Tile mason',
    'Granite mason',
    'Fabricator',
    'Other workers',
    'Interior carpenter'
  ];
  var tradesmen = [new TextEditingController()];
  var nos = [new TextEditingController()];

  @override
  void initState() {
    super.initState();
    _updateText = TextEditingController();
    call();
  }

  call() async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    user_id = prefs.getString('user_id');
  }

  Future<File> getImageFileFromAssets(Asset asset) async {
    final byteData = await asset.getByteData();

    final tempFile =
        File("${(await getTemporaryDirectory()).path}/${asset.name}");
    final file = await tempFile.writeAsBytes(
      byteData.buffer
          .asUint8List(byteData.offsetInBytes, byteData.lengthInBytes),
    );

    return file;
  }

  void getFile() async {
    var images = await MultiImagePicker.pickImages(
      maxImages: 10,
      materialOptions: MaterialOptions(
          actionBarColor: "#000055", actionBarTitle: 'buildAhome'),
    );
    for (var i = 0; i < images.length; i++) {
      print(images[i]);
      var image = await getImageFileFromAssets(images[i]);
      _imgpath = image.path;

      actual_filename =
          _imgpath.split('/')[_imgpath.split('/').length - 1].toString();

      update_pictures_b64.insert(0, image.readAsBytesSync().toList());
      update_pictures.insert(0, MemoryImage(image.readAsBytesSync()));
      update_pictures_names.insert(0, actual_filename);

      addPictureBtnText = "Add more pictures";
      pictures_path.add(image);
    }

    setState(() {});

//    Timer.periodic(new Duration(seconds: 1), (timer) {
//      if (timer.tick == 2) {
//        compressimage();
//      }
//    });
  }

  postImage(image) async {
    var uri = Uri.parse("https://app.buildahome.in/api/upload_image.php");
    var request = new http.MultipartRequest("POST", uri);

    var pic = await http.MultipartFile.fromPath("image", image.path);

    request.files.add(pic);
    var response = await request.send();
    var responseData = await response.stream.toBytes();
    var responseString = String.fromCharCodes(responseData);
    print(responseData);
    print(responseString);
    print(responseString.trim().toString() == "success");
    if (responseString.trim().toString() == "success") {
      success_response += 1;
      print(success_response);
      if (success_response == pictures_path.length) {
        Navigator.of(context, rootNavigator: true).pop('dialog');
        showDialog(
            context: context,
            builder: (BuildContext context) {
              return ShowAlert("Thanks for the update", false);
            });
        Navigator.push(
          context,
          MaterialPageRoute(builder: (context) => AdminDashboard()),
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
                                  offset: new Offset(5.0, 5.0))
                            ],
                          ),
                          padding: EdgeInsets.all(15),
                          child: Row(
                            children: <Widget>[
                              Container(
                                decoration: BoxDecoration(
                                    borderRadius:
                                        BorderRadius.all(Radius.circular(50)),
                                    color: Colors.white),
                                child: Icon(Icons.add_a_photo,
                                    size: 25, color: Colors.indigo[900]),
                              ),
                              Container(
                                  padding: EdgeInsets.only(left: 10),
                                  child: Text(addPictureBtnText,
                                      style: TextStyle(fontSize: 18)))
                            ],
                          )),
                    )),

                //List of images stacked horizontally
                if (update_pictures.length != 0)
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
                                        context,
                                        MaterialPageRoute(
                                            builder: (context) =>
                                                FullScreenImage(
                                                  update_pictures[Index],
                                                )),
                                      );
                                    },
                                    child: Container(
                                        margin: EdgeInsets.only(right: 10),
                                        height:
                                            (MediaQuery.of(context).size.width -
                                                    30) /
                                                2,
                                        width:
                                            (MediaQuery.of(context).size.width -
                                                    30) /
                                                2,
                                        decoration: BoxDecoration(
                                          image: DecorationImage(
                                            image: update_pictures[Index],
                                            fit: BoxFit.cover,
                                          ),
                                          border:
                                              Border.all(color: Colors.grey),
                                          borderRadius:
                                              BorderRadius.circular(13),
                                        ),
                                        alignment: Alignment.topRight,
                                        child: InkWell(
                                          child: Container(
                                              height: 30,
                                              width: 30,
                                              decoration: BoxDecoration(
                                                color: Colors.white,
                                                border: Border.all(),
                                                borderRadius:
                                                    BorderRadius.circular(30),
                                              ),
                                              padding: EdgeInsets.all(2),
                                              margin: EdgeInsets.all(5),
                                              child: Icon(Icons.close,
                                                  size: 15,
                                                  color: Colors.black)),
                                          onTap: () {
                                            setState(() {
                                              update_pictures.removeAt(Index);
                                              update_pictures_names
                                                  .removeAt(Index);
                                              if (update_pictures.length == 0) {
                                                addPictureBtnText =
                                                    "Add picture from phone";
                                              }
                                            });
                                          },
                                        )));
                              }))),
              ],
            ),
            Container(
              child: ListView(
                shrinkWrap: true,
                physics: NeverScrollableScrollPhysics(),
                padding: EdgeInsets.only(top: 15, right: 30, left: 30),
                children: <Widget>[
                  Container(
                      child: ListView.builder(
                          shrinkWrap: true,
                          itemCount: tradesmen.length,
                          itemBuilder: (BuildContext ctxt, int Index) {
                            return Row(
                              children: [
                                InkWell(
                                  child: Container(
                                    padding: EdgeInsets.symmetric(
                                        horizontal: 10, vertical: 13),
                                    width: (MediaQuery.of(context).size.width *
                                            .7) -
                                        20,
                                    margin: EdgeInsets.only(
                                        right: 10, bottom: 10, top: 10),
                                    alignment: Alignment.center,
                                    decoration: BoxDecoration(
                                        color: Colors.grey[300],
                                        border: Border.all(
                                            color: Colors.grey[500],
                                            width: 1.5)),
                                    child: Text(
                                        tradesmen[Index].text != null &&
                                                tradesmen[Index].text != ''
                                            ? tradesmen[Index].text
                                            : "Select tradesmen",
                                        style: get_button_text_style()),
                                  ),
                                  onTap: () async {
                                    //Get the project name to which the user wants to upload
                                    var unitDetails = await showDialog(
                                        context: context,
                                        builder: (BuildContext context) {
                                          return AlertDialog(
                                              contentPadding:
                                                  EdgeInsets.all(10),
                                              content: Column(children: [
                                                Container(
                                                    alignment:
                                                        Alignment.centerLeft,
                                                    padding: EdgeInsets.all(10),
                                                    child: Text(
                                                        "Select tradesmen")),
                                                Container(
                                                    height:
                                                        MediaQuery.of(context)
                                                                .size
                                                                .height -
                                                            130,
                                                    width:
                                                        MediaQuery.of(context)
                                                                .size
                                                                .width -
                                                            20,
                                                    child: ListView.builder(
                                                        shrinkWrap: true,
                                                        physics:
                                                            new BouncingScrollPhysics(),
                                                        scrollDirection:
                                                            Axis.vertical,
                                                        itemCount:
                                                            availableResources
                                                                .length,
                                                        itemBuilder:
                                                            (BuildContext ctxt,
                                                                int Index) {
                                                          return Container(
                                                              padding:
                                                                  EdgeInsets
                                                                      .all(20),
                                                              decoration:
                                                                  BoxDecoration(
                                                                color: Colors
                                                                    .white,
                                                                shape: BoxShape
                                                                    .rectangle,
                                                                border: Border(
                                                                  bottom: BorderSide(
                                                                      width:
                                                                          1.0,
                                                                      color: Colors
                                                                              .grey[
                                                                          300]),
                                                                ),
                                                              ),
                                                              child: InkWell(
                                                                  onTap: () {
                                                                    Navigator.pop(
                                                                        context,
                                                                        availableResources[
                                                                            Index]);
                                                                  },
                                                                  child: Text(
                                                                      availableResources[
                                                                          Index],
                                                                      style: TextStyle(
                                                                          fontSize:
                                                                              18,
                                                                          fontWeight:
                                                                              FontWeight.bold))));
                                                        }))
                                              ]));
                                        });
                                    setState(() {
                                      if (unitDetails != null)
                                        tradesmen[Index].text = unitDetails;
                                      else
                                        tradesmen[Index].text = null;
                                    });
                                  },
                                ),
                                Container(
                                    width: (MediaQuery.of(context).size.width *
                                            .3) -
                                        50,
                                    child: TextFormField(
                                      textAlign: TextAlign.center,
                                      controller: nos[Index],
                                      keyboardType:
                                          TextInputType.numberWithOptions(),
                                      decoration: InputDecoration(
                                        contentPadding: EdgeInsets.symmetric(
                                            horizontal: 10, vertical: 0),
                                        border: OutlineInputBorder(
                                          borderRadius: BorderRadius.zero,
                                          borderSide: BorderSide(
                                            color: Colors.grey[300],
                                            width: 1.0,
                                          ),
                                        ),
                                        hasFloatingPlaceholder: false,
                                        fillColor: Colors.white,
                                        focusColor: Colors.white,
                                        filled: true,
                                        hintText: 'Nos',
                                      ),
                                    )),
                              ],
                            );
                          })),
                  InkWell(
                    child: Container(
                      padding:
                          EdgeInsets.symmetric(horizontal: 10, vertical: 13),
                      margin: EdgeInsets.only(bottom: 10, top: 10),
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(5),
                          border:
                              Border.all(color: Colors.grey[500], width: 1.5)),
                      child: Row(
                        children: [
                          Container(
                              margin: EdgeInsets.only(right: 15),
                              child: Icon(Icons.add)),
                          Text('Add tradesmen', style: get_button_text_style())
                        ],
                      ),
                    ),
                    onTap: () {
                      setState(() {
                        tradesmen.add(new TextEditingController());
                        nos.add(new TextEditingController());
                      });
                    },
                  ),

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
                            right:
                                BorderSide(width: 2.0, color: Colors.black54),
                            top: BorderSide(width: 2.0, color: Colors.black54),
                          )
//                        borderRadius: BorderRadius.all(Radius.circular(5)),
                          ),
                      child: Row(
                        children: <Widget>[
                          Icon(Icons.event_note, size: 25, color: Colors.white),
                          Container(
                              padding: EdgeInsets.only(left: 10),
                              child: Text(
                                DateFormat("dd MMMM").format(DateTime.now()),
                                style: TextStyle(
                                    fontSize: 18, color: Colors.white),
                              )),
                        ],
                      )),
                  Container(
                      alignment: Alignment.topLeft,
                      child: TextFormField(
                        autocorrect: true,
                        controller: _updateText,
                        keyboardType: TextInputType.multiline,
                        textCapitalization: TextCapitalization.sentences,
                        maxLines: 8,
                        style: TextStyle(fontSize: 18),
                        decoration: InputDecoration(
                            focusColor: Colors.black,
                            hasFloatingPlaceholder: false,
                            errorBorder: OutlineInputBorder(
                              borderSide: BorderSide(
                                  color: Colors.indigo[900], width: 1.0),
                            ),
                            focusedBorder: OutlineInputBorder(
                              borderSide: BorderSide(
                                  color: Colors.indigo[900], width: 1.0),
                            ),
                            enabledBorder: OutlineInputBorder(
                              borderSide:
                                  BorderSide(color: Colors.black, width: 1.0),
                            ),
                            filled: true,
                            hintText: "What's done today?",
                            alignLabelWithHint: true,
                            labelText: "Type in update",
                            labelStyle: TextStyle(
                              fontSize: 18,
                            ),
                            fillColor: Colors.white),
                        validator: (value) {
                          if (value.isEmpty) {
                            return 'This field cannot be empty';
                          }
                          return null;
                        },
                      )),

                  // Add update button
                  Container(
                      margin: EdgeInsets.only(bottom: 50),
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
                            style: TextStyle(
                                fontSize: 18,
                                color: Colors.white,
                                fontWeight: FontWeight.bold),
                          ),
                        ),
                        onTap: () async {
                          var tradesmenMap = {};
                          for (int i = 0; i < tradesmen.length; i++) {
                            if (tradesmen[i].text != '' || nos[i].text != '') {
                              if (tradesmen[i].text == '' ||
                                  tradesmen[i].text == null) {
                                showDialog(
                                    context: context,
                                    builder: (BuildContext context) {
                                      return AlertDialog(
                                        content: Text(
                                            "Please Select tradesmen to continue"),
                                      );
                                    });
                                return;
                              }
                              if (nos[i].text == '' || nos[i].text == null) {
                                showDialog(
                                    context: context,
                                    builder: (BuildContext context) {
                                      return AlertDialog(
                                        content: Text(
                                            "Please enter number of tradesmen to continue"),
                                      );
                                    });
                                return;
                              }
                              tradesmenMap[tradesmen[i].text] = nos[i].text;
                            }
                          }
                          if (_updateText.text.trim() == "") {
                            showDialog(
                                context: context,
                                builder: (BuildContext context) {
                                  return AlertDialog(
                                    content: Text(
                                        "Update text field should not be empty"),
                                  );
                                });
                          } else {
                            //Get the project name to which the user wants to upload
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
                                barrierDismissible: false,
                                context: context,
                                builder: (BuildContext context) {
                                  return ShowAlert(
                                      "Hang in there. Submitting update", true);
                                });

                            var url =
                                'https://app.buildahome.in/api/add_daily_update.php';
                            for (int x = 0; x < update_pictures.length; x++) {
                              var response = await http.post(url, body: {
                                'pr_id': project_id.toString(),
                                'date': new DateFormat('EEEE MMMM dd')
                                    .format(DateTime.now())
                                    .toString(),
                                'desc': _updateText.text,
                                'image': update_pictures_names[x].toString(),
                                'tradesmenMap': tradesmenMap.toString(),
                              });

                              var uri = Uri.parse(
                                  "https://app.buildahome.in/erp/API/dpr_image_upload");
                              var request =
                                  new http.MultipartRequest("POST", uri);

                              var pic = await http.MultipartFile.fromPath(
                                  "image", pictures_path[x].path);

                              request.files.add(pic);
                              var fileResponse = await request.send();
                              var responseData =
                                  await fileResponse.stream.toBytes();
                              var responseString =
                                  String.fromCharCodes(responseData);
                              print(responseString);
                              if (responseString.trim().toString() ==
                                  "success") {
                                success_response += 1;
                                if (success_response == pictures_path.length) {
                                  await Navigator.of(context,
                                          rootNavigator: true)
                                      .pop('dialog');
                                  await showDialog(
                                      context: context,
                                      builder: (BuildContext context) {
                                        return ShowAlert(
                                            "DPR added succesfully", false);
                                      });
                                  setState(() {
                                    update_pictures.clear();
                                    pictures_path.clear();
                                    _updateText.text = '';
                                    tradesmen.clear();
                                    nos.clear();
                                  });
                                }
                              }
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
