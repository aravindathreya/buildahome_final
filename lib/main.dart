// Built in packages
import 'package:flutter/material.dart';
import 'Skin2/loginPage.dart';

void main() => runApp(App());

class App extends StatelessWidget {
  final fontName = 'Mulish-Regular';

  // Used globally for client logins
  late final project_id;
  late BuildContext mainContext;

  @override
  Widget build(BuildContext context) {
    final appTitle = 'buildAhome';

    return MaterialApp(
      title: appTitle,
      theme: ThemeData(fontFamily: fontName),
      home: Scaffold(
        body: LoginScreenNew(),
      ),
    );
  }
}



// class LoginForm extends StatefulWidget {
//   @override
//   LoginFormState createState() {
//     return LoginFormState();
//   }
// }

// class LoginFormState extends State<LoginForm> {
//   String loginAPIResponse = "";
//   String role;
//   bool showLoginForm = false;
//   final username = TextEditingController();
//   final password = TextEditingController();

//   void initState() {
//     super.initState();

//     checkIfAlreadyLoggedIn();
//     initFirebase();
//   }

//   initFirebase() {
//     // final FirebaseMessaging _messaging = FirebaseMessaging();

//     // _messaging.configure(
//     //   onMessage: (Map<String, dynamic> message) async {
//     //     if (role != 'Client') {
//     //       Navigator.push(context,
//     //           MaterialPageRoute(builder: (context) => Notifications()));
//     //     }
//     //   },
//     //   onLaunch: (Map<String, dynamic> message) async {
//     //     print("onLaunch: $message");
//     //     if (role != 'Client') {
//     //       Navigator.push(context,
//     //           MaterialPageRoute(builder: (context) => Notifications()));
//     //     }
//     //   },
//     //   onResume: (Map<String, dynamic> message) async {
//     //     print("onResume: $message");
//     //     if (role != 'Client') {
//     //       Navigator.push(context,
//     //           MaterialPageRoute(builder: (context) => Notifications()));
//     //     }
//     //   },
//     // );
//     // _messaging.getToken().then((token) {
//     //   print(token);
//     // });
//   }

//   checkIfAlreadyLoggedIn() async {
//     SharedPreferences prefs = await SharedPreferences.getInstance();
//     var username = prefs.getString('username');
//     role = prefs.getString('role');

//     setState(() {
//       if (username != null) {
//         showLoginForm = false;
//         if (role == "Client") {
//           Navigator.pushReplacement(
//             context,
//             MaterialPageRoute(builder: (context) => Home()),
//           );
//         } else {
//           Navigator.pushReplacement(
//             context,
//             MaterialPageRoute(builder: (context) => AdminDashboard()),
//           );
//         }
//       } else {
//         showLoginForm = true;
//       }
//     });
//   }

//   subscribeToFirebaseTopic(topic) {
//     // final FirebaseMessaging _messaging = FirebaseMessaging();
//     // _messaging.subscribeToTopic(topic.toString());
//   }

//   setSharedPrefs(username, role, projectId, projectValue, completed, userId,
//       location, apiToken) async {
//     SharedPreferences prefs = await SharedPreferences.getInstance();
//     prefs.setString("username", username.toString());
//     prefs.setString("role", role.toString());
//     prefs.setString("user_id", userId.toString());
//     prefs.setString("api_token", apiToken.toString());

//     if (role.toString() == 'Client') {
//       prefs.setString("project_id", projectId.toString());
//       prefs.setString("project_value", projectValue.toString());
//       prefs.setString("completed", completed.toString());
//       prefs.setString("location", location.toString());
//     }
//   }

//   validateLoginForm() {
//     if (username.text.trim() == '') {
//       return 'Please enter username to continue';
//     } else if (password.text.trim() == '') {
//       return 'Please enter password to continue';
//     } else
//       return true;
//   }

//   showFormFieldsInvalid(context, validationMessage) {
//     showDialog(
//         context: context,
//         builder: (BuildContext context) {
//           return AlertDialog(
//             content: Container(
//                 height: 130,
//                 child: Column(
//                   crossAxisAlignment: CrossAxisAlignment.start,
//                   children: [
//                     Container(
//                       margin: EdgeInsets.only(bottom: 20),
//                       child: Icon(Icons.warning_amber_rounded,
//                           size: 50, color: Colors.orange),
//                     ),
//                     Container(
//                       margin: EdgeInsets.only(left: 5),
//                       child: Text(
//                         validationMessage,
//                       ),
//                     )
//                   ],
//                 )),
//           );
//         });
//   }

//   loginUser() async {
//     // Show loader
//     showDialog(
//         context: context,
//         builder: (BuildContext context) {
//           return Loader();
//         });

//     var url = Uri.parse('https://office.buildahome.in/API/login');
//     var response = await http.post(url,
//         body: {'username': username.text, 'password': password.text});
//     Map<String, dynamic> jsonDecodedResponse = jsonDecode(response.body);
//     Navigator.of(context, rootNavigator: true).pop('dialog');

//     if (jsonDecodedResponse['message'].toString() != "success") {
//       setState(() {
//         loginAPIResponse = jsonDecodedResponse['message'];
//       });
//     } else {
//       if (jsonDecodedResponse['role'] == 'Client') {
//         setSharedPrefs(
//             username.text,
//             jsonDecodedResponse['role'],
//             jsonDecodedResponse['project_id'],
//             jsonDecodedResponse['project_value'],
//             jsonDecodedResponse['completed_percentage'],
//             jsonDecodedResponse['user_id'],
//             jsonDecodedResponse['location'],
//             jsonDecodedResponse['api_token']);

//         subscribeToFirebaseTopic(jsonDecodedResponse['user_id']);

//         Navigator.pushReplacement(
//           context,
//           MaterialPageRoute(builder: (context) => Home()),
//         );
//       } else {
//         setSharedPrefs(
//             username.text,
//             jsonDecodedResponse['role'],
//             '',
//             '',
//             '',
//             jsonDecodedResponse["user_id"],
//             '',
//             jsonDecodedResponse['api_token']);
//         subscribeToFirebaseTopic(jsonDecodedResponse['user_id']);
//         Navigator.pushReplacement(
//           context,
//           MaterialPageRoute(builder: (context) => AdminDashboard()),
//         );
//       }
//     }
//   }

//   @override
//   Widget build(BuildContext context) {
//     return ListView(
//       children: <Widget>[
//         // Logo container
//         Container(
//             padding: EdgeInsets.only(top: 40),
//             width: MediaQuery.of(context).size.width,
//             color: Colors.white,
//             height: MediaQuery.of(context).size.height * 0.4,
//             alignment: Alignment.center,
//             child: Image(
//               image: AssetImage('assets/images/logo-big.png'),
//               fit: BoxFit.fill,
//               height: 150,
//             )),

//         // Response from api
//         if (loginAPIResponse != '')
//           Padding(
//             padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 30),
//             child: Text(
//               loginAPIResponse,
//               style: TextStyle(fontSize: 16, color: Colors.red[500]),
//             ),
//           ),

//         // Username text field
//         if (showLoginForm)
//           Container(
//             padding: EdgeInsets.only(left: 30, right: 30, bottom: 30, top: 15),
//             alignment: Alignment.center,
//             color: Colors.white,
//             child: TextFormField(
//                 controller: username,
//                 scrollPadding: EdgeInsets.all(1),
//                 style: TextStyle(fontSize: 16.0),
//                 decoration: InputDecoration(
//                     labelText: 'Username',
//                     contentPadding: EdgeInsets.only(bottom: 5),
//                     labelStyle: TextStyle(fontSize: 16.0),
//                     fillColor: Colors.indigo)),
//           ),

//         // Password field
//         if (showLoginForm)
//           Container(
//             padding: EdgeInsets.only(left: 30, right: 30),
//             alignment: Alignment.center,
//             color: Colors.white,
//             child: TextFormField(
//               controller: password,
//               keyboardType: TextInputType.phone,
//               style: TextStyle(fontSize: 16.0),
//               obscureText: true,
//               decoration: InputDecoration(
//                 labelText: 'Password',
//                 contentPadding: EdgeInsets.only(bottom: 5),
//                 errorStyle: TextStyle(color: Colors.indigo[800]),
//                 labelStyle: TextStyle(fontSize: 16.0),
//               ),
//             ),
//           ),

//         // Button to login
//         if (showLoginForm)
//           Container(
//             padding: const EdgeInsets.symmetric(vertical: 40.0, horizontal: 30),
//             color: Colors.white,
//             child: InkWell(
//                 child: Container(
//                   alignment: Alignment.center,
//                   padding: EdgeInsets.all(8),
//                   decoration: BoxDecoration(
//                     gradient: LinearGradient(
//                       begin: Alignment.topLeft,
//                       end: Alignment.bottomRight,
//                       stops: [0.2, 0.5, 0.8],
//                       colors: [
//                         Color.fromARGB(255, 13, 17, 65),
//                         Colors.indigo[700],
//                         Color.fromARGB(255, 13, 17, 65),
//                       ],
//                     ),
//                     border: Border.all(color: Colors.black, width: 1),
//                     borderRadius: BorderRadius.all(Radius.circular(5)),
//                   ),
//                   child: Row(
//                     mainAxisAlignment: MainAxisAlignment.center,
//                     children: <Widget>[
//                       Text(
//                         "Step in ",
//                         style: TextStyle(
//                             fontSize: 18,
//                             color: Colors.white,
//                             fontWeight: FontWeight.bold),
//                       ),
//                       Icon(Icons.vpn_key, color: Colors.white),
//                     ],
//                   ),
//                 ),
//                 onTap: () {
//                   var validationMessage = validateLoginForm();
//                   if (validationMessage != true) {
//                     showFormFieldsInvalid(context, validationMessage);
//                   } else {
//                     loginUser();
//                   }
//                 }),
//           ),
//       ],
//     );
//   }
// }
