import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_spinkit/flutter_spinkit.dart';

class ShowAlert extends StatelessWidget{
  String mesaage;
  bool is_Loading=false;

  ShowAlert(this.mesaage, this.is_Loading);

  Widget build(BuildContext context){

    return AlertDialog(
      content:
      Column(
        mainAxisSize: MainAxisSize.min,

        children: <Widget>[
          Wrap(
            children: <Widget>[
              if(this.is_Loading==false)
                Row(children: <Widget>[
                  Icon(Icons.check_circle, color: Colors.green[800], size: 30),
                  Container(
                    width: 200,
                    padding: EdgeInsets.only(left: 10),
                    child: Text(this.mesaage, style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
                  ),

                ],),


              if(this.is_Loading==true)
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

