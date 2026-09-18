import 'package:flutter_test/flutter_test.dart';

import 'package:buildAhome/models/mobile_chatbot.dart';

void main() {
  group('MobileChatbotAskResult', () {
    test('paints answer and keeps conversation from a successful reply', () {
      final result = MobileChatbotAskResult.fromJson({
        'success': true,
        'ok': true,
        'answer':
            'BH-1\nCurrently 64% complete.\nCurrent activity: Electrical Work',
        'intent': 'PROJECT_STATUS',
        'supported': true,
        'conversation': {'intent': 'PROJECT_STATUS', 'sales_sop_id': 9},
        'stage': {
          'name': 'Electrical Work',
          'images': [
            {
              'url': 'https://office.buildahome.in/static/x.png',
              'caption': 'Stage',
              'kind': 'image',
            },
          ],
          'tracker': {'percent': 64, 'label': 'Currently 64% complete'},
        },
      });

      expect(result.success, isTrue);
      expect(result.supported, isTrue);
      expect(
        result.text,
        'BH-1\nCurrently 64% complete.\nCurrent activity: Electrical Work',
      );
      expect(result.intent, 'PROJECT_STATUS');
      expect(result.conversation, {
        'intent': 'PROJECT_STATUS',
        'sales_sop_id': 9,
      });
      expect(result.stage?.name, 'Electrical Work');
      expect(result.stage?.tracker.percent, 64);
      expect(result.stage?.imageUrls, [
        'https://office.buildahome.in/static/x.png',
      ]);
    });

    test('shows message when success is false', () {
      final result = MobileChatbotAskResult.fromJson({
        'success': false,
        'message': 'No project linked to this client',
      });
      expect(result.success, isFalse);
      expect(result.text, 'No project linked to this client');
    });

    test('still shows answer when supported is false', () {
      final result = MobileChatbotAskResult.fromJson({
        'success': true,
        'supported': false,
        'answer': "I can't answer that yet.",
        'conversation': {'intent': 'UNSUPPORTED'},
      });
      expect(result.success, isTrue);
      expect(result.supported, isFalse);
      expect(result.text, "I can't answer that yet.");
      expect(result.conversation?['intent'], 'UNSUPPORTED');
    });
  });

  group('MobileChatbotGreeting', () {
    test('reads greeting and chip questions', () {
      final greeting = MobileChatbotGreeting.fromJson({
        'success': true,
        'greeting': 'Hello from the project bot.',
        'questions': [
          "What's my project status?",
          {'text': 'Where are my payments?'},
        ],
      });
      expect(greeting.greeting, 'Hello from the project bot.');
      expect(greeting.questions, [
        "What's my project status?",
        'Where are my payments?',
      ]);
    });
  });
}
