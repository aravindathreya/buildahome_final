import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

class MaterialUnits extends StatelessWidget {
  String mesaage;
  var materialUnits = [
    'Bags',
    'CFT',
    'CUM',
    'Load',
    'Kg',
    'MT',
    'Nos',
    'Box',
    'Others',
  ];

  Widget build(BuildContext context) {
    return AlertDialog(
        contentPadding: EdgeInsets.all(0),
        content: Column(children: [
          Container(
              alignment: Alignment.centerLeft,
              padding: EdgeInsets.all(10),
              child: Text("Select unit")),
          Container(
              height: MediaQuery.of(context).size.height - 130,
              width: MediaQuery.of(context).size.width - 20,
              child: ListView.builder(
                  shrinkWrap: true,
                  physics: new BouncingScrollPhysics(),
                  scrollDirection: Axis.vertical,
                  itemCount: materialUnits.length,
                  itemBuilder: (BuildContext ctxt, int Index) {
                    return Container(
                        padding: EdgeInsets.all(15),
                        margin: EdgeInsets.only(bottom: 15),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          shape: BoxShape.rectangle,
                          border: Border(
                            bottom:
                                BorderSide(width: 1.0, color: Colors.grey[300]),
                          ),
                        ),
                        child: InkWell(
                            onTap: () {
                              print(materialUnits[Index]);
                              Navigator.pop(context, materialUnits[Index]);
                            },
                            child: Text(materialUnits[Index],
                                style: TextStyle(
                                    fontSize: 18,
                                    fontWeight: FontWeight.bold))));
                  }))
        ]));
  }
}
