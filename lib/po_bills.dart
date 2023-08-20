import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'NavMenu.dart';
import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';
import 'main.dart';
import 'contractor_bills.dart';

class POAndBills extends StatefulWidget {
  @override
  POAndBillsState createState() {
    return POAndBillsState();
  }
}

class POAndBillObject extends StatefulWidget {
  var parent;
  var children;
  var drawing_id;

  POAndBillObject(this.parent, this.children, this.drawing_id);

  @override
  POAndBillObjectState createState() {
    return POAndBillObjectState(this.parent, this.children, this.drawing_id);
  }
}

class POAndBillObjectState extends State<POAndBillObject> {
  var parent;
  var children;
  var drawing_id;
  bool vis = false;
  Icon _icon = Icon(Icons.expand_more);

  POAndBillObjectState(this.parent, this.children, this.drawing_id);

  _launchURL(url) async {
    print(url);
    await launch(url);
  }

  @override
  Widget build(BuildContext context) {
    return Container(
        decoration: BoxDecoration(
            color: Colors.grey[200], borderRadius: BorderRadius.circular(10)),
        margin: EdgeInsets.symmetric(vertical: 10, horizontal: 5),
        child: Column(
          children: <Widget>[
            InkWell(
              onTap: () {
                setState(() {
                  !vis
                      ? _icon = Icon(Icons.expand_less)
                      : _icon = Icon(Icons.expand_more);
                  vis = !vis;
                });
              },
              child: Container(
                padding: EdgeInsets.all(15),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: <Widget>[
                    Text(
                      this.parent.toString(),
                      style: TextStyle(fontSize: 16),
                    ),
                    _icon,
                  ],
                ),
              ),
            ),
            Visibility(
                visible: vis,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    for (int x = 0; x < this.children.length; x++)
                      InkWell(
                          onTap: () => {
                                showDialog(
                                    context: context,
                                    builder: (BuildContext context) {
                                      return AlertDialog(
                                          content: Text("Loading..."));
                                    }),
                                Navigator.of(context, rootNavigator: true)
                                    .pop(),
                                _launchURL(
                                    "https://app.buildahome.in/team/Drawings/" +
                                        children[x].toString()),
                              },
                          child: Container(
                            padding:
                                EdgeInsets.only(left: 15, right: 15, bottom: 5),
                            alignment: Alignment.centerLeft,
                            margin: EdgeInsets.only(top: 20),
                            child: Text(
                              children[x].toString(),
                              style: TextStyle(
                                  color: Colors.indigo[900],
                                  fontWeight: FontWeight.bold),
                            ),
                          ))
                  ],
                ))
          ],
        ));
  }
}

class POAndBillsState extends State<POAndBills> {
  var work_orders = [];
  var purchase_orders = [];
  var role;
  var bills = [];
  var nt_nmr_bills = [];

  call() async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    var id = prefs.getString('project_id');
    var _role = prefs.getString('role');
    var pos = [];
    var wos = [];
    var nt_nmrs = [];

    var po_url = 'https://app.buildahome.in/erp/API/get_POs?project_id=$id';
    var po_response = await http.get(Uri.parse(po_url));
    print(po_response.body);
    pos = jsonDecode(po_response.body);

    var wo_url =
        'https://app.buildahome.in/erp/API/get_work_orders?project_id=$id';
    var wo_response = await http.get(Uri.parse(wo_url));
    wos = jsonDecode(wo_response.body);

    var nt_nmr_url = 'https://app.buildahome.in/erp/API/nt_nmr?project_id=$id';
    var nt_nmr_response = await http.get(Uri.parse(nt_nmr_url));
    nt_nmrs = jsonDecode(nt_nmr_response.body);

    setState(() {
      role = _role;
      purchase_orders = pos;
      work_orders = wos;
      nt_nmr_bills = nt_nmrs;
    });
  }

  @override
  void initState() {
    super.initState();
    call();
  }

  @override
  Widget build(BuildContext context) {
    final appTitle = 'buildAhome';
    final GlobalKey<ScaffoldState> _scaffoldKey =
        new GlobalKey<ScaffoldState>();
    return Scaffold(
        key: _scaffoldKey,
        body: ListView(
          children: [
            Container(
              margin: EdgeInsets.symmetric(horizontal: 20, vertical: 15),
              padding: EdgeInsets.only(bottom: 5),
              child: Text(
                'Purchase orders',
                style: TextStyle(fontSize: 16),
              ),
              decoration: BoxDecoration(
                  border: Border(bottom: BorderSide(color: Colors.grey[300]!))),
            ),
            ListView.builder(
              shrinkWrap: true,
              physics: NeverScrollableScrollPhysics(),
              padding: EdgeInsets.all(15),
              itemCount: purchase_orders.length,
              itemBuilder: (BuildContext ctxt, int Index) {
                return InkWell(
                  child: Container(
                    margin: EdgeInsets.symmetric(vertical: 10),
                    padding: EdgeInsets.all(15),
                    decoration: BoxDecoration(
                        color: Colors.grey[200],
                        borderRadius: BorderRadius.circular(10)),
                    child: Text(
                      purchase_orders[Index][2] +
                          ' ' +
                          purchase_orders[Index][3] +
                          ' of ' +
                          purchase_orders[Index][1],
                      style: TextStyle(
                          color: Colors.indigo[900],
                          fontWeight: FontWeight.w600),
                    ),
                  ),
                  onTap: () async {
                    var url =
                        'https://app.buildahome.in/erp/files/${purchase_orders[Index][4]}';
                    await launch(url);
                  },
                );
              },
            ),
            Container(
              margin: EdgeInsets.symmetric(horizontal: 20, vertical: 15),
              padding: EdgeInsets.only(bottom: 5),
              child: Text(
                'Work orders',
                style: TextStyle(fontSize: 16),
              ),
              decoration: BoxDecoration(
                  border: Border(bottom: BorderSide(color: Colors.grey[300]!))),
            ),
            ListView.builder(
              shrinkWrap: true,
              physics: NeverScrollableScrollPhysics(),
              padding: EdgeInsets.all(15),
              itemCount: work_orders.length,
              itemBuilder: (BuildContext ctxt, int Index) {
                return InkWell(
                  child: Container(
                    margin: EdgeInsets.symmetric(vertical: 10),
                    padding: EdgeInsets.all(15),
                    decoration: BoxDecoration(
                        color: Colors.grey[200],
                        borderRadius: BorderRadius.circular(10)),
                    child: Text(
                      work_orders[Index][4] + " work order",
                      style: TextStyle(
                          color: Colors.indigo[900],
                          fontWeight: FontWeight.w600),
                    ),
                  ),
                  onTap: () async {
                    var url =
                        'https://app.buildahome.in/erp/files/work_order_${work_orders[Index][0]}.pdf';
                    await launch(url);
                  },
                );
              },
            ),
            Container(
              margin: EdgeInsets.symmetric(horizontal: 20, vertical: 15),
              padding: EdgeInsets.only(bottom: 5),
              child: Text(
                'Bills',
                style: TextStyle(fontSize: 16),
              ),
              decoration: BoxDecoration(
                  border: Border(bottom: BorderSide(color: Colors.grey[300]!))),
            ),
            ListView.builder(
              shrinkWrap: true,
              physics: NeverScrollableScrollPhysics(),
              padding: EdgeInsets.all(15),
              itemCount: work_orders.length,
              itemBuilder: (BuildContext ctxt, int Index) {
                return InkWell(
                  child: Container(
                    margin: EdgeInsets.symmetric(vertical: 10),
                    padding: EdgeInsets.all(15),
                    decoration: BoxDecoration(
                        color: Colors.grey[200],
                        borderRadius: BorderRadius.circular(10)),
                    child: Text(
                      work_orders[Index][1],
                      style: TextStyle(
                          color: Colors.indigo[900],
                          fontWeight: FontWeight.w600),
                    ),
                  ),
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                          builder: (context) => ContractorBills(
                              work_orders[Index][1],
                              work_orders[Index][3],
                              work_orders[Index][4])),
                    );
                  },
                );
              },
            ),
            Container(
              margin: EdgeInsets.symmetric(horizontal: 20, vertical: 15),
              padding: EdgeInsets.only(bottom: 5),
              child: Text(
                'NT/NMR',
                style: TextStyle(fontSize: 16),
              ),
              decoration: BoxDecoration(
                  border: Border(bottom: BorderSide(color: Colors.grey[300]!))),
            ),
            ListView.builder(
              shrinkWrap: true,
              physics: NeverScrollableScrollPhysics(),
              padding: EdgeInsets.all(15),
              itemCount: nt_nmr_bills.length,
              itemBuilder: (BuildContext ctxt, int Index) {
                return Container(
                    decoration: BoxDecoration(
                        color: Colors.grey[200],
                        borderRadius: BorderRadius.circular(10)),
                    padding: EdgeInsets.all(10),
                    margin: EdgeInsets.all(10),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Container(
                              margin: EdgeInsets.only(right: 10),
                              child: Text('Contractor name :'),
                            ),
                            Container(
                              margin: EdgeInsets.only(right: 10),
                              child: Text(
                                nt_nmr_bills[Index][1],
                                style: TextStyle(fontWeight: FontWeight.w600),
                              ),
                            )
                          ],
                        ),
                        Row(
                          children: [
                            Container(
                              margin: EdgeInsets.only(right: 10, top: 10),
                              child: Text('Contractor code :'),
                            ),
                            Container(
                              margin: EdgeInsets.only(right: 10, top: 10),
                              child: Text(
                                nt_nmr_bills[Index][2],
                                style: TextStyle(fontWeight: FontWeight.w600),
                              ),
                            )
                          ],
                        ),
                        SizedBox(height: 10,),
                        Row(
                          children: [
                            Container(
                              margin: EdgeInsets.only(right: 10, top: 10),
                              child: Text('Description :'),
                            ),
                            Expanded(
                              child: Text(
                                nt_nmr_bills[Index][3],
                                style: TextStyle(fontWeight: FontWeight.w600),
                              ),
                            )
                          ],
                        ),
                        SizedBox(height: 10,),
                        Row(
                          children: [
                            Container(
                              margin: EdgeInsets.only(right: 10, top: 10),
                              child: Text('Quantity :'),
                            ),
                            Container(
                              margin: EdgeInsets.only(right: 10, top: 10),
                              child: Text(
                                nt_nmr_bills[Index][4],
                                style: TextStyle(fontWeight: FontWeight.w600),
                              ),
                            )
                          ],
                        ),
                        Row(
                          children: [
                            Container(
                              margin: EdgeInsets.only(right: 10, top: 10),
                              child: Text('Rate :'),
                            ),
                            Container(
                              margin: EdgeInsets.only(right: 10, top: 10),
                              child: Text(
                                nt_nmr_bills[Index][5],
                                style: TextStyle(fontWeight: FontWeight.w600),
                              ),
                            )
                          ],
                        ),
                        Row(
                          children: [
                            Container(
                              margin: EdgeInsets.only(right: 10, top: 10),
                              child: Text('Total payable :'),
                            ),
                            Container(
                              margin: EdgeInsets.only(right: 10, top: 10),
                              child: Text(
                                nt_nmr_bills[Index][6],
                                style: TextStyle(fontWeight: FontWeight.w600),
                              ),
                            )
                          ],
                        ),
                      ],
                    ));
              },
            ),
            Container(
              margin: EdgeInsets.only(bottom: 100),
            )
          ],
        ));
  }
}
