import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

class MaterialUnits extends StatelessWidget {
  final materialUnits = [
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
          Container(alignment: Alignment.centerLeft, padding: EdgeInsets.all(10), child: Text("Select unit")),
          Container(
              height: MediaQuery.of(context).viewInsets.bottom > 0
                  ? MediaQuery.of(context).size.height * 0.3 // Reduce height when keyboard is active
                  : MediaQuery.of(context).size.height * 0.7,
              width: MediaQuery.of(context).size.width - 20,
              child: ListView.builder(
                  shrinkWrap: true,
                  physics: new BouncingScrollPhysics(),
                  scrollDirection: Axis.vertical,
                  itemCount: materialUnits.length,
                  itemBuilder: (BuildContext ctxt, int index) {
                    return Container(
                        padding: EdgeInsets.all(15),
                        margin: EdgeInsets.only(bottom: 15),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          shape: BoxShape.rectangle,
                          border: Border(
                            bottom: BorderSide(width: 1.0, color: Colors.grey[300]!),
                          ),
                        ),
                        child: InkWell(
                            onTap: () {
                              print(materialUnits[index]);
                              Navigator.pop(context, materialUnits[index]);
                            },
                            child: Text(materialUnits[index],
                                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold))));
                  }))
        ]));
  }
}
