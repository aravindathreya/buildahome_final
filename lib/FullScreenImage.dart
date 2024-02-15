import 'package:flutter/material.dart';
import 'package:flutter/widgets.dart';
import 'package:photo_view/photo_view.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'main.dart';

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
  Widget build(BuildContext context1) {
    return MaterialApp(
      theme: ThemeData(fontFamily: App().fontName),
      home: Scaffold(
        appBar: AppBar(
          automaticallyImplyLeading: true,
          title: Text(
            'buildAhome',
            style: TextStyle(color: Color.fromARGB(255, 224, 224, 224), fontSize: 16),
          ),
          leading: new IconButton(
              icon: new Icon(Icons.chevron_left),
              onPressed: () => {Navigator.pop(context)}),
          backgroundColor: Color.fromARGB(255, 6, 10, 43),
        ),
        body: imageOnly(this.image),
      ),
    );
  }
}

class imageOnly extends StatelessWidget {
  var image;
  imageOnly(this.image);
  Widget build(BuildContext context) {
    return Container(
        decoration: BoxDecoration(border: Border.all(color: Colors.black)),
        child: PhotoView(
          minScale: PhotoViewComputedScale.contained,
          imageProvider: CachedNetworkImageProvider(
            this.image,
          ),
        ));
  }
}
