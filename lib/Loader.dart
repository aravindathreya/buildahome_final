import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_spinkit/flutter_spinkit.dart';

class Loader extends StatelessWidget{
  Widget build(BuildContext context){

    return AlertDialog(
      content:
      Column(
        mainAxisSize: MainAxisSize.min,

        children: <Widget>[
          Wrap(
            children: <Widget>[
                Container(
                  padding: EdgeInsets.only(top: 20),
                  child: SpinKitThreeBounce(
                    color: Colors.indigo[900],
                    size: 30.0,
                  ),
                )


            ],
          )
        ],

      ),
    );

  }
}

