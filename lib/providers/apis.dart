import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';


update_indent_status(status, indent_id, acted_by_user, user_id, notification_body) async {

  DateTime now = DateTime.now();
  String formattedDate = DateFormat('EEEE d MMMM H:m').format(now);

  var url = 'https://app.buildahome.in/erp/API/change_indent_status';
  await http.post(Uri.parse(url), body: {
    'indent_id': indent_id,
    'status': status,
    'acted_by_user': acted_by_user.toString(),
    'user_id': user_id.toString(),
    'notification_body': notification_body,
    'timestamp': formattedDate,
  });

}