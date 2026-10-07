import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../app_navigator.dart';
import '../../chat_v1/chat_v1_socket.dart';
import '../notification_navigator.dart';
import '../notification_service.dart';
import 'alert_push.dart';
import 'chat_push_grouper.dart';
import 'chat_push_inbox.dart';
import 'fcm_token_client.dart';

const String _chatThreadsKey = 'chat_push_threads_v1';
const String _deviceIdKey = 'fcm_device_id';

@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  WidgetsFlutterBinding.ensureInitialized();
  await PushNotificationService.instance.presentRemoteMessage(
    message,
    backgroundIsolate: true,
  );
}

class PushNotificationService {
  PushNotificationService._()
      : _client = _sharedClient,
        coordinator = FcmSessionCoordinator(_sharedClient);

  static final FcmTokenClient _sharedClient = FcmTokenClient();
  static final PushNotificationService instance = PushNotificationService._();

  final FcmTokenClient _client;
  final FcmSessionCoordinator coordinator;
  final PushLaunchQueue launchQueue = PushLaunchQueue();
  final ShownPushRegistry shown = ShownPushRegistry();
  final FlutterLocalNotificationsPlugin _local =
      FlutterLocalNotificationsPlugin();

  bool _initialized = false;
  bool _firebaseReady = false;
  bool _localReady = false;

  Future<void> initialize() async {
    if (_initialized) return;
    _initialized = true;
    if (kIsWeb) return;

    FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);
    await _ensureFirebase();
    await _ensureLocalNotifications();
    ChatPushInbox.onMessage = _onSocketChat;
    ChatPushInbox.onConversationOpened = _onConversationOpened;
    AlertPushInbox.onDeliver = _onAlerts;
    if (!_firebaseReady) return;

    FirebaseMessaging.onMessage.listen((message) {
      unawaited(presentRemoteMessage(message, backgroundIsolate: false));
    });
    FirebaseMessaging.onMessageOpenedApp.listen((message) {
      unawaited(_openRemote(message));
    });
    FirebaseMessaging.instance.onTokenRefresh.listen((token) {
      unawaited(_onTokenRefresh(token));
    });

    try {
      await FirebaseMessaging.instance
          .setForegroundNotificationPresentationOptions(
        alert: false,
        badge: true,
        sound: false,
      );
    } catch (_) {}

    try {
      final initial = await FirebaseMessaging.instance.getInitialMessage();
      if (initial != null) {
        launchQueue.stage(normalizePushData(initial.data));
      }
    } catch (_) {}

    try {
      final launch = await _local.getNotificationAppLaunchDetails();
      if (launch?.didNotificationLaunchApp == true) {
        final payload = launch?.notificationResponse?.payload;
        final data = _decodePayload(payload);
        if (data != null) launchQueue.stage(data);
      }
    } catch (_) {}

    await syncTokenForCurrentUser();
  }

  /// Call once the user is on Home / Admin dashboard.
  Future<void> markAppReady() async {
    launchQueue.ready = true;
    final pending = launchQueue.take();
    if (pending == null) return;
    final context = globalNavigatorKey.currentContext;
    if (context == null) {
      launchQueue.stage(pending);
      return;
    }
    await NotificationNavigator.open(context, pending);
  }

  Future<void> syncTokenForCurrentUser() async {
    if (kIsWeb) return;
    await _ensureFirebase();
    if (!_firebaseReady) return;
    final prefs = await SharedPreferences.getInstance();
    final userId =
        (prefs.getString('userId') ?? prefs.getString('user_id') ?? '').trim();
    final apiToken = (prefs.getString('api_token') ?? '').trim();
    if (userId.isEmpty || apiToken.isEmpty) return;

    String? token;
    try {
      token = await FirebaseMessaging.instance.getToken();
    } catch (e) {
      debugPrint('[FCM] getToken failed: $e');
      return;
    }
    if (token == null || token.isEmpty) return;

    await coordinator.bind(
      FcmTokenRegistration(
        userId: userId,
        apiToken: apiToken,
        fcmToken: token,
        platform: _platformLabel(),
        deviceId: await _ensureDeviceId(prefs),
      ),
    );
  }

  Future<void> unbindCurrentUser() async {
    final prefs = await SharedPreferences.getInstance();
    final userId =
        (prefs.getString('userId') ?? prefs.getString('user_id') ?? '').trim();
    final apiToken = (prefs.getString('api_token') ?? '').trim();
    var token = coordinator.fcmToken;
    if ((token == null || token.isEmpty) && _firebaseReady) {
      try {
        token = await FirebaseMessaging.instance.getToken();
      } catch (_) {}
    }
    if (userId.isNotEmpty &&
        apiToken.isNotEmpty &&
        token != null &&
        token.isNotEmpty) {
      await _client.unregister(
        userId: userId,
        apiToken: apiToken,
        fcmToken: token,
        deviceId: prefs.getString(_deviceIdKey) ?? coordinator.deviceId ?? '',
      );
    } else if (coordinator.userId != null && coordinator.fcmToken != null) {
      await coordinator.logout(apiToken: apiToken);
    }
    coordinator.userId = null;
    coordinator.fcmToken = null;
    shown.clear();
    try {
      await prefs.remove(_chatThreadsKey);
    } catch (_) {}
    try {
      await _local.cancelAll();
    } catch (_) {}
  }

  Future<void> presentRemoteMessage(
    RemoteMessage message, {
    required bool backgroundIsolate,
  }) async {
    if (kIsWeb) return;
    await _ensureFirebase();
    await _ensureLocalNotifications();
    final data = normalizePushData(message.data);
    final notification = message.notification;
    if ((data['title'] ?? '').isEmpty && notification?.title != null) {
      data['title'] = notification!.title!;
    }
    if ((data['body'] ?? '').isEmpty && notification?.body != null) {
      data['body'] = notification!.body!;
    }
    data.putIfAbsent('type', () => 'alert');

    final type = (data['type'] ?? '').toLowerCase();
    final isChat = type == 'chat' ||
        type == 'message' ||
        type.contains('chat_message') ||
        (data['conversation_id'] ?? '').isNotEmpty && type.contains('chat');
    if (isChat) {
      if (backgroundIsolate && notification != null) {
        // A visible notification payload is already shown by the OS.
        // Grouping requires a data-only message so this handler owns the tray.
        return;
      }
      await _presentChatData(data);
      return;
    }

    if (backgroundIsolate && notification != null) return;
    await _showAlert(data);
  }

  Future<void> _onSocketChat(ChatPushIncoming incoming) async {
    await _ensureLocalNotifications();
    final threads = await _loadThreads();
    final notice = ChatPushGrouper.record(threads: threads, incoming: incoming);
    await _saveThreads(threads);
    if (notice == null) return;
    await _showChatNotice(notice);
  }

  Future<void> _onConversationOpened(String conversationId) async {
    final threads = await _loadThreads();
    final notice = ChatPushGrouper.clear(
      threads: threads,
      conversationId: conversationId,
    );
    await _saveThreads(threads);
    if (notice != null) await _showChatNotice(notice);
  }

  void _onAlerts(List<Map<String, dynamic>> alerts) {
    for (final alert in alerts) {
      unawaited(_showAlert(AlertPushMapper.toData(alert)));
    }
  }

  Future<void> _presentChatData(Map<String, String> data) async {
    final prefs = await SharedPreferences.getInstance();
    final me =
        (prefs.getString('userId') ?? prefs.getString('user_id') ?? '').trim();
    final threads = await _loadThreads();
    final notice = ChatPushGrouper.record(
      threads: threads,
      incoming: ChatPushIncoming(
        conversationId: data['conversation_id'] ?? '',
        senderName: data['sender_name'] ?? 'Someone',
        preview: data['preview'] ?? data['body'] ?? '',
        senderId: data['sender_id'],
        currentUserId: me,
        openConversationId: ChatV1Socket.instance.joinedConversationId,
        conversationTitle: data['conversation_title'] ?? data['title'],
        messageId: data['message_id'],
        messageType: data['message_type'],
        fromMe: (data['is_from_me'] ?? '') == '1',
        isGroup: (data['is_group'] ?? '') == '1' ||
            (data['is_group'] ?? '').toLowerCase() == 'true',
      ),
    );
    await _saveThreads(threads);
    if (notice == null) return;
    await _showChatNotice(notice);
  }

  Future<void> _showAlert(Map<String, String> data) async {
    final title = (data['title'] ?? '').trim();
    final body = (data['body'] ?? '').trim();
    if (title.isEmpty && body.isEmpty) return;
    final key = _alertKey(data);
    if (!shown.claim(key)) return;
    await _ensureLocalNotifications();
    NotificationService.instance.noteIncomingAlert(data);
    final badge = _shownBadge(data['badge']);
    final id = key.hashCode & 0x7fffffff;
    await _local.show(
      id,
      title.isEmpty ? 'buildAhome' : title,
      body,
      _alertDetails(badge),
      payload: jsonEncode(data),
    );
  }

  Future<void> _showChatNotice(ChatPushNotice notice) async {
    await _ensureLocalNotifications();
    if (notice.clearExisting) {
      NotificationService.instance.removeChatAlert(notice.conversationId);
      await _local.cancel(notice.notificationId);
      return;
    }
    final messageCount = notice.count < 1 ? 1 : notice.count;
    NotificationService.instance.upsertChatAlert(
      conversationId: notice.conversationId,
      title: notice.title,
      body: notice.body,
      count: messageCount,
    );
    final badge = _shownBadge(null);
    await _local.show(
      notice.notificationId,
      notice.title,
      notice.body,
      NotificationDetails(
        android: AndroidNotificationDetails(
          'buildahome_chat',
          'Chat messages',
          channelDescription: 'New chat messages',
          importance: Importance.high,
          priority: Priority.high,
          icon: '@drawable/ic_notification',
          number: messageCount,
          channelShowBadge: true,
          tag: 'chat_${notice.conversationId}',
          groupKey: 'chat_${notice.conversationId}',
          styleInformation: InboxStyleInformation(
            notice.lines,
            contentTitle: notice.title,
            summaryText: notice.body,
          ),
        ),
        iOS: DarwinNotificationDetails(
          threadIdentifier: 'chat_${notice.conversationId}',
          badgeNumber: badge,
          presentAlert: true,
          presentBadge: true,
          presentBanner: true,
          presentList: true,
          presentSound: true,
        ),
      ),
      payload: jsonEncode(notice.payload),
    );
  }

  int _shownBadge(String? fromPayload) {
    final fromServer = int.tryParse((fromPayload ?? '').trim());
    final local = NotificationService.instance.unreadCount;
    final count = local > 0 ? local : (fromServer ?? 1);
    return count < 1 ? 1 : count;
  }

  NotificationDetails _alertDetails(int badge) {
    return NotificationDetails(
      android: AndroidNotificationDetails(
        'buildahome_alerts',
        'Updates',
        channelDescription: 'Project, task, and payment updates',
        importance: Importance.high,
        priority: Priority.high,
        icon: '@drawable/ic_notification',
        number: badge,
        channelShowBadge: true,
      ),
      iOS: DarwinNotificationDetails(
        badgeNumber: badge,
        presentAlert: true,
        presentBadge: true,
        presentBanner: true,
        presentList: true,
        presentSound: true,
      ),
    );
  }

  Future<void> _openRemote(RemoteMessage message) async {
    final data = normalizePushData(message.data);
    if ((data['title'] ?? '').isEmpty && message.notification?.title != null) {
      data['title'] = message.notification!.title!;
    }
    if ((data['body'] ?? '').isEmpty && message.notification?.body != null) {
      data['body'] = message.notification!.body!;
    }
    if (!launchQueue.ready || globalNavigatorKey.currentContext == null) {
      launchQueue.stage(data);
      return;
    }
    await NotificationNavigator.open(globalNavigatorKey.currentContext!, data);
  }

  Future<void> _onLocalTap(NotificationResponse response) async {
    final data = _decodePayload(response.payload);
    if (data == null) return;
    if (!launchQueue.ready || globalNavigatorKey.currentContext == null) {
      launchQueue.stage(data);
      return;
    }
    await NotificationNavigator.open(globalNavigatorKey.currentContext!, data);
  }

  Map<String, String>? _decodePayload(String? payload) {
    if (payload == null || payload.trim().isEmpty) return null;
    try {
      final decoded = jsonDecode(payload);
      if (decoded is Map) {
        return normalizePushData(Map<String, dynamic>.from(decoded));
      }
    } catch (_) {}
    return null;
  }

  Future<void> _onTokenRefresh(String token) async {
    if (token.trim().isEmpty) return;
    final prefs = await SharedPreferences.getInstance();
    final userId =
        (prefs.getString('userId') ?? prefs.getString('user_id') ?? '').trim();
    final apiToken = (prefs.getString('api_token') ?? '').trim();
    if (userId.isEmpty || apiToken.isEmpty) return;
    coordinator.userId ??= userId;
    coordinator.deviceId ??= await _ensureDeviceId(prefs);
    await coordinator.onTokenRefresh(
      fcmToken: token,
      apiToken: apiToken,
      platform: _platformLabel(),
    );
  }

  Future<void> _ensureFirebase() async {
    if (_firebaseReady || kIsWeb) return;
    try {
      if (Firebase.apps.isEmpty) {
        await Firebase.initializeApp();
      }
      _firebaseReady = true;
    } catch (e) {
      debugPrint('[FCM] Firebase init failed: $e');
    }
  }

  /// Android 13+ system notification permission. No-op on other platforms.
  Future<bool?> requestAndroidNotificationPermission() async {
    if (kIsWeb || !Platform.isAndroid) return null;
    await _ensureLocalNotifications();
    final android = _local.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    return android?.requestNotificationsPermission();
  }

  Future<void> _ensureLocalNotifications() async {
    if (_localReady || kIsWeb) return;
    const android = AndroidInitializationSettings('@drawable/ic_notification');
    const ios = DarwinInitializationSettings(
      requestAlertPermission: false,
      requestBadgePermission: false,
      requestSoundPermission: false,
    );
    await _local.initialize(
      const InitializationSettings(android: android, iOS: ios),
      onDidReceiveNotificationResponse: (response) {
        unawaited(_onLocalTap(response));
      },
    );
    final androidPlugin = _local.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    if (androidPlugin != null) {
      const alerts = AndroidNotificationChannel(
        'buildahome_alerts',
        'Updates',
        description: 'Project, task, and payment updates',
        importance: Importance.high,
      );
      const chat = AndroidNotificationChannel(
        'buildahome_chat',
        'Chat messages',
        description: 'New chat messages',
        importance: Importance.high,
      );
      await androidPlugin.createNotificationChannel(alerts);
      await androidPlugin.createNotificationChannel(chat);
    }
    _localReady = true;
  }

  Future<Map<String, ChatPushThread>> _loadThreads() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_chatThreadsKey);
    if (raw == null || raw.isEmpty) return {};
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return {};
      final threads = <String, ChatPushThread>{};
      decoded.forEach((key, value) {
        if (value is! Map) return;
        final thread =
            ChatPushThread.fromJson(Map<String, dynamic>.from(value));
        final id = thread.conversationId.isEmpty
            ? key.toString()
            : thread.conversationId;
        threads[id] = thread;
      });
      return threads;
    } catch (_) {
      return {};
    }
  }

  Future<void> _saveThreads(Map<String, ChatPushThread> threads) async {
    final prefs = await SharedPreferences.getInstance();
    final encoded = <String, dynamic>{
      for (final entry in threads.entries) entry.key: entry.value.toJson(),
    };
    await prefs.setString(_chatThreadsKey, jsonEncode(encoded));
  }

  Future<String> _ensureDeviceId(SharedPreferences prefs) async {
    final existing = prefs.getString(_deviceIdKey)?.trim() ?? '';
    if (existing.isNotEmpty) return existing;
    final created =
        '${DateTime.now().microsecondsSinceEpoch.toRadixString(16)}${Random().nextInt(1 << 20).toRadixString(16)}';
    await prefs.setString(_deviceIdKey, created);
    return created;
  }

  String _platformLabel() {
    if (kIsWeb) return 'web';
    if (Platform.isIOS) return 'ios';
    return 'android';
  }

  String _alertKey(Map<String, String> data) {
    final id = (data['id'] ?? '').trim();
    if (id.isNotEmpty) return 'id:$id';
    return 't:${data['title'] ?? ''}|b:${data['body'] ?? ''}|ty:${data['type'] ?? ''}';
  }
}
