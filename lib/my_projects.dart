import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_spinkit/flutter_spinkit.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:buildahome/NavMenu.dart';
import 'package:buildahome/UserHome.dart';
import 'main.dart';

class MyProjects extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final appTitle = 'buildAhome';
    final GlobalKey<ScaffoldState> _scaffoldKey = new GlobalKey<ScaffoldState>();
    return MaterialApp(
      title: appTitle,
      theme: ThemeData(fontFamily: App().fontName),
      home: Scaffold(
        key: _scaffoldKey,
        // ADD THIS LINE
        backgroundColor: Colors.white,
        appBar: AppBar(
          automaticallyImplyLeading: true,
          title: Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [],
          ),
          shadowColor: Colors.grey[100]!,
          leading: new IconButton(
              icon: new Icon(Icons.chevron_left, color: Colors.black),
              onPressed: () async {
                Navigator.pop(context);
              }),
          backgroundColor: Colors.white,
        ),
        body: ProjectsModal(),
      ),
    );
  }
}

class ProjectsModal extends StatefulWidget {
  @override
  State<StatefulWidget> createState() => ProjectsModalBody();
}

class ProjectsModalBody extends State<ProjectsModal> {
  var id;
  var projects = [];
  var search_data = [];

  @override
  void initState() {
    super.initState();
    call();
  }

  call() async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    id = prefs.getString('user_id');
    var url =
        "https://app.buildahome.in/api/projects_access.php?id=${id.toString()}";
    var response = await http.get(Uri.parse(url));
    print(response.statusCode);
    setState(() {
      projects = jsonDecode(response.body);
      search_data = projects;
      print(search_data);
    });
  }


  Widget build(BuildContext context) {
    return ListView(
      padding: EdgeInsets.all(12),
      children: [
        Container(
            alignment: Alignment.centerLeft,
            padding: EdgeInsets.all(10),
            child: Text("Projects", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 20),)),
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
              color: Colors.indigo[900]!,
              lineWidth: 2,
              size: 20,
            ),
          ),
        if (search_data.length != 0)
          Container(
              height: MediaQuery.of(context).viewInsets.bottom > 0
                  ? MediaQuery.of(context).size.height * 0.3 // Reduce height when keyboard is active
                  : MediaQuery.of(context).size.height - 200,
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
                                  width: 1.0, color: Colors.grey[300]!),
                            ),
                          ),
                          child: InkWell(
                                onTap: () async {
                                  SharedPreferences prefs = await SharedPreferences.getInstance();
                                  await prefs.setString("project_id", search_data[Index]['id'].toString());
                                  await prefs.setString("client_name", search_data[Index]['name'].toString());

                                  Navigator.push(
                                    context,
                                    MaterialPageRoute(builder: (context) => Home()),
                                  );

                              },
                              child: Text(search_data[Index]['name'],
                                  style: TextStyle(
                                      fontSize: 18,
                                      fontWeight: FontWeight.bold))));
                  }))
      ],
    );
  }
}
