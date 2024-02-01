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
  var search_data = [];

  void call() async {
    var url = "https://office.buildahome.in/API/get_materials";
    var response = await http.get(Uri.parse(url));
    print(response.body);
    setState(() {
      var res = jsonDecode(response.body);
      materials = res['materials'];
      search_data = materials;
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
              margin: EdgeInsets.only(bottom: 10, top: 10),
              color: Colors.white,
              child: TextFormField(
                onChanged: (text) {
                  setState(() {
                    if (text.trim() == '') {
                      search_data = materials;
                    } else {
                      search_data = [];
                      for (int i = 0; i < materials.length; i++) {
                        if (materials[i]
                            .toLowerCase()
                            .contains(text.toLowerCase())) {
                          search_data.add(materials[i]);
                        }
                      }
                    }
                  });
                },
                decoration: InputDecoration(
                  hintText: 'Search material',
                  contentPadding: EdgeInsets.all(10),
                  suffixIcon: InkWell(child: Icon(Icons.search)),
                ),
              )),
          Container(
              height: MediaQuery.of(context).viewInsets.bottom > 0
                  ? MediaQuery.of(context).size.height * 0.3 // Reduce height when keyboard is active
                  : MediaQuery.of(context).size.height - 200,
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
                      itemCount: search_data.length,
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
                                  print(search_data[index]);
                                  Navigator.pop(context, search_data[index]);
                                },
                                child: Text(search_data[index],
                                    style: TextStyle(
                                        fontSize: 18,
                                        fontWeight: FontWeight.bold))));
                      }))
        ]));
  }
}
