import 'package:flutter/material.dart';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:flutter_spinkit/flutter_spinkit.dart';

class Materials extends StatefulWidget {
  @override
  State<StatefulWidget> createState() => MaterialState();
}

class MaterialState extends State<Materials> {
  var materials = [];

  void call() async {
    var url = "https://app.buildahome.in/erp/API/get_materials";
    var response = await http.get(Uri.parse(url));
    print(response.body);
    setState(() {
      var res = jsonDecode(response.body);
      materials = res['materials'];
    });
  }

  @override
  void initState() {
    super.initState();
    call();
  }

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
              child: materials.length == 0
                  ? SpinKitRing(
                      color: Colors.indigo[900]!,
                      lineWidth: 2,
                    )
                  : ListView.builder(
                      shrinkWrap: true,
                      physics: new BouncingScrollPhysics(),
                      scrollDirection: Axis.vertical,
                      itemCount: materials.length,
                      itemBuilder: (BuildContext ctxt, int index) {
                        return Container(
                            padding: EdgeInsets.all(15),
                            margin: EdgeInsets.only(bottom: 15),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              shape: BoxShape.rectangle,
                              border: Border(
                                bottom: BorderSide(
                                    width: 1.0, color: Colors.grey[300]!),
                              ),
                            ),
                            child: InkWell(
                                onTap: () {
                                  print(materials[index]);
                                  Navigator.pop(context, materials[index]);
                                },
                                child: Text(materials[index],
                                    style: TextStyle(
                                        fontSize: 18,
                                        fontWeight: FontWeight.bold))));
                      }))
        ]));
  }
}
