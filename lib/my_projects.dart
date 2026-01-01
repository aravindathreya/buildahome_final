import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_spinkit/flutter_spinkit.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:buildAhome/UserHome.dart';
import 'app_theme.dart';
import 'widgets/searchable_select.dart';

class MyProjects extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final appTitle = 'buildAhome';
    final GlobalKey<ScaffoldState> _scaffoldKey = new GlobalKey<ScaffoldState>();
    return MaterialApp(
      title: appTitle,
      theme: AppTheme.darkTheme,
      home: Scaffold(
        key: _scaffoldKey,
        backgroundColor: AppTheme.backgroundPrimary,
        appBar: AppBar(
          automaticallyImplyLeading: true,
          title: Text('Projects'),
          leading: IconButton(
            icon: Icon(Icons.arrow_back),
            onPressed: () {
              Navigator.pop(context);
            },
          ),
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
  var selectedProject;

  @override
  void initState() {
    super.initState();
    call();
  }

  call() async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    id = prefs.getString('user_id');
    var url =
        "https://office.buildahome.in/API/projects_access?id=${id.toString()}";
    print(url);
    var response = await http.get(Uri.parse(url));
    print(response.statusCode);
    setState(() {
      projects = jsonDecode(response.body);
      print(projects);
    });
  }

  Widget build(BuildContext context) {
    return ListView(
      padding: EdgeInsets.all(20),
      children: [
        // Section Header
        Row(
          children: [
            Container(
              width: 4,
              height: 24,
              decoration: BoxDecoration(
                color: AppTheme.primaryColorConst,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            SizedBox(width: 12),
            Text(
              'Select Project',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: AppTheme.textPrimary,
                letterSpacing: 0.5,
              ),
            ),
          ],
        ),
        SizedBox(height: 20),
        
        // Project Selection Button
        InkWell(
          onTap: () async {
            final result = await SearchableSelect.show(
              context: context,
              title: 'Select Project',
              items: projects,
              itemLabel: (item) => item['name'] ?? 'Unknown',
              selectedItem: selectedProject,
            );
            if (result != null) {
              setState(() {
                selectedProject = result;
              });
              
              // Navigate to Home with selected project
              SharedPreferences prefs = await SharedPreferences.getInstance();
              await prefs.setString("project_id", result['id'].toString());
              await prefs.setString("client_name", result['name'].toString());

              Navigator.pushReplacement(
                context,
                MaterialPageRoute(builder: (context) => Home()),
              );
            }
          },
          borderRadius: BorderRadius.circular(16),
          child: Container(
            padding: EdgeInsets.symmetric(horizontal: 16, vertical: 18),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  AppTheme.backgroundSecondary,
                  AppTheme.backgroundPrimaryLight,
                ],
              ),
              borderRadius: BorderRadius.circular(16),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.2),
                  blurRadius: 8,
                  offset: Offset(0, 4),
                ),
              ],
            ),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    selectedProject != null
                        ? (selectedProject['name'] ?? 'Unknown')
                        : 'Select a project',
                    style: TextStyle(
                      color: selectedProject != null
                          ? AppTheme.textPrimary
                          : AppTheme.textSecondary,
                      fontSize: 16,
                      fontWeight: selectedProject != null
                          ? FontWeight.w500
                          : FontWeight.normal,
                    ),
                  ),
                ),
                Icon(
                  Icons.arrow_forward_ios,
                  color: AppTheme.primaryColorConst,
                  size: 18,
                ),
              ],
            ),
          ),
        ),
        
        SizedBox(height: 30),
        
        // Projects List Section
        if (projects.length > 0) ...[
          Row(
            children: [
              Container(
                width: 4,
                height: 24,
                decoration: BoxDecoration(
                  color: AppTheme.primaryColorConst,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              SizedBox(width: 12),
              Text(
                'All Projects (${projects.length})',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: AppTheme.textPrimary,
                  letterSpacing: 0.5,
                ),
              ),
            ],
          ),
          SizedBox(height: 16),
          ...projects.map((project) {
            final projectName = project['name']?.toString() ?? '';
            if (projectName.trim().length == 0) return SizedBox.shrink();
            return Container(
              margin: EdgeInsets.only(bottom: 12),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    AppTheme.backgroundSecondary,
                    AppTheme.backgroundPrimaryLight,
                  ],
                ),
                borderRadius: BorderRadius.circular(16),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.2),
                    blurRadius: 8,
                    offset: Offset(0, 4),
                  ),
                ],
              ),
              child: Material(
                color: Colors.transparent,
                child: InkWell(
                  onTap: () async {
                    SharedPreferences prefs = await SharedPreferences.getInstance();
                    await prefs.setString("project_id", project['id'].toString());
                    await prefs.setString("client_name", project['name'].toString());

                    Navigator.pushReplacement(
                      context,
                      MaterialPageRoute(builder: (context) => Home()),
                    );
                  },
                  borderRadius: BorderRadius.circular(16),
                  child: Padding(
                    padding: EdgeInsets.symmetric(horizontal: 16, vertical: 18),
                    child: Row(
                      children: [
                        Container(
                          padding: EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: AppTheme.primaryColorConst.withOpacity(0.2),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Icon(
                            Icons.folder_special,
                            color: AppTheme.primaryColorConst,
                            size: 24,
                          ),
                        ),
                        SizedBox(width: 16),
                        Expanded(
                          child: Text(
                            projectName,
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                              color: AppTheme.textPrimary,
                            ),
                          ),
                        ),
                        Icon(
                          Icons.chevron_right,
                          color: AppTheme.textSecondary,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            );
          }).toList(),
        ] else ...[
          Center(
            child: Padding(
              padding: EdgeInsets.all(40),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  SpinKitRing(
                    color: AppTheme.primaryColorConst,
                    lineWidth: 2,
                    size: 40,
                  ),
                  SizedBox(height: 16),
                  Text(
                    'Loading projects...',
                    style: TextStyle(
                      color: AppTheme.textSecondary,
                      fontSize: 16,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ],
    );
  }
}
