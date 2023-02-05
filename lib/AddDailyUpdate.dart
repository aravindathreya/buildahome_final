import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'NavMenu.dart';
import 'package:multi_image_picker/multi_image_picker.dart';
import 'package:image/image.dart' as FlutterImage;
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import "ShowAlert.dart";
import 'projects.dart';
import 'package:photo_view/photo_view.dart';
import 'main.dart';
import 'utilities/styles.dart';
import 'package:path_provider/path_provider.dart';
import 'dart:async';
import 'dart:io';


class FullScreenImage extends StatefulWidget {
  final id;
  FullScreenImage(this.id);
  @override
  State<FullScreenImage> createState() => FullScreenFlutterImage(this.id);
}

class FullScreenFlutterImage extends State<FullScreenImage> {
  var image;

  FullScreenFlutterImage(this.image);

  @override
  Widget build(BuildContext context1) {
    return MaterialApp(
      theme: ThemeData(fontFamily: App().fontName),
      home: Scaffold(
        appBar: AppBar(
          automaticallyImplyLeading: true,
          title: Text('buildAhome'),
          leading: new IconButton(icon: new Icon(Icons.chevron_left), onPressed: () => {Navigator.pop(context)}),
          backgroundColor: Color(0xFF000055),
        ),
        body: imageOnly(this.image),
      ),
    );
  }
}

class imageOnly extends StatelessWidget {
  final image;
  imageOnly(this.image);
  Widget build(BuildContext context) {
    return Container(decoration: BoxDecoration(border: Border.all(color: Colors.black)), child: PhotoView(minScale: PhotoViewComputedScale.contained, imageProvider: this.image));
  }
}

class AddDailyUpdate extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final appTitle = 'buildAhome';
    final GlobalKey<ScaffoldState> _scaffoldKey = new GlobalKey<ScaffoldState>();
    return MaterialApp(
      title: appTitle,
      theme: ThemeData(fontFamily: App().fontName),
      home: Scaffold(
        key: _scaffoldKey, // ADD THIS LINE
        appBar: AppBar(
          automaticallyImplyLeading: false,
          title: Text(appTitle),
          leading: new IconButton(icon: new Icon(Icons.menu), onPressed: () => _scaffoldKey.currentState.openDrawer()),
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
  var attachPictureButtonText = 'Add picture from phone';
  var dailyUpdateTextController = new TextEditingController();
  var quantityTextController = new TextEditingController();

  var selectedPictures = [];
  var selectedPictureFilenames = [];
  var selectedPictureFilePaths = [];

  final maxImageHeight = 1000;
  final maxImageWidth = 1000;

  var projectNameText = "Choose project";
  var projectId;

  var userId;
  var successfulImageUploadCount = 0;
  var availableResources = ['Mason', 'Helper', 'Carpenter', 'Bar bender', 'Painter', 'Electrician', 'Plumber', 'Tile mason', 'Granite mason', 'Fabricator', 'Other workers', 'Interior carpenter'];
  var tradesmenTextControllers = [new TextEditingController()];
  var tradesmenCountTextControllers = [new TextEditingController()];

  @override
  void initState() {
    super.initState();
    setUserId();
  }

  void showProcessingSelectedPicturesDialog() {
    showDialog(
        barrierDismissible: false,
        context: context,
        builder: (BuildContext context) {
          return AlertDialog(
            content: Text("Processing selected images. Please wait.."),
          );
        });
  }

  setUserId() async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    userId = prefs.getString('user_id');
  }

  Future<File> getImageFileFromAssets(Asset asset) async {
    final byteData = await asset.getByteData(quality: 50);
    final tempFile = File("${(await getTemporaryDirectory()).path}/${asset.name}");
    final file = await tempFile.writeAsBytes(byteData.buffer.asUint8List(byteData.offsetInBytes, byteData.lengthInBytes));
    return file;
  }

  Future processSelectedPicture(picture) async {
    var imageAsFileObject = await getImageFileFromAssets(picture);
    var flutterImageObject = FlutterImage.decodeImage(imageAsFileObject.readAsBytesSync().toList());

    var actualWidth = flutterImageObject.width;
    var actualHeight = flutterImageObject.height;
    while (actualWidth > maxImageWidth || actualHeight > maxImageHeight) {
      actualWidth -= (actualWidth / 10).round();
      actualHeight -= (actualHeight / 10).round();
    }

    var imageAfterResizing = FlutterImage.copyResize(flutterImageObject, width: actualWidth, height: actualHeight);
    var imageFilename = imageAsFileObject.path.split('/')[imageAsFileObject.path.split('/').length - 1].toString();

    selectedPictures.insert(0, MemoryImage(FlutterImage.encodeNamedImage(imageAfterResizing, imageFilename)));
    selectedPictureFilenames.insert(0, imageFilename);
    selectedPictureFilePaths.add(imageAsFileObject.path);
  }

  void selectPicturesFromPhone() async {
    var multiImagePickerResult = await MultiImagePicker.pickImages(
      maxImages: 10,
      materialOptions: MaterialOptions(actionBarColor: "#000055", actionBarTitle: 'buildAhome'),
    );
    showProcessingSelectedPicturesDialog();

    for (var i = 0; i < multiImagePickerResult.length; i++) {
      await processSelectedPicture(multiImagePickerResult[i]);
    }

    Navigator.of(context, rootNavigator: true).pop();
    setState(() {
      attachPictureButtonText = "Add more pictures";
    });
  }

  @override
  Widget build(BuildContext context) {
    return ListView(
      children: <Widget>[
        Column(
          children: <Widget>[
            Container(
                padding: EdgeInsets.only(top: 20, left: 30, right: 30),
                child: InkWell(
                  onTap: () async => selectPicturesFromPhone(),
                  child: Container(
                      decoration: BoxDecoration(
                        color: Colors.white,
                        border: Border.all(width: 1.0, color: Colors.grey[300]),
                        borderRadius: BorderRadius.all(Radius.circular(5)),
                      ),
                      padding: EdgeInsets.all(15),
                      child: Row(
                        children: <Widget>[
                          Container(
                            decoration: BoxDecoration(borderRadius: BorderRadius.all(Radius.circular(50)), color: Colors.white),
                            child: Icon(Icons.add_a_photo, size: 25, color: Colors.indigo[900]),
                          ),
                          Container(padding: EdgeInsets.only(left: 10), child: Text(attachPictureButtonText, style: TextStyle(fontSize: 14)))
                        ],
                      )),
                )),

            //List of images stacked horizontally
            if (selectedPictures.length != 0)
              Container(
                  margin: EdgeInsets.symmetric(horizontal: 30, vertical: 20),
                  child: Container(
                      alignment: Alignment.topLeft,
                      height: 150,
                      child: ListView.builder(
                          shrinkWrap: true,
                          scrollDirection: Axis.horizontal,
                          itemCount: selectedPictures.length,
                          itemBuilder: (BuildContext ctxt, int Index) {
                            return InkWell(
                                onTap: () async {
                                  Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                        builder: (context) => FullScreenImage(
                                              selectedPictures[Index],
                                            )),
                                  );
                                },
                                child: Container(
                                    margin: EdgeInsets.only(right: 10),
                                    height: (MediaQuery.of(context).size.width - 30) / 2,
                                    width: (MediaQuery.of(context).size.width - 30) / 2,
                                    decoration: BoxDecoration(
                                      image: DecorationImage(
                                        image: selectedPictures[Index],
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
                                            borderRadius: BorderRadius.circular(30),
                                          ),
                                          padding: EdgeInsets.all(2),
                                          margin: EdgeInsets.all(5),
                                          child: Icon(Icons.close, size: 15, color: Colors.black)),
                                      onTap: () {
                                        setState(() {
                                          selectedPictures.removeAt(Index);
                                          selectedPictureFilenames.removeAt(Index);
                                          if (selectedPictures.length == 0) {
                                            attachPictureButtonText = "Add picture from phone";
                                          }
                                        });
                                      },
                                    )));
                          }))),
            
            Container(
              child: ListView(
                shrinkWrap: true,
                physics: NeverScrollableScrollPhysics(),
                padding: EdgeInsets.only(top: 15, right: 30, left: 30),
                children: <Widget>[
                  Container(
                      child: ListView.builder(
                          shrinkWrap: true,
                          itemCount: tradesmenTextControllers.length,
                          itemBuilder: (BuildContext ctxt, int Index) {
                            return Row(
                              children: [
                                InkWell(
                                  child: Container(
                                    padding: EdgeInsets.symmetric(horizontal: 10, vertical: 13),
                                    width: ((MediaQuery.of(context).size.width - 70) * .5),
                                    margin: EdgeInsets.only(right: 10, bottom: 10, top: 10),
                                    alignment: Alignment.center,
                                    decoration: BoxDecoration(color: Colors.grey[300], border: Border.all(color: Colors.grey[300], width: 1.5)),
                                    child: Text(tradesmenTextControllers[Index].text != null && tradesmenTextControllers[Index].text != '' ? tradesmenTextControllers[Index].text : "Select tradesmen", style: get_button_text_style()),
                                  ),
                                  onTap: () async {
                                    //Get the project name to which the user wants to upload
                                    var unitDetails = await showDialog(
                                        context: context,
                                        builder: (BuildContext context) {
                                          return AlertDialog(
                                              contentPadding: EdgeInsets.all(10),
                                              content: Column(children: [
                                                Container(alignment: Alignment.centerLeft, padding: EdgeInsets.all(10), child: Text("Select tradesmen")),
                                                Container(
                                                    height: MediaQuery.of(context).size.height - 180,
                                                    width: MediaQuery.of(context).size.width - 20,
                                                    child: ListView.builder(
                                                        shrinkWrap: true,
                                                        physics: new BouncingScrollPhysics(),
                                                        scrollDirection: Axis.vertical,
                                                        itemCount: availableResources.length,
                                                        itemBuilder: (BuildContext ctxt, int Index) {
                                                          return Container(
                                                              padding: EdgeInsets.all(20),
                                                              decoration: BoxDecoration(
                                                                color: Colors.white,
                                                                shape: BoxShape.rectangle,
                                                                border: Border(
                                                                  bottom: BorderSide(width: 1.0, color: Colors.grey[300]),
                                                                ),
                                                              ),
                                                              child: InkWell(
                                                                  onTap: () {
                                                                    Navigator.pop(context, availableResources[Index]);
                                                                  },
                                                                  child: Text(availableResources[Index], style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold))));
                                                        }))
                                              ]));
                                        });
                                    setState(() {
                                      if (unitDetails != null)
                                        tradesmenTextControllers[Index].text = unitDetails;
                                      else
                                        tradesmenTextControllers[Index].text = null;
                                    });
                                  },
                                ),
                                Container(
                                    width: ((MediaQuery.of(context).size.width - 70) * .3),
                                    child: TextFormField(
                                      textAlign: TextAlign.center,
                                      controller: tradesmenCountTextControllers[Index],
                                      style: TextStyle(fontSize: 14),
                                      keyboardType: TextInputType.numberWithOptions(),
                                      decoration: InputDecoration(
                                        contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 0),
                                        border: OutlineInputBorder(
                                          borderRadius: BorderRadius.zero,
                                          borderSide: BorderSide(
                                            color: Colors.grey[100],
                                            width: .5,
                                          ),
                                        ),
                                        floatingLabelBehavior: FloatingLabelBehavior.never,
                                        fillColor: Colors.white,
                                        focusColor: Colors.white,
                                        filled: true,
                                        hintText: 'Nos',
                                      ),
                                    )),
                                if (Index != 0)
                                  InkWell(
                                      onTap: () {
                                        setState(() {
                                          tradesmenTextControllers.removeAt(Index);
                                          tradesmenCountTextControllers.removeAt(Index);
                                        });
                                      },
                                      child: Container(margin: EdgeInsets.only(left: 10), child: Icon(Icons.close, color: Colors.red)))
                              ],
                            );
                          })),
                  InkWell(
                    child: Container(
                      padding: EdgeInsets.symmetric(horizontal: 10, vertical: 13),
                      margin: EdgeInsets.only(bottom: 10, top: 10),
                      width: 150,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(borderRadius: BorderRadius.circular(5), border: Border.all(color: Colors.grey[500], width: 1.5)),
                      child: Row(
                        children: [Container(margin: EdgeInsets.only(right: 15), child: Icon(Icons.add)), Text('Add tradesmen', style: get_button_text_style())],
                      ),
                    ),
                    onTap: () {
                      setState(() {
                        tradesmenTextControllers.add(new TextEditingController());
                        tradesmenCountTextControllers.add(new TextEditingController());
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
                            right: BorderSide(width: 2.0, color: Colors.black54),
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
                                style: TextStyle(fontSize: 18, color: Colors.white),
                              )),
                        ],
                      )),
                  Container(
                      alignment: Alignment.topLeft,
                      child: TextFormField(
                        autocorrect: true,
                        controller: dailyUpdateTextController,
                        keyboardType: TextInputType.multiline,
                        textCapitalization: TextCapitalization.sentences,
                        maxLines: 8,
                        style: TextStyle(fontSize: 18),
                        decoration: InputDecoration(
                            focusColor: Colors.black,
                            floatingLabelBehavior: FloatingLabelBehavior.never,
                            errorBorder: OutlineInputBorder(
                              borderSide: BorderSide(color: Colors.indigo[900], width: 1.0),
                            ),
                            focusedBorder: OutlineInputBorder(
                              borderSide: BorderSide(color: Colors.indigo[900], width: 1.0),
                            ),
                            enabledBorder: OutlineInputBorder(
                              borderSide: BorderSide(color: Colors.black, width: 1.0),
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
                            style: TextStyle(fontSize: 18, color: Colors.white, fontWeight: FontWeight.bold),
                          ),
                        ),
                        onTap: () async {
                          var tradesmenMap = {};
                          for (int i = 0; i < tradesmenTextControllers.length; i++) {
                            if (tradesmenTextControllers[i].text != '' || tradesmenCountTextControllers[i].text != '') {
                              if (tradesmenTextControllers[i].text == '' || tradesmenTextControllers[i].text == null) {
                                showDialog(
                                    context: context,
                                    builder: (BuildContext context) {
                                      return AlertDialog(
                                        content: Text("Please Select tradesmen to continue"),
                                      );
                                    });
                                return;
                              }
                              if (tradesmenCountTextControllers[i].text == '' || tradesmenCountTextControllers[i].text == null) {
                                showDialog(
                                    context: context,
                                    builder: (BuildContext context) {
                                      return AlertDialog(
                                        content: Text("Please enter number of tradesmen to continue"),
                                      );
                                    });
                                return;
                              }
                              tradesmenMap[tradesmenTextControllers[i].text] = tradesmenCountTextControllers[i].text;
                            }
                          }
                          if (dailyUpdateTextController.text.trim() == "") {
                            showDialog(
                                context: context,
                                builder: (BuildContext context) {
                                  return AlertDialog(
                                    content: Text("Update text field should not be empty"),
                                  );
                                });
                          } else {
                            //Get the project name to which the user wants to upload
                            var projectName = await showDialog(
                                context: context,
                                builder: (BuildContext context) {
                                  return ProjectsModal(userId);
                                });
                            projectName = projectName.split("|");
                            setState(() {
                              projectNameText = projectName[0];
                              projectId = projectName[1];
                            });

                            showDialog(
                                barrierDismissible: false,
                                context: context,
                                builder: (BuildContext context) {
                                  return ShowAlert("Submitting update", false);
                                });



                            var url = 'https://app.buildahome.in/api/add_daily_update.php';
                            for (int x = 0; x < selectedPictures.length; x++) {
                               Navigator.of(context, rootNavigator: true).pop('dialog');
                               showDialog(
                                barrierDismissible: false,
                                context: context,
                                builder: (BuildContext context) {
                                  return ShowAlert("Uploading picture ${successfulImageUploadCount + 1} of ${selectedPictureFilePaths.length}..", false);
                                }); 

                              var response = await http.post(Uri.parse(url), body: {
                                'pr_id': projectId.toString(),
                                'date': new DateFormat('EEEE MMMM dd').format(DateTime.now()).toString(),
                                'desc': dailyUpdateTextController.text,
                                'image': selectedPictureFilenames[x].toString(),
                                'tradesmenMap': tradesmenMap.toString(),
                              });

                              var uri = Uri.parse("https://app.buildahome.in/erp/API/dpr_image_upload");
                              var request = new http.MultipartRequest("POST", uri);

                              var pic = await http.MultipartFile.fromPath("image", selectedPictureFilePaths[x]);

                              request.files.add(pic);
                              var fileResponse = await request.send();
                              var responseData = await fileResponse.stream.toBytes();
                              var responseString = String.fromCharCodes(responseData);

                              if (responseString.trim().toString() == "success") {
                                successfulImageUploadCount += 1;
                                if (successfulImageUploadCount == selectedPictureFilePaths.length) {
                                  await Navigator.of(context, rootNavigator: true).pop('dialog');
                                  await showDialog(
                                      context: context,
                                      builder: (BuildContext context) {
                                        return ShowAlert("DPR added succesfully", false);
                                      });
                                  setState(() {
                                    selectedPictures.clear();
                                    selectedPictureFilePaths.clear();
                                    dailyUpdateTextController.text = '';
                                    tradesmenTextControllers.clear();
                                    tradesmenCountTextControllers.clear();
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
