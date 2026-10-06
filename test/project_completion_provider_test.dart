import 'dart:convert';

import 'package:buildAhome/services/data_provider.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final provider = DataProvider();
  final fixtures = <String, http.Response>{};
  final requestedIds = <String>[];
  final unexpectedRequests = <String>[];
  late String? previousRole;
  late String? previousProjectId;
  late String? previousCompletion;
  late double previousDelay;
  late int? previousTotal;
  late int? previousBase;

  // ApiHttp initializes its shared inner client on the first request. Reuse one
  // guarded mock across tests; every response is an in-memory fixture.
  final client = MockClient((request) async {
    final id = request.url.queryParameters['id'];
    if (request.method != 'GET' ||
        request.url.scheme != 'https' ||
        request.url.host != 'office.buildahome.in' ||
        request.url.path != '/API/get_project_percentage' ||
        request.url.queryParameters['detail'] != '1' ||
        id == null ||
        !fixtures.containsKey(id)) {
      unexpectedRequests.add('${request.method} ${request.url}');
      return http.Response('{}', 503);
    }
    requestedIds.add(id);
    return fixtures[id]!;
  });

  http.Response detail({
    required num? percent,
    required num? total,
    num? base,
    num delay = 0,
    bool? mappingResolved,
    bool? available,
  }) =>
      http.Response(
        jsonEncode({
          'percent': percent,
          'total_days': total,
          'base_total_days': base ?? total,
          'doc_delay_days_total': delay,
          if (mappingResolved != null) ...{
            'project_mapping_resolved': mappingResolved,
            'erp_project_id': 100,
          },
          if (available != null) 'available': available,
        }),
        200,
        headers: {'content-type': 'application/json'},
      );

  Future<void> refresh() => http.runWithClient(
        () => provider.refreshProjectPercentage(),
        () => client,
      );

  setUp(() {
    previousRole = provider.currentRole;
    previousProjectId = provider.clientProjectId;
    previousCompletion = provider.clientProjectCompletion;
    previousDelay = provider.clientDocDelayDays;
    previousTotal = provider.clientTotalDays;
    previousBase = provider.clientBaseTotalDays;
    provider.currentRole = 'Client';
    provider.clientProjectId = '100';
    provider.clientProjectCompletion = null;
    provider.clientDocDelayDays = 0;
    provider.clientTotalDays = null;
    provider.clientBaseTotalDays = null;
    fixtures.clear();
    requestedIds.clear();
    unexpectedRequests.clear();
    SharedPreferences.setMockInitialValues({
      'role': 'Client',
      'project_id': '100',
      'project_number': 'P100',
    });
  });

  tearDown(() {
    provider.currentRole = previousRole;
    provider.clientProjectId = previousProjectId;
    provider.clientProjectCompletion = previousCompletion;
    provider.clientDocDelayDays = previousDelay;
    provider.clientTotalDays = previousTotal;
    provider.clientBaseTotalDays = previousBase;
    expect(unexpectedRequests, isEmpty);
  });

  tearDownAll(client.close);

  test('zero ERP duration retries the linked project and persists valid days',
      () async {
    fixtures['100'] = detail(percent: 0, total: 0);
    fixtures['P100'] = detail(percent: 0, total: 364, base: 360, delay: 4);

    await refresh();

    expect(requestedIds, ['100', 'P100']);
    expect(provider.clientTotalDays, 364);
    expect(provider.clientBaseTotalDays, 360);
    expect(provider.clientDocDelayDays, 4);
    expect(provider.clientRemainingDays, 364);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getInt('total_days'), 364);
    expect(prefs.getInt('base_total_days'), 360);
    expect(prefs.getDouble('doc_delay_days'), 4);
  });

  test('both zero durations stay unknown and remove the old zero cache',
      () async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('completed', '0');
    await prefs.setInt('total_days', 0);
    await prefs.setInt('base_total_days', 0);
    fixtures['100'] = detail(percent: 0, total: 0);
    fixtures['P100'] = detail(percent: 0, total: 0);

    await refresh();

    expect(requestedIds, ['100', 'P100']);
    expect(provider.clientTotalDays, isNull);
    expect(provider.clientBaseTotalDays, isNull);
    expect(provider.clientRemainingDays, isNull);
    expect(provider.clientCompletedDays, isNull);
    expect(prefs.containsKey('total_days'), isFalse);
    expect(prefs.containsKey('base_total_days'), isFalse);
  });

  test('positive primary duration retains one pending day at 99.9 percent',
      () async {
    fixtures['100'] = detail(percent: 99.9, total: 364);

    await refresh();

    expect(requestedIds, ['100']);
    expect(provider.clientTotalDays, 364);
    expect(provider.clientRemainingDays, 1);
    expect(provider.clientCompletedDays, 363);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getInt('total_days'), 364);
  });

  test('canonical progress without days cannot be replaced by a numeric alias',
      () async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('project_number', '200');
    fixtures['100'] = detail(
      percent: 37.5,
      total: null,
      mappingResolved: true,
      available: true,
    );
    fixtures['200'] = detail(percent: 0, total: 364);

    await refresh();

    expect(requestedIds, ['100']);
    expect(provider.clientProjectCompletion, '37.5');
    expect(provider.clientTotalDays, isNull);
    expect(provider.clientRemainingDays, isNull);
    expect(prefs.getString('completed'), '37.5');
  });

  test('verified canonical zero remains valid project progress', () async {
    fixtures['100'] = detail(
      percent: 0,
      total: 364,
      mappingResolved: true,
      available: true,
    );

    await refresh();

    expect(requestedIds, ['100']);
    expect(provider.clientProjectCompletion, '0');
    expect(provider.clientRemainingDays, 364);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('completed'), '0');
  });

  test('explicit unavailable response clears stale progress and duration',
      () async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('completed', '0');
    await prefs.setInt('total_days', 364);
    await prefs.setInt('base_total_days', 360);
    await prefs.setDouble('doc_delay_days', 4);
    provider.clientProjectCompletion = '0';
    provider.clientTotalDays = 364;
    provider.clientBaseTotalDays = 360;
    provider.clientDocDelayDays = 4;
    fixtures['100'] = detail(
      percent: null,
      total: null,
      mappingResolved: true,
      available: false,
    );

    await refresh();

    expect(requestedIds, ['100']);
    expect(provider.clientProjectCompletion, isNull);
    expect(provider.clientTotalDays, isNull);
    expect(provider.clientBaseTotalDays, isNull);
    expect(provider.clientDocDelayDays, 0);
    expect(provider.clientRemainingDays, isNull);
    for (final key in [
      'completed',
      'total_days',
      'base_total_days',
      'doc_delay_days',
    ]) {
      expect(prefs.containsKey(key), isFalse, reason: key);
    }
  });

  test('legacy retry honors an explicit unavailable canonical response',
      () async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('completed', '0');
    await prefs.setInt('total_days', 364);
    fixtures['100'] = detail(percent: 0, total: null);
    fixtures['P100'] = detail(
      percent: null,
      total: null,
      mappingResolved: true,
      available: false,
    );

    await refresh();

    expect(requestedIds, ['100', 'P100']);
    expect(provider.clientProjectCompletion, isNull);
    expect(provider.clientTotalDays, isNull);
    expect(prefs.containsKey('completed'), isFalse);
    expect(prefs.containsKey('total_days'), isFalse);
  });

  test('valid progress recovers after a canonical unavailable response',
      () async {
    fixtures['100'] = detail(
      percent: null,
      total: null,
      mappingResolved: true,
      available: false,
    );
    await refresh();
    expect(provider.clientProjectCompletion, isNull);

    fixtures['100'] = detail(
      percent: 37.5,
      total: 364,
      mappingResolved: true,
      available: true,
    );
    await refresh();

    expect(requestedIds, ['100', '100']);
    expect(provider.clientProjectCompletion, '37.5');
    expect(provider.clientRemainingDays, 228);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('completed'), '37.5');
    expect(prefs.getInt('total_days'), 364);
  });

  test('API failures restore cached zero duration as unknown', () async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('completed', '0');
    await prefs.setInt('total_days', 0);
    await prefs.setInt('base_total_days', 0);
    fixtures['100'] = http.Response('{}', 503);
    fixtures['P100'] = http.Response('{}', 503);

    await refresh();

    expect(requestedIds, ['100', 'P100']);
    expect(provider.clientTotalDays, isNull);
    expect(provider.clientBaseTotalDays, isNull);
    expect(provider.clientRemainingDays, isNull);
  });

  test('API failures preserve a valid cached construction countdown', () async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('completed', '50');
    await prefs.setInt('total_days', 364);
    await prefs.setInt('base_total_days', 360);
    fixtures['100'] = http.Response('{}', 503);
    fixtures['P100'] = http.Response('{}', 503);

    await refresh();

    expect(requestedIds, ['100', 'P100']);
    expect(provider.clientTotalDays, 364);
    expect(provider.clientBaseTotalDays, 360);
    expect(provider.clientRemainingDays, 182);
    expect(provider.clientCompletedDays, 182);
    expect(prefs.getInt('total_days'), 364);
  });
}
