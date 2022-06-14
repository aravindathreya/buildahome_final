import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

class Confirmation extends StatelessWidget{
  String message;

  Confirmation(this.message);
  Widget build(BuildContext context){

    return AlertDialog(
      content:
      Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            margin: EdgeInsets.only(left: 15, right: 15, top: 10, bottom: 20),
            child: Text(message)
          ),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              InkWell(
                child: Container(
                  padding: EdgeInsets.all(10),
                  margin: EdgeInsets.only(right: 10),
                  child: Text('Cancel', style: TextStyle(color: Colors.indigo[900]),)
                ),
                onTap: () {
                  Navigator.pop(context, 'Cancel');
                },
              ),
              InkWell(
                child: Container(
                    padding: EdgeInsets.all(10),
                    margin: EdgeInsets.only(left: 10),
                    decoration: BoxDecoration(
                      color: Colors.indigo[900],
                      borderRadius: BorderRadius.circular(5)
                    ),
                    child: Text('Confirm', style: TextStyle(color: Colors.white),)
                ),
                onTap: () {
                  Navigator.pop(context, 'Confirm');
                },
              )
            ],
          )
        ],
        ),
    );

  }
}

