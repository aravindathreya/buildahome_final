import 'package:buildAhome/services/session_manager.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final session = SessionManager.instance;

  test('opening the app stays signed in on a bare 401 or a task list', () {
    expect(session.probeRequiresLogout(401, ''), isFalse);
    expect(session.probeRequiresLogout(401, '{"message":"not found"}'), isFalse);
    expect(session.probeRequiresLogout(500, 'gateway timeout'), isFalse);
    expect(
      session.probeRequiresLogout(
        200,
        '{"tasks":[{"id":1,"note":"all good"}]}',
      ),
      isFalse,
    );
  });

  test('opening the app logs out only for an explicit invalid token', () {
    expect(
      session.probeRequiresLogout(
        401,
        '{"success":false,"message":"Invalid api token"}',
      ),
      isTrue,
    );
    expect(
      session.probeRequiresLogout(
        200,
        '{"success":false,"message":"Invalid api token"}',
      ),
      isTrue,
    );
  });
}
