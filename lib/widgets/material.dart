import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

class Materials extends StatelessWidget {
  String mesaage;
  var materials = [
    'PCC M 7.5',
    'PCC M 15',
    'M 20',
    'M 25',
    'Red Bricks',
    'Exposed Bricks',
    'Wirecut bricks',
    'Earth Blocks',
    'Interlocking Blocks',
    'Solid blocks 4"',
    'Solid blocks 6"',
    'Solid blocks 8"',
    'Porotherm Full blocks 8"',
    'Porotherm Full blocks 6"',
    'Porotherm Full blocks 4"',
    'Porotherm End blocks 8"',
    'Porotherm End blocks 6"',
    'Porotherm End blocks 4"',
    'AAC Blocks 8"',
    'AAC Blocks 6"',
    'AAC Blocks 4"',
    'Glass blocks',
    'Jaali blocks',
    'Door frames',
    'Door Beading',
    'Door Shutters',
    'Windows frames',
    'Windows shutters',
    'UPVC windows',
    'Aluminum windows',
    'Window glass',
    'Hexagonl Rod',
    'Granite',
    'Tiles',
    'Marble',
    'Kota stone',
    'HPL Cladding',
    'Shera Cladding',
    'Floor mat',
    'Plumbing',
    'Sanitary',
    'Aggregates 12mm',
    'Aggregates 20mm',
    'Aggregates 40mm',
    'Cinder',
    'Size stone',
    'Boulders',
    'River sand',
    'POP',
    'white cement',
    'tile adhesive',
    'tile grout',
    'lime paste',
    'Sponge',
    'chicken mesh',
    'Motor',
    'Curing Pipe',
    'Helmet',
    'Jackets',
    'GI sheets',
    'Tarpaulin',
    'Nails',
    'Cement',
    'Steel',
    'M Sand',
    'P Sand',
    'Teak wood frame',
    'Sal wood frame',
    'Honne wood frame',
    'Teak wood door',
    'Sal wood door',
    'Flush door',
    'Binding wire',
    'Hardwares',
    'Chamber Covers',
    'Filler slab material'
  ];

  Widget build(BuildContext context) {
    return AlertDialog(
        contentPadding: EdgeInsets.all(0),
        content: Column(children: [
          Container(
              alignment: Alignment.centerLeft,
              padding: EdgeInsets.all(10),
              child: Text("Select material")),
          Container(
              height: MediaQuery.of(context).size.height - 130,
              width: MediaQuery.of(context).size.width - 20,
              child: ListView.builder(
                  shrinkWrap: true,
                  physics: new BouncingScrollPhysics(),
                  scrollDirection: Axis.vertical,
                  itemCount: materials.length,
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
                              print(materials[Index]);
                              Navigator.pop(context, materials[Index]);
                            },
                            child: Text(materials[Index],
                                style: TextStyle(
                                    fontSize: 18,
                                    fontWeight: FontWeight.bold))));
                  }))
        ]));
  }
}
