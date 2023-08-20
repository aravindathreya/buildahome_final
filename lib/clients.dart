import 'package:flutter/material.dart';
import 'package:flutter_spinkit/flutter_spinkit.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';

import 'package:http/http.dart';

class ClientsModal extends StatelessWidget {
  late final String message;
  final bool isLoading = false;

  Widget build(BuildContext context) {
    return AlertDialog(
        contentPadding: EdgeInsets.all(0),
        content: FutureBuilder<Response>(
          future: http.get(Uri.parse("https://app.buildahome.in/api/view_all_clients.php")),
          builder: (context, snapshot) {
            switch (snapshot.connectionState) {
              case ConnectionState.none:
                return Text('Press button to start.');
              case ConnectionState.active:
              case ConnectionState.waiting:
                return Container(
                  padding: EdgeInsets.only(top: 20),
                  child: SpinKitThreeBounce(
                    color: Colors.indigo[900],
                    size: 30.0,
                  ),
                );

              case ConnectionState.done:
                if (snapshot.hasError) return Text('Error: ${snapshot.error}');
                final Response response = snapshot.data!;
                final List<dynamic> clients = json.decode(response.body);
                return ListView(
                  scrollDirection: Axis.vertical,
                  children: <Widget>[
                    Container(
                      padding: EdgeInsets.all(15),
                      child: Text(
                        "Tap on client to select",
                      ),
                    ),
                    ListView(
                      shrinkWrap: true,
                      physics: new BouncingScrollPhysics(),
                      scrollDirection: Axis.vertical,
                      children: clients.map((client) => clientBlock(context, client['name'])).toList(),
                    ),
                  ],
                );
            }
          },
        ));
  }
}

Widget clientBlock(context, name) {
  return Container(
      padding: EdgeInsets.all(15),
      decoration: BoxDecoration(
        color: Colors.white,
        shape: BoxShape.rectangle,
        border: Border(
          bottom: BorderSide(width: 1.0, color: Colors.black54),
        ),
        boxShadow: [
          new BoxShadow(
            color: Colors.black12,
            blurRadius: 15,
            spreadRadius: 2,
          )
        ],
      ),
      child: InkWell(
          onTap: () {
            Navigator.pop(context, name);
          },
          child: Text(name, style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold))));
}
