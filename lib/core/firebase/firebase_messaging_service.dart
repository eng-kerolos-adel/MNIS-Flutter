import 'dart:async';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import '../../firebase_options.dart';
import 'firebase_analytics_service.dart';
import 'firebase_bootstrap.dart';

@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  try {
    if (Firebase.apps.isEmpty) {
      await Firebase.initializeApp(
        options: DefaultFirebaseOptions.currentPlatform,
      );
    }
  } catch (_) {}
}

class FirebaseMessagingService {
  FirebaseMessagingService._();
  static final FirebaseMessagingService instance =
      FirebaseMessagingService._();

  static const AndroidNotificationChannel _androidChannel =
      AndroidNotificationChannel(
    'mnis_alerts',
    'تنبيهات منظومة MNIS',
    description: 'إشعارات المواعيد والنتائج والروشتات وتأكيد الهوية',
    importance: Importance.high,
  );

  final FlutterLocalNotificationsPlugin _localNotifs =
      FlutterLocalNotificationsPlugin();
  final StreamController<RemoteMessage> _foregroundCtrl =
      StreamController<RemoteMessage>.broadcast();
  final StreamController<String> _routeCtrl =
      StreamController<String>.broadcast();

  Stream<RemoteMessage> get onForegroundMessage => _foregroundCtrl.stream;
  Stream<String> get onNavigateRoute => _routeCtrl.stream;

  bool _initialized = false;
  StreamSubscription<RemoteMessage>? _fgSub;
  StreamSubscription<RemoteMessage>? _openedSub;

  Future<void> initialize() async {
    if (_initialized || !FirebaseBootstrap.isInitialized) return;
    _initialized = true;

    if (!kIsWeb) {
      try {
        await _localNotifs.initialize(
          settings: const InitializationSettings(
            android: AndroidInitializationSettings('@mipmap/ic_launcher'),
          ),
          onDidReceiveNotificationResponse: (details) {
            final route = routeForNotificationType(details.payload ?? '');
            _routeCtrl.add(route);
          },
        );
        final androidImpl =
            _localNotifs.resolvePlatformSpecificImplementation<
                AndroidFlutterLocalNotificationsPlugin>();
        await androidImpl?.createNotificationChannel(_androidChannel);
        await androidImpl?.requestNotificationsPermission();
        await FirebaseMessaging.instance
            .setForegroundNotificationPresentationOptions(
          alert: true,
          badge: true,
          sound: true,
        );
      } catch (_) {}
    }

    _fgSub ??= FirebaseMessaging.onMessage.listen((message) {
      final type = (message.data['type'] as String?) ?? 'GENERAL';
      unawaited(FirebaseAnalyticsService.instance.logPushReceived(type));
      _foregroundCtrl.add(message);
      if (!kIsWeb) {
        unawaited(_showLocalNotification(message));
      }
    });

    _openedSub ??= FirebaseMessaging.onMessageOpenedApp.listen((message) {
      final type = (message.data['type'] as String?) ?? 'GENERAL';
      _routeCtrl.add(routeForNotificationType(type));
    });

    try {
      final initial = await FirebaseMessaging.instance.getInitialMessage();
      if (initial != null) {
        final type = (initial.data['type'] as String?) ?? 'GENERAL';
        _routeCtrl.add(routeForNotificationType(type));
      }
    } catch (_) {}
  }

  Future<void> _showLocalNotification(RemoteMessage message) async {
    final title = (message.data['titleAr'] as String?) ??
        message.notification?.title ??
        'MNIS';
    final body = (message.data['bodyAr'] as String?) ??
        message.notification?.body ??
        '';
    final type = (message.data['type'] as String?) ?? 'GENERAL';
    if (body.isEmpty && title.isEmpty) return;

    try {
      await _localNotifs.show(
        id: message.messageId?.hashCode ?? DateTime.now().millisecond,
        title: title,
        body: body,
        notificationDetails: NotificationDetails(
          android: AndroidNotificationDetails(
            _androidChannel.id,
            _androidChannel.name,
            channelDescription: _androidChannel.description,
            importance: Importance.high,
            priority: Priority.high,
          ),
        ),
        payload: type,
      );
    } catch (_) {}
  }

  static String routeForNotificationType(String type) {
    switch (type) {
      case 'APPOINTMENT_CONFIRMED':
      case 'APPOINTMENT_REJECTED':
        return '/appointments';
      case 'LAB_RESULT_READY':
        return '/lab-results';
      case 'PRESCRIPTION_DISPENSED':
      case 'RENEWAL_DECIDED':
        return '/prescriptions';
      default:
        return '/notifications';
    }
  }
}
