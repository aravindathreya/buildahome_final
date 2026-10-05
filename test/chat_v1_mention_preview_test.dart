import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:buildAhome/chat_v1/chat_v1_controller.dart';
import 'package:buildAhome/chat_v1/chat_v1_mapper.dart';
import 'package:buildAhome/chat_v1/chat_v1_theme.dart';
import 'package:buildAhome/chat_v1/widgets/chat_v1_chat_tile.dart';
import 'package:buildAhome/chat_v1/widgets/chat_v1_mention_banner.dart';
import 'package:buildAhome/chat_v1/widgets/chat_v1_message_bubble.dart';

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    await (FontLoader(ChatV1Theme.fontFamily)
          ..addFont(rootBundle.load('assets/fonts/Mulish/Mulish-Regular.ttf')))
        .load();
    var sdkDir = File(Platform.resolvedExecutable).parent;
    while (!File(sdkDir.path +
                '/artifacts/material_fonts/materialicons-regular.otf')
            .existsSync() &&
        sdkDir.parent.path != sdkDir.path) {
      sdkDir = sdkDir.parent;
    }
    await (FontLoader('MaterialIcons')
          ..addFont(File(sdkDir.path +
                  '/artifacts/material_fonts/materialicons-regular.otf')
              .readAsBytes()
              .then((bytes) => ByteData.sublistView(bytes))))
        .load();
  });

  testWidgets(
      'phone-width list badge, inside highlight and jump remain distinct',
      (tester) async {
    tester.view.physicalSize = const Size(780, 620);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final ctrl = ChatV1Controller.instance;
    final oldId = ctrl.currentUserId;
    ctrl.currentUserId = '7';
    addTearDown(() => ctrl.currentUserId = oldId);
    final tagged = ChatV1Mapper.conversationToChatItem({
      'id': 1,
      'title': 'General',
      'unread_count': 3,
      'unread_mention_count': 1,
      'unread_mention_message_id': 12,
      'last_message': {'body': 'Aravind: @Alex Please check the site photos'},
    });
    final ordinary = ChatV1Mapper.conversationToChatItem({
      'id': 2,
      'title': 'Architectural',
      'unread_count': 2,
      'unread_mention_count': 0,
      'last_message': {'body': 'Rohit: Updated plans are ready'},
    });
    final base = <String, dynamic>{
      'id': 12,
      'sender_id': 2,
      'sender_name': 'Aravind',
      'body':
          '@Alex Please check the site photos and confirm if we can proceed.',
      'created_at': '2026-10-04T17:24:00',
      'mentions': [
        {'user_id': 7, 'name': 'Alex Kumar'}
      ],
    };
    final message = ChatV1Mapper.messageFromJson(base, currentUserId: '7');
    var jumps = 0;
    await tester.pumpWidget(RepaintBoundary(
      key: const ValueKey('mention-preview'),
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: ChatV1Theme.data(dark: true),
        home: Row(children: [
          Expanded(
              child: Scaffold(
            appBar: AppBar(title: const Text('Chats')),
            body: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Padding(
                      padding: EdgeInsets.all(16), child: Text('Channels')),
                  Cv1ChatTile(item: tagged, onTap: () {}),
                  Cv1ChatTile(item: ordinary, onTap: () {}),
                  Cv1ChatTile(item: ordinary.copyWith(unread: 0), onTap: () {}),
                ]),
          )),
          const VerticalDivider(width: 1),
          Expanded(
              child: Scaffold(
            backgroundColor: ChatV1Theme.darkChatBg,
            appBar: AppBar(title: const Text('General')),
            body: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Cv1MentionBanner(onTap: () => jumps++),
                  const SizedBox(height: 16),
                  Cv1MessageBubble(
                      message: ChatV1Mapper.messageFromJson({
                    ...base,
                    'id': 11,
                    'body': 'The foundation work is completed today.',
                    'mentions': [],
                  }, currentUserId: '7')),
                  const SizedBox(height: 12),
                  Cv1MessageBubble(message: message),
                  const SizedBox(height: 12),
                  Cv1MessageBubble(
                      message: ChatV1Mapper.messageFromJson({
                    ...base,
                    'id': 13,
                    'sender_id': 8,
                    'sender_name': 'Priya',
                    'body': 'I will share the progress report shortly.',
                    'mentions': [],
                  }, currentUserId: '7')),
                ]),
          )),
        ]),
      ),
    ));
    await tester.pumpAndSettle();
    expect(find.text('@'), findsOneWidget);
    expect(find.text('@You'), findsOneWidget);
    expect(find.text('You were tagged here'), findsOneWidget);
    await tester.tap(find.text('View message'));
    expect(jumps, 1);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await tester.runAsync(() async {
      final boundary = tester.renderObject<RenderRepaintBoundary>(
          find.byKey(const ValueKey('mention-preview')));
      final image = await boundary.toImage(pixelRatio: 1);
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      final dir = Directory('build/chat_mentions_preview')
        ..createSync(recursive: true);
      File(dir.path + '/green_mentions.png')
          .writeAsBytesSync(bytes!.buffer.asUint8List());
      image.dispose();
    });
  });
}
