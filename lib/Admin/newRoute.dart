import 'package:flutter/material.dart';

class NewRoute extends StatelessWidget {
  // This widget is the root of your application.
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Connect dots',
      home: HomePage(),
    );
  }
}

class HomePage extends StatefulWidget {

  @override
  _HomePageState createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {

  var gridSize = TextEditingController();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text("Connect the dots"),
      ),
      body: Center(
        child: Column(
          children: <Widget>[
            Container(
              margin: EdgeInsets.all(15),
              child: Text("Hey, Welcome! Enter grid size to play", style: TextStyle(fontSize: 16))
            ),
            Container(
              alignment: Alignment.center,
              width: 60,
              child: TextFormField(
                controller: gridSize,
                keyboardType: TextInputType.numberWithOptions(),
                style: TextStyle(fontSize: 24),
                decoration: InputDecoration(
                  contentPadding: EdgeInsets.all(5),
                ),
                textAlign: TextAlign.center,
              )
            ),
            Container(
              margin: EdgeInsets.all(25),
              child: InkWell(
                onTap: (){
                  Navigator.pop(context);
                },
                child: Container(
                  alignment: Alignment.center,
                  width: 150,
                  padding: EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: Color(0xFFe35349),
                    borderRadius: BorderRadius.circular(20),
                    boxShadow: [new BoxShadow(
                      color: Colors.grey[400]!,
                      blurRadius: 5.0,
                      offset: Offset(0.0, 1.0)
                    ),]
                  ),
                  child: Text("Play", style: TextStyle(color: Colors.white),)
                )
              ),
            )
          ],
        )
      ),
    );
  }
}
