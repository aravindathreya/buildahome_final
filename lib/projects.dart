import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_spinkit/flutter_spinkit.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

class ProjectsModal extends StatefulWidget {
  var id;
  ProjectsModal(this.id);

  @override
  State<StatefulWidget> createState() => ProjectsModalBody(this.id);
}

class ProjectsModalBody extends State<ProjectsModal> {
  String mesaage;
  bool is_Loading = false;
  var id;
  var projects = [];
  var search_data = [];

  @override
  void initState() {
    super.initState();
    call();
  }

  call() async {
    var url =
        "https://app.buildahome.in/api/projects_access.php?id=${this.id.toString()}";
    var response = await http.get(url);
    setState(() {
      projects = jsonDecode(response.body);
      search_data = projects;
      print(search_data);
    });
  }

  ProjectsModalBody(this.id);

  Widget build(BuildContext context) {
    return AlertDialog(
        contentPadding: EdgeInsets.all(0),
        content: Column(
          children: [
            Container(
                alignment: Alignment.centerLeft,
                padding: EdgeInsets.all(10),
                child: Text("Select project")),
            Container(
                margin: EdgeInsets.only(bottom: 10, top: 10),
                color: Colors.white,
                child: TextFormField(
                  onChanged: (text) {
                    setState(() {
                      if (text.trim() == '') {
                        search_data = projects;
                      } else {
                        search_data = [];
                        for (int i = 0; i < projects.length; i++) {
                          if (projects[i]['name']
                              .toLowerCase()
                              .contains(text.toLowerCase())) {
                            search_data.add(projects[i]);
                          }
                        }
                      }
                    });
                  },
                  decoration: InputDecoration(
                    hintText: 'Search project',
                    contentPadding: EdgeInsets.all(10),
                    suffixIcon: InkWell(child: Icon(Icons.search)),
                  ),
                )),
            if (search_data.length == 0)
              Container(
                height: 150,
                width: MediaQuery.of(context).size.width - 20,
                child: SpinKitRing(
                  color: Colors.indigo[900],
                  lineWidth: 2,
                  size: 20,
                ),
              ),
            if (search_data.length != 0)
              Container(
                  height: MediaQuery.of(context).size.height - 200,
                  width: MediaQuery.of(context).size.width - 20,
                  child: ListView.builder(
                      shrinkWrap: true,
                      physics: new BouncingScrollPhysics(),
                      scrollDirection: Axis.vertical,
                      itemCount: search_data.length,
                      // ignore: missing_return
                      itemBuilder: (BuildContext ctxt, int Index) {
                        if (search_data[Index]['name'].trim().length == 0)
                          return Container();
                        if (search_data[Index]['name'].trim().length > 0)
                          return Container(
                              padding: EdgeInsets.symmetric(
                                  horizontal: 15, vertical: 20),
                              decoration: BoxDecoration(
                                color: Colors.white,
                                shape: BoxShape.rectangle,
                                border: Border(
                                  bottom: BorderSide(
                                      width: 1.0, color: Colors.grey[300]),
                                ),
                              ),
                              child: InkWell(
                                  onTap: () {
                                    print(search_data[Index]['name'] +
                                        "|" +
                                        search_data[Index]['id']);
                                    Navigator.pop(
                                        context,
                                        search_data[Index]['name'] +
                                            "|" +
                                            search_data[Index]['id']);
                                  },
                                  child: Text(search_data[Index]['name'],
                                      style: TextStyle(
                                          fontSize: 18,
                                          fontWeight: FontWeight.bold))));
                      }))
          ],
        ));
  }
}
