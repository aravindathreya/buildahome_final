import 'dart:async';

import 'chat_push_grouper.dart';

/// Hook the chat socket uses. Push display is attached at startup so chat
/// code never talks to Firebase directly.
class ChatPushInbox {
  static Future<void> Function(ChatPushIncoming message)? onMessage;
  static Future<void> Function(String conversationId)? onConversationOpened;

  static void messageReceived(ChatPushIncoming message) {
    final handler = onMessage;
    if (handler == null) return;
    unawaited(handler(message));
  }

  static void conversationOpened(String conversationId) {
    final handler = onConversationOpened;
    if (handler == null) return;
    unawaited(handler(conversationId));
  }
}
