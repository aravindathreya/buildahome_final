import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'NavMenu.dart';
import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

class ContractorBills extends StatefulWidget {
  final contractorName;
  final contractorCode;
  final trade;

  ContractorBills(this.contractorName, this.contractorCode, this.trade);

  @override
  ContractorBillsState createState() {
    return ContractorBillsState(
        this.contractorName, this.contractorCode, this.trade);
  }
}

class ContractorBillsState extends State<ContractorBills> {
  var bills = [];
  var contractorName;
  var contractorCode;
  var trade;

  ContractorBillsState(this.contractorName, this.contractorCode, this.trade);

  call() async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    var id = prefs.getString('project_id');
    var _bills;

    var billsUrl =
        'https://app.buildahome.in/erp/API/view_bills?project_id=$id&trade=${this.trade}&name=${this.contractorName}&code=${this.contractorCode}';
    var billsResponse = await http.get(Uri.parse(billsUrl));
    _bills = jsonDecode(billsResponse.body);

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
                'Bills for contractor ${this.contractorName}',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.w600),
              ),
              decoration: BoxDecoration(
                  border: Border(bottom: BorderSide(color: Colors.grey[300]!))),
            ),
            ListView.builder(
              shrinkWrap: true,
              physics: NeverScrollableScrollPhysics(),
              padding: EdgeInsets.all(15),
              itemCount: bills.length,
              itemBuilder: (BuildContext ctxt, int index) {
                print(bills[index]);
                return Container(
                    margin: EdgeInsets.symmetric(vertical: 10),
                    padding: EdgeInsets.all(15),
                    decoration: BoxDecoration(
                      color: Colors.grey[200],
                      border: Border(
                          left: BorderSide(
                              color: bills[index][3] == null
                                  ? Colors.grey[300]!
                                  : Colors.green[400]!,
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
                            'Stage: ' + bills[index][0].toString(),
                            style: TextStyle(fontWeight: FontWeight.w600),
                          ),
                        ),
                        Container(
                          margin: EdgeInsets.only(bottom: 5),
                          child: Text(
                            'Percentage: ' +
                                (bills[index][1] == null
                                    ? "0"
                                    : bills[index][1].toString()) +
                                '%',
                          ),
                        ),
                        Container(
                          margin: EdgeInsets.only(bottom: 5),
                          child: Text(
                            'Total payable: ' +
                                (bills[index][2] == null
                                    ? '0'
                                    : bills[index][2].toString()),
                          ),
                        ),
                        Container(
                          margin: EdgeInsets.only(bottom: 5),
                          child: Text(
                            'Amoount: ' +
                                (bills[index][3] == null
                                    ? '0'
                                    : bills[index][3].toString()),
                          ),
                        ),
                        Container(
                          margin: EdgeInsets.only(bottom: 5),
                          child: Text(
                            'Created on: ' +
                                (bills[index][5] == null
                                    ? ''
                                    : bills[index][5].toString()),
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
