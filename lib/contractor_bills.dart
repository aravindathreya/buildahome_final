import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'NavMenu.dart';
import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';
import 'main.dart';

class ContractorBills extends StatefulWidget {
  var contractor_name;
  var contractor_code;
  var trade;

  ContractorBills(this.contractor_name, this.contractor_code, this.trade);

  @override
  ContractorBillsState createState() {
    return ContractorBillsState(
        this.contractor_name, this.contractor_code, this.trade);
  }
}

class ContractorBillsState extends State<ContractorBills> {
  var bills = [];
  var contractor_name;
  var contractor_code;
  var trade;

  ContractorBillsState(this.contractor_name, this.contractor_code, this.trade);

  call() async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    var id = prefs.getString('project_id');
    var _bills;

    var bills_url =
        'https://app.buildahome.in/erp/API/view_bills?project_id=$id&trade=${this.trade}&name=${this.contractor_name}&code=${this.contractor_code}';
    var bills_response = await http.get(bills_url);

    _bills = jsonDecode(bills_response.body);

    setState(() {
      bills = _bills;
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
        appBar: AppBar(
          automaticallyImplyLeading: true,
          title: Text(appTitle),
          leading: new IconButton(
              icon: new Icon(Icons.chevron_left),
              onPressed: () => {Navigator.pop(context)}),
          backgroundColor: Color(0xFF000055),
        ),
        drawer: NavMenuWidget(),
        body: ListView(
          children: [
            Container(
              margin: EdgeInsets.symmetric(horizontal: 20, vertical: 15),
              padding: EdgeInsets.only(bottom: 5),
              child: Text(
                'Bills for contractor ${this.contractor_name}',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.w600),
              ),
              decoration: BoxDecoration(
                  border: Border(bottom: BorderSide(color: Colors.grey[300]))),
            ),
            ListView.builder(
              shrinkWrap: true,
              physics: NeverScrollableScrollPhysics(),
              padding: EdgeInsets.all(15),
              itemCount: bills.length,
              itemBuilder: (BuildContext ctxt, int Index) {
                print(bills[Index]);
                return Container(
                    margin: EdgeInsets.symmetric(vertical: 10),
                    padding: EdgeInsets.all(15),
                    decoration: BoxDecoration(
                      color: Colors.grey[200],
                      border: Border(
                          left: BorderSide(
                              color: bills[Index][3] == null
                                  ? Colors.grey[300]
                                  : Colors.green[400],
                              width: 5)),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(
                          margin: EdgeInsets.only(bottom: 5),
                          child: Text(
                            'Trade: ' + this.trade,
                            style: TextStyle(fontWeight: FontWeight.w600),
                          ),
                        ),
                        Container(
                          margin: EdgeInsets.only(bottom: 5),
                          child: Text(
                            'Stage: ' + bills[Index][0] == null
                                ? ''
                                : bills[Index][0].toString(),
                            style: TextStyle(fontWeight: FontWeight.w600),
                          ),
                        ),
                        Container(
                          margin: EdgeInsets.only(bottom: 5),
                          child: Text(
                            'Percentage: ' +
                                (bills[Index][1] == null
                                    ? "0"
                                    : bills[Index][1].toString()) +
                                '%',
                          ),
                        ),
                        Container(
                          margin: EdgeInsets.only(bottom: 5),
                          child: Text(
                            'Total payable: ' +
                                (bills[Index][2] == null
                                    ? '0'
                                    : bills[Index][2].toString()),
                          ),
                        ),
                        Container(
                          margin: EdgeInsets.only(bottom: 5),
                          child: Text(
                            'Amoount: ' +
                                (bills[Index][3] == null
                                    ? '0'
                                    : bills[Index][3].toString()),
                          ),
                        ),
                        Container(
                          margin: EdgeInsets.only(bottom: 5),
                          child: Text(
                            'Created on: ' +
                                (bills[Index][5] == null
                                    ? ''
                                    : bills[Index][5].toString()),
                          ),
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
