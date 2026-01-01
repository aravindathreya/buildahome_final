import 'package:flutter/material.dart';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:flutter_spinkit/flutter_spinkit.dart';
import '../app_theme.dart';
import 'package:provider/provider.dart';
import '../providers/theme_provider.dart';

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
    return Consumer<ThemeProvider>(
      builder: (context, themeProvider, child) {
        final maxHeight = MediaQuery.of(context).viewInsets.bottom > 0
            ? MediaQuery.of(context).size.height * 0.3
            : MediaQuery.of(context).size.height * 0.6;
        
        return Dialog(
          backgroundColor: AppTheme.getBackgroundSecondary(context),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          child: Container(
            width: MediaQuery.of(context).size.width * 0.9,
            constraints: BoxConstraints(
              maxHeight: maxHeight + 200, // Add space for header and search
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Header
                Container(
                  padding: EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: AppTheme.getBackgroundSecondary(context),
                    borderRadius: BorderRadius.only(
                      topLeft: Radius.circular(20),
                      topRight: Radius.circular(20),
                    ),
                  ),
                  child: Row(
                    children: [
                      Container(
                        padding: EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: AppTheme.getPrimaryColor(context).withOpacity(0.1),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Icon(
                          Icons.inventory_2,
                          color: AppTheme.getPrimaryColor(context),
                          size: 24,
                        ),
                      ),
                      SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          "Select Material",
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            color: AppTheme.getTextPrimary(context),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                // Search field
                Container(
                  margin: EdgeInsets.fromLTRB(20, 16, 20, 16),
                  decoration: BoxDecoration(
                    color: AppTheme.getBackgroundPrimary(context),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: AppTheme.getPrimaryColor(context).withOpacity(0.2),
                    ),
                  ),
                  child: TextFormField(
                    style: TextStyle(
                      color: AppTheme.getTextPrimary(context),
                      fontSize: 16,
                    ),
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
                      hintStyle: TextStyle(
                        color: AppTheme.getTextSecondary(context),
                      ),
                      contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                      border: InputBorder.none,
                      suffixIcon: Icon(
                        Icons.search,
                        color: AppTheme.getPrimaryColor(context),
                      ),
                    ),
                  ),
                ),
                // Materials list
                Flexible(
                  child: Container(
                    constraints: BoxConstraints(
                      maxHeight: maxHeight,
                    ),
                    child: materials.length == 0
                        ? Container(
                            padding: EdgeInsets.all(40),
                            child: SpinKitRing(
                              color: AppTheme.getPrimaryColor(context),
                              lineWidth: 3,
                              size: 40,
                            ),
                          )
                        : search_data.length == 0
                            ? Container(
                                padding: EdgeInsets.all(40),
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(
                                      Icons.search_off,
                                      size: 48,
                                      color: AppTheme.getTextSecondary(context),
                                    ),
                                    SizedBox(height: 16),
                                    Text(
                                      'No materials found',
                                      style: TextStyle(
                                        color: AppTheme.getTextSecondary(context),
                                        fontSize: 16,
                                      ),
                                    ),
                                  ],
                                ),
                              )
                            : ListView.builder(
                                shrinkWrap: true,
                                physics: BouncingScrollPhysics(),
                                scrollDirection: Axis.vertical,
                                itemCount: search_data.length,
                                padding: EdgeInsets.symmetric(horizontal: 20),
                                itemBuilder: (BuildContext ctxt, int index) {
                                  return Container(
                                    margin: EdgeInsets.only(bottom: 8),
                                    decoration: BoxDecoration(
                                      color: AppTheme.getBackgroundSecondary(context),
                                      borderRadius: BorderRadius.circular(12),
                                      border: Border.all(
                                        color: AppTheme.getPrimaryColor(context).withOpacity(0.2),
                                        width: 1,
                                      ),
                                      boxShadow: [
                                        BoxShadow(
                                          color: Colors.black.withOpacity(0.05),
                                          blurRadius: 4,
                                          offset: Offset(0, 2),
                                        ),
                                      ],
                                    ),
                                    child: Material(
                                      color: Colors.transparent,
                                      child: InkWell(
                                        onTap: () {
                                          Navigator.pop(context, search_data[index]);
                                        },
                                        borderRadius: BorderRadius.circular(12),
                                        child: Container(
                                          padding: EdgeInsets.all(16),
                                          child: Row(
                                            children: [
                                              Container(
                                                padding: EdgeInsets.all(8),
                                                decoration: BoxDecoration(
                                                  color: AppTheme.getPrimaryColor(context).withOpacity(0.15),
                                                  borderRadius: BorderRadius.circular(8),
                                                ),
                                                child: Icon(
                                                  Icons.inventory_2_outlined,
                                                  color: AppTheme.getPrimaryColor(context),
                                                  size: 20,
                                                ),
                                              ),
                                              SizedBox(width: 12),
                                              Expanded(
                                                child: Text(
                                                  search_data[index].toString(),
                                                  style: TextStyle(
                                                    fontSize: 16,
                                                    fontWeight: FontWeight.w600,
                                                    color: AppTheme.getTextPrimary(context),
                                                  ),
                                                ),
                                              ),
                                              Icon(
                                                Icons.arrow_forward_ios,
                                                size: 16,
                                                color: AppTheme.getTextSecondary(context),
                                              ),
                                            ],
                                          ),
                                        ),
                                      ),
                                    ),
                                  );
                                },
                              ),
                  ),
                ),
                SizedBox(height: 20),
              ],
            ),
          ),
        );
      },
    );
  }
}
