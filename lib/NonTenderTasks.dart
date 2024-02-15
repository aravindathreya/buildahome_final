import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'NavMenu.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'main.dart';
import 'AnimationHelper.dart';

class NonTenderTaskWidget extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final appTitle = 'buildAhome';

    final GlobalKey<ScaffoldState> _scaffoldKey = new GlobalKey<ScaffoldState>();
    return MaterialApp(
      title: appTitle,
      theme: ThemeData(fontFamily: App().fontName),
      home: Scaffold(
        key: _scaffoldKey,
        backgroundColor: Color.fromARGB(255, 233, 233, 233),
        drawer: NavMenuWidget(),
        appBar: AppBar(
          automaticallyImplyLeading: true,
          title: Text(
            appTitle,
            style: TextStyle(color: Color.fromARGB(255, 224, 224, 224), fontSize: 16),
          ),
          leading: new IconButton(
              icon: new Icon(Icons.chevron_left),
              onPressed: () async {
                Navigator.pop(context);
              }),
          backgroundColor: Color.fromARGB(255, 6, 10, 43),
        ),
        body: NTPaymentTasksClass(),
      ),
    );
  }
}

class NTPaymentTasksClass extends StatefulWidget {
  @override
  NTPaymentTasks createState() {
    return NTPaymentTasks();
  }
}

class TaskItem extends StatefulWidget {
  final String _taskName;
  final _color = Colors.white;
  final _paymentPercentage;
  final status;

  TaskItem(this._taskName, this._paymentPercentage, this.status);

  @override
  TaskItemWidget createState() {
    return TaskItemWidget(this._taskName, this._color, this._paymentPercentage, this.status);
  }
}

class TaskItemWidget extends State<TaskItem> with SingleTickerProviderStateMixin {
  String _taskName;
  var _color;
  var vis = false;
  var _paymentPercentage;
  var sprRadius = 1.0;
  var pad = 10.0;
  var valueStr;
  var value = 0.0;
  var status;
  var amt;

  @override
  void initState() {
    super.initState();
    _setValue();
    _progress();
  }

  _setValue() async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    valueStr = prefs.getString('projectValue');
    if (valueStr == null) valueStr = '0';
    value = double.parse(valueStr);
    setState(() {
      amt = ((double.parse(this._paymentPercentage)) / 100) * value;
    });
  }

  _progress() {
    if (this.status == 'not due') {
      this._color = Colors.white;
    } else if (this.status == 'paid') {
      this._color = Color(0xff009900);
    } else {
      this._color = Color(0xFF7b0909);
    }
  }

  var view = Icons.expand_more;

  _expandCollapse() {
    setState(() {
      if (vis == false) {
        vis = true;
        view = Icons.expand_less;
        sprRadius = 1.0;
      } else if (vis == true) {
        vis = false;
        view = Icons.expand_more;
        sprRadius = 1.0;
      }
    });
  }

  TaskItemWidget(this._taskName, this._color, this._paymentPercentage, this.status);

  @override
  Widget build(BuildContext context) {
    return Column(
      children: <Widget>[
        Container(
            child: AnimatedContainer(
          duration: Duration(milliseconds: 500),
          margin: EdgeInsets.only(left: 20, top: 15, right: 20),
          decoration:
              BoxDecoration(borderRadius: BorderRadius.circular(5), color: Color.fromARGB(255, 26, 26, 26), gradient: LinearGradient(colors: [Color.fromARGB(255, 167, 166, 166), Color.fromARGB(255, 221, 221, 221)])),
          padding: EdgeInsets.all(this.pad),
          child: Container(
            child: Column(children: <Widget>[
              AnimatedContainer(
                duration: Duration(milliseconds: 900),
                padding: EdgeInsets.only(left: 7),
                child: Row(
                  children: <Widget>[
                    InkWell(
                      onTap: _expandCollapse,
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: <Widget>[
                          if (this._color == Color(0xff009900))
                            Container(
                              height: 45,
                              width: 45,
                              alignment: Alignment.center,
                              decoration: BoxDecoration(color: Colors.green[900], borderRadius: BorderRadius.circular(50)),
                              child: Text(
                                'PAID',
                                style: TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold),
                              ),
                            ),
                          if (this._color == Colors.white)
                            Container(
                              height: 45,
                              width: 45,
                              alignment: Alignment.center,
                              decoration: BoxDecoration(color: Colors.yellow[700], borderRadius: BorderRadius.circular(50)),
                              child: Text(
                                'WIP',
                                style: TextStyle(color: const Color.fromARGB(255, 0, 0, 0), fontSize: 10, fontWeight: FontWeight.bold),
                              ),
                            ),
                          if (this._color == Color(0xFF7b0909))
                            Container(
                              height: 45,
                              width: 45,
                              alignment: Alignment.center,
                              decoration: BoxDecoration(color: Colors.red[700], borderRadius: BorderRadius.circular(50)),
                              child: Text(
                                'DUE',
                                style: TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold),
                              ),
                            ),
                          SizedBox(
                            width: 15,
                          ),
                          Container(
                            width: MediaQuery.of(context).size.width * .6 - 7,
                            child: Text(
                              this._taskName,
                              textAlign: TextAlign.left,
                              style: TextStyle(fontSize: 14, fontWeight: FontWeight.normal, color: Color.fromARGB(255, 44, 44, 44)),
                            ),
                          ),
                          new Icon(
                            view,
                            color: Color.fromARGB(255, 44, 44, 44),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              Visibility(
                  visible: this.vis,
                  child: Container(
                      padding: EdgeInsets.all(10),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: <Widget>[
                          Text(
                            "₹  " + this._paymentPercentage.toString(),
                            style: TextStyle(
                              fontSize: 18,
                              color: Color.fromARGB(255, 44, 44, 44),
                              fontWeight: FontWeight.bold,
                            ),
                          )
                        ],
                      ))),
            ]),
          ),
        )),
      ],
    );
  }
}

class NTPaymentTasks extends State<NTPaymentTasksClass> {
  var body;
  var outstanding = '';
  var totalPaid = '';
  var projectValue = '';

  @override
  void initState() {
    super.initState();
    call();
  }

  var tasks = [];

  call() async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    var id = prefs.getString('project_id');
    var url = 'https://office.buildahome.in/API/get_all_non_tender?project_id=$id ';
    var response = await http.get(Uri.parse(url));
    var url1 = 'https://office.buildahome.in/API/get_payment?project_id=$id ';
    var response1 = await http.get(Uri.parse(url1));
    var details = jsonDecode(response1.body);
    setState(() {
      outstanding = details[0]['nt_outstanding'];
      totalPaid = details[0]['nt_total_paid'];
      projectValue = details[0]['nt_value'].toString();
      body = jsonDecode(response.body);
      print(body);
    });
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        Opacity(
          opacity: 0.3,
          child: Container(
            width: MediaQuery.of(context).size.width,
            height: MediaQuery.of(context).size.height,
            decoration: BoxDecoration(
                color: Color.fromARGB(255, 214, 214, 214),
                border: Border.all(width: 1, color: Colors.grey[200]!),
                borderRadius: BorderRadius.circular(10),
                ),
            
            child: Image.network("https://images.unsplash.com/photo-1602343168117-bb8ffe3e2e9f?w=500&auto=format&fit=crop&q=60&ixlib=rb-4.0.3&ixid=M3wxMjA3fDB8MHxzZWFyY2h8NTV8fEhvdXNlfGVufDB8fDB8fHww", fit: BoxFit.fill),
          ),
        ),
        Padding(
          padding: EdgeInsets.only(bottom: 1),
          child: ListView(children: <Widget>[
            Container(
                margin: EdgeInsets.only(top: 20, left: 20, bottom: 10),
                child: Text("Non Tender Payments",
                    style: TextStyle(
                      fontSize: 20,
                      color: const Color.fromARGB(255, 34, 34, 34),
                    ))),
            Container(
              height: 2,
              color: const Color.fromARGB(255, 32, 32, 32),
              width: 200,
              margin: EdgeInsets.only(left: 15, right: 150),
            ),
            Container(
              margin: EdgeInsets.symmetric(vertical: 20, horizontal: 10),
              padding: EdgeInsets.all(10),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(5),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Container(
                    width: 150,
                    margin: EdgeInsets.symmetric(vertical: 5),
                    padding: EdgeInsets.all(10),
                    decoration: BoxDecoration(color: Color.fromARGB(255, 240, 255, 242), borderRadius: BorderRadius.circular(6)),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(child: Text("Total NT Value", style: TextStyle(fontSize: 12))),
                        Container(margin: EdgeInsets.only(top: 5), child: Text("₹ " + projectValue, style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold))),
                      ],
                    ),
                  ),
                  Container(
                    width: 150,
                    margin: EdgeInsets.symmetric(vertical: 5),
                    padding: EdgeInsets.all(10),
                    decoration: BoxDecoration(color: Color.fromARGB(255, 255, 237, 237), borderRadius: BorderRadius.circular(6)),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(
                            child: Text("Paid till date",
                                style: TextStyle(
                                  fontSize: 12,
                                ))),
                        Container(margin: EdgeInsets.only(top: 5), child: Text("₹ " + totalPaid, style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.green[700]))),
                      ],
                    ),
                  ),
                  Container(
                    width: 150,
                    margin: EdgeInsets.symmetric(vertical: 5),
                    padding: EdgeInsets.all(10),
                    decoration: BoxDecoration(color: Color.fromARGB(255, 246, 248, 225), borderRadius: BorderRadius.circular(6)),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(
                            child: Text("Current Outstanding",
                                style: TextStyle(
                                  fontSize: 12,
                                ))),
                        Container(margin: EdgeInsets.only(top: 5), child: Text("₹ " + outstanding, style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.red[500]))),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            new ListView.builder(
                shrinkWrap: true,
                itemCount: body == null ? 0 : body.length,
                physics: NeverScrollableScrollPhysics(),
                itemBuilder: (BuildContext ctxt, int index) {
                  return AnimatedWidgetSlide(
                      direction: index % 2 == 0 ? SlideDirection.leftToRight : SlideDirection.rightToLeft, // Specify the slide direction
                      duration: Duration(milliseconds: 300),
                      child: Container(
                        child: TaskItem(body[index]['task_name'].toString(), body[index]['payment'].toString(), body[index]['paid'].toString()),
                      ));
                }),
          ]),
        )
      ],
    );
  }
}
